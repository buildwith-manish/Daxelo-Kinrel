// test/features/games/shared/temporary_lobby_layout_test.dart
//
// Contract test for the shared TemporaryLobbyView waiting-room layout:
//
//   • ONLY the player roster scrolls — the room status card, the
//     Family Members / Invite Family section, the chat dock and the
//     bottom action bar all stay pinned, even in a 30-slot room.
//   • The Family Members section sits directly below the player list:
//     the one-tap FamilyInviteCard (inline member rows + Invite
//     buttons + View All) is always visible without scrolling.
//   • Room full → the card stays in place with a clear "Room is full"
//     state (it never disappears).
//   • Non-host → the card renders read-only (no Invite actions).
//   • The roster preserves actual join order, opens auto-scrolled to
//     the local player's slot, and keeps that row highlighted.
//   • Game extras (footer, e.g. Tug of War's team board) render in a
//     height-bounded dock without hiding the pinned zones.
//   • The chat dock renders collapsed as a slim bar by default and
//     expands in place on tap without pushing pinned zones off screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/shared/widgets/family_invite_card.dart';
import 'package:kinrel/features/games/shared/widgets/temporary_lobby_view.dart';

TemporaryLobbyPlayer _p(
  String id,
  String name, {
  bool isReady = true,
  bool isHost = false,
  DateTime? joinedAt,
}) =>
    TemporaryLobbyPlayer(
      userId: id,
      userName: name,
      isReady: isReady,
      isHost: isHost,
      joinedAt: joinedAt,
    );

TemporaryLobbyConfig _config({
  required List<TemporaryLobbyPlayer> players,
  required String hostId,
  int maxPlayers = 30,
}) =>
    TemporaryLobbyConfig(
      gameTable: 'bingo_games',
      gameId: 'game-1234',
      familyId: 'fam-1',
      hostUserId: hostId,
      players: players,
      maxPlayers: maxPlayers,
      status: TemporaryLobbyStatus.waiting,
    );

