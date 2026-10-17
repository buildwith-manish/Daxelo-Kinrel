// test/features/family/wedge_e2e_visual_test.dart
//
// End-to-end verification of the wedge interaction model on the REAL
// FamilyGraphScreen + engine view, with a mocked family dataset:
//
//   • the viewer sees their top 8 connections (spouse + hub + 6 kids)
//   • collapsed hubs with connections show "+N" count badges
//   • tapping a collapsed person expands them in place (first 8 of
//     their children appear + a "+N" page bubble)
//   • tapping the "+N" bubble loads the remaining children and the
//     bubble disappears when nothing remains
//   • tapping the focused, expanded person collapses them
//
// When the WEDGE_SHOT_DIR environment variable is set, PNG screenshots
// of each stage are written there for visual (human/VLM) review.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_graph_screen.dart';
import 'package:kinrel/graph/widgets/graph_node.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';
import 'package:kinrel/graph/interaction/wedge_view_state.dart';
import 'package:kinrel/graph/interaction/proximity_graph_state.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';

class _FakeFamilyGraphNotifier extends FamilyGraphNotifier {
  _FakeFamilyGraphNotifier(this._graphData);

  final FlatGraphResult _graphData;

  @override
  Future<FlatGraphResult> build(String familyId) async {
    return _graphData;
  }

  // No network in tests — the branch fetch is a no-op that just
  // re-emits the same (fully loaded) graph.
  @override
  Future<void> fetchBranchAndMerge({
    required String rootPersonId,
    required String branchType,
    int depth = 2,
  }) async {}
}

/// A 25-person family:
///   viewer (anchor) — 8 connections: spouse, hub (brother), a1..a6
///   hub             — 11 children (k1..k11)  → first 8 + a "+3" bubble
///   a1              — 3 children (d1..d3)   → "+4" badge (4 connections)
///   a2              — 2 children (s1..s2)    → "+3" badge
FlatGraphResult _wedgeFamily() {
  final persons = <Map<String, dynamic>>[
    _p('viewer', 'Me The Viewer', anchor: true),
    _p('spouse', 'Spouse Person'),
    _p('hub', 'Hub Brother'),
    for (var i = 1; i <= 6; i++) _p('a$i', 'Kid $i'),
    for (var i = 1; i <= 11; i++) _p('k$i', 'Hub Kid $i'),
    for (var i = 1; i <= 3; i++) _p('d$i', 'Grandkid D$i'),
    for (var i = 1; i <= 2; i++) _p('s$i', 'Grandkid S$i'),
  ];
  final rels = <Map<String, dynamic>>[
    _r('r00', 'viewer', 'spouse', 'spouse'),
    _r('r01', 'viewer', 'hub', 'brother'),
    for (var i = 1; i <= 6; i++) _r('rv$i', 'viewer', 'a$i', 'son'),
    for (var i = 1; i <= 11; i++) _r('rk$i', 'hub', 'k$i', 'son'),
    for (var i = 1; i <= 3; i++) _r('rd$i', 'a1', 'd$i', 'son'),
    for (var i = 1; i <= 2; i++) _r('rs$i', 'a2', 's$i', 'son'),
  ];
  return FlatGraphResult(persons: persons, relationships: rels);
}

Map<String, dynamic> _p(String id, String name, {bool anchor = false}) => {
      'id': id,
      'name': name,
      'gender': 'male',
      'generationIndex': 0,
      'isAnchor': anchor,
      'photoUrl': null,
      'isDeceased': false,
    };

Map<String, dynamic> _r(String id, String from, String to, String key) => {
      'id': id,
      'fromPersonId': from,
      'toPersonId': to,
      'relationshipKey': key,
      'isPrivate': false,
    };

GoRouter _testRouter() => GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const FamilyGraphScreen(
          familyId: 'wedge-family',
          familyName: 'Wedge Family',
        ),
      ),
      GoRoute(
        path: '/family/:familyId/add-person',
        builder: (context, state) => const Scaffold(body: Text('Add')),
      ),
    ]);

