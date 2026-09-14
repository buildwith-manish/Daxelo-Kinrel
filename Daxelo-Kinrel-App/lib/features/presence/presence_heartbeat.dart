// lib/features/presence/presence_heartbeat.dart
//
// DAXELO KINREL — App-wide Presence Heartbeat (Task 4)
//
// Marks the signed-in user ONLINE the moment the app boots (or right
// after sign-in) and keeps them online with a 30-second heartbeat
// (fn_update_last_seen(true)). Other family members see the change
// instantly: lastSeenProvider subscribes to UserPresence realtime, and
// every surface that renders an online dot / "last seen" label watches
// it — no refresh needed.
//
// Before this widget, only the family-chat screen updated presence, so
// a member browsing the Games Hub or a lobby appeared OFFLINE to
// everyone else. The heartbeat runs for the whole app lifetime.
//
// Sign-out: the auth listener flips presence offline immediately.
//
// Server-side safety net: a killed tab / lost connection can't run the
// offline call, so the pg_cron job `sweep-stale-user-presence` flips
// offline any presence row whose heartbeat stopped more than 75
// seconds ago (see migration 20260914080000).
//
// Placement: wraps the app root in main.dart's MaterialApp.builder,
// around GameInviteListener.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';
import 'last_seen_provider.dart';

/// Interval between presence heartbeats. The server-side sweeper
/// declares a row offline after 75s without a heartbeat, so 30s leaves
/// comfortable margin for one dropped RPC.
const _kHeartbeatInterval = Duration(seconds: 30);

class PresenceHeartbeat extends ConsumerStatefulWidget {
  const PresenceHeartbeat({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PresenceHeartbeat> createState() =>
      _PresenceHeartbeatState();
}

class _PresenceHeartbeatState extends ConsumerState<PresenceHeartbeat> {
  Timer? _heartbeatTimer;
  StreamSubscription<dynamic>? _authSub;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Post-frame: touching providers (ref.read) inside initState throws
    // during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    if (!mounted) return;
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    // Start immediately when the user is already signed in (session
    // recovered from storage on app boot).
    final user = client.auth.currentUser;
    if (user != null) {
      _start();
    }

    // React to sign-in / sign-out for the whole app lifetime.
    _authSub = client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      switch (data.event) {
        case AuthChangeEvent.signedIn:
          _start();
          break;
        case AuthChangeEvent.signedOut:
          _stop(markOffline: true);
          break;
        default:
          break;
      }
    });
  }

  void _start() {
    if (_started) return;
    _started = true;
    debugPrint('🟢 PresenceHeartbeat: online + 30s heartbeat started');
    _beat(); // immediate first beat
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_kHeartbeatInterval, (_) => _beat());
  }

  Future<void> _beat() async {
    // Read the notifier synchronously; never touch ref after an await.
    final notifier = ref.read(lastSeenProvider.notifier);
    await notifier.updateMyPresence(true);
  }

  void _stop({bool markOffline = false}) {
    _started = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (markOffline) {
      // Capture the notifier synchronously before awaiting.
      final notifier = ref.read(lastSeenProvider.notifier);
      unawaited(notifier.updateMyPresence(false));
      debugPrint('⚪ PresenceHeartbeat: offline (signed out)');
    }
  }

  @override
  void dispose() {
    // The app root never disposes in practice; the auth listener and the
    // server-side sweeper cover teardown for killed sessions.
    _heartbeatTimer?.cancel();
    unawaited(_authSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
