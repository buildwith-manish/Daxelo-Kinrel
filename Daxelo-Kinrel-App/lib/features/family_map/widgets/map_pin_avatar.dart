// lib/features/family_map/widgets/map_pin_avatar.dart
//
// DAXELO KINREL — Map Pin Avatar Widget.
//
// A 44×44 circular avatar used as a map marker pin. Shows a
// [CachedAvatar] with an orange border, or initials on a dark-card
// background when no photo is available.
//
// Extracted from `family_map_screen.dart` (originally the private
// `_MapPinAvatar` widget) as part of the file decomposition. The
// public class is named [MapPinAvatar].

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../providers/family_map_provider.dart';
import 'map_initials.dart';

/// A 44×44 circular avatar used as a map marker pin.
///
/// Shows [CachedAvatar] with an orange border, or initials on
/// [KinrelColors.darkCard] background when no photo is available.
class MapPinAvatar extends StatelessWidget {
  const MapPinAvatar({super.key, required this.pin});

  final MapPin pin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: KinrelColors.orange,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: pin.photoUrl != null && pin.photoUrl!.isNotEmpty
            ? CachedAvatar(
                imageUrl: pin.photoUrl,
                radius: 20,
                backgroundColor: KinrelColors.darkCard,
              )
            : Container(
                color: KinrelColors.darkCard,
                child: Center(
                  child: Text(
                    initials(pin.name),
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.orange,
                      height: 1,
                    ),
                  ),
                ),
              ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms)
        .scale(
          begin: const Offset(0.6, 0.6),
          end: const Offset(1.0, 1.0),
          duration: 300.ms,
          curve: Curves.easeOutBack,
        );
  }
}
