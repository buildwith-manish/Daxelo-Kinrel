// test/features/story_threads/story_threads_test.dart
// P7.4a — Family Story Threads tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/story_threads/providers/story_threads_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7.4a — Story Threads', () {
    test('StoryThread constructs correctly', () {
      final thread = StoryThread(
        id: 't1',
        personId: 'p1',
        personName: 'Grandpa',
        prompt: 'Share a memory',
        createdAt: DateTime(2026),
      );
      expect(thread.id, equals('t1'));
      expect(thread.personName, equals('Grandpa'));
    });

    test('addThread adds to state', () {
      final controller = StoryThreadsController();
      controller.addThread(StoryThread(
        id: 't1', personId: 'p1', personName: 'A', prompt: 'Test', createdAt: DateTime.now(),
      ));
      expect(controller.state.threads.length, equals(1));
      controller.dispose();
    });

    test('removeThread removes from state', () {
      final controller = StoryThreadsController();
      controller.addThread(StoryThread(
        id: 't1', personId: 'p1', personName: 'A', prompt: 'Test', createdAt: DateTime.now(),
      ));
      controller.removeThread('t1');
      expect(controller.state.threads, isEmpty);
      controller.dispose();
    });

    test('story prompts are neutral (no guilt/urgency)', () {
      for (final prompt in storyPrompts) {
        expect(prompt.toLowerCase(), isNot(contains('don\'t forget')));
        expect(prompt.toLowerCase(), isNot(contains('only')));
        expect(prompt.toLowerCase(), isNot(contains('streak')));
      }
    });

    test('story prompts are open-ended', () {
      for (final prompt in storyPrompts) {
        expect(prompt.contains('[person]'), isTrue,
            reason: 'Prompts should be personalized with [person] placeholder');
      }
    });
  });
}
