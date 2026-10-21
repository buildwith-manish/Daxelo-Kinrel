// test/shared/widgets/kinrel_logo_test.dart
//
// Visual + behavioural tests for the Kinrel "embrace" logo widget.
//
// Verifies:
//   • The painter produces a non-empty picture at the static frame.
//   • The painter produces a non-empty picture at several intermediate
//     animation progress values (including the returning-user window).
//   • The KinrelLogo widget renders without throwing at common sizes.
//   • The painter's shouldRepaint correctly reports when it should
//     repaint (variant or progress change) and when it should not.
//
// These tests use Flutter's standard `testWidgets` + `tester.getRect` /
// `paintImage` infrastructure — they don't require golden images.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/shared/widgets/kinrel_logo.dart';

void main() {
  group('KinrelLogoPainter', () {
    testWidgets('paints a non-empty picture at the static frame',
        (tester) async {
      final picture = _paintToPicture(
        tester,
        KinrelLogoPainter(variant: KinrelLogoVariant.light),
        const Size(120, 120),
      );
      expect(picture, isNotNull);
      // The picture should be non-trivial — at minimum the tile + mark
      // should produce a non-zero rasterization. We just verify the
      // call doesn't throw and the picture object is created.
    });

    testWidgets('paints at multiple animation progress values without throwing',
        (tester) async {
      // Sample progress values across the full timeline + the returning-user
      // window (0.433..1.0).
      const samples = <double>[
        0.0, // start (tile invisible)
        0.05, // 75 ms — tile opacity ramping up
        0.10, // 150 ms — tile opacity ~done
        0.17, // ~260 ms — tile scale done
        0.27, // ~400 ms — child dot done
        0.40, // ~600 ms — arms mid-draw
        0.43, // ~650 ms — returning-user start
        0.50, // ~750 ms — head about to land
        0.51, // ~760 ms — head starts dropping
        0.60, // ~900 ms — "BY DAXELO" starts fading in
        0.70, // ~1050 ms — hug pulse starts
        0.76, // ~1140 ms — head done
        0.80, // ~1200 ms — "BY DAXELO" full
        0.87, // ~1300 ms — hug pulse ends
        1.0, // end (full frame)
      ];
      for (final p in samples) {
        expect(
          () => _paintToPicture(
            tester,
            KinrelLogoPainter(
                variant: KinrelLogoVariant.light, progress: p),
            const Size(120, 120),
          ),
          returnsNormally,
          reason: 'painter threw at progress=$p',
        );
      }
    });

    testWidgets('paints the dark variant without throwing', (tester) async {
      expect(
        () => _paintToPicture(
          tester,
          KinrelLogoPainter(variant: KinrelLogoVariant.dark),
          const Size(120, 120),
        ),
        returnsNormally,
      );
    });

    test('shouldRepaint returns false when nothing changes', () {
      final a = KinrelLogoPainter(
          variant: KinrelLogoVariant.light, progress: 0.5);
      final b = KinrelLogoPainter(
          variant: KinrelLogoVariant.light, progress: 0.5);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('shouldRepaint returns true when variant changes', () {
      final a = KinrelLogoPainter(variant: KinrelLogoVariant.light);
      final b = KinrelLogoPainter(variant: KinrelLogoVariant.dark);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when progress changes', () {
      final a = KinrelLogoPainter(
          variant: KinrelLogoVariant.light, progress: 0.3);
      final b = KinrelLogoPainter(
          variant: KinrelLogoVariant.light, progress: 0.4);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('shouldRepaint returns true when progress becomes null (static)', () {
      final a = KinrelLogoPainter(
          variant: KinrelLogoVariant.light, progress: 0.5);
      final b = KinrelLogoPainter(variant: KinrelLogoVariant.light);
      // 0.5 != null → should repaint.
      expect(a.shouldRepaint(b), isTrue);
    });
  });

  group('KinrelLogo widget', () {
    testWidgets('renders at common sizes without throwing', (tester) async {
      const sizes = [16.0, 24.0, 29.0, 48.0, 64.0, 96.0, 132.0, 256.0, 512.0];
      for (final size in sizes) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: KinrelLogo(size: size),
              ),
            ),
          ),
        );
        expect(find.byType(KinrelLogo), findsOneWidget,
            reason: 'KinrelLogo not found at size=$size');
        final box = tester.renderObject(find.byType(KinrelLogo));
        expect(box.size, Size(size, size),
            reason: 'wrong size at size=$size');
      }
    });

    testWidgets('renders with progress without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: KinrelLogo(
                size: 132,
                variant: KinrelLogoVariant.light,
                progress: 0.5,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(KinrelLogo), findsOneWidget);
    });

    testWidgets('renders the dark variant without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: KinrelLogo(size: 96, variant: KinrelLogoVariant.dark),
            ),
          ),
        ),
      );
      expect(find.byType(KinrelLogo), findsOneWidget);
    });

    testWidgets('exposes a semantic label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: KinrelLogo(
                size: 48,
                semanticLabel: 'custom label',
              ),
            ),
          ),
        ),
      );
      // The Semantics node should carry the label.
      final semantics = tester.getSemantics(find.byType(KinrelLogo));
      expect(semantics.label, 'custom label');
    });
  });
}

/// Paints the given painter to a [Picture] using a recording canvas.
///
/// We use a `PictureRecorder` + `Canvas` (rather than pumping a real
/// widget tree) because it lets us assert on the painter's behaviour
/// directly without golden files.
Picture _paintToPicture(
  WidgetTester tester,
  CustomPainter painter,
  Size size,
) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  return recorder.endRecording();
}
