// lib/graph/widgets/relationship_info_sheet.dart
//
// DAXELO KINREL — Relationship Info Sheet
//
// Bottom sheet shown when the user taps a connection midpoint dot.
// Displays:
//   • Both person avatars (initials + name)
//   • The connection line with the relationship label at midpoint
//   • Two human-readable sentences, one per direction:
//       "[A] is the father of [B]"
//       "[B] is the son of [A]"
//
// The inverse relationship is gender-aware so the label is always
// grammatically correct (e.g. father → son/daughter, not always "son").

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════════════════

class RelationshipInfoSheet {
  RelationshipInfoSheet._();

  /// Show the bottom sheet for a tapped edge.
  static Future<void> show(
    BuildContext context, {
    required String sourceId,
    required String sourceName,
    required String? sourceGender,
    required String targetId,
    required String targetName,
    required String? targetGender,
    required String relationshipKey,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      isScrollControlled: true,
      builder: (_) => _RelationshipInfoContent(
        sourceName: sourceName,
        sourceGender: sourceGender,
        targetName: targetName,
        targetGender: targetGender,
        relationshipKey: relationshipKey,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHEET CONTENT
// ═══════════════════════════════════════════════════════════════════════

class _RelationshipInfoContent extends StatelessWidget {
  const _RelationshipInfoContent({
    required this.sourceName,
    required this.sourceGender,
    required this.targetName,
    required this.targetGender,
    required this.relationshipKey,
  });

  final String sourceName;
  final String? sourceGender;
  final String targetName;
  final String? targetGender;
  final String relationshipKey;

  static const Color _bg = Color(0xFF0F1318);
  static const Color _card = Color(0xFF1A1F2B);
  static const Color _orange = Color(0xFFE8863A);
  static const Color _textWhite = Color(0xFFFFFFFF);
  static const Color _textSilver = Color(0xFF9CA3AF);
  static const Color _divider = Color(0xFF2A3040);

  @override
  Widget build(BuildContext context) {
    final fwd = _formatKey(relationshipKey);
    final inv = _formatKey(_genderAwareInverse(relationshipKey, targetGender));
    final sourceInitials = _initials(sourceName);
    final targetInitials = _initials(targetName);
    final sourceColor = _avatarColor(sourceGender);
    final targetColor = _avatarColor(targetGender);

    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Title ───────────────────────────────────────────────────
          const Text(
            'Connection',
            style: TextStyle(
              color: _textWhite,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 24),

          // ── Avatar connector row ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                // Source avatar
                _PersonAvatar(
                  initials: sourceInitials,
                  name: sourceName,
                  color: sourceColor,
                ),

                // Connector line with dot
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: _ConnectorLine(
                      label: fwd,
                      color: _orange,
                    ),
                  ),
                ),

                // Target avatar
                _PersonAvatar(
                  initials: targetInitials,
                  name: targetName,
                  color: targetColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Divider ──────────────────────────────────────────────────
          Container(height: 1, color: _divider),

          // ── Relationship sentences ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 20,
            ),
            child: Column(
              children: [
                _RelationRow(
                  fromName: sourceName,
                  relation: fwd,
                  toName: targetName,
                  arrowColor: _orange,
                ),
                const SizedBox(height: 12),
                _RelationRow(
                  fromName: targetName,
                  relation: inv,
                  toName: sourceName,
                  arrowColor: _orange.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),

          // ── Safe area bottom ─────────────────────────────────────────
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, math.min(2, parts[0].length)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static Color _avatarColor(String? gender) {
    if (gender == 'female') return const Color(0xFF7B5EA7);
    return const Color(0xFF2A7BB5);
  }

  static String _formatKey(String key) {
    return key
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Returns the inverse relationship key, taking the target's gender
  /// into account for parent/child and sibling types.
  static String _genderAwareInverse(String key, String? targetGender) {
    final isFemale = targetGender == 'female';
    final isMale = targetGender == 'male';

    switch (key) {
      // parent → child uses child's gender
      case 'father':
      case 'mother':
        return isFemale ? 'daughter' : 'son';

      // child → parent uses parent's gender
      case 'son':
      case 'daughter':
        return isFemale ? 'mother' : 'father';

      // sibling
      case 'brother':
        return isFemale ? 'sister' : 'brother';
      case 'sister':
        return isMale ? 'brother' : 'sister';

      // spouse
      case 'husband':
        return 'wife';
      case 'wife':
        return 'husband';
      case 'spouse':
      case 'partner':
        return key;

      // grandparent → grandchild
      case 'grandfather':
      case 'paternal_grandfather':
      case 'maternal_grandfather':
        return isFemale ? 'granddaughter' : 'grandson';
      case 'grandmother':
      case 'paternal_grandmother':
      case 'maternal_grandmother':
        return isFemale ? 'granddaughter' : 'grandson';

      // grandchild → grandparent
      case 'grandson':
      case 'granddaughter':
        return isFemale ? 'grandmother' : 'grandfather';

      // uncle/aunt ↔ nephew/niece
      case 'uncle':
      case 'paternal_uncle':
      case 'maternal_uncle':
        return isFemale ? 'niece' : 'nephew';
      case 'aunt':
      case 'paternal_aunt':
      case 'maternal_aunt':
        return isFemale ? 'niece' : 'nephew';
      case 'nephew':
        return isFemale ? 'aunt' : 'uncle';
      case 'niece':
        return isFemale ? 'aunt' : 'uncle';

      // cousin
      case 'cousin':
        return 'cousin';
      case 'cousin_brother':
        return isFemale ? 'cousin_sister' : 'cousin_brother';
      case 'cousin_sister':
        return isMale ? 'cousin_brother' : 'cousin_sister';

      // in-law
      case 'father_in_law':
        return isFemale ? 'daughter_in_law' : 'son_in_law';
      case 'mother_in_law':
        return isFemale ? 'daughter_in_law' : 'son_in_law';
      case 'son_in_law':
        return isFemale ? 'mother_in_law' : 'father_in_law';
      case 'daughter_in_law':
        return isFemale ? 'mother_in_law' : 'father_in_law';
      case 'brother_in_law':
        return isFemale ? 'sister_in_law' : 'brother_in_law';
      case 'sister_in_law':
        return isMale ? 'brother_in_law' : 'sister_in_law';

      // step-family
      case 'stepfather':
        return isFemale ? 'stepdaughter' : 'stepson';
      case 'stepmother':
        return isFemale ? 'stepdaughter' : 'stepson';
      case 'stepson':
        return isFemale ? 'stepmother' : 'stepfather';
      case 'stepdaughter':
        return isFemale ? 'stepmother' : 'stepfather';
      case 'stepbrother':
        return isFemale ? 'stepsister' : 'stepbrother';
      case 'stepsister':
        return isMale ? 'stepbrother' : 'stepsister';

      // half-sibling
      case 'half_brother':
        return isFemale ? 'half_sister' : 'half_brother';
      case 'half_sister':
        return isMale ? 'half_brother' : 'half_sister';

      default:
        return key;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PERSON AVATAR
// ═══════════════════════════════════════════════════════════════════════

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.initials,
    required this.name,
    required this.color,
  });

  final String initials;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 72,
          child: Text(
            name,
            style: const TextStyle(
              color: _RelationshipInfoContent._textWhite,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CONNECTOR LINE (drawn between the two avatars)
// ═══════════════════════════════════════════════════════════════════════

class _ConnectorLine extends StatelessWidget {
  const _ConnectorLine({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: CustomPaint(
        painter: _ConnectorPainter(label: label, color: color),
      ),
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final midX = size.width / 2;
    final midY = size.height / 2;

    // ── Glow ────────────────────────────────────────────────────────
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(ui.BlurStyle.normal, 6);

    // ── Dashed line ─────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw glow
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), glowPaint);

    // Draw dashed line
    _drawDashed(canvas, Offset(0, midY), Offset(size.width, midY), linePaint);

    // ── Midpoint dot with glow halo ──────────────────────────────────
    final haloPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(midX, midY), 11, haloPaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(midX, midY), 6, dotPaint);

    // Inner white highlight on dot
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(midX - 1.5, midY - 1.5), 2, highlightPaint);
  }

  void _drawDashed(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final total = math.sqrt(dx * dx + dy * dy);
    if (total == 0) return;
    final ux = dx / total;
    final uy = dy / total;
    double covered = 0;
    bool draw = true;
    while (covered < total) {
      final len = draw ? dashLen : gapLen;
      final next = (covered + len).clamp(0.0, total);
      if (draw) {
        canvas.drawLine(
          Offset(start.dx + ux * covered, start.dy + uy * covered),
          Offset(start.dx + ux * next, start.dy + uy * next),
          paint,
        );
      }
      covered = next;
      draw = !draw;
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      label != old.label || color != old.color;
}

// ═══════════════════════════════════════════════════════════════════════
// RELATION ROW
// ═══════════════════════════════════════════════════════════════════════

class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.fromName,
    required this.relation,
    required this.toName,
    required this.arrowColor,
  });

  final String fromName;
  final String relation;
  final String toName;
  final Color arrowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: arrowColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              fromName,
              style: const TextStyle(
                color: _RelationshipInfoContent._textWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 1.5,
                  color: arrowColor.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: arrowColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: arrowColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      relation,
                      style: TextStyle(
                        color: arrowColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // RTL: flip the arrow so the visual flow matches the
                // text direction. In LTR the arrow points forward (→),
                // in RTL it points the other way (←).
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: arrowColor,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              toName,
              style: const TextStyle(
                color: _RelationshipInfoContent._textWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
