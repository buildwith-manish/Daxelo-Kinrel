// test/graph/widgets/gender_aware_inverse_test.dart
//
// 2026-10-19 — Unit tests for the gender-aware inverse relationship
// label resolver.
//
// Verifies that `genderAwareInverse` correctly computes the reverse
// relationship label for both directions of a relationship, taking
// gender into account.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/widgets/relationship_info_sheet.dart'
    show genderAwareInverse;

void main() {
  group('genderAwareInverse — parent/child', () {
    test('mother + male target → son', () {
      expect(genderAwareInverse('mother', 'male'), 'son');
    });
    test('mother + female target → daughter', () {
      expect(genderAwareInverse('mother', 'female'), 'daughter');
    });
    test('father + male target → son', () {
      expect(genderAwareInverse('father', 'male'), 'son');
    });
    test('father + female target → daughter', () {
      expect(genderAwareInverse('father', 'female'), 'daughter');
    });
    test('son + female source → mother', () {
      // son → parent uses parent's gender
      expect(genderAwareInverse('son', 'female'), 'mother');
    });
    test('son + male source → father', () {
      expect(genderAwareInverse('son', 'male'), 'father');
    });
    test('daughter + female source → mother', () {
      expect(genderAwareInverse('daughter', 'female'), 'mother');
    });
    test('daughter + male source → father', () {
      expect(genderAwareInverse('daughter', 'male'), 'father');
    });
  });

  group('genderAwareInverse — spouse', () {
    test('husband → wife', () {
      expect(genderAwareInverse('husband', 'female'), 'wife');
    });
    test('wife → husband', () {
      expect(genderAwareInverse('wife', 'male'), 'husband');
    });
    test('spouse → spouse (neutral)', () {
      expect(genderAwareInverse('spouse', 'male'), 'spouse');
      expect(genderAwareInverse('spouse', 'female'), 'spouse');
    });
  });

  group('genderAwareInverse — sibling', () {
    test('brother + female target → sister', () {
      expect(genderAwareInverse('brother', 'female'), 'sister');
    });
    test('brother + male target → brother', () {
      expect(genderAwareInverse('brother', 'male'), 'brother');
    });
    test('sister + male target → brother', () {
      expect(genderAwareInverse('sister', 'male'), 'brother');
    });
    test('sister + female target → sister', () {
      expect(genderAwareInverse('sister', 'female'), 'sister');
    });
  });

  group('genderAwareInverse — step-family', () {
    test('stepmother + male target → stepson', () {
      expect(genderAwareInverse('stepmother', 'male'), 'stepson');
    });
    test('stepmother + female target → stepdaughter', () {
      expect(genderAwareInverse('stepmother', 'female'), 'stepdaughter');
    });
    test('stepson + female source → stepmother', () {
      expect(genderAwareInverse('stepson', 'female'), 'stepmother');
    });
    test('stepson + male source → stepfather', () {
      expect(genderAwareInverse('stepson', 'male'), 'stepfather');
    });
  });

  group('genderAwareInverse — grandparent/grandchild', () {
    test('grandmother + male target → grandson', () {
      expect(genderAwareInverse('grandmother', 'male'), 'grandson');
    });
    test('grandmother + female target → granddaughter', () {
      expect(genderAwareInverse('grandmother', 'female'), 'granddaughter');
    });
    test('grandson + female source → grandmother', () {
      expect(genderAwareInverse('grandson', 'female'), 'grandmother');
    });
    test('grandson + male source → grandfather', () {
      expect(genderAwareInverse('grandson', 'male'), 'grandfather');
    });
  });

  group('genderAwareInverse — uncle/aunt/nephew/niece', () {
    test('uncle + female target → niece', () {
      expect(genderAwareInverse('uncle', 'female'), 'niece');
    });
    test('uncle + male target → nephew', () {
      expect(genderAwareInverse('uncle', 'male'), 'nephew');
    });
    test('nephew + female source → aunt', () {
      expect(genderAwareInverse('nephew', 'female'), 'aunt');
    });
    test('nephew + male source → uncle', () {
      expect(genderAwareInverse('nephew', 'male'), 'uncle');
    });
  });

  group('genderAwareInverse — in-law', () {
    test('father_in_law + female target → daughter_in_law', () {
      expect(genderAwareInverse('father_in_law', 'female'), 'daughter_in_law');
    });
    test('father_in_law + male target → son_in_law', () {
      expect(genderAwareInverse('father_in_law', 'male'), 'son_in_law');
    });
    test('son_in_law + female source → mother_in_law', () {
      expect(genderAwareInverse('son_in_law', 'female'), 'mother_in_law');
    });
    test('son_in_law + male source → father_in_law', () {
      expect(genderAwareInverse('son_in_law', 'male'), 'father_in_law');
    });
  });

  group('genderAwareInverse — unknown gender (neutral)', () {
    test('mother + null gender → son (defaults to male)', () {
      // null gender → isFemale=false, isMale=false → returns 'son'
      // (the male form is the default when gender is unknown)
      expect(genderAwareInverse('mother', null), 'son');
    });
    test('father + null gender → son', () {
      expect(genderAwareInverse('father', null), 'son');
    });
    test('brother + null gender → brother', () {
      expect(genderAwareInverse('brother', null), 'brother');
    });
    test('spouse + null gender → spouse', () {
      expect(genderAwareInverse('spouse', null), 'spouse');
    });
  });

  group('genderAwareInverse — custom/unknown relationship name', () {
    test('custom name → returns unchanged (identity)', () {
      // Custom relationship names (e.g. "Best Friend", "Mentor") are
      // not in the switch — the default case returns the key unchanged.
      expect(genderAwareInverse('Best Friend', 'male'), 'Best Friend');
      expect(genderAwareInverse('Mentor', 'female'), 'Mentor');
      expect(genderAwareInverse('Custom Label', null), 'Custom Label');
    });
  });

  group('genderAwareInverse — cousin', () {
    test('cousin → cousin (gender-neutral)', () {
      expect(genderAwareInverse('cousin', 'male'), 'cousin');
      expect(genderAwareInverse('cousin', 'female'), 'cousin');
    });
    test('cousin_brother + female target → cousin_sister', () {
      expect(genderAwareInverse('cousin_brother', 'female'), 'cousin_sister');
    });
    test('cousin_sister + male target → cousin_brother', () {
      expect(genderAwareInverse('cousin_sister', 'male'), 'cousin_brother');
    });
  });
}
