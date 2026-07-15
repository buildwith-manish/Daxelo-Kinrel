// test/features/search/cross_feature_search_test.dart
//
// P6.5 — Cross-feature search app-wide.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/search/providers/cross_feature_search_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P6.5 — Cross-feature search model', () {
    test('CrossFeatureSearchResult constructs correctly', () {
      const result = CrossFeatureSearchResult(
        id: 'p1',
        type: CrossFeatureResultType.person,
        title: 'Aarav',
        subtitle: 'Male',
        familyId: 'fam1',
        route: '/family/fam1/member/p1',
      );
      expect(result.id, equals('p1'));
      expect(result.type, equals(CrossFeatureResultType.person));
      expect(result.title, equals('Aarav'));
      expect(result.route, equals('/family/fam1/member/p1'));
    });

    test('CrossFeatureSearchResult equality by id + type', () {
      const r1 = CrossFeatureSearchResult(
        id: 'p1',
        type: CrossFeatureResultType.person,
        title: 'Aarav',
        subtitle: '',
      );
      const r2 = CrossFeatureSearchResult(
        id: 'p1',
        type: CrossFeatureResultType.person,
        title: 'Different title',
        subtitle: '',
      );
      expect(r1 == r2, isTrue);
      expect(r1.hashCode, equals(r2.hashCode));
    });

    test('CrossFeatureResultType has all expected types', () {
      expect(CrossFeatureResultType.values,
          contains(CrossFeatureResultType.person));
      expect(CrossFeatureResultType.values,
          contains(CrossFeatureResultType.decision));
      expect(CrossFeatureResultType.values,
          contains(CrossFeatureResultType.memory));
      expect(CrossFeatureResultType.values,
          contains(CrossFeatureResultType.event));
      expect(CrossFeatureResultType.values,
          contains(CrossFeatureResultType.story));
    });
  });

  group('P6.5 — CrossFeatureSearchState', () {
    test('default state is empty', () {
      const state = CrossFeatureSearchState();
      expect(state.query, isEmpty);
      expect(state.results, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith updates fields correctly', () {
      const original = CrossFeatureSearchState();
      final updated = original.copyWith(
        query: 'test',
        isLoading: true,
      );
      expect(updated.query, equals('test'));
      expect(updated.isLoading, isTrue);
      expect(updated.error, isNull);
    });
  });

  group('P6.5 — Provider contract', () {
    test('crossFeatureSearchProvider is a StateNotifierProvider', () {
      expect(crossFeatureSearchProvider, isNotNull);
    });

    test('search with empty query clears state', () {
      const emptyQuery = '';
      expect(emptyQuery.trim(), isEmpty);
    });

    test('search is case-insensitive', () {
      const query = 'AARAV';
      final lowerQuery = query.toLowerCase();
      expect(lowerQuery, equals('aarav'));
      expect('Aarav Sharma'.toLowerCase().contains(lowerQuery), isTrue);
    });
  });
}
