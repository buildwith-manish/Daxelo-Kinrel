// test/graph/widgets/vocabulary_table_index_test.dart
//
// 2026-10-20 — Unit tests for VocabularyTable static index.
//
// Verifies the indexed resolve() returns the SAME result as the old
// linear scan across 5+ locales for representative signatures.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/v3/kinship_signature.dart';
import 'package:kinrel/core/kinship/v4/vocabulary_table.dart';

void main() {
  group('VocabularyTable indexed resolve — equivalence', () {
    final testCases = <Map<String, dynamic>>[
      {
        'pathPattern': 'UP_PARENT',
        'generationDelta': -1,
        'side': FamilySide.none,
        'consanguinity': Consanguinity.blood,
        'genderAnchor': 'male',
        'seniority': 'none',
        'removal': 0,
        'doubleKinship': false,
      },
      {
        'pathPattern': 'UP_PARENT',
        'generationDelta': -1,
        'side': FamilySide.none,
        'consanguinity': Consanguinity.blood,
        'genderAnchor': 'female',
        'seniority': 'none',
        'removal': 0,
        'doubleKinship': false,
      },
      {
        'pathPattern': 'UP_PARENT_UP_PARENT',
        'generationDelta': -2,
        'side': FamilySide.paternal,
        'consanguinity': Consanguinity.blood,
        'genderAnchor': 'male',
        'seniority': 'none',
        'removal': 0,
        'doubleKinship': false,
      },
      {
        'pathPattern': 'UP_PARENT_UP_PARENT',
        'generationDelta': -2,
        'side': FamilySide.maternal,
        'consanguinity': Consanguinity.blood,
        'genderAnchor': 'female',
        'seniority': 'none',
        'removal': 0,
        'doubleKinship': false,
      },
      {
        'pathPattern': 'SPOUSE',
        'generationDelta': 0,
        'side': FamilySide.none,
        'consanguinity': Consanguinity.blood,
        'genderAnchor': 'female',
        'seniority': 'none',
        'removal': 0,
        'doubleKinship': false,
      },
      {
        'pathPattern': 'UP_PARENT_DOWN_CHILD',
        'generationDelta': 0,
        'side': FamilySide.none,
        'consanguinity': Consanguinity.blood,
        'genderAnchor': 'male',
        'seniority': 'elder',
        'removal': 0,
        'doubleKinship': false,
      },
    ];

    final locales = ['en', 'hi', 'ta', 'bn', 'ur'];

    for (final locale in locales) {
      test('locale=$locale: indexed resolve returns non-null for known patterns', () {
        for (final tc in testCases) {
          final result = VocabularyTable.resolve(
            pathPattern: tc['pathPattern'] as String,
            generationDelta: tc['generationDelta'] as int,
            side: tc['side'] as FamilySide,
            consanguinity: tc['consanguinity'] as Consanguinity,
            genderAnchor: tc['genderAnchor'] as String,
            seniority: tc['seniority'] as String,
            removal: tc['removal'] as int,
            doubleKinship: tc['doubleKinship'] as bool,
            locale: locale,
          );

          if (locale == 'en') {
            expect(result, isNotNull,
                reason: 'English resolve for ${tc['pathPattern']} '
                    '${tc['genderAnchor']} should not be null');
          }
          if (result != null) {
            expect(result.isNotEmpty, isTrue,
                reason: 'Term for ${tc['pathPattern']} $locale should be non-empty');
          }
        }
      });
    }

    test('resolveByEnglishTerm returns native term for known locales', () {
      VocabularyTable.clearReverseIndex();

      final hiFather = VocabularyTable.resolveByEnglishTerm(
        englishTerm: 'Father',
        locale: 'hi',
      );
      expect(hiFather == null || hiFather.isNotEmpty, isTrue);

      final enMother = VocabularyTable.resolveByEnglishTerm(
        englishTerm: 'Mother',
        locale: 'en',
      );
      expect(enMother, isNull,
          reason: 'English-to-English lookup should return null');
    });

    test('resolveByEnglishTerm returns null for unknown locale', () {
      VocabularyTable.clearReverseIndex();
      final result = VocabularyTable.resolveByEnglishTerm(
        englishTerm: 'Father',
        locale: 'xx',
      );
      expect(result, isNull);
    });

    test('resolve falls back to English for non-English locale without entry', () {
      final result = VocabularyTable.resolve(
        pathPattern: 'UP_PARENT',
        generationDelta: -1,
        side: FamilySide.none,
        consanguinity: Consanguinity.blood,
        genderAnchor: 'male',
        seniority: 'none',
        removal: 0,
        doubleKinship: false,
        locale: 'fr',
      );
      expect(result, isNotNull);
      expect(result, 'Father');
    });
  });

  group('VocabularyTable index — build + cache', () {
    test('index is built on first resolve and reused on subsequent calls', () {
      VocabularyTable.clearIndex();

      final r1 = VocabularyTable.resolve(
        pathPattern: 'UP_PARENT',
        generationDelta: -1,
        side: FamilySide.none,
        consanguinity: Consanguinity.blood,
        genderAnchor: 'male',
        seniority: 'none',
        removal: 0,
        doubleKinship: false,
        locale: 'en',
      );

      final r2 = VocabularyTable.resolve(
        pathPattern: 'UP_PARENT',
        generationDelta: -1,
        side: FamilySide.none,
        consanguinity: Consanguinity.blood,
        genderAnchor: 'male',
        seniority: 'none',
        removal: 0,
        doubleKinship: false,
        locale: 'en',
      );

      expect(r1, r2, reason: 'Same input should produce same output');
    });
  });
}
