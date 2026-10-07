// lib/core/utils/perf_lab_panel.dart
//
// DAXELO KINREL — Hidden Performance Test Lab Panel (PERF_LAB)
//
// The small "LAB" chip pinned to the left edge of the screen and the
// bottom sheet that lets the developer toggle the five PerfLab switches
// (and optionally the on-screen performance overlay) at runtime. The
// chip + sheet are ONLY rendered when [PerfLab.enabled] is true —
// i.e. when the app is built with `--dart-define=PERF_LAB=true`.
//
// In every release build (PERF_LAB off), this file is imported by
// lib/main.dart but its single public widget [PerfLabChip] is wrapped
// in a `if (!PerfLab.enabled) return child;` guard inside MaterialApp's
// builder. The const-false guard means the chip is never constructed,
// the sheet is never shown, and no listener is ever registered —
// matching the strict rule that the app must look and behave exactly
// as on main when PERF_LAB is off.
//
// This file deliberately keeps all UI styling local so the only
// modification to lib/main.dart is the MaterialApp builder (and the
// existing showPerformanceOverlay line).

import 'package:flutter/material.dart';

import 'perf_lab.dart';

/// A small semi-transparent "LAB" chip pinned to the left edge of the
/// screen, visible only when [PerfLab.enabled] is true. Tapping it opens
/// [showPerfLabSheet] — a bottom sheet with the five PerfLab switches, a
/// performance-overlay toggle, and a Reset button.
///
/// The chip is intentionally minimal — a thin black pill aligned to the
/// left edge, vertically centered, with the white text "LAB". It does not
/// intercept any gestures outside its own bounds (it uses
/// [HitTestBehavior.opaque] only on its own rect), so the rest of the
/// app remains fully interactive.
class PerfLabChip extends StatelessWidget {
  const PerfLabChip({
    super.key,
    required this.perfOverlayEnabled,
    required this.onTogglePerfOverlay,
  });

  /// The current runtime state of `MaterialApp.showPerformanceOverlay`.
  /// The bottom sheet uses this to render the perf-overlay switch's
  /// current state.
  final bool perfOverlayEnabled;

  /// Called when the user toggles the perf-overlay switch in the sheet.
  /// The parent ([KinrelApp] state) updates its `_labPerfOverlay` field
  /// via setState so the MaterialApp rebuilds with the new value.
  final ValueChanged<bool> onTogglePerfOverlay;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Only the top inset — the chip is meant to float at the left edge
      // from the very top of the screen, but it shouldn't overlap the
      // status bar on devices that draw under it.
      top: true,
      bottom: false,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _showPerfLabSheet(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              // Rounded only on the right edge so the chip visually
              // "hangs" off the left edge of the screen.
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(8),
              ),
            ),
            child: const Text(
              'LAB',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPerfLabSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF11131A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Performance Lab',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // Reset button — resets all five switches to false
                    // (the default). Does NOT touch the perf-overlay
                    // state (which has its own toggle below) because the
                    // perf-overlay is owned by the parent MaterialApp
                    // state, not by PerfLab.
                    TextButton(
                      onPressed: () {
                        PerfLab.reset();
                        // Force the sheet to rebuild so the switch
                        // tiles reflect the reset values. The
                        // ValueListenableBuilders below will rebuild
                        // automatically because their notifiers changed;
                        // but the sheet itself doesn't need setState
                        // since it has no other state.
                      },
                      child: const Text(
                        'Reset',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2C38), height: 1),

              // ── The five PerfLab switches ──────────────────────────
              _PerfLabSwitchTile(
                notifier: PerfLab.plainBackground,
                title: 'Plain background',
                subtitle: 'Flat solid color (no gradient, wallpaper, blur)',
              ),
              _PerfLabSwitchTile(
                notifier: PerfLab.flatBubbles,
                title: 'Flat bubbles',
                subtitle: 'Solid fill, no shadow/glow/gradient',
              ),
              _PerfLabSwitchTile(
                notifier: PerfLab.plainInviteCards,
                title: 'Plain invite cards',
                subtitle: 'Text-only container (no icon/chips/gradient)',
              ),
              _PerfLabSwitchTile(
                notifier: PerfLab.hideChrome,
                title: 'Hide chrome',
                subtitle: 'Hide header, input bar, family nav',
              ),
              _PerfLabSwitchTile(
                notifier: PerfLab.pauseAnimations,
                title: 'Pause animations',
                subtitle: 'TickerMode(enabled: false) on entire app',
              ),

              const Divider(color: Color(0xFF2A2C38), height: 1),

              // ── Performance overlay toggle ─────────────────────────
              // Lets the user turn the on-screen raster/UI stats
              // overlay on or off at runtime. The parent MaterialApp
              // state owns this value (because MaterialApp reads it as
              // a plain bool from `showPerformanceOverlay`), so toggling
              // it calls back into [onTogglePerfOverlay] which the
              // parent uses to setState.
              SwitchListTile(
                title: const Text(
                  'Performance overlay',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'On-screen raster/UI thread stats',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: perfOverlayEnabled,
                onChanged: onTogglePerfOverlay,
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// A [SwitchListTile] that directly reads/writes a [ValueNotifier<bool>].
/// Local helper so the bottom sheet code stays compact.
class _PerfLabSwitchTile extends StatelessWidget {
  const _PerfLabSwitchTile({
    required this.notifier,
    required this.title,
    required this.subtitle,
  });

  final ValueNotifier<bool> notifier;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, _) {
        return SwitchListTile(
          title: Text(title,
              style: const TextStyle(color: Colors.white)),
          subtitle: Text(subtitle,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12)),
          value: value,
          onChanged: (v) => notifier.value = v,
        );
      },
    );
  }
}
