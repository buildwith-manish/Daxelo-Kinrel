// lib/features/chat/presentation/widgets/thread_markers.dart
//
// DAXELO KINREL — v143 Signature §D (date marker) + §E (unread marker)
//
// ThreadDateMarker: a compact rounded pill with the date label.
// UnreadMarker: same pill layout but with orange accent.
//
// v143 redesign: the date separator is now a simple rounded pill
// (no horizontal lines, no decorative dots) matching the reference
// image. The pill uses chatCard background, pillText typography,
// and KinrelRadius.full for fully rounded corners.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../chat_ui_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════
// ThreadDateMarker — §D (date separator pill)
// ═══════════════════════════════════════════════════════════════════════

/// Centered rounded pill with the date label. No horizontal lines,
/// no decorative dots — just a compact, dark navy-blue pill with
/// muted-light text, fully rounded corners, centered horizontally.
/// v143 redesign: replaced the old line+dot+label+dot+line layout
/// with a simple pill matching the reference image.
class ThreadDateMarker extends StatelessWidget {
  const ThreadDateMarker({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        label: label,
        excludeSemantics: false,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: ChatUi.chatCard,
              borderRadius: BorderRadius.circular(KinrelRadius.full),
            ),
            child: Text(
              label,
              style: ChatUi.pillText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// UnreadMarker — §E
// ═══════════════════════════════════════════════════════════════════════

/// Same pill layout as [ThreadDateMarker] but with an orange accent:
/// orange background tint, orange text, orange border. Reads "N new
/// messages" (1 new message for one).
class UnreadMarker extends StatelessWidget {
  const UnreadMarker({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 new message' : '$count new messages';
    return RepaintBoundary(
      child: Semantics(
        label: '$count new messages',
        excludeSemantics: false,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(KinrelRadius.full),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: KinrelColors.orange,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
