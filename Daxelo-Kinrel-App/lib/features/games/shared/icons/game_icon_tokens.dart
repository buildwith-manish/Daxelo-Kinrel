// lib/features/games/shared/icons/game_icon_tokens.dart
//
// Centralized color + style tokens for all game icons.
// Each game has a distinct accent color drawn from Kinrel's extended palette.
// All icons use a single accent color + white for contrast — max 2 colors.

import 'package:flutter/material.dart';

class GameIconTokens {
  GameIconTokens._();

  /// Accent color for each game.
  static const Map<String, Color> colors = {
    'ghost-painter':    Color(0xFFEC4899), // pink
    'freeze-dash':      Color(0xFF10B981), // emerald
    'sos':              Color(0xFFF59E0B), // amber
    'antakshari':       Color(0xFF8B5CF6), // purple
    'bingo':            Color(0xFF06B6D4), // cyan
    'checkers':         Color(0xFF6366F1), // indigo
    'ludo':             Color(0xFFE11D48), // rose
    'carrom':           Color(0xFFF59E0B), // amber (warm wood)
    'chess':            Color(0xFF64748B), // slate
    'chitmatch':        Color(0xFFEC4899), // pink (chit cards)
    'nameplace':        Color(0xFF10B981), // emerald (letter tiles)
    'tictactoe':        Color(0xFF8B5CF6), // purple
    'truthordare':      Color(0xFFEF4444), // red
    'twotruths':        Color(0xFFD946EF), // fuchsia
    'dotsboxes':        Color(0xFF06B6D4), // cyan
    'hot-seat':         Color(0xFFF59E0B), // amber
    'relation-riddles':  Color(0xFF8B5CF6), // purple
    'truth-streak':     Color(0xFFE8612A), // orange (Kinrel brand)
  };

  /// Get the accent color for a game.
  static Color colorFor(String gameId) => colors[gameId] ?? const Color(0xFFE8612A);

  /// Standard icon size for compact horizontal-row cards.
  static const double compactSize = 22.0;

  /// Standard icon size for Games Hub catalog cards.
  static const double catalogSize = 24.0;

  /// Standard icon size for game screen headers.
  static const double headerSize = 32.0;
}
