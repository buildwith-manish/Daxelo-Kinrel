// lib/features/cameo/presentation/widgets/cameo_fallback_config.dart
//
// KINREL CAMEO — CameoFallbackConfig
//
// A small immutable config that [CachedAvatar] and [InitialsAvatar]
// accept optionally. When the photo URL is null/empty AND this config
// is provided, the avatar renders a [CameoAvatar] instead of the
// legacy person-icon fallback.
//
// This is the SAFE wiring point between the existing photo-avatar
// system and the new Cameo visual identity. Existing call sites are
// 100% preserved — they simply don't pass this config and get the
// legacy behavior.

import 'package:flutter/foundation.dart';
import '../../style/cameo_shape_language.dart';

/// Configuration for the Kinrel Cameo fallback on [CachedAvatar].
///
/// Pass this to [CachedAvatar.cameoFallback] (or [InitialsAvatar.cameoFallback])
/// to opt that avatar into the Kinrel Cameo visual identity when no
/// photo URL is available.
@immutable
class CameoFallbackConfig {
  const CameoFallbackConfig({
    required this.personName,
    required this.ageBand,
    required this.skinToneIndex,
    this.surfaceId = 'profile_hero',
    this.expressionId,
    this.poseId,
    this.memorialAtmosphere,
    this.familyEventId,
    this.relationshipLabel,
    this.isDeceased = false,
    this.enableAnimation = true,
  });

  /// The display name of the person. Used for the semantic label and
  /// the monogram fallback.
  final String personName;

  /// The person's age band. Drives shape, pose, hair greying, skin aging.
  final CameoAgeBand ageBand;

  /// 1–10 (CameoColorPalette.skinTone).
  final int skinToneIndex;

  /// Which surface this avatar is rendered on. Default: 'profile_hero'.
  final String surfaceId;

  final String? expressionId;
  final String? poseId;
  final String? memorialAtmosphere;
  final String? familyEventId;
  final String? relationshipLabel;
  final bool isDeceased;
  final bool enableAnimation;
}
