// lib/features/aura/widgets/role_glyph_badge.dart
//
// AURA — Role Glyph Badge (Phase 12).
//
// A small badge that gets dropped onto a member's avatar to show their
// AURA role (root / anchor / bridge / weaver / leaf / twin_node).
//
// The badge is intentionally tiny (16px) and uses only the role's glyph
// color + a single-letter label, so it works on avatars of any size
// without crowding them. Used in the family graph node, the member list,
// and the profile sheet.
//
// Privacy note (Phase 19.1): the badge reveals only the member's role
// within the family graph (root/anchor/etc), not raw graph metrics like
// betweenness centrality or degree count. Safe to display on shared
// family views.

import 'package:flutter/material.dart';

import '../data/archetype_strings.dart';
import '../data/aura_model.dart';

/// A small badge showing a member's AURA role.
///
/// Drop this on top of a member avatar (e.g. as the bottom-right child
/// of a Stack) to surface their role within the family graph. The badge
/// is sized to ~18px so it doesn't crowd the avatar.
class RoleGlyphBadge extends StatelessWidget {
  const RoleGlyphBadge({
    super.key,
    required this.role,
    this.size = 18,
    this.showLabel = false,
  });

  /// The role glyph to render. Pass `null` (via [RoleGlyphBadge.none])
  /// if AURA hasn't been computed yet — the badge renders nothing.
  final RoleGlyph? role;

  /// Diameter of the badge circle.
  final double size;

  /// If true, render the role name to the right of the badge instead of
  /// inside it. Used in the role legend / list views.
  final bool showLabel;

  /// Returns an empty badge (renders nothing) — convenience for callers
  /// that don't yet have a role.
  const RoleGlyphBadge.none({super.key})
      : role = null,
        size = 18,
        showLabel = false;

  @override
  Widget build(BuildContext context) {
    if (role == null) return const SizedBox.shrink();
    final r = role!;
    final color = _parseColor(r.glyphColorHex);
    final label = roleLabel(r.roleKey);

    if (showLabel) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BadgeDot(color: color, glyphChar: _glyphChar(r.roleKey), size: size),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
    }
    return _BadgeDot(
      color: color,
      glyphChar: _glyphChar(r.roleKey),
      size: size,
    );
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot({
    required this.color,
    required this.glyphChar,
    required this.size,
  });

  final Color color;
  final String glyphChar;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 3,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Center(
        child: Text(
          glyphChar,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.55,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Pick a single-character glyph for each role. Kept short so it fits
/// inside the small badge circle.
String _glyphChar(String roleKey) {
  switch (roleKey) {
    case 'root':
      return 'R';
    case 'anchor':
      return 'A';
    case 'bridge':
      return 'B';
    case 'weaver':
      return 'W';
    case 'leaf':
      return 'L';
    case 'twin_node':
      return 'T';
    default:
      return '?';
  }
}

Color _parseColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final value = int.tryParse('FF$h', radix: 16);
    if (value != null) return Color(value);
  }
  return const Color(0xFFC8853A);
}
