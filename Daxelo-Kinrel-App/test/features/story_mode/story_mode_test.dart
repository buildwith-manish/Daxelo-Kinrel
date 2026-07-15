// test/features/story_mode/story_mode_test.dart
//
// P7.2 — Story Mode tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/story_mode/providers/story_mode_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7.2 — Story Mode controller', () {
    test('default state is empty with subtitles enabled', () {
      const state = StoryModeState();
      expect(state.chapters, isEmpty);
      expect(state.currentIndex, equals(0));
      expect(state.isPlaying, isFalse);
      expect(state.subtitlesEnabled, isTrue);
    });

    test('loadChapters sets chapters', () {
      final controller = StoryModeController();
      controller.loadChapters([
        const StoryChapter(
            id: '1', title: 'Ch 1', narration: 'Test', focusPersonId: 'p1'),
      ]);
      expect(controller.state.chapters.length, equals(1));
      controller.dispose();
    });

    test('play sets isPlaying=true', () {
      final controller = StoryModeController();
      controller.play();
      expect(controller.state.isPlaying, isTrue);
      controller.dispose();
    });

    test('pause sets isPaused=true', () {
      final controller = StoryModeController();
      controller.play();
      controller.pause();
      expect(controller.state.isPaused, isTrue);
      controller.dispose();
    });

    test('next advances currentIndex', () {
      final controller = StoryModeController();
      controller.loadChapters([
        const StoryChapter(id: '1', title: 'A', narration: '', focusPersonId: 'p1'),
        const StoryChapter(id: '2', title: 'B', narration: '', focusPersonId: 'p2'),
      ]);
      controller.next();
      expect(controller.state.currentIndex, equals(1));
      controller.dispose();
    });

    test('next on last chapter stops playback', () {
      final controller = StoryModeController();
      controller.loadChapters([
        const StoryChapter(id: '1', title: 'A', narration: '', focusPersonId: 'p1'),
      ]);
      controller.play();
      controller.next();
      expect(controller.state.isPlaying, isFalse);
      controller.dispose();
    });

    test('previous does not go below 0', () {
      final controller = StoryModeController();
      controller.loadChapters([
        const StoryChapter(id: '1', title: 'A', narration: '', focusPersonId: 'p1'),
      ]);
      controller.previous();
      expect(controller.state.currentIndex, equals(0));
      controller.dispose();
    });

    test('toggleSubtitles toggles subtitlesEnabled', () {
      final controller = StoryModeController();
      expect(controller.state.subtitlesEnabled, isTrue);
      controller.toggleSubtitles();
      expect(controller.state.subtitlesEnabled, isFalse);
      controller.dispose();
    });

    test('stop resets to default state', () {
      final controller = StoryModeController();
      controller.loadChapters([
        const StoryChapter(id: '1', title: 'A', narration: '', focusPersonId: 'p1'),
      ]);
      controller.play();
      controller.stop();
      expect(controller.state.chapters, isEmpty);
      expect(controller.state.isPlaying, isFalse);
      controller.dispose();
    });

    test('subtitles are always on by default (accessibility)', () {
      const state = StoryModeState();
      expect(state.subtitlesEnabled, isTrue,
          reason: 'Subtitles must be on by default per spec');
    });
  });
}
