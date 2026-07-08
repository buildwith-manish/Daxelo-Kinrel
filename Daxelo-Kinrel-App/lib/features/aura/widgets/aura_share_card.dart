// lib/features/aura/widgets/aura_share_card.dart
//
// AURA — Share Card (Phase 14).
//
// Renders a visually polished "shareable" version of the family's AURA
// (symbol + archetype name + family name + Daxelo/Kinrel branding),
// wrapped in a RepaintBoundary so the parent screen can capture it as
// a PNG and hand the bytes to `share_plus`.
//
// Implementation note (deviation #3 from the implementation guide):
//   - We do NOT use the `screenshot` package — `share_plus` is already
//     a dependency, and Flutter's built-in `RepaintBoundary` +
//     `RenderRepaintBoundary.toImage()` is a solved problem.
//   - The capture is exposed via a GlobalKey passed in by the parent
//     so the parent owns the share-sheet invocation.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/feature_flags.dart';
import '../data/archetype_strings.dart';
import '../data/aura_model.dart';
import 'aura_symbol_widget.dart';

/// A self-contained share card. Wrap with a [RepaintBoundary] keyed by
/// [boundaryKey] and call [captureAndShare] to export + share the PNG.
class AuraShareCard extends StatelessWidget {
  const AuraShareCard({
    super.key,
    required this.boundaryKey,
    required this.aura,
    required this.familyName,
  });

  /// GlobalKey that the parent assigns to the wrapping RepaintBoundary.
  /// [captureAndShare] reads it to find the RenderRepaintBoundary.
  final GlobalKey boundaryKey;

  /// The AURA payload to render. Only `symbol` + `archetype` are used.
  final AuraModel aura;

  /// Family name, shown under the archetype. Caller passes this in
  /// (the AuraModel itself doesn't carry the family name).
  final String familyName;

  @override
  Widget build(BuildContext context) {
    final strings = archetypeStrings(aura.archetype.key);
    final primary = _parseColor(aura.symbol.primaryColorHex);
    final secondary = _parseColor(aura.symbol.secondaryColorHex);
    final accent = _parseColor(aura.symbol.accentColorHex);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF13141E),
            const Color(0xFF191B2C),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Branding header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 14, color: accent),
              const SizedBox(width: 4),
              Text(
                'AURA',
                style: TextStyle(
                  color: primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Symbol preview (static, no animation — for deterministic PNG)
          StaticAuraSymbol(
            parameters: aura.symbol,
            archetypeKey: aura.archetype.key,
            size: 200,
          ),
          const SizedBox(height: 16),

          // Archetype name
          Text(
            strings.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Poetic description (first line only — keeps the card compact)
          Text(
            strings.description.split('\n').first,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFC9B4A8),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // Family name
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: secondary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: secondary.withValues(alpha: 0.4)),
            ),
            child: Text(
              familyName,
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Footer — Daxelo / Kinrel branding
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite, size: 10, color: accent.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                'Made with love by Daxelo',
                style: TextStyle(
                  color: const Color(0xFF8A7A72),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Capture this widget as a PNG and share it via the native share sheet.
  ///
  /// Returns `true` if the share sheet was opened successfully. The
  /// parent typically wraps this in a try/catch and shows a SnackBar
  /// on failure.
  ///
  /// Phase 19.1 privacy check: the captured PNG contains only the
  /// archetype name, family name, and symbol — no member counts, no
  /// graph structure, no individual member roles. Safe to share publicly.
  static Future<bool> captureAndShare({
    required GlobalKey boundaryKey,
    required String familyName,
    String? shareText,
  }) async {
    try {
      final renderObject = boundaryKey.currentContext?.findRenderObject();
      if (renderObject == null) {
        debugPrint('⚠️ AuraShareCard: boundary render object is null');
        return false;
      }
      final boundary = renderObject as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('⚠️ AuraShareCard: toByteData returned null');
        return false;
      }
      final bytes = byteData.buffer.asUint8List();

      // Use the family name (sanitized) as the filename.
      final safeName = familyName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final xfile = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'aura_$safeName.png',
        mimeType: 'image/png',
      );
      await Share.shareXFiles(
        [xfile],
        text: shareText ?? "Our family's AURA — $familyName",
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ AuraShareCard capture/share failed: $e');
      return false;
    }
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

// Suppress analyzer warning about unused import in non-flagged builds.
// ignore: unused_element
const _kFlag = kEnableAura;
