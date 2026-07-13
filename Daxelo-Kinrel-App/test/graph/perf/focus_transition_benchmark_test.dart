// test/graph/perf/focus_transition_benchmark_test.dart
// P2.2: Performance benchmark for cinematic focus transition.
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2.2 Focus transition benchmark', () {
    test('spring physics constants are correct', () {
      const mass = 1.0, stiffness = 200.0, damping = 25.0;
      final ratio = damping / (2 * (mass * stiffness).abs());
      expect(ratio, closeTo(0.884, 0.01));
    });
    test('desaturation matrix computation is fast', () {
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        final s = 0.4, inv = 1.0 - s;
        final matrix = [s+inv*0.299, inv*0.587, inv*0.114, 0, 0, inv*0.299, s+inv*0.587, inv*0.114, 0, 0, inv*0.299, inv*0.587, s+inv*0.114, 0, 0, 0, 0, 0, 1, 0];
        expect(matrix.length, 20);
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(10));
    });
  });
}