Future<void> _shoot(WidgetTester tester, String name) async {
  final dir = Platform.environment['WEDGE_SHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  // Artifact generation for visual review: run with BOTH the env var
  // set AND --update-goldens, then inspect the written PNGs.
  await expectLater(
    find.byType(FamilyGraphScreen),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  testWidgets('wedge e2e: top-8 view, badges, tap expand, +N page '
      'bubble, tap-collapse', (tester) async {
    tester.view.physicalSize = const Size(2160, 3840);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyGraphProvider.overrideWith(
            () => _FakeFamilyGraphNotifier(_wedgeFamily()),
          ),
        ],
        child: MaterialApp.router(routerConfig: _testRouter()),
      ),
    );
    // Fixed pumps — always-on animations never settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    // SPY: log every graphLayoutProvider emission forever.
    {
      final sctx = tester.element(find.byType(FamilyGraphScreen));
      final sc = ProviderScope.containerOf(sctx);
      sc.listen<AsyncValue<dynamic>>(
        graphLayoutProvider('wedge-family'),
        (prev, next) {
          final v = next.valueOrNull;
          if (v == null) {
            debugPrint('[SPY] emit: null');
          } else {
            final positions = (v as dynamic).positions as Map<String, dynamic>;
            debugPrint('[SPY] emit: #${positions.length} '
                'hub=${positions['hub']} k7=${positions['k7']}');
          }
        },
        fireImmediately: true,
      );
    }
    await _shoot(tester, 'wedge_1_initial_top8');

    // 1. The viewer sees exactly their top 8: spouse + hub + a1..a6
    //    (the hub's 11 children are NOT on the canvas yet).
    expect(find.text('Me The Viewer'), findsWidgets);
    expect(find.text('Hub Brother'), findsWidgets);
    for (var i = 1; i <= 6; i++) {
      expect(find.text('Kid $i'), findsWidgets,
          reason: 'viewer child a$i is in the top-8 view');
    }
    expect(find.text('Hub Kid 1'), findsNothing,
        reason: 'the hub is collapsed — its children are hidden');
    expect(find.text('Hub Kid 11'), findsNothing);

    // 2. Count badges on collapsed hubs with connections: hub has 12
    //    connections, a1 has 4, a2 has 3.
    expect(find.text('+12'), findsOneWidget,
        reason: 'the collapsed hub shows its connection count');
    expect(find.text('+4'), findsOneWidget,
        reason: 'collapsed a1 (4 connections) shows a badge');
    expect(
      find.byWidgetPredicate((w) =>
          w is Text && w.data == '+3' && (w.style?.fontSize ?? 0) >= 14),
      findsOneWidget,
      reason: 'collapsed a2 (3 connections) shows a readable badge '
          '(number at least 14px per the spec)',
    );

    // 3. Tap the collapsed hub → expands in place with its FIRST 8
    //    children + a "+3" page bubble. (Tap the node's AVATAR CIRCLE —
    //    the name labels of neighbours can overlap a node's label at
    //    some zooms, but the circles themselves never overlap.)
    Future<void> tapHubNode() async {
      final node = find
          .ancestor(
              of: find.text('Hub Brother'),
              matching: find.byType(GraphNode))
          .first;
      final rect = tester.getRect(node);
      await tester.tapAt(Offset(rect.center.dx, rect.top + 60));
    }

    await tapHubNode();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    {
      final dctx = tester.element(find.byType(FamilyGraphScreen));
      final dcontainer = ProviderScope.containerOf(dctx);
      final wedgeState = dcontainer.read(wedgeViewProvider);
      debugPrint('[E2E DEBUG after hub tap] expanded='
          '${wedgeState.expandedRoots} revision=${wedgeState.revision}');
      final layoutNow =
          dcontainer.read(graphLayoutProvider('wedge-family')).valueOrNull;
      final hubKidPositions = <String>[];
      layoutNow?.positions.forEach((id, _) {
        if (id.startsWith('k')) hubKidPositions.add(id);
      });
      debugPrint('[E2E DEBUG] hub kids in LAYOUT: ${hubKidPositions.length}'
          ' / total positions=${layoutNow?.positions.length}');
    }
    await _shoot(tester, 'wedge_2_hub_expanded');

    var hubKidsVisible = 0;
    for (var i = 1; i <= 11; i++) {
      if (find.text('Hub Kid $i').evaluate().isNotEmpty) hubKidsVisible++;
    }
    expect(hubKidsVisible, 8,
        reason: 'exactly the first 8 of the hub children render');
    expect(
      find.byWidgetPredicate((w) =>
          w is Text && w.data == '+3' && (w.style?.fontSize ?? 0) >= 15),
      findsOneWidget,
      reason: 'the hub now has a "+3" page bubble (11 - 8)',
    );

    // 4. Tap the "+3" PAGE BUBBLE (the hub's — fontSize 15 — not a
    //    collapsed person's count badge, which is fontSize 11 and may
    //    show the same number) → the remaining 3 children load in and
    //    the bubble disappears (nothing remains).
    final hubBubble = find.byWidgetPredicate((w) =>
        w is Text && w.data == '+3' && (w.style?.fontSize ?? 0) >= 15);
    expect(hubBubble, findsOneWidget,
        reason: 'the hub\'s "+3" page bubble is showing');
    await tester.tap(hubBubble, warnIfMissed: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    // DEBUG: inspect the wedge state after the +N tap.
    {
      final dctx = tester.element(find.byType(FamilyGraphScreen));
      final dcontainer = ProviderScope.containerOf(dctx);
      final wedgeState = dcontainer.read(wedgeViewProvider);
      debugPrint('[E2E DEBUG] pages=${wedgeState.pages} '
          'expanded=${wedgeState.expandedRoots} '
          'focused=${wedgeState.focusedPersonId} '
          'revision=${wedgeState.revision}');
      debugPrint('[E2E DEBUG] step4 container='
          '${dcontainer.hashCode} provider='
          '${dcontainer.read(graphLayoutProvider('wedge-family')).hashCode}');
      final layoutNow =
          dcontainer.read(graphLayoutProvider('wedge-family')).valueOrNull;
      debugPrint('[E2E DEBUG] positions=${layoutNow?.positions.length}');
    }
    await _shoot(tester, 'wedge_3_next_page_loaded');

    hubKidsVisible = 0;
    for (var i = 1; i <= 11; i++) {
      if (find.text('Hub Kid $i').evaluate().isNotEmpty) hubKidsVisible++;
    }
    // Also verify via the layout provider (zoom-independent truth).
    {
      final dctx = tester.element(find.byType(FamilyGraphScreen));
      final dcontainer = ProviderScope.containerOf(dctx);
      final layoutNow =
          dcontainer.read(graphLayoutProvider('wedge-family')).valueOrNull;
      final hubKidPositions = layoutNow?.positions.keys
              .where((id) => id.startsWith('k'))
              .length ??
          0;
      expect(hubKidPositions, 3,
          reason: 'the next page window shows the remaining 3 children');
    }
    expect(hubKidsVisible <= 8 && hubKidsVisible >= 3, isTrue,
        reason: 'the next page window renders (at most 8 per hub)');
    // The bubble's exit is ANIMATED by design: after the hub pages to
    // its very end, the chip fades out over a short cycle (260ms fade
    // + 400ms cleanup) that only starts once the re-paced layout lands.
    // Pump past the fade window before requiring the text to be gone.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(hubBubble, findsNothing,
        reason: 'the bubble disappears when nothing remains');

    // 5. Tap the hub (now the focused, expanded person) → collapses.
    // Extra pumps — if the entrance animation were stuck, this won't
    // help; if it's merely slow, the kids reach their final spots.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    {
      final node = find
          .ancestor(
              of: find.text('Hub Brother'),
              matching: find.byType(GraphNode))
          .first;
      final rect = tester.getRect(node);
      debugPrint('[E2E DEBUG] hub node rect=$rect tap='
          '${Offset(rect.center.dx, rect.top + 60)}');
      {
        final dctx = tester.element(find.byType(FamilyGraphScreen));
        final dcontainer = ProviderScope.containerOf(dctx);
        final layoutNow = dcontainer
            .read(graphLayoutProvider('wedge-family')).valueOrNull;
        debugPrint('[E2E DEBUG] step5 container='
            '${dcontainer.hashCode}');
        debugPrint('[E2E DEBUG] ALL POSITIONS: '
            '${layoutNow?.positions}');
        final prox = dcontainer.read(proximityGraphProvider);
        {
          // Direct engine call with the same inputs — compare.
          final links = <WedgeLink>[
            for (final Map<String, dynamic> r in _wedgeFamily().relationships)
              WedgeLink(
                fromId: (r['fromPersonId'] ?? '').toString(),
                toId: (r['toPersonId'] ?? '').toString(),
                relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
                keyAtoB: r['relationshipKey'] as String?,
              ),
          ];
          final out = ViewerWedgeLayout().compute(
            loadedPersonIds: prox.visibleIds,
            nameOf: const {},
            links: links,
            viewerId: 'viewer',
            expandedPersonIds: const {'hub'},
            manualPages: const {'hub': 1},
            expansionOrder: const ['hub'],
          );
          debugPrint('[E2E DEBUG] DIRECT ENGINE: '
              'hub=${out.positions['hub']} k9=${out.positions['k9']}');
        }
        debugPrint('[E2E DEBUG] proximity visible: '
            '${prox.visibleIds.toList()..sort()}');
      }
      // Where is k9?
      for (var i = 9; i <= 11; i++) {
        final t = find.text('Hub Kid $i');
        if (t.evaluate().isNotEmpty) {
          final krect = tester.getRect(t);
          debugPrint('[E2E DEBUG] k$i label rect=$krect');
        }
      }
    }
    await tapHubNode();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    await _shoot(tester, 'wedge_4_hub_collapsed');

    var hubKidsAfterCollapse = 0;
    for (var i = 1; i <= 11; i++) {
      if (find.text('Hub Kid $i').evaluate().isNotEmpty) hubKidsAfterCollapse++;
    }
    expect(hubKidsAfterCollapse, 0,
        reason: 'tapping the focused, expanded hub collapsed it');
    // ...and its count badge comes back.
    expect(find.text('+12'), findsOneWidget);

    // Let the collapse's async provider work (layout recompute +
    // microtask-scheduled chip-slot writes) settle while the tree is
    // still mounted — otherwise those writes land during the post-test
    // unmount and trip the defunct-element assert in riverpod.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  });
}
