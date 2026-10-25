// lib/features/family_map/widgets/location_sharing_toggle.dart
//
// DAXELO KINREL — Location Sharing Toggle
//
// A floating action button on the Family Map that the user taps to
// start (or stop) sharing their live location with their family.
//
// The full opt-in flow:
//   1. User taps the FAB.
//   2. If sharing is currently OFF:
//        a. Show a "Why we need your location" explanation sheet
//           with two buttons: "Share my location" / "Not now".
//        b. On "Share my location": request OS-level permission via
//           [requestLocationPermission].
//           - granted → call [LiveLocationNotifier.setSharing(true)]
//             + capture initial position → broadcast.
//           - denied → show a "Permission denied" sheet with a button
//             to open OS settings.
//           - deniedForever → same as denied, plus instructions.
//           - serviceDisabled → show "Location services are off"
//             sheet with a button to open OS location settings.
//   3. If sharing is currently ON:
//        a. Tap the FAB → confirmation sheet "Stop sharing?" with
//           "Stop sharing" / "Keep sharing" buttons.
//        b. On "Stop sharing": call [setSharing(false)] + stop the
//           broadcast loop.
//
// The FAB's icon + label reflects the current sharing state:
//   OFF  → location_off icon, dim grey
//   ON   → location_on icon, orange + pulsing ring (live indicator)
//
// The widget is a ConsumerWidget so it can read + write the
// [liveLocationProvider] directly. No parent ref plumbing needed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../helpers/distance_helper.dart';
import '../helpers/location_permission_helper.dart';
import '../providers/live_location_provider.dart';

/// Floating action button that toggles the user's family-map live
/// location sharing. Place inside a Stack with the map below.
///
/// On first tap (sharing off), runs the OS permission flow + the
/// friendly opt-in explanation. On subsequent taps (sharing on),
/// shows a confirmation sheet before stopping.
class LocationSharingToggle extends ConsumerWidget {
  const LocationSharingToggle({
    super.key,
    required this.familyId,
    this.viewerPersonId,
    this.onSharingStarted,
    this.onSharingStopped,
  });

  /// The family whose map this toggle lives on. Used to scope the
  /// setSharing DB upsert.
  final String familyId;

  /// The Person.id of the current viewer (their own Person row in
  /// this family). Required for setSharing because the DB row
  /// keys on personId, not userId.
  final String? viewerPersonId;

  /// Callback when sharing was successfully started. The map screen
  /// uses this to kick off the broadcast loop with the user's first
  /// GPS capture.
  final void Function(double lat, double lng)? onSharingStarted;

  /// Callback when sharing was stopped. The map screen uses this to
  /// cancel the broadcast timer.
  final VoidCallback? onSharingStopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveState = ref.watch(liveLocationProvider);
    final isSharing = liveState.isSharing;
    final isPaused = liveState.isPaused;

    // FAB visual state:
    //   OFF          → location_off icon, dim grey background
    //   ON + paused  → location_off icon, dim grey background + "Paused" tooltip
    //   ON + sharing → location_on icon, orange background + pulsing ring
    final effectiveOff = !isSharing || isPaused;

