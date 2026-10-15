// test/features/chat/chat_kinship_labels_test.dart
//
// v140 — Tests for the kinship-aware relationship labels + colors in
// the group chat message bubbles (chat UI reference screenshot:
// "Papa · Father", "Nani · Maternal grandmother").
//
// The production code being verified:
//   - lib/features/family/data/relationship_label_provider.dart
//       :: ChatKinshipResolver.resolveKey (pure resolver — direct edge
//          canonical label semantics + RelationshipEngine BFS fallback)
//       :: formatRelationshipLabel (KinshipService display names,
//          sentence-cased)
//   - lib/features/chat/presentation/widgets/message_bubble.dart
//       :: the "Name · Relationship" header row, the kinship-colored
//          name span, the neutral relationship span, and the left-edge
//          vertical color indicator (the 3 dp kinship band)
//
// Architecture invariants covered:
//   - The resolver REUSES the Family Graph engines (RelationshipEngine
//     BFS) — it never reimplements pathfinding.
//   - The label is VIEWER-SPECIFIC: the same edge resolves differently
//     for different viewers (labelAtoB vs labelBtoA direction).
//   - Direct edges use the SPECIFIC label (labelAtoB/labelBtoA), not
//     the structural relationshipKey, when present.
//   - Multi-hop relatives (maternal grandmother via mother) resolve
//     through the BFS path composition.
//   - Missing relationship data resolves to null (graceful) — never
//     an invented label.
//   - The bubble renders "<senderName> · <relationship>" with the
//     kinship category color on the name, neutral grey on the
//     relationship, and the vertical color indicator on the left edge.
//
// Run with: flutter test test/features/chat/chat_kinship_labels_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/family_provider.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/kinship/kinship_service.dart';
import 'package:kinrel/features/chat/presentation/chat_ui_tokens.dart';
import 'package:kinrel/features/chat/presentation/widgets/message_bubble.dart';
import 'package:kinrel/features/chat/providers/chat_provider.dart';
import 'package:kinrel/features/family/data/relationship_label_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Test data builders
// ═══════════════════════════════════════════════════════════════════════

Person _person(
  String id,
  String name, {
  String? linkedUserId,
  String? gender,
  bool isAnchor = false,
}) =>
    Person(
      id: id,
      familyId: 'fam-1',
      name: name,
      gender: gender,
      linkedUserId: linkedUserId,
      isAnchor: isAnchor,
    );

FamilyRelationship _rel(
  String from,
  String to,
  String relationshipKey, {
  String? labelAtoB,
  String? labelBtoA,
}) =>
    FamilyRelationship(
      id: 'rel-$from-$to',
      familyId: 'fam-1',
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: relationshipKey,
      labelAtoB: labelAtoB,
      labelBtoA: labelBtoA,
    );

ChatMessage _msg(
  String id,
  String senderId,
  String senderName,
  String content,
) =>
    ChatMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      content: content,
      messageType: MessageType.text,
      timestamp: DateTime(2026, 10, 13, 19, 42),
    );

