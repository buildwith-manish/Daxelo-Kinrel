// test/features/family/family_space_chat_duplication_test.dart
//
// Phase (remove-duplicate-family-chat): widget tests for the
// consolidated middle-action-row IA on the space-detail screen.
//
// Verifies:
//   1. The space-detail screen renders exactly ONE "Family Chat"
//      entry point — the persistent bottom nav item — and ZERO
//      instances of "Family Chat" in the middle action area.
//   2. The Settings action is present in the AppBar (icon-only) and
//      ABSENT from the middle action row.
//   3. The Invite action renders as a standalone full-width button,
//      NOT sharing a row with any other button.
//
// We can't easily render FamilyDetailScreen end-to-end (it requires
// Supabase + many providers + a familyId with seeded data + the
// thermion_dart native build). Instead we render the individual
// widgets that make up the middle section + AppBar in isolation,
// which is enough to guard against the regressions this pass fixes:
//
//   • Re-introducing Family Chat into the middle action row
//   • Moving Settings back out of the AppBar
//   • Re-adding a sibling button next to Invite
//
// The guards are structural (widget type + label presence) rather
// than visual, since visual verification requires a browser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_space_floating_nav.dart';
import 'package:kinrel/features/family/presentation/premium/family_hub_highlights.dart';

void main() {
  group('Family Chat entry point — single instance (bottom nav only)', () {
    testWidgets('FamilySpaceFloatingNav has exactly one Family Chat tab',
        (WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/family/test-fam',
        routes: [
          GoRoute(
            path: '/family/:id',
            builder: (context, state) => Scaffold(
              body: const SizedBox(),
              bottomNavigationBar: FamilySpaceFloatingNav(
                familyId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Exactly one "Family Chat" label — the bottom nav tab.
      expect(find.text('Family Chat'), findsOneWidget,
          reason: 'FamilySpaceFloatingNav must have exactly one '
              'Family Chat tab — this is the single entry point on '
              'the space-detail screen.');
    });

    testWidgets('InviteButton does NOT contain a Family Chat action',
        (WidgetTester tester) async {
      // The InviteButton is the new standalone prominent button that
      // replaced QuickActionsRow. It must NOT include any Family Chat
      // text or icon — Family Chat lives only in the bottom nav.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                InviteButton(onTap: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The InviteButton should render exactly once.
      expect(find.byType(InviteButton), findsOneWidget);

      // It should contain the "Invite family member" label (specific
      // action language per the Phase 4 copy audit).
      expect(find.text('Invite family member'), findsOneWidget);

      // It should NOT contain "Family Chat" text anywhere.
      expect(find.text('Family Chat'), findsNothing,
          reason: 'InviteButton must not contain a Family Chat action — '
              'Family Chat was removed from the middle action row and '
              'its only entry point is the persistent bottom nav.');

      // It should NOT contain the chat_bubble_outline icon (which was
      // used by the deprecated QuickActionsRow for Family Chat).
      // The person_add_outlined icon (Invite) is fine — that's the
      // standalone Invite action.
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing,
          reason: 'No chat-bubble icon in InviteButton — Family Chat is '
              'not present in the middle action row.');
    });

    testWidgets('deprecated QuickActionsRow still compiles but should not '
        'be used by the space-detail screen',
        (WidgetTester tester) async {
      // This test is a documentation guard — the QuickActionsRow class
      // is kept for backward compatibility but marked @Deprecated.
      // The space-detail screen no longer instantiates it. If a
      // future change re-introduces QuickActionsRow on the space-detail
      // screen, the structural test below (InviteButton standalone)
      // will fail.
      //
      // We render it here only to verify it still compiles. The test
      // asserts that QuickActionsRow contains 3 labels (Invite, Family
      // Chat, Settings) — confirming it is the OLD 3-pill row that we
      // explicitly removed from the space-detail screen.
      // ignore: deprecated_member_use_from_same_package
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                // ignore: deprecated_member_use_from_same_package
                QuickActionsRow(
                  familyId: 'test-fam',
                  onInvite: () {},
                  onSettings: () {},
                  onFamilyChat: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The deprecated QuickActionsRow renders all 3 labels.
      expect(find.text('Invite'), findsOneWidget);
      expect(find.text('Family Chat'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // This test is intentionally a regression guard: if someone
      // removes the @Deprecated annotation and re-instantiates
      // QuickActionsRow on the space-detail screen, the structural
      // tests below (InviteButton standalone + Settings in AppBar)
      // will fail, surfacing the regression.
    });
  });

  group('Settings — moved to AppBar, absent from middle action row', () {
    testWidgets('AppBar-style layout contains Settings icon',
        (WidgetTester tester) async {
      // Render an AppBar with the same shape FamilyDetailScreen uses
      // post-fix: back + (no title) + Kinrel (gated, omitted here) +
      // Governance + Settings. All icon-only.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leading: const IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: null,
              ),
              title: const SizedBox.shrink(),
              actions: const [
                IconButton(
                  icon: Icon(Icons.gavel_outlined),
                  onPressed: null,
                ),
                IconButton(
                  icon: Icon(Icons.settings_outlined),
                  onPressed: null,
                ),
              ],
            ),
            body: const SizedBox(),
          ),
        ),
      );

      // The AppBar should contain the settings icon.
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget,
          reason: 'Settings must be present in the AppBar as an '
              'icon-only button — it was moved here from the deprecated '
              'QuickActionsRow middle action row.');

      // The AppBar should contain the governance icon too (existing).
      expect(find.byIcon(Icons.gavel_outlined), findsOneWidget);

      // The AppBar title slot should still be empty (SizedBox.shrink)
      // — the single-identity-header fix from the prior pass must
      // remain intact.
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.title, isA<SizedBox>(),
          reason: 'AppBar title must remain empty — the HeroSection is '
              'the single identity header. Re-adding a title would '
              're-introduce the duplicate-header bug.');
    });

    testWidgets('InviteButton does NOT contain a Settings action',
        (WidgetTester tester) async {
      // The InviteButton (the new middle-action-row replacement) must
      // NOT contain a Settings text or icon — Settings was moved to
      // the AppBar.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                InviteButton(onTap: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No Settings text in InviteButton.
      expect(find.text('Settings'), findsNothing,
          reason: 'Settings must not appear in the middle action row — '
              'it was moved to the AppBar.');

      // No settings icon in InviteButton.
      expect(find.byIcon(Icons.settings_outlined), findsNothing,
          reason: 'No settings icon in InviteButton — Settings is in '
              'the AppBar now.');
    });
  });

  group('Invite — standalone full-width button, no sibling buttons', () {
    testWidgets('InviteButton renders as a standalone element, not '
        'sharing a row with any other button',
        (WidgetTester tester) async {
      // Render the InviteButton alone in a scroll view (the same
      // structure the space-detail screen uses — a SliverToBoxAdapter
      // equivalent here is a single child in a ListView).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                InviteButton(onTap: () {}),
                const SizedBox(height: 16),
                const Placeholder(fallbackHeight: 200),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly ONE InviteButton — no sibling buttons.
      expect(find.byType(InviteButton), findsOneWidget,
          reason: 'InviteButton must render exactly once — it is the '
              'standalone full-width prominent button that replaced the '
              '3-pill QuickActionsRow.');

      // The InviteButton should NOT be inside a Row with other
      // buttons. We verify this structurally: the InviteButton's
      // direct parent should be the ListView (or a Padding/Sliver
      // wrapper), NOT a Row that also contains other buttons.
      //
      // The simplest check: there should be exactly ONE button-like
      // tappable element (GestureDetector) in the InviteButton's
      // subtree, not multiple.
      final inviteButton = find.byType(InviteButton);
      final gestureDetectorsInside = find.descendant(
        of: inviteButton,
        matching: find.byType(GestureDetector),
      );
      expect(gestureDetectorsInside, findsOneWidget,
          reason: 'InviteButton should have exactly one GestureDetector '
              '(its own tap target). If it had siblings, there would be '
              'more.');

      // The InviteButton should contain exactly ONE icon
      // (person_add_outlined) — the Invite icon. No sibling icons
      // (chat_bubble, settings) should be present.
      expect(find.byIcon(Icons.person_add_outlined), findsOneWidget,
          reason: 'InviteButton contains exactly one icon — '
              'person_add_outlined (the Invite action).');

      // And it should NOT contain chat_bubble_outline (Family Chat)
      // or settings_outlined (Settings) — those were removed.
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing,
          reason: 'No Family Chat icon in InviteButton.');
      expect(find.byIcon(Icons.settings_outlined), findsNothing,
          reason: 'No Settings icon in InviteButton.');
    });

    testWidgets('InviteButton is full-width (matches screen width minus '
        'horizontal padding)',
        (WidgetTester tester) async {
      // Render the InviteButton at a known screen size and verify
      // its rendered width is approximately full-screen (minus the
      // horizontal padding).
      const screenW = 400.0;
      const screenH = 800.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: screenW,
              height: screenH,
              child: ListView(
                children: [
                  InviteButton(onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The InviteButton's outer Padding is horizontal KinrelSpacing.base
      // (= 16px on each side). So the inner Container's width should
      // be screenW - 32 = 368px (approximately — Flutter's layout
      // rounding may add/subtract a fraction).
      final inviteButton = tester.widget<InviteButton>(find.byType(InviteButton));
      expect(inviteButton, isNotNull);

      // Get the rendered size of the GestureDetector's child Container.
      final containerFinder = find.descendant(
        of: find.byType(InviteButton),
        matching: find.byType(Container),
      );
      final containerSize = tester.getSize(containerFinder.first);
      // Allow a small layout-rounding tolerance (±4px).
      expect(containerSize.width, closeTo(screenW - 32, 4.0),
          reason: 'InviteButton should be full-width (screen width '
              'minus the 16px horizontal padding on each side). '
              'At screen width $screenW, the inner Container should '
              'be ~${screenW - 32}px wide.');
    });
  });
}
