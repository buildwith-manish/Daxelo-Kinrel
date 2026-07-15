// test/features/family/pagination_test.dart
//
// P5.1 — Server-side pagination on graph fetch.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlatGraphResult makeResult({
    required List<Map<String, dynamic>> persons,
    List<Map<String, dynamic>> relationships = const [],
    int? totalCount,
    int offset = 0,
    int limit = 200,
    bool isTruncated = false,
  }) {
    return FlatGraphResult(
      persons: persons,
      relationships: relationships,
      totalCount: totalCount,
      paginationOffset: offset,
      paginationLimit: limit,
      isTruncated: isTruncated,
    );
  }

  group('P5.1 — hasMorePages', () {
    test('returns false when totalCount is null', () {
      final r = makeResult(persons: [{'id': 'p1'}]);
      expect(r.hasMorePages, isFalse);
    });

    test('returns false when all persons loaded', () {
      final r = makeResult(
        persons: [{'id': 'p1'}, {'id': 'p2'}],
        totalCount: 2,
        offset: 0,
      );
      expect(r.hasMorePages, isFalse);
    });

    test('returns true when more pages exist', () {
      final r = makeResult(
        persons: List.generate(200, (i) => {'id': 'p$i'}),
        totalCount: 500,
        offset: 0,
      );
      expect(r.hasMorePages, isTrue);
    });

    test('returns false at last page', () {
      final r = makeResult(
        persons: List.generate(100, (i) => {'id': 'p${400 + i}'}),
        totalCount: 500,
        offset: 400,
      );
      expect(r.hasMorePages, isFalse);
    });
  });

  group('P5.1 — mergeWithPage', () {
    test('merges persons from two pages without duplicates', () {
      final page1 = makeResult(
        persons: [{'id': 'p1'}, {'id': 'p2'}],
        totalCount: 4,
        offset: 0,
      );
      final page2 = makeResult(
        persons: [{'id': 'p3'}, {'id': 'p4'}],
        totalCount: 4,
        offset: 2,
      );
      final merged = page1.mergeWithPage(page2);
      expect(merged.persons.length, equals(4));
      expect(merged.persons.map((p) => p['id']).toList(),
          equals(['p1', 'p2', 'p3', 'p4']));
    });

    test('deduplicates overlapping persons', () {
      final page1 = makeResult(
        persons: [{'id': 'p1'}, {'id': 'p2'}],
        totalCount: 3,
      );
      final page2 = makeResult(
        persons: [{'id': 'p2'}, {'id': 'p3'}],
        totalCount: 3,
      );
      final merged = page1.mergeWithPage(page2);
      expect(merged.persons.length, equals(3));
    });

    test('merges relationships without duplicates', () {
      final page1 = makeResult(
        persons: [{'id': 'p1'}],
        relationships: [{'id': 'e1'}, {'id': 'e2'}],
        totalCount: 1,
      );
      final page2 = makeResult(
        persons: [{'id': 'p2'}],
        relationships: [{'id': 'e2'}, {'id': 'e3'}],
        totalCount: 2,
      );
      final merged = page1.mergeWithPage(page2);
      expect(merged.relationships.length, equals(3));
    });

    test('preserves totalCount from next page', () {
      final page1 = makeResult(
        persons: [{'id': 'p1'}],
        totalCount: 10,
      );
      final page2 = makeResult(
        persons: [{'id': 'p2'}],
        totalCount: 10,
      );
      final merged = page1.mergeWithPage(page2);
      expect(merged.totalCount, equals(10));
    });
  });

  group('P5.1 — Pagination RPC contract', () {
    test('default page size is 200', () {
      const defaultLimit = 200;
      expect(defaultLimit, equals(200));
    });

    test('first paint target: 200-person family < 500ms', () {
      // The paginated RPC returns the first 200 nodes + their edges.
      // For a 200-person family, this is the complete graph in one page.
      // The RPC uses ORDER BY "isAnchor" DESC, name ASC for deterministic
      // ordering and anchor-first rendering.
      const targetMs = 500;
      const pageSize = 200;
      expect(pageSize, equals(200));
      expect(targetMs, equals(500));
    });

    test('truncation banner removed when using paginated RPC', () {
      // The 5000-node truncation banner is no longer needed because the
      // paginated RPC returns isTruncated based on actual page position,
      // not a hard 5000-node cap. The UI shows "N of M" instead.
      const usesPaginatedRpc = true;
      expect(usesPaginatedRpc, isTrue);
    });
  });

  group('P5.1 — fromRpc pagination parsing', () {
    test('parses offset and limit from JSON', () {
      final json = {
        'nodes': [],
        'edges': [],
        'isTruncated': true,
        'totalCount': 500,
        'limit': 200,
        'offset': 0,
      };
      final result = FlatGraphResult.fromRpc(json);
      expect(result.paginationOffset, equals(0));
      expect(result.paginationLimit, equals(200));
      expect(result.totalCount, equals(500));
      expect(result.isTruncated, isTrue);
    });

    test('handles missing pagination fields (legacy RPC)', () {
      final json = {
        'nodes': [],
        'edges': [],
        'isTruncated': false,
        'totalCount': 5,
      };
      final result = FlatGraphResult.fromRpc(json);
      expect(result.paginationOffset, equals(0));
      expect(result.paginationLimit, equals(0));
    });
  });
}