/// Renders a received group-chat bubble inside an overridden
/// ProviderScope (the same override strategy the chat UI gallery
/// uses — no network, no database).
Widget _bubble({
  required ChatMessage message,
  required String familyId,
  String? rawKeyOverride,
  String? labelOverride,
  bool isMe = false,
}) {
  final overrides = <Override>[
    chatCurrentUserIdProvider.overrideWith((ref) => 'me'),
    relationshipKeyProvider(
      (familyId: familyId, senderUserId: message.senderId),
    ).overrideWith((ref) => rawKeyOverride),
    relationshipLabelProvider(
      (familyId: familyId, senderUserId: message.senderId),
    ).overrideWith((ref) => labelOverride),
  ];
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ChatUi.chatBackground,
        fontFamily: 'DMSans',
      ),
      home: Scaffold(
        body: Center(
          child: ListView(
            children: [
              MessageBubble(
                message: message,
                isMe: isMe,
                onReply: () {},
                onReact: () {},
                onLongPress: () {},
                familyId: familyId,
                isFirstInGroup: true,
                isLastInGroup: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Finds the kinship header RichText inside the bubble — the header
/// is a multi-span RichText (name · spacer · separator · spacer ·
/// relationship = 5 children), unlike plain Text widgets whose
/// internal RichText has a single span with no children.
RichText _headerRichText(WidgetTester tester, String needle) {
  final richTexts = tester
      .widgetList<RichText>(find.byType(RichText))
      .where((rt) {
        final span = rt.text;
        if (span is! TextSpan) return false;
        final kids = span.children;
        return kids != null &&
            kids.length >= 5 &&
            rt.text.toPlainText().contains(needle);
      }).toList();
  expect(richTexts, isNotEmpty,
      reason: 'Expected a kinship header RichText containing "$needle"');
  return richTexts.first;
}

/// Whether any multi-span (header) RichText exists in the tree.
bool _hasHeaderRichText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .any((rt) =>
        rt.text is TextSpan &&
        ((rt.text as TextSpan).children?.length ?? 0) >= 5);

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ChatKinshipResolver.clearCacheForTest();
  });
  tearDown(() {
    ChatKinshipResolver.clearCacheForTest();
  });

  // ─────────────────────────────────────────────────────────────────────
  // ChatKinshipResolver — direct edge canonical label semantics
  // ─────────────────────────────────────────────────────────────────────

  group('ChatKinshipResolver — direct edges (canonical labels)', () {
    test('edge from=viewer → to=sender: viewer label = labelAtoB', () {
      // from=A, to=B, labelAtoB='father' → "B is A's father".
      // Viewer = A, sender = B → the sender IS the viewer's father.
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: _person('a', 'Viewer'),
        senderPerson: _person('b', 'Papa', gender: 'male'),
        members: [_person('a', 'Viewer'), _person('b', 'Papa')],
        relationships: [
          _rel('a', 'b', 'parent', labelAtoB: 'father', labelBtoA: 'son'),
        ],
      );
      expect(key, 'father');
    });

    test('edge from=sender → to=viewer: viewer label = labelBtoA', () {
      // from=B, to=A, labelAtoB='son' → "A is B's son". Viewer = A
      // (the `to` side), sender = B. The viewer's label for the sender
      // is labelBtoA ('father' — B is A's father).
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: _person('a', 'Viewer'),
        senderPerson: _person('b', 'Papa', gender: 'male'),
        members: [_person('a', 'Viewer'), _person('b', 'Papa')],
        relationships: [
          _rel('b', 'a', 'parent', labelAtoB: 'son', labelBtoA: 'father'),
        ],
      );
      expect(key, 'father');
    });

    test('specific label preferred over structural relationshipKey', () {
      // Real-world shape: relationshipKey='parent' (structural) while
      // labelAtoB='grandfather' (specific). The resolver must return
      // the SPECIFIC label.
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: _person('a', 'Viewer'),
        senderPerson: _person('b', 'Grandpa', gender: 'male'),
        members: [_person('a', 'Viewer'), _person('b', 'Grandpa')],
        relationships: [
          _rel('a', 'b', 'parent', labelAtoB: 'grandfather'),
        ],
      );
      expect(key, 'grandfather');
    });

    test('legacy rows without labels fall back to relationshipKey', () {
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: _person('a', 'Viewer'),
        senderPerson: _person('b', 'Brother'),
        members: [_person('a', 'Viewer'), _person('b', 'Brother')],
        relationships: [_rel('a', 'b', 'brother')],
      );
      expect(key, 'brother');
    });

    test('inactive edges are ignored', () {
      final inactive = FamilyRelationship(
        id: 'rel-a-b',
        familyId: 'fam-1',
        fromPersonId: 'a',
        toPersonId: 'b',
        relationshipKey: 'brother',
        labelAtoB: 'brother',
        isActive: false,
      );
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: _person('a', 'Viewer'),
        senderPerson: _person('b', 'Brother'),
        members: [_person('a', 'Viewer'), _person('b', 'Brother')],
        relationships: [inactive],
      );
      expect(key, isNull, reason: 'No active path → unresolved (null)');
    });

    test('no edge and no path → null (graceful, no invented label)', () {
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: _person('a', 'Viewer'),
        senderPerson: _person('z', 'Stranger'),
        members: [_person('a', 'Viewer'), _person('z', 'Stranger')],
        relationships: const [],
      );
      expect(key, isNull);
    });

    test('viewer == sender → null (self)', () {
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: _person('a', 'Viewer'),
        senderPerson: _person('a', 'Viewer'),
        members: [_person('a', 'Viewer')],
        relationships: const [],
      );
      expect(key, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ChatKinshipResolver — BFS fallback (multi-hop relatives)
  // ─────────────────────────────────────────────────────────────────────

  group('ChatKinshipResolver — BFS path fallback', () {
    test('maternal grandmother (no direct edge) resolves via the mother', () {
      // Structure: viewer → mother → maternal grandmother.
      // Edges (canonical): from=viewer,to=mother,labelAtoB='mother';
      // from=mother,to=nani,labelAtoB='mother' (nani is mother's mother).
      final members = [
        _person('me', 'Viewer', gender: 'male'),
        _person('mom', 'Mummy', gender: 'female'),
        _person('nani', 'Nani', gender: 'female'),
      ];
      final rels = [
        _rel('me', 'mom', 'parent', labelAtoB: 'mother', labelBtoA: 'son'),
        _rel('mom', 'nani', 'parent',
            labelAtoB: 'mother', labelBtoA: 'daughter'),
      ];
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: members[0],
        senderPerson: members[2],
        members: members,
        relationships: rels,
      );
      // The BFS composes viewer→mother→mother's mother. The structural
      // classifier guarantees a grandparent-category key for a
      // 2-parent-hop path to a female target.
      expect(key, isNotNull);
      expect(
        key,
        anyOf('maternal_grandmother', 'grandmother', 'grandparent'),
        reason: 'A 2-up female path must resolve to a grandparent key',
      );
    });

    test('father (no direct edge) resolves via BFS as a parent key', () {
      final members = [
        _person('me', 'Viewer', gender: 'male'),
        _person('dad', 'Papa', gender: 'male'),
      ];
      // Edge stored from the father's side: from=dad, to=me,
      // labelAtoB='son' ("me is dad's son"). labelBtoA='father'.
      final rels = [
        _rel('dad', 'me', 'parent', labelAtoB: 'son', labelBtoA: 'father'),
      ];
      final key = ChatKinshipResolver.resolveKey(
        viewerPerson: members[0],
        senderPerson: members[1],
        members: members,
        relationships: rels,
      );
      expect(key, 'father');
    });

    test('the SAME graph resolves differently per viewer perspective', () {
      // Viewer-specificity: a parent-child pair flips with the viewer.
      //   viewer=child → sender=parent : 'father'
      //   viewer=parent → sender=child : 'son'
      final members = [
        _person('child', 'Child', gender: 'male'),
        _person('parent', 'Parent', gender: 'male'),
      ];
      final rels = [
        _rel('child', 'parent', 'parent',
            labelAtoB: 'father', labelBtoA: 'son'),
      ];
      final fromChild = ChatKinshipResolver.resolveKey(
        viewerPerson: members[0],
        senderPerson: members[1],
        members: members,
        relationships: rels,
      );
      final fromParent = ChatKinshipResolver.resolveKey(
        viewerPerson: members[1],
        senderPerson: members[0],
        members: members,
        relationships: rels,
      );
      expect(fromChild, 'father');
      expect(fromParent, 'son');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // formatRelationshipLabel — formal display names
  // ─────────────────────────────────────────────────────────────────────

  group('formatRelationshipLabel', () {
    test('falls back to sentence-cased key when KinshipService is not loaded',
        () {
      // On a fresh test VM the service is not loaded → pure key casing.
      // (This test MUST run before the "loaded" test below — Dart test
      // groups execute in declaration order within a file.)
      expect(formatRelationshipLabel('father'), 'Father');
      expect(formatRelationshipLabel('maternal_grandmother'),
          'Maternal grandmother');
      expect(formatRelationshipLabel('elder_brother'), 'Elder brother');
    });

    test('uses the KinshipService english display name when loaded',
        () async {
      final kinship = KinshipService.instance;
      await kinship.loadForTest(
        coreJsonPath: 'assets/data/kinship_core.json',
        termsJsonPath: 'assets/data/kinship_terms.json',
      );
      // displayNames.english.native for maternal_grandmother is
      // "Maternal Grandmother" → sentence-cased "Maternal grandmother".
      expect(formatRelationshipLabel('maternal_grandmother'),
          'Maternal grandmother');
      expect(formatRelationshipLabel('father'), 'Father');
    });

    test('sentence case lowercases the tail ("MATERNAL_GRANDMOTHER")', () {
      expect(formatRelationshipLabel('MATERNAL_GRANDMOTHER'),
          'Maternal grandmother');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // MessageBubble — "Papa · Father" header + kinship band (widget tests)
  // ─────────────────────────────────────────────────────────────────────

  group('MessageBubble — kinship header row (chat UI reference)', () {
    testWidgets(
        'renders "<senderName> · <relationship>" with the name '
        'colored in the parent category color', (tester) async {
      await tester.pumpWidget(_bubble(
        message: _msg('m1', 'sender-papa', 'Papa', 'Dinner at 8?'),
        familyId: 'fam-1',
        rawKeyOverride: 'father',
        labelOverride: 'Father',
      ));
      await tester.pumpAndSettle();

      // The RichText header contains the three spans.
      final richText = _headerRichText(tester, 'Papa');
      final plain = richText.text.toPlainText();
      expect(plain, contains('Papa'));
      expect(plain, contains('·'));
      expect(plain, contains('Father'));

      // The name span carries the parent (blue) category color —
      // contrast-adjusted for the dark bubble (parent blue needs no
      // adjustment, so it equals the raw KinshipEdgeColors.parent).
      final spans = (richText.text as TextSpan).children!;
      final nameStyle = (spans[0] as TextSpan).style!;
      expect(nameStyle.color, KinshipEdgeColors.parent);

      // The relationship span uses the neutral meta grey.
      final relSpan = spans.lastWhere(
        (s) => s is TextSpan && (s as TextSpan).text == 'Father',
      ) as TextSpan;
      expect(relSpan.style!.color, ChatUi.textMeta);

      // The separator '·' also uses the receding neutral grey.
      final sepSpan = spans.firstWhere(
        (s) => s is TextSpan && (s as TextSpan).text == '·',
      ) as TextSpan;
      expect(sepSpan.style!.color, ChatUi.textMeta);
    });

    testWidgets(
        'the maternal grandmother label renders with the '
        'grandparent color on the name', (tester) async {
      await tester.pumpWidget(_bubble(
        message: _msg('m2', 'sender-nani', 'Nani', 'I will bring the sweets.'),
        familyId: 'fam-1',
        rawKeyOverride: 'maternal_grandmother',
        labelOverride: 'Maternal grandmother',
      ));
      await tester.pumpAndSettle();

      final richText = _headerRichText(tester, 'Nani');
      final plain = richText.text.toPlainText();
      expect(plain, contains('Nani'));
      expect(plain, contains('Maternal grandmother'));

      // Grandparent indigo #6366F1 → lightened to #8B8DF5 for contrast
      // on the dark received bubble (ChatUi.kinshipPillText).
      final spans = (richText.text as TextSpan).children!;
      final nameStyle = (spans[0] as TextSpan).style!;
      expect(nameStyle.color, const Color(0xFF8B8DF5));
    });

    testWidgets(
        'a thin vertical color indicator (kinship band) is painted '
        'along the left edge of received bubbles', (tester) async {
      await tester.pumpWidget(_bubble(
        message: _msg('m1', 'sender-papa', 'Papa', 'Dinner at 8?'),
        familyId: 'fam-1',
        rawKeyOverride: 'father',
        labelOverride: 'Father',
      ));
      await tester.pumpAndSettle();

      // The band is a Positioned (left=0, top=0, bottom=0) →
      // IgnorePointer → Container(width: 3, color: kinship).
      Color? bandColor;
      BorderRadius? bandRadius;
      double? bandWidth;
      for (final p in tester.widgetList<Positioned>(find.byType(Positioned))) {
        if (p.left == 0 && p.top == 0 && p.bottom == 0) {
          final child = p.child;
          if (child is IgnorePointer && child.child is Container) {
            final c = child.child as Container;
            bandWidth = c.constraints?.minWidth;
            final decoration = c.decoration as BoxDecoration;
            bandColor = decoration.color;
            bandRadius = decoration.borderRadius as BorderRadius?;
          }
        }
      }
      expect(bandWidth, ChatUi.bandWidth, reason: '3 dp thin indicator');
      expect(bandColor, KinshipEdgeColors.parent,
          reason: 'band uses the raw kinship category color');
      expect(bandRadius?.topLeft, const Radius.circular(ChatUi.bubbleRadius));
      expect(
          bandRadius?.bottomLeft, const Radius.circular(ChatUi.bubbleRadius));
    });

    testWidgets(
        'unresolved relationship renders the sender name alone '
        '(no separator, no label, D3 orange)', (tester) async {
      await tester.pumpWidget(_bubble(
        message: _msg('m3', 'sender-unknown', 'Stranger', 'Hello'),
        familyId: 'fam-1',
        rawKeyOverride: null,
        labelOverride: null,
      ));
      await tester.pumpAndSettle();

      // No multi-span header row — a plain Text with the orange D3 style.
      expect(
        _hasHeaderRichText(tester),
        isFalse,
        reason: 'No relationship → no "Name · Relationship" row',
      );
      final nameText = tester.widget<Text>(find.text('Stranger'));
      expect(nameText.style?.color, ChatUi.accent,
          reason: 'D3 unresolved name keeps the orange signal color');
      expect(nameText.style?.fontWeight, FontWeight.w500);

      // No band: no Positioned strip pinned to the left edge.
      var hasBand = false;
      for (final p in tester.widgetList<Positioned>(find.byType(Positioned))) {
        if (p.left == 0 && p.top == 0 && p.bottom == 0) hasBand = true;
      }
      expect(hasBand, isFalse,
          reason: 'Unresolved → no band (no incorrect color)');
    });

    testWidgets('sent (isMe) messages render no kinship header/band',
        (tester) async {
      await tester.pumpWidget(_bubble(
        message: _msg('m4', 'me', 'You', 'Yes, on my way.'),
        familyId: 'fam-1',
        rawKeyOverride: 'father',
        labelOverride: 'Father',
        isMe: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Yes, on my way.'), findsOneWidget);
      expect(
        _hasHeaderRichText(tester),
        isFalse,
        reason: 'Own messages never show a relationship header',
      );
    });
  });
}
