// lib/features/family_map/widgets/map_initials.dart
//
// DAXELO KINREL — Shared initials helper for map widgets.
//
// Generates initials from a person's display name. Used by the pin
// avatar marker, the legend's unpinned sheet, and the various map
// bottom sheets.
//
// Previously a file-private `_initials` function inside
// `family_map_screen.dart`. Promoted to a public helper so the
// extracted widgets can share the same implementation without
// duplicating it.

/// Generates initials from a name for avatar display.
///
/// Returns `'?'` for empty names. For two+ word names, returns the
/// first letter of the first two words (uppercased). For single-word
/// names, returns the first letter (uppercased).
String initials(String name) {
  if (name.isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return parts[0][0].toUpperCase();
}
