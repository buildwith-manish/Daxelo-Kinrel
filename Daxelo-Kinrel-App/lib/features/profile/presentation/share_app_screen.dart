// lib/features/profile/presentation/share_app_screen.dart
//
// DAXELO KINREL — Share App Utility
//
// Not a separate route — this is a helper that can be called
// from the profile screen or anywhere else. Uses share_plus
// to share a pre-built message with the user's family link.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/brand_typography.dart';
import '../data/profile_provider.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);

/// Utility class for sharing the Kinrel app with friends.
///
/// Usage:
/// ```dart
/// // Simple share with default message
/// ShareAppHelper.share();
///
/// // Show family picker if user has multiple families
/// ShareAppHelper.showFamilyPickerAndShare(context, profileState);
/// ```
class ShareAppHelper {
  ShareAppHelper._();

  /// Base share message template.
  static const String _baseMessage =
      'Hey! I\'m using Daxelo Kinrel to build my family tree in 14 Indian languages. Join me! 🌳👨‍👩‍👧‍👦\n'
      'Download: https://daxelokinrel.com/download';

  /// Share with a specific family username link.
  static void share({String? familyUsername}) {
    final message = familyUsername != null
        ? '$_baseMessage\nJoin my family: kinrel.co/f/@$familyUsername'
        : _baseMessage;

    Share.share(message, subject: 'Join me on Daxelo Kinrel!');
  }

  /// Show a bottom sheet to pick a family if the user has multiple families,
  /// then share with the selected family link.
  ///
  /// If the user has only one family, shares directly with that family's link.
  /// If no families, shares without a family link.
  static void showFamilyPickerAndShare(
    BuildContext context,
    ProfileState profileState,
  ) {
    final families = profileState.families;

    // No families — share without family link
    if (families.isEmpty) {
      share();
      return;
    }

    // Single family — share directly with its username
    if (families.length == 1) {
      final family = families.first;
      share(familyUsername: family.username);
      return;
    }

    // Multiple families — show picker
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _textDim.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Which family to share?',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose a family to include its invite link',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _textDim,
              ),
            ),
            const SizedBox(height: 16),
            // Family options
            ...families.map(
              (family) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      family.name.isNotEmpty
                          ? family.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _orange,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  family.name,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                subtitle: family.username != null
                    ? Text(
                        '@${family.username}',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 12,
                          color: _textDim,
                        ),
                      )
                    : null,
                trailing: Icon(Icons.share_outlined, color: _orange, size: 20),
                onTap: () {
                  Navigator.of(ctx).pop();
                  share(familyUsername: family.username);
                },
              ),
            ),
            // Option to share without family link
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _textDim.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.link_off_outlined,
                    color: _textDim,
                    size: 20,
                  ),
                ),
              ),
              title: const Text(
                'Share without family link',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _textSecondary,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                share();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
