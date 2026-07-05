// lib/features/games/shared/widgets/spectator_toggle.dart
//
// Toggle switch shown in the game-creation setup view of every lobby.
// Lets the host opt-in (default) or opt-out of spectator access for the
// room they're about to create. The chosen value is written to the
// `spectatorsEnabled` column on the game row at INSERT time.
//
// Usage:
//   SpectatorToggle(
//     value: _spectatorsEnabled,
//     onChanged: (v) => setState(() => _spectatorsEnabled = v),
//   )

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

class SpectatorToggle extends StatelessWidget {
  const SpectatorToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              color: KinrelColors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow spectators',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Family members can watch read-only'
                      : 'Only players in this room can see the game',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: KinrelColors.orange,
          ),
        ],
      ),
    );
  }
}
