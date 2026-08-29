// lib/features/games/sos/sos_reconnecting_banner.dart
//
// SOS Game — non-blocking banner shown above the lobby / board when the
// Supabase Realtime channel is not in a healthy state.
//
// Three visual modes, driven by [SosConnectionStatus]:
//
//   idle / connected → banner is invisible (SizedBox.shrink).
//   connecting       → thin amber strip with a spinner + "Connecting to room…".
//   reconnecting     → thin amber strip with a spinner + "Reconnecting…".
//                      Non-blocking — the SDK is auto-retrying; the user
//                      can keep using the UI (lobby chat, share code, etc.).
//   error            → full-width red strip with "Connection lost" + a
//                      "Retry" button. Tapping Retry calls back into the
//                      notifier's retryConnection() method.
//
// The banner never shows raw socket / Postgres errors — those are mapped
// to friendly strings by friendlySosError() in sos_connection_status.dart.

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import 'sos_connection_status.dart';

class SosReconnectingBanner extends StatelessWidget {
  const SosReconnectingBanner({
    super.key,
    required this.status,
    required this.friendlyError,
    required this.onRetry,
  });

  final SosConnectionStatus status;
  final String? friendlyError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final label = connectionStatusLabel(status);
    if (label == null) {
      return const SizedBox.shrink();
    }

    final isError = status == SosConnectionStatus.error;
    final bgColor = isError
        ? const Color(0xFFEF4444).withValues(alpha: 0.15)
        : KinrelColors.orange.withValues(alpha: 0.12);
    final accentColor = isError
        ? const Color(0xFFEF4444)
        : KinrelColors.orange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: accentColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (!isError)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(accentColor),
              ),
            )
          else
            Icon(Icons.cloud_off, size: 16, color: accentColor),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                if (isError && friendlyError != null && friendlyError != label)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      friendlyError!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isError)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.sm,
                  vertical: 0,
                ),
                minimumSize: const Size(44, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
