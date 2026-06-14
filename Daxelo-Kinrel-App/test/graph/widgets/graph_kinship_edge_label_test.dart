// test/graph/widgets/graph_kinship_edge_label_test.dart
//
// AGENT-08 (Quality & Testing) — Regression test for BUG-4:
// Kinship term flows into graph edge labels.
//
// Verifies:
//   1. KinshipService loads indian_kinship.json successfully
//   2. getRelationship('father') returns a non-null KinshipRelationship
//   3. nativeName for 'father' in Hindi is non-empty (e.g. '\u092A\u093F\u0924\u093E' = पिता)
//   4. totalRelationships >= 5300
//
// This is a unit test (not widget test) that validates the KinshipService
// data pipeline: JSON asset → KinshipData → KinshipRelationship lookup.
// If this pipeline breaks, graph edge labels will show blank/wrong data.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/kinship/kinship_service.dart';
import 'package:kinrel/core/kinship/kinship_models.dart';

void main() {
  group('Kinship edge label regression (BUG-4)', () {
    late KinshipService service;

    setUp(() async {
      service = KinshipService();

      // Load the kinship data from the JSON asset.
      // In a unit test, rootBundle is not available, so we load
      // the file directly from the filesystem and parse it manually.
      final file = File('assets/data/indian_kinship.json');
      final jsonStr = await file.readAsString();
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final data = KinshipData.fromJson(jsonData);

      // Manually set the internal state via reflection-like approach:
      // Since KinshipService.load() uses rootBundle which isn't available
      // in unit tests, we use a test-friendly approach: load the JSON
      // directly and construct the service state.
      //
      // We access the service through its public API after loading data
      // via a test helper that bypasses rootBundle.
      await _loadServiceForTest(service, jsonData);
    });

    test(
      'BUG-4: KinshipService loads indian_kinship.json successfully',
      () {
        expect(service.isLoaded, isTrue, reason: 'KinshipService must load successfully');
      },
    );

    test(
      'BUG-4: getRelationship("father") returns non-null KinshipRelationship',
      () {
        final relationship = service.getRelationship('father');

        expect(relationship, isNotNull, reason: 'getRelationship("father") must return non-null');
        expect(relationship!.englishTerm, equals('Father'));
        expect(relationship.relationshipKey, isNotEmpty);
        expect(relationship.gender, isNotEmpty);
        expect(relationship.lineage, isNotEmpty);
      },
    );

    test(
      'BUG-4: Hindi nativeName for "father" is non-empty (पिता)',
      () {
        final translation = service.getKinshipTerm('father', 'hindi');

        expect(translation, isNotNull, reason: 'Hindi translation for "father" must exist');
        expect(translation!.native, isNotEmpty, reason: 'Hindi native name for "father" must be non-empty');
        // The Hindi word for father is पिता (pita)
        expect(translation.native, equals('\u092A\u093F\u0924\u093E'));
        expect(translation.latin, isNotEmpty, reason: 'Latin transliteration must be non-empty');
      },
    );

    test(
      'BUG-4: totalRelationships >= 5300',
      () {
        expect(
          service.totalRelationships,
          greaterThanOrEqualTo(5300),
          reason: 'Kinship database must contain at least 5300 relationships',
        );
      },
    );

    test(
      'BUG-4: getKinshipTermByLocale returns Hindi native for "father" via locale code',
      () {
        final nativeName = service.getKinshipTermByLocale('father', 'hi');

        expect(nativeName, isNotNull, reason: 'Locale-based lookup must return non-null');
        expect(nativeName, isNotEmpty, reason: 'Hindi native name via locale code must be non-empty');
      },
    );

    test(
      'BUG-4: Kinship term for "fathers_sister" resolves correctly',
      () {
        // This verifies that compound relationship keys (used in graph edges)
        // resolve to proper kinship terms with native translations.
        final relationship = service.getRelationship('fathers_sister');

        expect(relationship, isNotNull, reason: 'Compound key "fathers_sister" must resolve');
        expect(relationship!.englishTerm, isNotEmpty);

        final translation = service.getKinshipTerm('fathers_sister', 'hindi');
        expect(translation, isNotNull, reason: 'Hindi translation for "fathers_sister" must exist');
        expect(translation!.native, isNotEmpty, reason: 'Hindi native for "fathers_sister" must be non-empty');
      },
    );

    test(
      'BUG-4: Generic term "parent" resolves to specific key "father"',
      () {
        // The service maps generic terms to specific keys.
        // "parent" → "father" via _resolveToExistingKey
        final relationship = service.getRelationship('parent');

        expect(relationship, isNotNull, reason: 'Generic term "parent" must resolve to a specific key');
        expect(relationship!.englishTerm, isNotEmpty);
      },
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST HELPER: Load KinshipService without rootBundle
// ═══════════════════════════════════════════════════════════════════════════

/// Loads kinship data into the [service] by directly parsing [jsonData]
/// and using the service's public API where possible.
///
/// Since KinshipService.load() depends on rootBundle (unavailable in unit
/// tests), we use a workaround: we construct a KinshipData from the JSON
/// and inject it using the service's internal state via dart:developer or
/// by directly calling a test-friendly initialization.
///
/// This approach mirrors what KinshipService.load() does internally but
/// bypasses the asset bundle.
Future<void> _loadServiceForTest(
  KinshipService service,
  Map<String, dynamic> jsonData,
) async {
  // KinshipService doesn't expose a public method to inject data,
  // so we reconstruct the loading logic here using the same parsing
  // that KinshipService.load() uses internally.
  //
  // Alternative: We could make the service testable by adding a
  // KinshipService.fromData() constructor (agent-0's domain), but
  // for regression tests we use the existing public API.
  //
  // Since we cannot set _data directly, we'll attempt to use
  // the load() method with a mocked asset bundle. However, in
  // flutter_test, rootBundle may not resolve assets correctly.
  //
  // Best approach for unit tests: use TestWidgetsFlutterBinding
  // to set up the asset bundle, or use a file-based approach.

  // Use flutter_test's asset bundle support:
  // TestDefaultBinaryBinding ensures rootBundle works if assets
  // are configured in pubspec.yaml. But for pure unit tests,
  // we need to call service.load() which reads from rootBundle.
  //
  // Since this test file runs as a unit test (not widget test),
  // we need to ensure the test assets are available.
  // The safest approach is to rely on the service.load() method
  // with a properly configured test environment.

  try {
    await service.load();
  } catch (e) {
    // If rootBundle fails, fall back to manual injection.
    // This should not happen if the test is run with `flutter test`
    // which sets up the asset bundle correctly.
    //
    // As a last resort, we fail the test with a clear message.
    throw StateError(
      'KinshipService.load() failed in test. Ensure indian_kinship.json '
      'is in assets/data/ and pubspec.yaml declares it under flutter.assets. '
      'Original error: $e',
    );
  }
}
