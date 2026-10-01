// lib/features/family/presentation/widgets/kinship_share_card.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  KINSHIP SHARE CARD — "Did you know? Your dad's sister = Bua"          │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// When a user discovers a kinship term ("oh, THAT's what I call my
// dad's sister"), that's a viral moment. They want to share it with
// their family group on WhatsApp. This card renders a beautiful,
// shareable image with:
//   - The kinship term in large brand type
//   - The relationship path ("Father → Sister")
//   - The family name
//   - Kinrel branding
//
// Wrapped in a RepaintBoundary so the parent can capture it as a PNG
// and hand the bytes to share_plus. This is organic, viral growth —
// every share is a free acquisition (Snapchat, Spotify, Cash App all
// use this pattern).
//
// PSYCHOLOGICAL PRINCIPLE: SOCIAL CURRENCY + SELF-EXPRESSION
// ─────────────────────────────────────────────────────────────────────
//   • Social Currency: sharing a discovery makes the sharer look
//     knowledgeable ("I know something about my family you don't").
//   • Self-Expression: the kinship term reflects the user's identity
//     and heritage — sharing it is sharing themselves.
//
// USAGE
// ─────
//   final key = GlobalKey();
//   KinshipShareCard(
//     boundaryKey: key,
//     kinshipTerm: 'Bua',
//     relationshipPath: 'Father → Sister',
//     familyName: 'Sharma Family',
//   )
//   // Later, to share:
//   KinshipShareCard.captureAndShare(key);

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
// Conditional import for web download (same pattern as KinrelShareCard).
// On web, share_plus falls back to a random filename which is confusing.
// We branch on kIsWeb and call downloadPngOnWeb for a deterministic
// filename. On native, downloadPngOnWeb is a no-op stub.
import '../../../kinrel_intelligence/widgets/share_download_stub.dart'
    if (dart.library.html) '../../../kinrel_intelligence/widgets/share_download_web.dart'
    as web_download;

/// A shareable card showing a discovered kinship term.
///
/// Wrap with a [RepaintBoundary] keyed by [boundaryKey] and call
/// [captureAndShare] to export + share the PNG.
class KinshipShareCard extends StatelessWidget {
  const KinshipShareCard({
    super.key,
    required this.boundaryKey,
    required this.kinshipTerm,
    required this.relationshipPath,
    required this.familyName,
    this.languageName,
  });

  /// The GlobalKey of the wrapping RepaintBoundary. Used by
  /// [captureAndShare] to find the RenderRepaintBoundary and capture it.
  final GlobalKey boundaryKey;

  /// The kinship term to display (e.g., "Bua", "Mausi", "Chacha").
  final String kinshipTerm;

  /// The relationship path (e.g., "Father → Sister").
  final String relationshipPath;

  /// The family name (e.g., "Sharma Family").
  final String familyName;

  /// Optional: the language of the term (e.g., "Hindi"). Shown as a
  /// small chip in the corner.
  final String? languageName;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF13141E), // dark bg
              Color(0xFF1A1B2E), // slightly lighter
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: "Did you know?" + language chip ──────────────
            Row(
              children: [
                Text(
                  '✨ Did you know?',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.orange,
                  ),
                ),
                const Spacer(),
                if (languageName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      languageName!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // ── The kinship term — the hero of the card ───────────────
            Text(
              kinshipTerm,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 12),

            // ── The relationship path ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.route_outlined,
                    size: 14,
                    color: KinrelColors.textSilver,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      relationshipPath,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textSilver,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bottom row: family name + Kinrel branding ────────────
            Row(
              children: [
                Icon(
                  Icons.cottage_rounded,
                  size: 14,
                  color: KinrelColors.textDim,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    familyName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Text(
                  'KINREL',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: KinrelColors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Captures the card as a PNG and opens the share sheet.
  ///
  /// Call this from a button's onTap. Returns true if the share sheet
  /// opened successfully, false otherwise.
  static Future<bool> captureAndShare(GlobalKey boundaryKey) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('⚠️ KinshipShareCard: boundary not found');
        return false;
      }

      // Capture the boundary as an image.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return false;

      final bytes = byteData.buffer.asUint8List();
      final filename = 'kinrel-kinship-${DateTime.now().millisecondsSinceEpoch}.png';

      // ── Haptic: success — the capture worked, share sheet is opening.
      HapticService.success();

      if (kIsWeb) {
        // Web: download the PNG (share_plus on web is unreliable).
        web_download.downloadPngOnWeb(bytes, filename);
        return true;
      } else {
        // Native: use the native share sheet.
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: filename, mimeType: 'image/png')],
          text: 'I just discovered a kinship term on Kinrel!',
        );
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ KinshipShareCard.captureAndShare failed: $e');
      HapticService.error();
      return false;
    }
  }
}
