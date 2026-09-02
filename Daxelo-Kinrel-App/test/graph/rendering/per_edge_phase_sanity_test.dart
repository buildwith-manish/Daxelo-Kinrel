// Quick verification script — runs in the dart VM via `flutter test`.
// Verifies the per-edge phase function produces deterministic values
// spread across [-1, 1] for various edge IDs.
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/widgets/engine/engine_edge_painter.dart';

void main() {
  test('Per-edge phase sanity check', () {
    // Use the public computeVisualMidpoint as a proxy to verify the
    // per-edge phase is deterministic and produces varied values
    // across different edge IDs.
    const s = Offset(0, 0);
    const t = Offset(200, 0);

    final ids = [
      'edge-001', 'edge-002', 'edge-003', 'edge-004', 'edge-005',
      'edge-006', 'edge-007', 'edge-008', 'edge-009', 'edge-010',
      'rel-abc-123', 'rel-xyz-789', 'rel-mno-456',
      'a', 'b', 'c', 'd', 'e',
      '11111111-1111-1111-1111-111111111111',
      '22222222-2222-2222-2222-222222222222',
    ];

    final midpoints = <String, Offset>{};
    for (final id in ids) {
      // Call twice to verify determinism
      final m1 = EngineEdgePainter.computeVisualMidpoint(s, t, edgeId: id);
      final m2 = EngineEdgePainter.computeVisualMidpoint(s, t, edgeId: id);
      expect(m1, equals(m2),
          reason: 'Per-edge phase must be deterministic for id=$id');
      midpoints[id] = m1;
    }

    // Print summary
    print('Per-edge midpoint positions (s=(0,0), t=(200,0)):');
    for (final entry in midpoints.entries) {
      print('  ${entry.key}: ${entry.value}');
    }

    // Verify variation — the midpoints should NOT all be identical.
    final uniqueMids = midpoints.values.toSet();
    print('Unique midpoint count: ${uniqueMids.length} of ${ids.length}');
    expect(uniqueMids.length, greaterThan(1),
        reason: 'Per-edge phase must produce varied midpoints, not all identical');

    // Verify spread — at least 3 distinct midpoints for 20 IDs.
    expect(uniqueMids.length, greaterThanOrEqualTo(3),
        reason: 'Per-edge phase must produce meaningful variation '
            '(>= 3 distinct positions for 20 IDs)');

    // Verify the midpoints are within reasonable bounds (not NaN, not infinite).
    for (final m in midpoints.values) {
      expect(m.dx.isFinite, isTrue);
      expect(m.dy.isFinite, isTrue);
      expect(m.dx.abs(), lessThan(1000));
      expect(m.dy.abs(), lessThan(1000));
    }

    print('All per-edge phase sanity checks PASSED.');
  });
}
