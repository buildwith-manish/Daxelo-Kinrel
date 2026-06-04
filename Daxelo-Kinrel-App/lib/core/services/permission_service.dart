// lib/core/services/permission_service.dart
//
// DAXELO KINREL — Permission Service (P4-F4: Play Store Compliance)
//
// Centralised permission request handler using permission_handler.
// Every request explains WHY before asking, never crashes on denial,
// and offers a Settings redirect when permanently denied.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/brand_colors.dart';
import '../constants/brand_typography.dart';

/// Result of a permission request.
enum PermissionResult {
  /// Permission was granted.
  granted,

  /// Permission was denied (can ask again).
  denied,

  /// Permission was permanently denied (must go to Settings).
  permanentlyDenied,
}

/// Centralised service for requesting runtime permissions.
///
/// Always explains WHY a permission is needed before requesting it,
/// handles denial gracefully (never crashes), and offers a Settings
/// redirect when the permission is permanently denied.
class PermissionService {
  PermissionService._();

  // ── Camera ────────────────────────────────────────────────────────

  /// Request camera permission.
  ///
  /// Shows an explanatory dialog before the system prompt.
  /// Returns [PermissionResult.granted] if allowed,
  /// [PermissionResult.denied] if the user tapped "Deny",
  /// [PermissionResult.permanentlyDenied] if the user selected
  /// "Don't ask again".
  static Future<PermissionResult> requestCamera(BuildContext context) async {
    return _requestWithRationale(
      context: context,
      permission: Permission.camera,
      title: 'Camera Access',
      reason:
          'KINREL needs camera access so you can take photos of family '
          'members and add them to your family tree.',
    );
  }

  // ── Storage (Photos) ──────────────────────────────────────────────

  /// Request storage / photo permission.
  ///
  /// On Android 13+ this requests READ_MEDIA_IMAGES;
  /// on older Android it requests READ_EXTERNAL_STORAGE.
  static Future<PermissionResult> requestStorage(
      BuildContext context) async {
    final Permission permission;
    if (Platform.isAndroid) {
      // permission_handler automatically maps to the correct
      // permission based on SDK level when using .photos.
      permission = Permission.photos;
    } else {
      permission = Permission.photos;
    }

    return _requestWithRationale(
      context: context,
      permission: permission,
      title: 'Photo Access',
      reason:
          'KINREL needs access to your photos so you can choose a profile '
          'picture or add family photos to your tree.',
    );
  }

  // ── Notifications ─────────────────────────────────────────────────

  /// Request notification permission.
  ///
  /// Should be called after onboarding completes on Android 13+.
  static Future<PermissionResult> requestNotifications(
      BuildContext context) async {
    return _requestWithRationale(
      context: context,
      permission: Permission.notification,
      title: 'Notifications',
      reason:
          'KINREL sends notifications so you never miss important family '
          'updates, invitations, or festival reminders.',
    );
  }

  // ── Open App Settings ─────────────────────────────────────────────

  /// Open the app's settings page in the system Settings app.
  ///
  /// Use this when a permission is permanently denied and the user
  /// must manually re-enable it.
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  // ── Internal Helpers ──────────────────────────────────────────────

  /// Core permission request flow:
  /// 1. Check current status — if already granted, return immediately.
  /// 2. Show rationale dialog explaining WHY.
  /// 3. Request permission via permission_handler.
  /// 4. If denied, show a non-blocking message.
  /// 5. If permanently denied, offer to open Settings.
  static Future<PermissionResult> _requestWithRationale({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String reason,
  }) async {
    // 1. Fast path — already granted
    final currentStatus = await permission.status;
    if (currentStatus.isGranted) {
      return PermissionResult.granted;
    }

    // 2. Show rationale dialog
    if (context.mounted) {
      final shouldAsk = await _showRationaleDialog(
        context: context,
        title: title,
        reason: reason,
      );
      if (!shouldAsk) return PermissionResult.denied;
    }

    // 3. Request permission
    PermissionStatus status;
    try {
      status = await permission.request();
    } catch (_) {
      // Never crash — treat unexpected errors as denied
      return PermissionResult.denied;
    }

    // 4. Handle result
    if (status.isGranted) {
      return PermissionResult.granted;
    }

    if (status.isPermanentlyDenied) {
      // 5. Offer Settings redirect
      if (context.mounted) {
        await _showPermanentlyDeniedDialog(
          context: context,
          title: title,
        );
      }
      return PermissionResult.permanentlyDenied;
    }

    // Denied (can ask again)
    if (context.mounted) {
      _showDeniedSnackbar(context, title);
    }
    return PermissionResult.denied;
  }

  /// Show a dialog explaining WHY the permission is needed.
  /// Returns `true` if the user wants to proceed, `false` if cancelled.
  static Future<bool> _showRationaleDialog({
    required BuildContext context,
    required String title,
    required String reason,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: KinrelColors.elevation3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textPrimary,
          ),
        ),
        content: Text(
          reason,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Not now',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Continue',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show a dialog offering to open Settings when permission is
  /// permanently denied.
  static Future<void> _showPermanentlyDeniedDialog({
    required BuildContext context,
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: KinrelColors.elevation3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '$title Required',
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textPrimary,
          ),
        ),
        content: const Text(
          'You previously denied this permission. To enable it, '
          'please open Settings and grant the permission manually.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textSecondary,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show a non-blocking snackbar when permission is denied.
  static void _showDeniedSnackbar(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: KinrelColors.elevation3,
        content: Text(
          '$title permission was denied. You can enable it later in Settings.',
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textSecondary,
          ),
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Settings',
          textColor: KinrelColors.orange,
          onPressed: openAppSettings,
        ),
      ),
    );
  }
}
