// lib/features/games/game_motion_tokens.dart
//
// DAXELO KINREL — Shared animation tokens for all games
//
// Extracted from Ghost Painter so future games (Hot Seat, Relation
// Riddles) can reuse the same polish level. Import this file instead
// of hardcoding curves/durations/haptics.

import 'package:flutter/animation.dart';
import 'package:flutter/services.dart';

class GameMotionTokens {
  GameMotionTokens._();

  // ── Curves ──────────────────────────────────────────────────────
  static const Curve entrance = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve bounce = Curves.elasticOut;
  static const Curve smooth = Curves.easeInOut;

  // ── Durations ───────────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration stagger = Duration(milliseconds: 80);

  // ── Haptics ─────────────────────────────────────────────────────
  static Future<void> tap() => HapticFeedback.lightImpact();
  static Future<void> success() => HapticFeedback.mediumImpact();
  static Future<void> error() => HapticFeedback.selectionClick();
  static Future<void> celebrate() => HapticFeedback.heavyImpact();
}
