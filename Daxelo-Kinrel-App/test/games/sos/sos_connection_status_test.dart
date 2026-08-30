// Tests for the SOS connection status state machine + friendly error mapping.
//
// These tests cover the new multiplayer-flow work added in PR #58:
//   - SosConnectionStatus enum + connectionStatusLabel
//   - friendlySosError mapping (raw exception → user-safe string)
//   - SosState preserves connectionStatus + friendlyError across copyWith
//
// The provider's _onChannelStatus callback is private, but its effects are
// observable through SosState fields — the integration test below exercises
// the state transitions by constructing SosState directly the same way the
// notifier does.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/sos/sos_connection_status.dart';
import 'package:kinrel/features/games/sos/sos_models.dart';
import 'package:kinrel/features/games/sos/sos_provider.dart';

void main() {
  group('connectionStatusLabel', () {
    test('returns null for idle (no banner needed)', () {
      expect(connectionStatusLabel(SosConnectionStatus.idle), isNull);
    });

    test('returns null for connected (no banner needed)', () {
      expect(connectionStatusLabel(SosConnectionStatus.connected), isNull);
    });

    test('returns "Connecting to room…" for connecting', () {
      expect(
        connectionStatusLabel(SosConnectionStatus.connecting),
        'Connecting to room…',
      );
    });

    test('returns "Reconnecting…" for reconnecting', () {
      expect(
        connectionStatusLabel(SosConnectionStatus.reconnecting),
        'Reconnecting…',
      );
    });

    test('returns "Connection lost" for error', () {
      expect(
        connectionStatusLabel(SosConnectionStatus.error),
        'Connection lost',
      );
    });
  });

  group('friendlySosError', () {
    test('returns null for null input', () {
      expect(friendlySosError(null), isNull);
    });

    test('maps "Not signed in" to a sign-in prompt', () {
      final result = friendlySosError('Not signed in')!;
      expect(result, contains('sign in'));
      expect(result, anyOf(contains('Sign in'), contains('sign in')));
      // Must NOT leak any auth internals.
      expect(result, isNot(contains('JWT')));
      expect(result, isNot(contains('AuthException')));
    });

    test('maps SocketException to a connection error message', () {
      final result = friendlySosError(
        'SocketException: Failed host lookup: \'promxswvsnvilplmrtsj.supabase.co\'',
      )!;
      expect(result, anyOf(contains('connection'), contains('connection')));
      expect(result, isNot(contains('SocketException')));
      expect(result, isNot(contains('host lookup')));
      expect(result, isNot(contains('supabase.co')));
    });

    test('maps WebSocketException to a friendly connection error', () {
      final result = friendlySosError(
        'WebSocketException: Connection to \'...\' was not upgraded to websocket',
      )!;
      expect(result, isNot(contains('WebSocket')));
      expect(result, isNot(contains('upgraded')));
    });

    test('maps TimeoutException to a friendly connection error', () {
      final result = friendlySosError('TimeoutException after 0:00:30.000000')!;
      expect(result, isNot(contains('TimeoutException')));
      expect(result, isNot(contains('0:00:30')));
    });

    test('maps RLS violation to an access-denied message', () {
      final result = friendlySosError(
        'PostgresException: new row violates row-level security policy for table "sos_games"',
      )!;
      expect(result, contains('access'));
      // Must NOT leak the table name or "RLS" / "policy" jargon.
      expect(result, isNot(contains('sos_games')));
      expect(result, isNot(contains('row-level')));
      expect(result, isNot(contains('policy')));
      expect(result, isNot(contains('Postgres')));
    });

    test('maps "not found" / PGRST116 to a room-gone message', () {
      final result = friendlySosError(
        'PostgrestException(message: JSON object requested, multiple (or no) rows returned, code: PGRST116)',
      )!;
      expect(result, anyOf(contains('no longer'), contains('doesn\'t exist')));
      expect(result, isNot(contains('PGRST116')));
      expect(result, isNot(contains('Postgrest')));
    });

    test('maps "room is full" patterns to a room-full message', () {
      final result = friendlySosError('maximum players reached')!;
      expect(result.toLowerCase(), contains('full'));
    });

    test('maps CHANNEL_ERROR to a retry prompt', () {
      final result = friendlySosError('RealtimeSubscribeError: CHANNEL_ERROR')!;
      expect(result, anyOf(contains('Retry'), contains('try again'), contains('connection')));
      expect(result, isNot(contains('CHANNEL_ERROR')));
      expect(result, isNot(contains('RealtimeSubscribe')));
    });

    test('uses fallback for unknown errors and never leaks raw text', () {
      final result = friendlySosError(
        'SomeWeirdInternalException: stack trace line 1\nline 2',
        fallback: 'Custom fallback message',
      )!;
      expect(result, 'Custom fallback message');
      expect(result, isNot(contains('SomeWeird')));
      expect(result, isNot(contains('stack trace')));
    });

    test('default fallback is generic and safe', () {
      final result = friendlySosError('completely unknown error shape')!;
      expect(result, isNot(contains('completely unknown')));
      expect(result, isNot(contains('error shape')));
    });

    test('handles actual exception objects (not just strings)', () {
      final result = friendlySosError(
        Exception('SocketException: Connection refused'),
      )!;
      expect(result, isNot(contains('SocketException')));
      expect(result, isNot(contains('Exception')));
    });
  });

  group('SosState connectionStatus + friendlyError', () {
    final game = SosGame(
      id: 'g1',
      familyId: 'fam1',
      hostUserId: 'user-me',
      hostUserName: 'Me',
      mode: SosMode.twoPlayer,
      gridSize: 7,
      status: SosGameStatus.lobby,
      currentTurnOrder: 0,
      createdAt: DateTime.now(),
    );

    test('defaults to idle connection status', () {
      const state = SosState();
      expect(state.connectionStatus, SosConnectionStatus.idle);
      expect(state.friendlyError, isNull);
    });

    test('preserves connectionStatus across copyWith when not passed', () {
      final initial = SosState(
        game: game,
        connectionStatus: SosConnectionStatus.reconnecting,
      );
      // Realtime callback updates players — connectionStatus must persist.
      final updated = initial.copyWith(players: const []);
      expect(updated.connectionStatus, SosConnectionStatus.reconnecting);
    });

    test('preserves friendlyError across copyWith when not passed', () {
      final initial = SosState(
        game: game,
        friendlyError: 'Reconnecting…',
      );
      final updated = initial.copyWith(players: const []);
      expect(updated.friendlyError, 'Reconnecting…');
    });

    test('can clear friendlyError via clearFriendlyError', () {
      final initial = SosState(
        game: game,
        friendlyError: 'Connection lost',
      );
      final updated = initial.copyWith(clearFriendlyError: true);
      expect(updated.friendlyError, isNull);
    });

    test('can update connectionStatus via copyWith', () {
      const initial = SosState();
      final updated = initial.copyWith(
        connectionStatus: SosConnectionStatus.connected,
      );
      expect(updated.connectionStatus, SosConnectionStatus.connected);
    });

    test('can set both error + friendlyError together (as notifier._setError does)', () {
      const initial = SosState();
      final updated = initial.copyWith(
        error: 'PostgresException: ...',
        friendlyError: 'Couldn\'t join the room. Tap to try again.',
        connectionStatus: SosConnectionStatus.error,
      );
      expect(updated.error, 'PostgresException: ...');
      expect(updated.friendlyError, 'Couldn\'t join the room. Tap to try again.');
      expect(updated.connectionStatus, SosConnectionStatus.error);
    });
  });

  group('SosReconnectingBanner visibility logic (via connectionStatusLabel)', () {
    // The banner widget itself is a StatelessWidget that renders based on
    // connectionStatusLabel(status). If the label is null, the banner is
    // invisible (SizedBox.shrink). These tests verify the label contract
    // that the banner depends on.

    test('banner is invisible when idle (the default state)', () {
      expect(connectionStatusLabel(SosConnectionStatus.idle), isNull);
    });

    test('banner is invisible when connected (the healthy state)', () {
      expect(connectionStatusLabel(SosConnectionStatus.connected), isNull);
    });

    test('banner is visible when connecting (initial subscribe)', () {
      expect(connectionStatusLabel(SosConnectionStatus.connecting), isNotNull);
    });

    test('banner is visible when reconnecting (transient error, auto-retry)', () {
      expect(connectionStatusLabel(SosConnectionStatus.reconnecting), isNotNull);
    });

    test('banner is visible when error (needs explicit Retry tap)', () {
      expect(connectionStatusLabel(SosConnectionStatus.error), isNotNull);
    });
  });
}
