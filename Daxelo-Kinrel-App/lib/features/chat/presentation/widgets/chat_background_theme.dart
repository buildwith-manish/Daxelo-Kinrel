// lib/features/chat/presentation/widgets/chat_background_theme.dart
//
// DAXELO KINREL — Premium Chat Background Theme System (v132)
//
// A curated set of conversational atmospheres inspired by Telegram,
// iMessage, and Discord. Each theme defines a soft ambient gradient
// (no harsh color explosions, no neon, no busy patterns) that gives
// the chat space depth and warmth without competing with messages.
//
// Design language:
//   - All themes live in a dark register (the app is dark-first).
//     Light themes would clash with the bubble palette.
//   - Gradients are RADIAL or LINEAR with very low hue variance —
//     the eye should read "softly illuminated from within," not
//     "obvious gradient."
//   - Accent glows are kept at 8-15% alpha so they never overpower
//     message bubbles. Bubbles always remain the primary focus.
//   - Every theme includes a subtle vignette layer to add spatial
//     depth without darkening the readable center region.
//
// A theme can be applied per-chat (each conversation gets its own
// atmosphere) or globally. Persisted via chatWallpaperProvider using
// the chatId key — the value is stored as "theme:<themeId>" so it
// coexists with custom image wallpapers ("data:..." or file paths).

import 'package:flutter/material.dart';