    // Phase A (#1) — wrap the FAB in a GestureDetector so we can detect
    // long-press (FloatingActionButton's own onLongPress parameter is
    // inconsistent across Flutter versions; the wrapper is reliable).
    return GestureDetector(
      onLongPress: (isSharing && !isPaused)
          ? () => _onLongPressForPause(context, ref)
          : null,
      child: FloatingActionButton(
        heroTag: 'family_map_location_toggle_$familyId',
        backgroundColor:
            effectiveOff ? KinrelColors.darkCard : KinrelColors.orange,
        foregroundColor:
            effectiveOff ? KinrelColors.textSilver : Colors.white,
        elevation: effectiveOff ? 2 : 6,
        onPressed: () => _onTap(context, ref, isSharing, isPaused),
        tooltip: isPaused
            ? 'Sharing paused — tap to resume'
            : (isSharing
                ? 'Sharing live — long-press to pause'
                : 'Share my location'),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing ring when sharing — visual indicator that the
            // user's location is being broadcast every 5s.
            if (isSharing && !isPaused)
              SizedBox(
                width: 48,
                height: 48,
                child: CustomPaint(painter: _PulsingRingPainter()),
              ),
            // Phase A (#8) — When driving (status derived from GPS
            // speed), overlay a small car badge on the FAB icon so
            // the user (and any onlookers) can see they're moving.
            if (isSharing && !isPaused && liveState.viewerStatus == MemberStatus.driving)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Icon(
                    Icons.directions_car_rounded,
                    size: 12,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            Icon(
              effectiveOff
                  ? (isPaused ? Icons.pause_circle_outline : Icons.location_off_rounded)
                  : Icons.location_on_rounded,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    bool isCurrentlySharing,
    bool isCurrentlyPaused,
  ) async {
    // If currently paused, a tap resumes sharing immediately.
    if (isCurrentlyPaused) {
      ref.read(liveLocationProvider.notifier).clearPaused();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live location sharing resumed.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (isCurrentlySharing) {
      // Sharing is ON → ask to stop.
      final shouldStop = await _showStopConfirmation(context);
      if (shouldStop != true) return;

      // Capture the last known position so we can pass it to
      // setSharing (which writes isSharing=false + the last lat/lng
      // to the DB so the row state stays consistent).
      final liveState = ref.read(liveLocationProvider);
      final myLoc = viewerPersonId != null
          ? liveState.locations[viewerPersonId!]
          : null;
      final lat = myLoc?.lat ?? 0.0;
      final lng = myLoc?.lng ?? 0.0;
      if (viewerPersonId == null) return;

      await ref.read(liveLocationProvider.notifier).setSharing(
            sharing: false,
            familyId: familyId,
            personId: viewerPersonId!,
            lat: lat,
            lng: lng,
          );
      onSharingStopped?.call();
      return;
    }

    // Sharing is OFF → run the opt-in flow.
    final shouldShare = await _showOptInSheet(context);
    if (shouldShare != true) return;

    // Request OS-level permission.
    final permResult = await requestLocationPermission();
    if (!context.mounted) return;

    switch (permResult) {
      case PermissionResult.granted:
        // Capture initial position to seed the DB row + broadcast.
        final pos = await getCurrentPosition();
        // If context died during the await, abort silently — we can't
        // show UI on a dead context.
        if (!context.mounted) return;
        if (pos == null || viewerPersonId == null) {
          await _showErrorSheet(
            context,
            'Could not get your location',
            'Please make sure location services are on and try again.',
          );
          return;
        }
        await ref.read(liveLocationProvider.notifier).setSharing(
              sharing: true,
              familyId: familyId,
              personId: viewerPersonId!,
              lat: pos.latitude,
              lng: pos.longitude,
            );
        onSharingStarted?.call(pos.latitude, pos.longitude);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live location sharing is now on. '
                'Your family can see where you are on the map.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;
      case PermissionResult.denied:
        if (!context.mounted) return;
        await _showErrorSheet(
          context,
          'Location permission denied',
          'Without location permission, your family can\'t see where '
              'you are. Tap the button below to try again, or enable '
              'location in your device settings.',
          actionLabel: 'Open settings',
          onAction: openLocationSettings,
        );
        break;
      case PermissionResult.deniedForever:
        if (!context.mounted) return;
        await _showErrorSheet(
          context,
          'Location permission permanently denied',
          'You previously denied location permission. To share your '
              'live location with your family, you need to enable it '
              'in your device settings → App permissions → Location → '
              'Allow only while using the app.',
          actionLabel: 'Open settings',
          onAction: openLocationSettings,
        );
        break;
      case PermissionResult.serviceDisabled:
        if (!context.mounted) return;
        await _showErrorSheet(
          context,
          'Location services are off',
          'Your device\'s location services are disabled. Turn them '
              'on in your device settings → Location → On, then come '
              'back here to share your live location with your family.',
        );
        break;
    }
  }

  /// First-time opt-in explanation sheet. Returns true if the user
  /// confirmed they want to share.
  Future<bool?> _showOptInSheet(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (c) => Container(
        decoration: const BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.location_on_rounded,
                      color: KinrelColors.orange, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Share your live location',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Your family will be able to see where you are on the '
                'family map, in real time. This helps with planning '
                'family events, knowing when someone\'s travelling, '
                'and just feeling connected.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 16),
              const _PrivacyBullet(
                icon: Icons.visibility_outlined,
                text: 'Only members of THIS family can see your location.',
              ),
              const SizedBox(height: 10),
              const _PrivacyBullet(
                icon: Icons.timer_outlined,
                text: 'You can turn it off anytime — your last known '
                    'position is removed within seconds.',
              ),
              const SizedBox(height: 10),
              const _PrivacyBullet(
                icon: Icons.battery_charging_full_outlined,
                text: 'Optimized for battery — broadcasts every 5s, '
                    'throttled DB writes every 30s.',
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(c).pop(false),
                      child: const Text(
                        'Not now',
                        style: TextStyle(color: KinrelColors.textSilver),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: KinrelColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(c).pop(true),
                      child: const Text(
                        'Share my location',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Phase A (#1) — Long-press the FAB → pause sheet. Lets the user
  /// temporarily suspend sharing without fully turning it off (so
  /// their settings + DB row stay configured; just no broadcasts +
  /// no GPS captures during the pause).
  ///
  /// Preset durations cover the common cases (1 hour meeting, 4 hour
  /// flight, until-tomorrow good night). When the user taps an option,
  /// the pause is recorded in [LiveLocationState.pausedUntil] and the
  /// broadcast loop's tick becomes a no-op until the timestamp elapses.
  /// A regular tap on the FAB resumes immediately.
  Future<void> _onLongPressForPause(BuildContext context, WidgetRef ref) async {
    final duration = await _showPauseSheet(context);
    if (duration == null) return;

    ref.read(liveLocationProvider.notifier).setPaused(duration);
    if (!context.mounted) return;

    // Human-readable label for the SnackBar.
    final label = duration.inHours == 1
        ? '1 hour'
        : (duration.inHours == 4
            ? '4 hours'
            : 'until tomorrow');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sharing paused $label. Tap the FAB to resume.'),
        duration: const Duration(seconds: 3),
      ),
    );

    // Cancel the broadcast loop immediately (don't wait for the next
    // tick — we want to stop NOW).
    onSharingStopped?.call();
  }

  /// Bottom sheet offering the pause presets. Returns the chosen
  /// Duration (null if dismissed).
  Future<Duration?> _showPauseSheet(BuildContext context) {
    return showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (c) => Container(
        decoration: const BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.pause_circle_outline_rounded,
                      color: KinrelColors.orange, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Pause sharing',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Temporarily stop broadcasting your location. Your '
                'settings stay on — sharing resumes automatically '
                'after the pause, or you can tap the FAB to resume '
                'anytime.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 20),
              _PauseOption(
                icon: Icons.hourglass_bottom_rounded,
                title: '1 hour',
                subtitle: 'Quick meeting, doctor visit, errand',
                onTap: () => Navigator.of(c).pop(const Duration(hours: 1)),
              ),
              _PauseOption(
                icon: Icons.flight_takeoff_rounded,
                title: '4 hours',
                subtitle: 'Flight, transit, work shift',
                onTap: () => Navigator.of(c).pop(const Duration(hours: 4)),
              ),
              _PauseOption(
                icon: Icons.nights_stay_rounded,
                title: 'Until tomorrow',
                subtitle: 'Good night — resumes at this time tomorrow',
                onTap: () => Navigator.of(c).pop(const Duration(hours: 24)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(c).pop(null),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: KinrelColors.textSilver),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Confirmation sheet when the user is already sharing and taps the
  /// FAB to stop.
  Future<bool?> _showStopConfirmation(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (c) => Container(
        decoration: const BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.location_off_rounded,
                      color: KinrelColors.textSilver, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Stop sharing location?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Your family will no longer see your live location on '
                'the map. Your last known position will be cleared '
                'from the family map within seconds.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(c).pop(false),
                      child: const Text(
                        'Keep sharing',
                        style: TextStyle(color: KinrelColors.textSilver),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(c).pop(true),
                      child: const Text(
                        'Stop sharing',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showErrorSheet(
    BuildContext context,
    String title,
    String body, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (c) => Container(
        decoration: const BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Location sharing',
                style: TextStyle(
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 24),
              if (actionLabel != null && onAction != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KinrelColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(c).pop();
                      onAction();
                    },
                    child: Text(actionLabel),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(c).pop(),
                    child: const Text('Got it'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyBullet extends StatelessWidget {
  const _PrivacyBullet({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: KinrelColors.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: KinrelColors.textSilver,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pulses a teal ring around the FAB icon while sharing is active.
/// Indicates to the user (and any onlookers) that the location is
/// being broadcast live.
class _PulsingRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2 - 4;

    // Static ring (always visible while sharing).
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, baseRadius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tappable row in the pause sheet. Shows an icon + title + subtitle.
class _PauseOption extends StatelessWidget {
  const _PauseOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: KinrelColors.orange),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: KinrelColors.textDim,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: KinrelColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
