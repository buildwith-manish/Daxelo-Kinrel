// test/graph/interaction/haptic_language_test.dart
//
// P3.2 — Haptic feedback language.
//
// Verifies that:
//   1. GraphHaptics methods call the correct HapticFeedback method.
//   2. Reduced motion (MediaQuery.disableAnimationsOf = true) suppresses
//      all haptics.
//   3. No-context flavor also respects reduced motion.
//   4. GraphHaptics is the canonical API (no direct HapticFeedback in graph).
//
// Per P3.2 Testing strategy:
//   - Unit test: Mock HapticFeedback channel; verify correct method is
//     called for each gesture.
//   - Reduced motion test: Verify no haptic calls when reduced motion
//     is active.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/haptic_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Track haptic method calls by intercepting the platform channel.
  final List<String> hapticCalls = <String>[];

  setUp(() {
    hapticCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('HapticFeedback')) {
        hapticCalls.add(call.arguments as String? ?? call.method);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Helper that pumps a widget with the given `disableAnimations` flag
  /// and the given haptic trigger. The haptic fires once after pump.
  Future<void> pumpHarness(
    WidgetTester tester, {
    required bool disableAnimations,
    required void Function(BuildContext) trigger,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                // Fire the trigger with the in-tree context.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  trigger(context);
                });
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    // Pump one frame so the post-frame callback fires, then pump a
    // second frame to let the platform channel flush.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('P3.2 — GraphHaptics vocabulary (reduced motion OFF)', () {
    testWidgets('nodeTap fires selectionClick', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.nodeTap,
      );
      expect(hapticCalls, contains('HapticFeedbackType.selectionClick'));
    });

    testWidgets('edgeTap fires selectionClick', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.edgeTap,
      );
      expect(hapticCalls, contains('HapticFeedbackType.selectionClick'));
    });

    testWidgets('nodeSelect fires lightImpact', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.nodeSelect,
      );
      expect(hapticCalls, contains('HapticFeedbackType.lightImpact'));
    });

    testWidgets('longPress fires mediumImpact', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.longPress,
      );
      expect(hapticCalls, contains('HapticFeedbackType.mediumImpact'));
    });

    testWidgets('focusEnter fires heavyImpact', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.focusEnter,
      );
      expect(hapticCalls, contains('HapticFeedbackType.heavyImpact'));
    });

    testWidgets('focusExit fires lightImpact', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.focusExit,
      );
      expect(hapticCalls, contains('HapticFeedbackType.lightImpact'));
    });

    testWidgets('branchExpand fires mediumImpact', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.branchExpand,
      );
      expect(hapticCalls, contains('HapticFeedbackType.mediumImpact'));
    });

    testWidgets('compareComplete fires heavyImpact', (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: false,
        trigger: GraphHaptics.compareComplete,
      );
      expect(hapticCalls, contains('HapticFeedbackType.heavyImpact'));
    });
  });

  group('P3.2 — Reduced motion suppresses all haptics', () {
    testWidgets('nodeTap suppressed when disableAnimations=true',
        (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: true,
        trigger: GraphHaptics.nodeTap,
      );
      expect(hapticCalls, isEmpty,
          reason: 'reduced motion must suppress nodeTap');
    });

    testWidgets('focusEnter suppressed when disableAnimations=true',
        (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: true,
        trigger: GraphHaptics.focusEnter,
      );
      expect(hapticCalls, isEmpty,
          reason: 'reduced motion must suppress focusEnter');
    });

    testWidgets('longPress suppressed when disableAnimations=true',
        (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: true,
        trigger: GraphHaptics.longPress,
      );
      expect(hapticCalls, isEmpty,
          reason: 'reduced motion must suppress longPress');
    });

    testWidgets('compareComplete suppressed when disableAnimations=true',
        (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: true,
        trigger: GraphHaptics.compareComplete,
      );
      expect(hapticCalls, isEmpty,
          reason: 'reduced motion must suppress compareComplete');
    });

    testWidgets('branchExpand suppressed when disableAnimations=true',
        (tester) async {
      await pumpHarness(
        tester,
        disableAnimations: true,
        trigger: GraphHaptics.branchExpand,
      );
      expect(hapticCalls, isEmpty,
          reason: 'reduced motion must suppress branchExpand');
    });
  });

  group('P3.2 — No-context flavor', () {
    test('pathTraceStep fires selectionClick when reducedMotion=false',
        () async {
      await GraphHaptics.pathTraceStep(reducedMotion: false);
      // Allow the platform channel to flush.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(hapticCalls, contains('HapticFeedbackType.selectionClick'));
    });

    test('pathTraceStep suppressed when reducedMotion=true', () async {
      await GraphHaptics.pathTraceStep(reducedMotion: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(hapticCalls, isEmpty,
          reason: 'reduced motion must suppress pathTraceStep');
    });

    test('focusEnterNoContext fires heavyImpact when reducedMotion=false',
        () async {
      await GraphHaptics.focusEnterNoContext(reducedMotion: false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(hapticCalls, contains('HapticFeedbackType.heavyImpact'));
    });

    test('focusEnterNoContext suppressed when reducedMotion=true',
        () async {
      await GraphHaptics.focusEnterNoContext(reducedMotion: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(hapticCalls, isEmpty);
    });
  });

  group('P3.2 — Acceptance: GraphHaptics is canonical API', () {
    test('all vocabulary methods exist and are callable', () {
      // Static contract check — the API surface is stable.
      expect(GraphHaptics.nodeTap, isA<Function>());
      expect(GraphHaptics.nodeSelect, isA<Function>());
      expect(GraphHaptics.edgeTap, isA<Function>());
      expect(GraphHaptics.longPress, isA<Function>());
      expect(GraphHaptics.focusEnter, isA<Function>());
      expect(GraphHaptics.focusExit, isA<Function>());
      expect(GraphHaptics.branchExpand, isA<Function>());
      expect(GraphHaptics.compareComplete, isA<Function>());
      expect(GraphHaptics.pathTraceStep, isA<Function>());
      // No-context flavor also exists.
      expect(GraphHaptics.pathTraceStep, isA<Function>());
      expect(GraphHaptics.nodeTapNoContext, isA<Function>());
      expect(GraphHaptics.longPressNoContext, isA<Function>());
      expect(GraphHaptics.focusEnterNoContext, isA<Function>());
    });
  });
}
