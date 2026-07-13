// test/features/generational_interviews/interview_prompts_test.dart
// P7.4c — Generational interviews tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/generational_interviews/providers/interview_prompts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7.4c — Interview prompts', () {
    test('prompts are curated (not AI-generated)', () {
      // The prompts are static constants — human-curated.
      expect(InterviewPrompts.childhood, isNotEmpty);
      expect(InterviewPrompts.wisdom, isNotEmpty);
      expect(InterviewPrompts.heritage, isNotEmpty);
    });

    test('all prompts are open-ended questions', () {
      for (final prompt in InterviewPrompts.all) {
        expect(prompt.endsWith('?'), isTrue,
            reason: 'Prompt should be a question: "$prompt"');
      }
    });

    test('no guilt language in prompts', () {
      for (final prompt in InterviewPrompts.all) {
        final lower = prompt.toLowerCase();
        expect(lower, isNot(contains('don\'t forget')));
        expect(lower, isNot(contains('must')));
        expect(lower, isNot(contains('should')));
        expect(lower, isNot(contains('have to')));
      }
    });

    test('no urgency language in prompts', () {
      for (final prompt in InterviewPrompts.all) {
        final lower = prompt.toLowerCase();
        expect(lower, isNot(contains('only')));
        expect(lower, isNot(contains('last chance')));
        expect(lower, isNot(contains('hurry')));
        expect(lower, isNot(contains('before it\'s too late')));
      }
    });

    test('no comparison language in prompts', () {
      for (final prompt in InterviewPrompts.all) {
        final lower = prompt.toLowerCase();
        expect(lower, isNot(contains('other elders')));
        expect(lower, isNot(contains('most people')));
        expect(lower, isNot(contains('better than')));
      }
    });

    test('byTheme has 3 themes', () {
      expect(InterviewPrompts.byTheme.keys.length, equals(3));
      expect(InterviewPrompts.byTheme.keys, contains('Childhood & Origins'));
      expect(InterviewPrompts.byTheme.keys, contains('Life & Wisdom'));
      expect(InterviewPrompts.byTheme.keys, contains('Heritage & Traditions'));
    });

    test('all() has 15 prompts', () {
      expect(InterviewPrompts.all.length, equals(15));
    });
  });
}
