// lib/features/games/sos/sos_connection_status.dart
//
// SOS Game — connection status tracking + friendly error mapping.
//
// Supabase Realtime channels auto-reconnect under the hood, but the user
// sees nothing during the gap. This module exposes a small state machine
// that the provider updates as the channel transitions between states
// (SUBSCRIBED / CHANNEL_ERROR / TIMED_OUT / CLOSED), and a helper that
// maps raw Postgres / Realtime / network errors into short, friendly
// strings the UI can show without leaking implementation detail.
//
// The goal: "Couldn't reach the room. Tap to try again." instead of
// "PostgresException: relation 'sos_games' does not exist" or
// "WebSocketException: Connection to '...' was not upgraded to websocket".

/// Coarse-grained connection state for the SOS realtime channel.
///
/// The provider owns one of these at a time in [SosState.connectionStatus].
/// The UI reads it to decide whether to show a "Reconnecting…" banner, a
/// full-screen retry sheet, or nothing at all.
enum SosConnectionStatus {
  /// No channel yet — haven't called createGame / joinGame.
  idle,

  /// Channel created, .subscribe() called, waiting for SUBSCRIBED ack.
  connecting,

  /// Channel is SUBSCRIBED — realtime events are flowing.
  connected,

  /// Channel hit CHANNEL_ERROR or TIMED_OUT. Supabase SDK auto-retries
  /// with exponential backoff; we just show a non-blocking banner.
  reconnecting,

  /// Channel hit CLOSED or retry budget exhausted. Needs explicit user
  /// action (tap "Retry") to re-subscribe.
  error,
}

/// Map a raw [error] from Supabase / Postgres / network into a short,
/// user-facing string. Returns null if the error is null.
///
/// Design goals:
///   - Never leak DB table names, SQL fragments, or stack traces.
///   - Never say "socket", "websocket", "Postgres", "RLS", etc.
///   - Always offer an actionable verb: "try again", "wait", "restart".
///   - Keep it short — the UI shows this in a small banner or toast.
String? friendlySosError(Object? error, {String? fallback}) {
  if (error == null) return null;
  final raw = error.toString();

  // Auth / not-signed-in — most common cause of "nothing works".
  if (raw.contains('Not signed in') ||
      raw.contains('AuthException') ||
      raw.contains('JWT') ||
      raw.contains('auth.currentUser')) {
    return 'You need to sign in to play. Restart the app and try again.';
  }

  // Network / connection — covers offline, DNS failure, websocket timeout.
  if (raw.contains('SocketException') ||
      raw.contains('WebSocketException') ||
      raw.contains('HandshakeException') ||
      raw.contains('ClientException') ||
      raw.contains('TimeoutException') ||
      raw.contains('timeout') ||
      raw.contains('timed out') ||
      raw.contains('network') ||
      raw.contains('host lookup failed') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection closed')) {
    return 'Couldn\'t reach the room. Check your connection and try again.';
  }

  // RLS / permission — the user tried to join a game in a family they're
  // not a member of. Don't say "RLS" — say it plainly.
  if (raw.contains('new row violates row-level security') ||
      raw.contains('permission denied') ||
      raw.contains('RLS') ||
      raw.contains('policy')) {
    return 'You don\'t have access to this game room.';
  }

  // Room not found / already deleted.
  if (raw.contains('PGRST116') || // .single() returned 0 rows
      raw.contains('JSON object requested, multiple (or no) rows returned') ||
      raw.contains('does not exist') ||
      raw.contains('not found')) {
    return 'This game room no longer exists.';
  }

  // Room full — the UNIQUE constraint on (gameId, userId) doesn't enforce
  // max players, but the lobby checks state.players.length >= max before
  // letting the next person join. If the user double-taps fast they can
  // race past the check; the server-side insert will still succeed (no
  // max-players constraint at DB level), so this branch is rare. Catch
  // it anyway with a clear message.
  if (raw.contains('maximum players') ||
      raw.contains('room is full') ||
      raw.contains('max_players')) {
    return 'This room is full.';
  }

  // Realtime channel errors — surfaced via the channel status callback,
  // not via thrown exceptions, but defensively mapped here too.
  if (raw.contains('CHANNEL_ERROR') ||
      raw.contains('TIMED_OUT') ||
      raw.contains('RealtimeSubscribeError')) {
    return 'Lost connection to the room. Tap to try again.';
  }

  // Generic fallback — never leak the raw error to the user.
  return fallback ?? 'Something went wrong. Tap to try again.';
}

/// Human-readable label for the [SosConnectionStatus], shown in the
/// non-blocking reconnecting banner. Returns null for [idle] and
/// [connected] (no banner needed).
String? connectionStatusLabel(SosConnectionStatus status) {
  switch (status) {
    case SosConnectionStatus.idle:
      return null;
    case SosConnectionStatus.connecting:
      return 'Connecting to room…';
    case SosConnectionStatus.connected:
      return null;
    case SosConnectionStatus.reconnecting:
      return 'Reconnecting…';
    case SosConnectionStatus.error:
      return 'Connection lost';
  }
}
