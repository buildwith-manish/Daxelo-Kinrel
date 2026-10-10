// lib/features/chat/presentation/widgets/send_silently_sheet.dart
//
// DAXELO KINREL — Tier 1 Feature 1.4: Send Without Sound — Sheet
//
// A bottom sheet shown when the user long-presses the send button (or
// picks "Send" from a long-press menu). Offers two choices:
//   • Send normally (default) — high-priority FCM, sound + vibration.
//   • Send silently — low-priority FCM, no sound + no vibration.
//
// The chosen `silent` flag is passed to ChatService.sendMessage via
// the existing chat:sendMessage socket event (the gateway already
// honors the silent field — added in this Tier 1 batch).
//
// UX matches WhatsApp: long-press the send button to reveal the
// silent-send option. Quick tap = normal send.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/theme/kinrel_fx.dart';

/// Shows the send-mode picker. Returns true for "send silently",
/// false for "send normally", or null when the user dismisses.
Future<bool?> showSendSilentlySheet({
  required BuildContext context,
  String? messagePreview,
}) {
  return showModalSheet<bool>(
    context: context,
    builder: (ctx) => const _SendSilentlySheet(),
  );
}

class _SendSilentlySheet extends ConsumerWidget {
  const _SendSilentlySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        12,
        KinrelSpacing.base,
        32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Drag handle ──────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KinrelColors.textSilver.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Title ────────────────────────────────────────────────
          const Text(
            'Send message',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how this message is delivered.',
            style: TextStyle(
              color: KinrelColors.textSilver.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          // ── Send normally ───────────────────────────────────────
          _SendOptionTile(
            icon: Icons.send_rounded,
            iconColor: KinrelColors.orange,
            title: 'Send normally',
            subtitle:
                "The recipient's phone will ring or vibrate based on their settings.",
            onTap: () => Navigator.of(context).pop(false),
          ),
          const Divider(color: KinrelColors.darkElevated, height: 1),
          // ── Send silently ───────────────────────────────────────
          _SendOptionTile(
            icon: Icons.notifications_off_outlined,
            iconColor: KinrelColors.textSilver,
            title: 'Send silently',
            subtitle:
                "Delivered quietly — no sound or vibration. Useful for late-night "
                'messages or when you know the recipient is busy.',
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 8),
          // ── Cancel ──────────────────────────────────────────────
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendOptionTile extends StatelessWidget {
  const _SendOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: KinrelColors.textWhite,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: KinrelColors.textSilver.withOpacity(0.85),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local wrapper around showModalBottomSheet so the call site can stay
/// terse. The Material showModalBottomSheet signature is awkward when
/// returning nullable values from the popped result.
Future<T?> showModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: builder,
  );
}
