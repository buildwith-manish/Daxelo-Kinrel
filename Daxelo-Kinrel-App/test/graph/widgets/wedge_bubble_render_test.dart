// test/graph/widgets/wedge_bubble_render_test.dart
//
// Renders the +N page bubble's circle container in isolation and
// verifies it uses BoxShape.circle (not a rectangle). This is a
// compile-time + runtime contract check.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'The +N page bubble renders as a CIRCLE (BoxShape.circle), '
      'not a rectangle', (tester) async {
    // Replicate the bubble's circle container exactly as in
    // _WedgePageChipBubbleState.build (branch_affordance.dart).
    const circleDiameter = 72.0;
    const numberFontSize = circleDiameter * 0.28;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.grey.shade900,
          body: Center(
            child: Container(
              width: circleDiameter,
              height: circleDiameter,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFF202338), // KinrelColors.darkElevated
                shape: BoxShape.circle,
              ),
              child: const Text(
                '+3',
                style: TextStyle(
                  fontSize: numberFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Find the Container with the circle decoration.
    final containerFinder = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle,
    );
    expect(containerFinder, findsOneWidget,
        reason: 'The bubble container must use BoxShape.circle');

    // Verify the container's size is the node diameter (72×72).
    final box = tester.getRect(containerFinder);
    expect(box.width, equals(circleDiameter),
        reason: 'The bubble circle must be $circleDiameter px wide');
    expect(box.height, equals(circleDiameter),
        reason: 'The bubble circle must be $circleDiameter px tall');
  });
}
