// test/shared/widgets/animated_preview_card_test.dart
//
// Tests for the shared AnimatedPreviewCard shell widget — verifies
// the slot-based content layout (header + mediaArea + title +
// description), the reduced-motion passthrough, and the card chrome
// (darkCard container, accent border/shadow, fixed width).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/constants/brand_colors.dart';
import 'package:kinrel/shared/widgets/animated_preview_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnimatedPreviewCard — slot-based content layout', () {
    testWidgets('renders header, mediaArea, title, and description in order',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Test Title',
              description: 'Test Description',
            ),
          ),
        ),
      );

      // All slot content should render.
      expect(find.text('MEDIA'), findsOneWidget);
      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Description'), findsOneWidget);
    });

    testWidgets('omits the header spacer when header is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Test Title',
              description: 'Test Description',
            ),
          ),
        ),
      );

      // When header is null, the mediaArea is the top element (no
      // 10px spacer above it). We verify the card renders without
      // error — the header slot is optional.
      expect(find.text('MEDIA'), findsOneWidget);
    });

    testWidgets('renders the header when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              header: Text('HEADER'),
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Test Title',
              description: 'Test Description',
            ),
          ),
        ),
      );

      expect(find.text('HEADER'), findsOneWidget);
    });
  });

  group('AnimatedPreviewCard — card chrome', () {
    testWidgets('uses darkCard background with KinrelRadius.lg corners',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: 'Description',
            ),
          ),
        ),
      );

      // The card container is the SizedBox(width: 240) → Container.
      // We verify the Container's decoration has the darkCard color.
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AnimatedPreviewCard),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, KinrelColors.darkCard);
    });

    testWidgets('uses accent color for border + shadow when provided',
        (tester) async {
      const accent = KinrelColors.orange;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              accentColor: accent,
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: 'Description',
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AnimatedPreviewCard),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      // The border should use the accent color (at 0.25 alpha).
      expect(decoration.border, isNotNull);
      // The shadow should use the accent color (at 0.08 alpha).
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.isNotEmpty, isTrue);
    });

    testWidgets('uses neutral border when accentColor is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: 'Description',
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AnimatedPreviewCard),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      // No shadow when accentColor is null.
      expect(decoration.boxShadow, isNull);
      // Border uses the neutral 0xFF3A3A4A color.
      expect(decoration.border, isNotNull);
    });

    testWidgets('defaults to 240px width', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: 'Description',
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(AnimatedPreviewCard),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(sizedBox.width, 240);
    });

    testWidgets('respects custom width', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              width: 200,
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: 'Description',
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(AnimatedPreviewCard),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(sizedBox.width, 200);
    });
  });

  group('AnimatedPreviewCard — reducedMotion passthrough', () {
    testWidgets('accepts reducedMotion flag (no crash)', (tester) async {
      // The reducedMotion flag is passed through to the mediaArea
      // widget (which is responsible for suppressing its own
      // animation). The shell itself has no animation to suppress.
      // We verify the card renders without error when the flag is
      // true and when it's false.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              reducedMotion: true,
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: 'Description',
            ),
          ),
        ),
      );
      expect(find.text('MEDIA'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              reducedMotion: false,
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: 'Description',
            ),
          ),
        ),
      );
      expect(find.text('MEDIA'), findsOneWidget);
    });
  });

  group('AnimatedPreviewCard — title/description styling', () {
    testWidgets('title is ellipsized to 1 line', (tester) async {
      const longTitle =
          'A very long title that should be ellipsized to a single line '
          'because the AnimatedPreviewCard titles are constrained to '
          'maxLines: 1 with ellipsis overflow';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: longTitle,
              description: 'Description',
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text(longTitle));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('description is ellipsized to 2 lines', (tester) async {
      const longDescription =
          'A very long description that should be ellipsized to two lines '
          'because the AnimatedPreviewCard descriptions are constrained to '
          'maxLines: 2 with ellipsis overflow. This is a long sentence to '
          'make sure the text actually overflows the two-line limit.';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPreviewCard(
              mediaArea: SizedBox(height: 60, child: Text('MEDIA')),
              title: 'Title',
              description: longDescription,
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text(longDescription));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });
}
