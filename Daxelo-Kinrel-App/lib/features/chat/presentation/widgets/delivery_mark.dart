// lib/features/chat/presentation/widgets/delivery_mark.dart
//
// DAXELO KINREL — v143 Signature §C
//
// DeliveryMark — a single CustomPainter that replaces the Material
// `Icons.done` (single tick) and `Icons.done_all` (double tick) for
// chat message delivery receipts. The Kinrel visual: connected nodes
// + a linking edge — distinct from WhatsApp's two-tick and Telegram's
// checkmarks.
//
// States (per implementation brief §C):
//   • sending — hollow ring, radius 3, stroke 1.4, centered at (5,5),
//     color textMeta.
//   • sent — filled dot, radius 3, at (5,5), color textMeta.
//   • delivered — filled dot radius 2.6 at (4,5), a 1.2 stroke line
//     from x 6.8 to 10.2 at y 5, hollow ring radius 2.6 stroke 1.4 at
//     (12.4,5), all textMeta.
//   • read — same as delivered but both circles filled and the line,
//     all in orange (KinrelColors.orange).
//
// Bounds: 18 dp wide, 10 dp tall. Right of the time with a 6 dp gap.
// The existing status logic + the failed state in chat_meta.dart's
// ReadReceipt are kept unchanged; only the drawn mark is replaced.
//
// Accessibility:
//   • Semantics labels: "Sending", "Sent", "Delivered", "Read".
//   • The painter is decorative (excluded from semantics) — the
//     Semantics widget wraps the whole DeliveryMark with the label.
//   • State differs by SHAPE (hollow ring → filled dot → dot+line+
//     hollow ring → dot+line+filled dot), not by color alone — passes
//     the "never rely on color alone" rule.
//   • Tap target: the 18x10 painter is wrapped in a 48x48 hit-test
//     area when interactive (handled by the parent — here we just
//     render the painter at size).

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../chat_ui_tokens.dart';

/// The Kinrel delivery-mark states. Maps to the existing
/// `messageStatus` field on ChatMessage but with explicit enum values
/// so the painter can switch exhaustively.
enum DeliveryMarkStatus {
  sending,
  sent,
  delivered,
  read,
}

/// A 18x10 CustomPainter that draws the Kinrel connected-nodes
/// delivery mark for a given [DeliveryMarkStatus].
///
/// Use [DeliveryMark] (the StatelessWidget wrapper) at call sites —
/// it handles Semantics + sizing.
class DeliveryMark extends StatelessWidget {
  const DeliveryMark({
    super.key,
    required this.status,
    this.size = const Size(ChatUi.deliveryMarkWidth, ChatUi.deliveryMarkHeight),
  });

  final DeliveryMarkStatus status;
  final Size size;

  /// Map an existing ChatMessage.messageStatus string to a
  /// DeliveryMarkStatus. Unknown values map to [DeliveryMarkStatus.sent].
  static DeliveryMarkStatus fromString(String? status, {bool isRead = false}) {
    if (status == 'sending') return DeliveryMarkStatus.sending;
    if (isRead || status == 'read') return DeliveryMarkStatus.read;
    if (status == 'delivered') return DeliveryMarkStatus.delivered;
    return DeliveryMarkStatus.sent;
  }

  /// Semantics label for this status — used by callers that want to
  /// wrap the painter in a Semantics widget.
  static String semanticsLabel(DeliveryMarkStatus status) {
    switch (status) {
      case DeliveryMarkStatus.sending:
        return 'Sending';
      case DeliveryMarkStatus.sent:
        return 'Sent';
      case DeliveryMarkStatus.delivered:
        return 'Delivered';
      case DeliveryMarkStatus.read:
        return 'Read';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = status == DeliveryMarkStatus.read
        ? KinrelColors.orange
        : ChatUi.textMeta;
    return Semantics(
      label: semanticsLabel(status),
      excludeSemantics: false,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CustomPaint(
          painter: _DeliveryMarkPainter(status: status, color: color),
          size: size,
        ),
      ),
    );
  }
}

class _DeliveryMarkPainter extends CustomPainter {
  _DeliveryMarkPainter({required this.status, required this.color});

  final DeliveryMarkStatus status;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // All geometry is in the 18x10 coordinate space defined by §C.
    // We don't scale — the parent SizedBox enforces the size.
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (status) {
      case DeliveryMarkStatus.sending:
        // Hollow ring, radius 3, stroke 1.4, centered at (5,5).
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        canvas.drawCircle(const Offset(5, 5), 3, paint);
        break;
      case DeliveryMarkStatus.sent:
        // Filled dot, radius 3, at (5,5).
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(5, 5), 3, paint);
        break;
      case DeliveryMarkStatus.delivered:
        // Filled dot radius 2.6 at (4,5).
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(4, 5), 2.6, paint);
        // 1.2 stroke line from x 6.8 to 10.2 at y 5.
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawLine(
            const Offset(6.8, 5), const Offset(10.2, 5), paint);
        // Hollow ring radius 2.6 stroke 1.4 at (12.4,5).
        paint.strokeWidth = 1.4;
        canvas.drawCircle(const Offset(12.4, 5), 2.6, paint);
        break;
      case DeliveryMarkStatus.read:
        // Same as delivered but both circles FILLED + the line, all orange.
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(4, 5), 2.6, paint);
        // Line.
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawLine(
            const Offset(6.8, 5), const Offset(10.2, 5), paint);
        // Second circle FILLED.
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(12.4, 5), 2.6, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_DeliveryMarkPainter oldDelegate) {
    return oldDelegate.status != status || oldDelegate.color != color;
  }
}
