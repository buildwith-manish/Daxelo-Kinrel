// test/memorymatch_card_faces_test.dart
//
// Smoke test: every one of the 72 vector card faces (4 packs x 18
// symbols) must build + paint without throwing at multiple box sizes
// (chip 16px, small tile 48px, full tile 140px, non-square 90x120).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/memorymatch/memorymatch_card_faces.dart';
import 'package:kinrel/features/games/memorymatch/memorymatch_models.dart';

void main() {
  final packs = ['classic', 'family', 'food', 'animals'];

  test('registry covers every server symbol key in every pack', () {
    for (final packId in packs) {
      final pack = MemoryCardPack.all.firstWhere((p) => p.id == packId);
      for (final key in pack.symbols.keys) {
        final spec = MemoryCardFaces.specFor(packId, key);
        expect(spec.key, key, reason: '$packId/$key resolved to ${spec.key}');
        expect(spec.painter, isNotNull);
      }
    }
  });

  test('unknown keys fall back to a safe face', () {
    final spec = MemoryCardFaces.specFor('classic', 'definitely-not-a-key');
    expect(spec.key, MemoryCardFaces.fallbackKey);
  });

  testWidgets('every face paints at chip, tile, and oversize boxes',
      (tester) async {
    for (final packId in packs) {
      final pack = MemoryCardPack.all.firstWhere((p) => p.id == packId);
      for (final key in pack.symbols.keys) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: MemoryCardFaceIcon(symbolKey: key, packId: packId),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: MemoryCardFaceIcon(symbolKey: key, packId: packId),
                  ),
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: MemoryCardFaceIcon(symbolKey: key, packId: packId),
                  ),
                  SizedBox(
                    width: 90,
                    height: 120,
                    child: MemoryCardFaceIcon(
                        symbolKey: key, packId: packId, dimmed: true),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // No exception = pass. Rendering happens on the test canvas.
      }
    }
  });
}
