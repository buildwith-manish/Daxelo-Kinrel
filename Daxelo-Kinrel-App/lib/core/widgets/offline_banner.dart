// lib/core/widgets/offline_banner.dart
//
// DAXELO KINREL — Offline Banner
//
// A slim banner that appears at the top of the screen when the device
// is offline AND at least one network request has failed in the last
// 30 seconds.
//
// Requirements:
// - Max height 28px, animated show/hide
// - Shows ONLY when connectivity == none AND recent request failure exists
// - Hides with slide-up animation when reconnected
// - Text: "No internet connection" — small font, centered
// - Color from app theme error color (Theme.of(context))
// - No icons, no buttons, no close button

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/sync/connectivity_service.dart';
import '../utils/accessibility_utils.dart';

// ---------------------------------------------------------------------------
// Provider — tracks recent network request failures
// ---------------------------------------------------------------------------

/// Tracks the timestamp of the most recent network request failure.
///
/// Updated by [ConnectivityInterceptor] in `dio_client.dart` when a
/// connection error is detected. The [OfflineBanner] reads this to
/// determine whether a failure occurred within the last 30 seconds.
final recentRequestFailureProvider = StateProvider<DateTime?>((ref) => null);

// ---------------------------------------------------------------------------
// OfflineBanner widget
// ---------------------------------------------------------------------------

/// A slim AnimatedContainer banner (max height 28px) that appears at the
/// top of the screen when the device is offline and at least one network
/// request has failed in the last 30 seconds.
///
/// Integration: placed inside the `MaterialApp.builder` callback as a
/// persistent overlay using a Column wrapper. Does NOT alter any
/// existing screen's Scaffold.
///
/// Wrapped in ErrorBoundary so that if connectivity providers fail,
/// the banner silently disappears instead of crashing the app.
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    // Periodically re-evaluate whether the 30-second failure window
    // has expired, so the banner hides automatically after 30s even
    // if no new provider state change occurs.
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      try {
        final lastFailure = ref.read(recentRequestFailureProvider);
        if (lastFailure != null &&
            DateTime.now().difference(lastFailure).inSeconds >= 30) {
          // Force a rebuild so the banner hides
          setState(() {});
        }
      } catch (_) {
        // Provider may not be ready — ignore
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isOnline = true;
    DateTime? lastFailure;

    // Safely read providers — if they throw (e.g., Supabase not ready),
    // default to online = true so the banner doesn't show.
    try {
      isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
      lastFailure = ref.watch(recentRequestFailureProvider);
    } catch (_) {
      isOnline = true;
    }

    final show = !isOnline &&
        lastFailure != null &&
        DateTime.now().difference(lastFailure).inSeconds < 30;

    // AnimatedContainer provides the slide-up/down animation:
    // - When `show` is true: height animates to 28px (banner slides in)
    // - When `show` is false: height animates to 0 (banner slides up out)
    // ClipRect ensures the text is clipped during the transition,
    // creating a smooth slide-up visual effect.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: show ? 28.0 : 0.0,
      child: ClipRect(
        child: semanticLiveRegion(
          assertive: true,
          child: Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.error,
            alignment: Alignment.center,
            child: Text(
              'No internet connection',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onError,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
