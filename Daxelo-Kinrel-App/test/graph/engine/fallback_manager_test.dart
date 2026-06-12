// test/graph/engine/fallback_manager_test.dart
//
// Tests for the FallbackManager engine tier switching per V2.1 Blueprint §29.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/fallback_manager.dart';

void main() {
  group('FallbackManager', () {
    late FallbackManager manager;

    setUp(() {
      manager = FallbackManager();
    });

    tearDown(() {
      manager.dispose();
    });

    group('engine tier selection', () {
      test('engine tier is Tier1 for 0-300 nodes', () {
        manager.updateNodeCount(0);
        expect(manager.state.currentTier, equals(EngineTier.force));

        manager.updateNodeCount(150);
        expect(manager.state.currentTier, equals(EngineTier.force));

        manager.updateNodeCount(300);
        expect(manager.state.currentTier, equals(EngineTier.force));
      });

      test('engine switches to Tier2 at 301 nodes (after 2s debounce)', () {
        manager.updateNodeCount(301);
        // The recommended tier should change immediately
        expect(manager.state.recommendedTier, equals(EngineTier.hybrid));
        // But current tier may still be Tier1 due to debounce
        expect(manager.state.switchPending, isTrue);
      });

      test('engine switches to Tier5 (emergency) at 5001 nodes', () {
        manager.updateNodeCount(5001);
        expect(manager.state.recommendedTier, equals(EngineTier.emergency));
      });
    });

    group('tier switching behavior', () {
      test('downgrade emits user notification string', () async {
        // Force an immediate switch by using setUserOverride
        manager.setUserOverride(EngineTier.radial);

        expect(manager.state.notificationMessage, isNotNull);
        expect(manager.state.notificationMessage, contains('Radial'));
      });

      test('manual override bypasses automatic switching', () {
        manager.setUserOverride(EngineTier.hierarchical);
        expect(manager.state.currentTier, equals(EngineTier.hierarchical));
        expect(manager.state.userOverride, isTrue);

        // Automatic switching should be suppressed
        manager.updateNodeCount(10); // Would normally be Tier1
        expect(manager.state.currentTier, equals(EngineTier.hierarchical));
      });

      test('clearing user override resumes automatic management', () {
        manager.setUserOverride(EngineTier.emergency);
        expect(manager.state.userOverride, isTrue);

        manager.clearUserOverride();
        expect(manager.state.userOverride, isFalse);
      });
    });

    group('tier thresholds', () {
      test('default thresholds match blueprint spec', () {
        const thresholds = TierThresholds();
        expect(thresholds.forceMax, equals(300));
        expect(thresholds.hybridMax, equals(1000));
        expect(thresholds.radialMax, equals(3000));
        expect(thresholds.hierarchicalMax, equals(5000));
        expect(thresholds.debounceMs, equals(2000));
        expect(thresholds.crossfadeMs, equals(500));
      });
    });
  });
}
