// test/core/utils/form_validators_test.dart
//
// v2.2 — Tests for the web-safe nameValidator regex.
//
// Verifies that names with digits ("T1"), ASCII names, Hindi/Devanagari
// names, and European accented names all pass validation. This was the
// root cause of the "Next button permanently disabled" bug on Flutter Web.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/utils/form_validators.dart';

void main() {
  group('nameValidator — web-safe regex', () {
    test('returns null for valid ASCII names', () {
      expect(nameValidator('John'), isNull);
      expect(nameValidator('Mary Jane'), isNull);
      expect(nameValidator("O'Brien"), isNull);
      expect(nameValidator('Anne-Marie'), isNull);
      expect(nameValidator('Dr. Smith'), isNull);
    });

    test('returns null for names with digits (e.g. "T1")', () {
      // This was the bug — "T1" was rejected on web because \p{N} is
      // not supported by dart2js.
      expect(nameValidator('T1'), isNull);
      expect(nameValidator('Test 1'), isNull);
      expect(nameValidator('Example 2'), isNull);
      expect(nameValidator('Family 123'), isNull);
    });

    test('returns null for Hindi/Devanagari names', () {
      expect(nameValidator('अर्जुन'), isNull); // Arjun
      expect(nameValidator('प्रिया'), isNull); // Priya
      expect(nameValidator('राज कुमार'), isNull); // Raj Kumar
    });

    test('returns null for Bengali names', () {
      expect(nameValidator('অর্জুন'), isNull); // Arjun in Bengali
      expect(nameValidator('প্রিয়া'), isNull); // Priya in Bengali
    });

    test('returns null for European accented names', () {
      expect(nameValidator('Renée'), isNull);
      expect(nameValidator('François'), isNull);
      expect(nameValidator('Müller'), isNull);
      expect(nameValidator('José'), isNull);
    });

    test('returns error for empty or null names', () {
      expect(nameValidator(null), isNotNull);
      expect(nameValidator(''), isNotNull);
      expect(nameValidator('   '), isNotNull);
    });

    test('returns error for names shorter than 2 characters', () {
      expect(nameValidator('A'), isNotNull);
      expect(nameValidator('T'), isNotNull);
    });

    test('returns error for names with special characters', () {
      expect(nameValidator('John@'), isNotNull);
      expect(nameValidator('John#'), isNotNull);
      expect(nameValidator('John!'), isNotNull);
      expect(nameValidator('John\$'), isNotNull);
    });
  });

  group('nameValidator — regression: button enablement', () {
    // This is the exact scenario that was broken on web:
    // User types "T1" in the name field → nameValidator returns null
    // → _canProceed() returns true → "Next" button enables.
    test('"T1" passes validation (regression test for web bug)', () {
      final result = nameValidator('T1');
      expect(result, isNull,
          reason: 'Name "T1" must pass validation so the Next button '
              'enables on Flutter Web. This was broken because \\p{N} '
              'is not supported by dart2js.');
    });

    test('"Test 1" passes validation (regression test)', () {
      final result = nameValidator('Test 1');
      expect(result, isNull);
    });
  });
}
