// test/features/memories/years_ago_badge_test.dart
//
// Tests for the "X years ago" badge suppression when yearsAgo == 0
// (same-year memories). Pre-fix: the badge showed "0 years ago" which
// reads awkwardly. Post-fix: the badge is suppressed entirely via
// `if (memory.yearsAgo > 0)` in the card UI, AND the `yearsAgoLabel`
// getter returns empty string as a defensive backstop.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/memories/providers/memories_provider.dart';

void main() {
  group('OnThisDayMemory.yearsAgoLabel', () {
    OnThisDayMemory makeMemory({required int yearsAgo}) {
      return OnThisDayMemory(
        id: 'm1',
        title: 'Test',
        originalDate: DateTime(2024, 1, 1),
        yearsAgo: yearsAgo,
      );
    }

    test('returns empty string when yearsAgo == 0 (same-year memory)', () {
      final m = makeMemory(yearsAgo: 0);
      expect(m.yearsAgoLabel, '',
          reason: 'Same-year memories should NOT show "0 years ago" — '
              'the badge is suppressed entirely.');
    });

    test('returns "1 year ago" (singular) when yearsAgo == 1', () {
      final m = makeMemory(yearsAgo: 1);
      expect(m.yearsAgoLabel, '1 year ago');
    });

    test('returns "2 years ago" (plural) when yearsAgo == 2', () {
      final m = makeMemory(yearsAgo: 2);
      expect(m.yearsAgoLabel, '2 years ago');
    });

    test('returns "6 years ago" when yearsAgo == 6', () {
      final m = makeMemory(yearsAgo: 6);
      expect(m.yearsAgoLabel, '6 years ago');
    });

    test('returns empty string when yearsAgo < 0 (defensive)', () {
      final m = makeMemory(yearsAgo: -1);
      expect(m.yearsAgoLabel, '',
          reason: 'Negative yearsAgo should also return empty (defensive).');
    });
  });
}