/// Eight players who joined one second apart (join order = index).
List<TemporaryLobbyPlayer> _eightPlayers({String hostId = 'u0'}) => [
      for (int i = 0; i < 8; i++)
        _p('u$i', 'Player$i',
            isHost: i == 0, joinedAt: DateTime(2026, 1, 1, 0, 0, i)),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required TemporaryLobbyConfig config,
  String? myUserId,
  VoidCallback? onInviteFamily,
  Widget? footer,
  Size size = const Size(420, 880),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: TemporaryLobbyView(
            config: config,
            myUserId: myUserId,
            onToggleReady: (_) async {},
            onStartMatch: () async {},
            onCancelRoom: () async {},
            onInviteFamily: onInviteFamily,
            footer: footer,
          ),
        ),
      ),
    ),
  );
  // Run post-frame callbacks (roster auto-scroll). Deliberately NOT
  // pumpAndSettle — the lobby's 1-second auto-close countdown timer
  // keeps scheduling frames.
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  testWidgets(
      'only the roster scrolls; invite, chat and actions stay pinned '
      'in a 30-slot room', (tester) async {
    await _pump(
      tester,
      config: _config(players: _eightPlayers(), hostId: 'u0'),
      myUserId: 'u0', // host
    );

    // Exactly ONE scrollable surface: the roster list. The chat dock
    // is collapsed by default and there is no game footer here.
    expect(find.byType(Scrollable), findsOneWidget);
    final roster = find.byType(ListView);
    expect(roster, findsOneWidget);

    // All pinned zones are on screen at the same time.
    expect(find.byType(FamilyInviteCard), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
    expect(find.text('Lobby chat'), findsOneWidget);
    expect(find.text('Start Match'), findsOneWidget);
    expect(find.text('Close Room'), findsOneWidget);

    // The roster really overflows (30 slots x 60px rows).
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));

    // The Family Members section sits BELOW the player list.
    final rosterRect = tester.getRect(roster);
    final inviteRect = tester.getRect(find.byType(FamilyInviteCard));
    expect(inviteRect.top, greaterThanOrEqualTo(rosterRect.bottom - 1));

    // Scroll the player rows hard — every pinned zone stays on screen
    // and fully tappable.
    await tester.drag(roster, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      tester.getRect(find.byType(FamilyInviteCard)).bottom,
      lessThanOrEqualTo(880),
      reason: 'invite card must stay on screen while roster scrolls',
    );
    expect(
      tester.getRect(find.text('Close Room')).bottom,
      lessThanOrEqualTo(880),
      reason: 'action bar must stay on screen while roster scrolls',
    );
    expect(find.text('Lobby chat'), findsOneWidget);
    expect(find.text('Start Match'), findsOneWidget);

    // The invite card header ("View All" opens the full sheet) is
    // still tappable after scrolling — tapping must not throw.
    await tester.tap(find.text('View All'));
    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets('opens auto-scrolled to my slot with context above',
      (tester) async {
    await _pump(
      tester,
      config: _config(players: _eightPlayers(), hostId: 'u0'),
      myUserId: 'u7', // I joined 8th
    );

    expect(find.text("You're #8"), findsOneWidget);
    // My own row is rendered and visible…
    expect(find.text('Player7').hitTestable(), findsOneWidget);
    // …the list is NOT at the top (earlier slots scrolled away)…
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    // …and not at the very end either (open slots still below me).
    expect(scroll.position.pixels,
        lessThan(scroll.position.maxScrollExtent));
    // Slot #1 is off screen — the list opened around MY position.
    expect(find.text('#1').hitTestable(), findsNothing);
  });

  testWidgets('preserves actual join order regardless of input order',
      (tester) async {
    final players = [
      _p('u2', 'Cara', joinedAt: DateTime(2026, 1, 1, 0, 0, 2)),
      _p('u0', 'Manish', isHost: true, joinedAt: DateTime(2026, 1, 1, 0, 0, 0)),
      _p('u1', 'Priya', joinedAt: DateTime(2026, 1, 1, 0, 0, 1)),
    ];
    await _pump(
      tester,
      config: _config(players: players, hostId: 'u0', maxPlayers: 6),
      myUserId: 'u0',
    );

    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);

    // Vertical order matches join order: Manish → Priya → Cara.
    final m = tester.getTopLeft(find.text('Manish')).dy;
    final p = tester.getTopLeft(find.text('Priya')).dy;
    final c = tester.getTopLeft(find.text('Cara')).dy;
    expect(m, lessThan(p));
    expect(p, lessThan(c));
  });

  testWidgets('invite stays visible but disabled when the room is full',
      (tester) async {
    final players = [
      _p('u0', 'Manish', isHost: true, joinedAt: DateTime(2026, 1, 1)),
      _p('u1', 'Priya', joinedAt: DateTime(2026, 1, 1, 0, 0, 1)),
      _p('u2', 'Aarav', joinedAt: DateTime(2026, 1, 1, 0, 0, 2)),
      _p('u3', 'Diya', joinedAt: DateTime(2026, 1, 1, 0, 0, 3)),
    ];
    await _pump(
      tester,
      config: _config(players: players, hostId: 'u0', maxPlayers: 4),
      myUserId: 'u0',
    );

    // The card stays on screen — never hidden when the room is full.
    expect(find.byType(FamilyInviteCard), findsOneWidget);
    expect(find.textContaining('Room is full'), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
  });

  testWidgets('non-host sees the host-only note, not the invite button',
      (tester) async {
    await _pump(
      tester,
      config: _config(players: _eightPlayers(), hostId: 'u0'),
      myUserId: 'u4',
    );

    // The card renders read-only for non-hosts (no invite actions),
    // and the host keeps exclusive control of room actions.
    expect(find.byType(FamilyInviteCard), findsOneWidget);
    expect(find.text('Close Room'), findsNothing);
    expect(find.textContaining('Waiting for host'), findsOneWidget);
    // Roster still present for non-hosts.
    expect(find.text('Players'), findsOneWidget);
  });

  testWidgets('game extras render below the roster without hiding the '
      'pinned zones', (tester) async {
    await _pump(
      tester,
      config: _config(players: _eightPlayers(), hostId: 'u0'),
      myUserId: 'u0',
      footer: Container(
        key: const Key('game-extras'),
        height: 320,
        color: Colors.red,
      ),
    );

    // The extras dock renders (height-bounded)…
    expect(find.byKey(const Key('game-extras')), findsOneWidget);
    final extras = tester.getRect(find.byKey(const Key('game-extras')));
    expect(extras.height, lessThanOrEqualTo(320));

    // …and every pinned zone remains fully on screen.
    expect(find.byType(FamilyInviteCard), findsOneWidget);
    expect(
      tester.getRect(find.byType(FamilyInviteCard)).bottom,
      lessThanOrEqualTo(880),
    );
    expect(
      tester.getRect(find.text('Close Room')).bottom,
      lessThanOrEqualTo(880),
    );
    // Extras sit between roster and the Family Members section.
    final rosterRect = tester.getRect(find.byType(ListView));
    final inviteRect = tester.getRect(find.byType(FamilyInviteCard));
    expect(extras.top, greaterThanOrEqualTo(rosterRect.top));
    expect(extras.bottom, lessThanOrEqualTo(inviteRect.top + 1));
  });

  testWidgets('chat dock is a slim collapsed bar by default and expands '
      'in place on tap', (tester) async {
    await _pump(
      tester,
      config: _config(players: _eightPlayers(), hostId: 'u0'),
      myUserId: 'u0',
    );

    // Collapsed: header only, no message list / input.
    expect(find.text('Lobby chat'), findsOneWidget);
    expect(find.text('Type a message…'), findsNothing);
    final collapsedBottom =
        tester.getRect(find.text('Lobby chat')).bottom;

    // Expand in place.
    await tester.tap(find.text('Lobby chat'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Type a message…'), findsOneWidget);
    final expandedTop = tester.getRect(find.text('Type a message…')).top;
    expect(expandedTop, greaterThan(collapsedBottom - 1),
        reason: 'chat expands BELOW its header, in place');

    // Pinned zones still on screen while chat is expanded.
    expect(find.byType(FamilyInviteCard), findsOneWidget);
    expect(
      tester.getRect(find.byType(FamilyInviteCard)).bottom,
      lessThanOrEqualTo(880),
    );
    expect(
      tester.getRect(find.text('Close Room')).bottom,
      lessThanOrEqualTo(880),
    );
  });

  testWidgets('ready toggle and start button stay pinned for non-hosts',
      (tester) async {
    await _pump(
      tester,
      config: _config(
        players: [
          _p('u0', 'Manish', isHost: true, joinedAt: DateTime(2026, 1, 1)),
          _p('u1', 'Priya', isReady: false,
              joinedAt: DateTime(2026, 1, 1, 0, 0, 1)),
        ],
        hostId: 'u0',
        maxPlayers: 6,
      ),
      myUserId: 'u1',
    );

    expect(find.text("Tap when you're ready"), findsOneWidget);
    expect(find.textContaining('Waiting for host'), findsOneWidget);

    // The controls are pinned and on screen.
    expect(
      tester.getRect(find.text("Tap when you're ready")).bottom,
      lessThanOrEqualTo(880),
    );
  });
}