/// A premium chat background atmosphere.
///
/// Each [ChatBackgroundTheme] defines the colors and stops used by the
/// [ChatBackground] widget to render a multi-layer ambient background:
///   1. Base radial gradient (the dominant atmosphere)
///   2. Accent corner glow (a warmer or cooler tint in one corner)
///   3. Vignette overlay (subtle darkening at the very edges)
class ChatBackgroundTheme {
  const ChatBackgroundTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.baseColors,
    required this.accentColor,
    required this.accentAlignment,
    required this.vignetteColor,
  });

  /// Stable identifier persisted in shared_preferences.
  /// Format: "theme:<id>" (e.g. "theme:aurora").
  final String id;

  /// Human-readable name shown in the theme picker.
  final String name;

  /// One-line description for the picker subtitle.
  final String description;

  /// Two or three colors forming the base radial/linear gradient.
  /// Ordered from center-out for radial, top-bottom for linear.
  /// All colors should be dark (luminance < 0.2) to keep messages
  /// readable and the app feeling premium.
  final List<Color> baseColors;

  /// A single warm or cool accent color rendered as a soft corner glow.
  /// Kept at low alpha by the widget (10-15%) so it never overpowers.
  final Color accentColor;

  /// Where the accent glow sits. Top-right feels like a window;
  /// bottom-left feels like reflected light. Varies per theme for
  /// visual variety across the picker.
  final Alignment accentAlignment;

  /// Color used for the edge vignette. Usually a very dark version
  /// of the dominant base color.
  final Color vignetteColor;

  /// Returns true if [value] (a stored wallpaper string) encodes a
  /// theme reference rather than an image path/URI.
  static bool isThemeValue(String? value) {
    return value != null && value.startsWith('theme:');
  }

  /// Parses a stored "theme:<id>" string into a [ChatBackgroundTheme].
  /// Returns [defaultTheme] if the id is unknown or malformed.
  static ChatBackgroundTheme fromStoredValue(String? value) {
    if (!isThemeValue(value)) return defaultTheme;
    final id = value.substring('theme:'.length);
    return allThemes.firstWhere(
      (t) => t.id == id,
      orElse: () => defaultTheme,
    );
  }

  /// The default atmosphere used when no theme and no image wallpaper
  /// is selected. "Midnight" — a deep blue-black with a faint cool
  /// top-right glow suggesting a distant window. Quiet, premium,
  /// universally readable.
  static const ChatBackgroundTheme defaultTheme = ChatBackgroundTheme(
    id: 'midnight',
    name: 'Midnight',
    description: 'Deep blue-black with a soft cool glow',
    baseColors: [
      Color(0xFF16182B), // center — warm dark navy
      Color(0xFF101220), // mid — deeper navy
      Color(0xFF0A0B16), // edge — near-black navy
    ],
    accentColor: Color(0xFF3B4178), // muted indigo glow
    accentAlignment: Alignment.topRight,
    vignetteColor: Color(0xFF06070E),
  );

  /// The full curated catalog. Order = display order in the picker.
  /// Midnight is first because it's the default; the rest are sorted
  /// by mood (cool → warm → dark) for a natural browsing flow.
  static const List<ChatBackgroundTheme> allThemes = [
    midnight,
    aurora,
    ocean,
    forest,
    sunset,
    space,
    luxuryDark,
    twilight,
  ];

  // ── Individual theme definitions ────────────────────────────────

  static const ChatBackgroundTheme midnight = defaultTheme;

  /// Aurora — a faint green-teal wash suggesting northern lights.
  /// Cool, calming, slightly mystical without being theatrical.
  static const ChatBackgroundTheme aurora = ChatBackgroundTheme(
    id: 'aurora',
    name: 'Aurora',
    description: 'Soft teal-green wash like northern lights',
    baseColors: [
      Color(0xFF0E1F1C),
      Color(0xFF0A1816),
      Color(0xFF06100F),
    ],
    accentColor: Color(0xFF2A6B5A),
    accentAlignment: Alignment.topLeft,
    vignetteColor: Color(0xFF040A09),
  );

  /// Ocean — deep navy with a hint of marine blue. Quiet, vast,
  /// professional. Reads as "calm water at night."
  static const ChatBackgroundTheme ocean = ChatBackgroundTheme(
    id: 'ocean',
    name: 'Ocean',
    description: 'Deep marine blue, calm and vast',
    baseColors: [
      Color(0xFF0A1828),
      Color(0xFF07121F),
      Color(0xFF040B14),
    ],
    accentColor: Color(0xFF1F4F7A),
    accentAlignment: Alignment.bottomRight,
    vignetteColor: Color(0xFF02060C),
  );

  /// Forest — warm dark green-brown suggesting deep woodland at dusk.
  /// Earthy, grounded, intimate.
  static const ChatBackgroundTheme forest = ChatBackgroundTheme(
    id: 'forest',
    name: 'Forest',
    description: 'Earthy dark green at woodland dusk',
    baseColors: [
      Color(0xFF15201A),
      Color(0xFF0F1814),
      Color(0xFF08100B),
    ],
    accentColor: Color(0xFF3A5A3E),
    accentAlignment: Alignment.bottomLeft,
    vignetteColor: Color(0xFF040805),
  );

  /// Sunset — warm ember tones suggesting late evening. Pairs
  /// naturally with the app's ember accent without competing.
  static const ChatBackgroundTheme sunset = ChatBackgroundTheme(
    id: 'sunset',
    name: 'Sunset',
    description: 'Warm ember glow of late evening',
    baseColors: [
      Color(0xFF22181A),
      Color(0xFF1A1213),
      Color(0xFF100A0B),
    ],
    accentColor: Color(0xFF8A4530),
    accentAlignment: Alignment.topRight,
    vignetteColor: Color(0xFF080506),
  );

  /// Space — near-black with a faint violet nebula tint. Feels
  /// infinite and quiet. The closest to "pure dark" while still
  /// having personality.
  static const ChatBackgroundTheme space = ChatBackgroundTheme(
    id: 'space',
    name: 'Space',
    description: 'Near-black with a faint violet nebula',
    baseColors: [
      Color(0xFF14121F),
      Color(0xFF0E0C18),
      Color(0xFF070610),
    ],
    accentColor: Color(0xFF4A3868),
    accentAlignment: Alignment.center,
    vignetteColor: Color(0xFF030308),
  );

  /// Luxury Dark — rich near-black with a gold whisper. The most
  /// "premium" feeling theme, pairs with the gold read-receipt.
  static const ChatBackgroundTheme luxuryDark = ChatBackgroundTheme(
    id: 'luxuryDark',
    name: 'Luxury Dark',
    description: 'Rich black with a whisper of gold',
    baseColors: [
      Color(0xFF1A1714),
      Color(0xFF131110),
      Color(0xFF0B0A09),
    ],
    accentColor: Color(0xFF6B5A2E),
    accentAlignment: Alignment.topCenter,
    vignetteColor: Color(0xFF050403),
  );

  /// Twilight — soft purple-grey of dusk. Transitional, calm,
  /// slightly romantic without being saccharine.
  static const ChatBackgroundTheme twilight = ChatBackgroundTheme(
    id: 'twilight',
    name: 'Twilight',
    description: 'Soft purple-grey of approaching dusk',
    baseColors: [
      Color(0xFF1E1A24),
      Color(0xFF16131B),
      Color(0xFF0D0B12),
    ],
    accentColor: Color(0xFF5A4A6B),
    accentAlignment: Alignment.topLeft,
    vignetteColor: Color(0xFF060508),
  );
}
