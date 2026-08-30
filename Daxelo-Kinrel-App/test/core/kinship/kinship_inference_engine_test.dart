// test/core/kinship/kinship_inference_engine_test.dart
//
// Tests for the Smart Kinship Inference Engine (v5.1).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/family_provider.dart';
import 'package:kinrel/core/kinship/kinship_inference_engine.dart';

void main() {
  group('KinshipInferenceEngine — v5.1 Smart Inference', () {
    test('TEST 1: Older female → mother', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1990,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Sushma',
        gender: 'female',
        birthYear: 1965,
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates, isNotEmpty);
      expect(candidates.first.key, 'mother',
          reason: 'A 25-year-older female should be inferred as mother');
      expect(candidates.first.confidence, greaterThanOrEqualTo(0.85));
    });

    test('TEST 2: Older male → father', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1990,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Rajesh',
        gender: 'male',
        birthYear: 1960,
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates.first.key, 'father',
          reason: 'A 30-year-older male should be inferred as father');
    });

    test('TEST 3: Younger female → daughter', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1980,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Priya',
        gender: 'female',
        birthYear: 2010,
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates.first.key, 'daughter',
          reason: 'A 30-year-younger female should be inferred as daughter');
    });

    test('TEST 4: Younger male → son', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1980,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Arjun',
        gender: 'male',
        birthYear: 2015,
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates.first.key, 'son',
          reason: 'A 35-year-younger male should be inferred as son');
    });

    test('TEST 5: Similar-age opposite gender, no spouse → wife', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1990,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Yakshiii',
        gender: 'female',
        birthYear: 1992,
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates.first.key, 'wife',
          reason: 'Similar-age opposite gender with no existing spouse '
              'should be inferred as wife');
    });

    test('TEST 6: Similar-age same gender → brother', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1990,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Yakshiii',
        gender: 'male',
        birthYear: 1992,
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates.first.key, 'brother',
          reason: 'Similar-age same-gender males should be inferred as brothers');
    });

    test('TEST 7: Always returns at least 4 candidates (fallback chain)', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'A',
        gender: 'male',
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'B',
        gender: 'male',
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      // Should have at least: father, son, husband, brother (4 fundamental types)
      expect(candidates.length, greaterThanOrEqualTo(4),
          reason: 'Fallback chain must ensure at least 4 candidates');

      // Verify all 4 fundamental types are present
      final keys = candidates.map((c) => c.key).toSet();
      expect(keys.contains('father'), isTrue);
      expect(keys.contains('son'), isTrue);
      expect(keys.contains('husband'), isTrue);
      expect(keys.contains('brother'), isTrue);
    });

    test('TEST 8: Candidates are sorted by confidence (highest first)', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1990,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Sushma',
        gender: 'female',
        birthYear: 1965,
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      for (int i = 0; i < candidates.length - 1; i++) {
        expect(candidates[i].confidence,
            greaterThanOrEqualTo(candidates[i + 1].confidence),
            reason: 'Candidates must be sorted by confidence descending');
      }
    });

    test('TEST 9: Existing spouse reduces spouse inference confidence', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
        birthYear: 1990,
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Priya',
        gender: 'female',
        birthYear: 1992,
      );

      // A already has a spouse
      final existingRels = [
        FamilyRelationship(
          id: 'r1',
          familyId: 'fam',
          fromPersonId: 'A',
          toPersonId: 'C',
          relationshipKey: 'wife',
        ),
      ];

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: existingRels,
      );

      // With an existing spouse, the spouse inference should NOT be the top candidate
      expect(candidates.first.key, isNot('wife'),
          reason: 'When A already has a spouse, spouse should not be the '
              'top inference for a similar-age opposite-gender person');
    });

    test('TEST 10: labelFor converts keys to human-readable labels', () {
      expect(KinshipInferenceEngine.labelFor('father'), 'Father');
      expect(KinshipInferenceEngine.labelFor('mother'), 'Mother');
      expect(KinshipInferenceEngine.labelFor('son'), 'Son');
      expect(KinshipInferenceEngine.labelFor('daughter'), 'Daughter');
      expect(KinshipInferenceEngine.labelFor('husband'), 'Husband');
      expect(KinshipInferenceEngine.labelFor('wife'), 'Wife');
      expect(KinshipInferenceEngine.labelFor('brother'), 'Brother');
      expect(KinshipInferenceEngine.labelFor('sister'), 'Sister');
      expect(KinshipInferenceEngine.labelFor('parent'), 'Parent');
      expect(KinshipInferenceEngine.labelFor('child'), 'Child');
      expect(KinshipInferenceEngine.labelFor('sibling'), 'Sibling');
      expect(KinshipInferenceEngine.labelFor('spouse'), 'Spouse');
    });

    test('TEST 11: No birth year + opposite gender + no spouse → spouse', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Priya',
        gender: 'female',
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates.first.key, 'wife',
          reason: 'No birth year + opposite gender + no spouse → wife');
    });

    test('TEST 12: No birth year + same gender → sibling', () {
      final personA = Person(
        id: 'A',
        familyId: 'fam',
        name: 'Manish',
        gender: 'male',
      );
      final personB = Person(
        id: 'B',
        familyId: 'fam',
        name: 'Arjun',
        gender: 'male',
      );

      final candidates = KinshipInferenceEngine.infer(
        personA: personA,
        personB: personB,
        existingRelationships: const [],
      );

      expect(candidates.first.key, 'brother',
          reason: 'No birth year + same gender → brother');
    });
  });
}
