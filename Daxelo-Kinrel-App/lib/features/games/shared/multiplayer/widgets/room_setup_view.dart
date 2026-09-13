// lib/features/games/shared/multiplayer/widgets/room_setup_view.dart
//
// Shared "Create Room" setup view for every multiplayer game. Renders:
//   • Spectator toggle (Allow spectators)
//   • Auto-close duration selector (3 / 5 / 10 / 15 minutes)
//   • Game-specific setup fields (passed as a child widget)
//   • Create Game button
//
// Per the spec:
//   • Spectator toggle lets the host opt-in (default) or opt-out of
//     spectator access for the room.
//   • Auto-close timer is set at create time and is server-authoritative.
//
// Each game's lobby screen renders its own setup view using this widget
// as a scaffold, passing the game-specific mode selector + rules card
// as the `child` parameter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../shared/widgets/dk_components.dart';
import '../../widgets/spectator_toggle.dart';
import '../room_controller.dart';

/// Auto-close duration choices offered to the host.
class AutoCloseDuration {
  const AutoCloseDuration({required this.minutes, required this.label});
  final int minutes;
  final String label;
}

const _durations = [
  AutoCloseDuration(minutes: 3, label: '3 min'),
  AutoCloseDuration(minutes: 5, label: '5 min'),
  AutoCloseDuration(minutes: 10, label: '10 min'),
  AutoCloseDuration(minutes: 15, label: '15 min'),
];

class RoomSetupView extends ConsumerStatefulWidget {
  const RoomSetupView({
    super.key,
    required this.roomKey,
    required this.createGame,
    required this.createButtonLabel,
    required this.child,
    this.defaultAutoCloseMinutes,
  });

  /// The room key (config + familyId) used to create the controller.
  final RoomControllerKey roomKey;

  /// Called when the user taps "Create Game". Should perform any
  /// game-specific setup (e.g. compute the SOS mode) and return a
  /// Map of game-specific fields to write into the game row.
  /// Returns null to cancel creation.
  final Future<Map<String, dynamic>?> Function() createGame;

  /// Label for the create button (e.g. 'Create Game', 'Start Bingo').
  final String createButtonLabel;

  /// Game-specific setup fields (mode selector, rules card, etc.).
  final Widget child;

  /// If set, overrides the config's default auto-close duration.
  final int? defaultAutoCloseMinutes;

  @override
  ConsumerState<RoomSetupView> createState() => _RoomSetupViewState();
}

class _RoomSetupViewState extends ConsumerState<RoomSetupView> {
  bool _spectatorsEnabled = true;
  int _autoCloseMinutes = 5;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _autoCloseMinutes = widget.defaultAutoCloseMinutes ??
        widget.roomKey.config.defaultAutoCloseMinutes;
  }

  Future<void> _handleCreate() async {
    setState(() => _creating = true);
    try {
      final gameFields = await widget.createGame();
      if (gameFields == null) {
        // Cancelled by the game's callback
        return;
      }
      await ref.read(roomControllerProvider(widget.roomKey).notifier).createRoom(
            gameSpecificFields: gameFields,
            spectatorsEnabled: _spectatorsEnabled,
            autoCloseMinutes: _autoCloseMinutes,
          );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        // Game-specific setup fields
        widget.child,
        const SizedBox(height: KinrelSpacing.lg),

        // Spectator toggle
        SpectatorToggle(
          value: _spectatorsEnabled,
          onChanged: (v) => setState(() => _spectatorsEnabled = v),
        ),
        const SizedBox(height: KinrelSpacing.md),

        // Auto-close duration selector
        _sectionLabel('Auto-close room after'),
        const SizedBox(height: KinrelSpacing.sm),
        Wrap(
          spacing: KinrelSpacing.sm,
          runSpacing: KinrelSpacing.sm,
          children: _durations.map((d) {
            final selected = d.minutes == _autoCloseMinutes;
            return GestureDetector(
              onTap: () => setState(() => _autoCloseMinutes = d.minutes),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: KinrelSpacing.sm, horizontal: KinrelSpacing.md),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.lg),
                  border: Border.all(
                    color: selected ? KinrelColors.orange : KinrelColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Text(
                  d.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? KinrelColors.orange : KinrelColors.textDim,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: KinrelSpacing.xl),

        // Create button
        DKButton(
          label: widget.createButtonLabel,
          variant: DKButtonVariant.gradient,
          fullWidth: true,
          isLoading: _creating,
          onPressed: _handleCreate,
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textDim,
          letterSpacing: 0.5,
        ),
      );
}
