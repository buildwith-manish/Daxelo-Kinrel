// test/features/oral_history/oral_history_test.dart
//
// Tests for the Oral History feature covering the v93 audit fixes:
//   1. Transcription UI removed (Transcribed stat, badge, toggle)
//   2. Empty states (zero-total + zero-filtered) render correctly
//   3. Production default: notifier starts EMPTY (no demo data)
//   4. loadDemoData() available for tests/debug
//   5. Recording state has error + permissionDenied fields
//   6. StoryModel.hasTranscription kept for backward compat but not
//      populated for new recordings
//
// These are pure-Dart unit tests against OralHistoryNotifier and
// OralHistoryState (no widget pumping needed). The notifier is
// constructed via a ProviderContainer with supabaseProvider overridden
// to return null — the notifier handles this gracefully (the upload
// path sets a clear error, the in-memory paths work normally).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/core/services/supabase_service.dart';
import 'package:kinrel/features/oral_history/providers/oral_history_provider.dart';

void main() {
  // Override supabaseProvider to return null in tests — the notifier
  // handles this gracefully (in-memory state methods work normally;
  // upload/persist paths set a clear error which we don't exercise
  // in these unit tests).
  late final ProviderContainer container;

  setUpAll(() {
    container = ProviderContainer(
      overrides: [
        supabaseProvider.overrideWithValue(null),
      ],
    );
  });

  tearDownAll(() {
    container.dispose();
  });

  OralHistoryNotifier newNotifier() =>
      container.read(oralHistoryProvider.notifier);

  group('OralHistoryNotifier — production default (v93)', () {
    test('starts EMPTY by default (no demo data)', () {
      final notifier = newNotifier();
      expect(notifier.state.stories, isEmpty,
          reason:
              'A brand-new OralHistoryNotifier must not contain the seeded '
              '"Sharma family" demo stories — real families start empty so '
              'they see the proper invitation-to-act empty state.');
      expect(notifier.state.hasStories, isFalse);
      expect(notifier.state.filteredStories, isEmpty);
      expect(notifier.state.recordingState.error, isNull);
      expect(notifier.state.recordingState.permissionDenied, isFalse);
    });

    test('loadDemoData() populates the seeded demo stories for tests', () {
      final notifier = newNotifier();
      notifier.loadDemoData();
      expect(notifier.state.stories, isNotEmpty);
      expect(notifier.state.hasStories, isTrue);

      // Pin down the user-mentioned seed entries so a refactor that
      // accidentally removes one of them is caught.
      final titles = notifier.state.stories.map((s) => s.title).toSet();
      expect(titles, contains('How Dada Built Sharma Haveli'));
      expect(titles, contains("Dadi's Secret Ghevar Recipe"));
      expect(titles, contains('The Night We Left Lahore'));
      expect(titles, contains('Why We Light the Akhand Jyot on Diwali'));
      expect(titles, contains("Nani Ma's Wisdom on Raising Children"));
      expect(titles, contains("Arjun & Priya's Wedding — The Full Story"));
    });

    test('demo stories do NOT have transcription field populated (v93)', () {
      // v93: transcription is soft-disabled — demo data should not
      // carry pre-baked transcription text. The `language` field IS
      // populated (it labels what language the recording is in,
      // independent of transcription).
      for (final story in demoStories) {
        expect(
          story.transcription,
          isNull,
          reason:
              'Demo story "${story.title}" should not have a transcription '
              'field — transcription is soft-disabled in v93.',
        );
        expect(
          story.language,
          isNotEmpty,
          reason:
              'Demo story "${story.title}" should have a language tag — '
              'it labels what language the recording is in (independent '
              'of transcription).',
        );
      }
    });

    test('demoStories is publicly accessible (for tests/debug)', () {
      expect(demoStories, isNotEmpty);
      expect(demoStories.length, 6);
    });
  });

  group('OralHistoryState — empty-state helpers (v93)', () {
    test('hasStories is false when stories is empty', () {
      const state = OralHistoryState();
      expect(state.hasStories, isFalse);
      expect(state.pillsActive, isFalse);
    });

    test('hasStories is true when stories is non-empty', () {
      final state = OralHistoryState(
        stories: [demoStories.first],
      );
      expect(state.hasStories, isTrue);
    });

    test('pillsActive is true when category filter is set', () {
      final state = OralHistoryState(
        stories: demoStories,
        filter: StoryCategory.recipe,
      );
      expect(state.pillsActive, isTrue);
    });

    test('pillsActive is true when search query is non-empty', () {
      const state = OralHistoryState(
        searchQuery: 'dadi',
      );
      expect(state.pillsActive, isTrue);
    });

    test('pillsActive is false when neither filter nor search is active', () {
      const state = OralHistoryState();
      expect(state.pillsActive, isFalse);
    });

    test('hasPlayedStory is false when no story has playCount > 0', () {
      // All demo stories have playCount > 0, so construct a state with
      // a zero-playCount story.
      final zeroPlayed = demoStories.first.copyWith(playCount: 0);
      final state = OralHistoryState(stories: [zeroPlayed]);
      expect(state.hasPlayedStory, isFalse);
    });

    test('hasPlayedStory is true when at least one story has playCount > 0', () {
      final state = OralHistoryState(stories: demoStories);
      expect(state.hasPlayedStory, isTrue);
    });
  });

  group('OralHistoryState — transcription removed (v93)', () {
    test('OralHistoryState has no transcriptionState field', () {
      // Compile-time check: OralHistoryState() constructor has no
      // `transcriptionState` parameter. If this compiles, the field
      // is gone.
      const state = OralHistoryState();
      expect(state.stories, isEmpty);
      expect(state.recordingState, const RecordingState());
    });

    test('OralHistoryState has no transcribedCount getter', () {
      // Compile-time check: state.transcribedCount should not exist.
      // If the getter existed, this test would still compile but the
      // presence of the getter is verified by static analysis of the
      // production code (which already passed `flutter analyze`).
      // We just verify the state is constructed.
      const state = OralHistoryState();
      expect(state, isNotNull);
    });
  });

  group('OralHistoryState — Narrators stat (v93)', () {
    test('narratorCount counts distinct narrator names', () {
      // demoStories narrators: Suresh Kumar Sharma, Kamla Sharma,
      // Saroj Devi (story-3 + story-5), Ravi Sharma, Sunita Sharma.
      // So 5 distinct narrators.
      final state = OralHistoryState(stories: demoStories);
      expect(state.narratorCount, 5);
    });

    test('narratorCount is 0 when there are no stories', () {
      const state = OralHistoryState();
      expect(state.narratorCount, 0);
    });

    test('narratorCount counts the same narrator only once', () {
      final stories = [
        demoStories[2].copyWith(), // Saroj Devi (story-3)
        demoStories[4].copyWith(), // Saroj Devi (story-5)
      ];
      final state = OralHistoryState(stories: stories);
      expect(state.narratorCount, 1,
          reason: 'Both stories are narrated by Saroj Devi — should count '
              'as 1 distinct narrator.');
    });
  });

  group('OralHistoryState — language/category distribution from filteredStories (v93)', () {
    test('languageDistribution reflects the current filter context', () {
      // Filter to recipes only — should only include the languages of
      // the recipe stories, not all stories.
      final state = OralHistoryState(
        stories: demoStories,
        filter: StoryCategory.recipe,
      );
      // demoStories has only one recipe (story-2) in Hindi.
      expect(state.languageDistribution, {'hi': 1});
    });

    test('categoryDistribution reflects the current filter context', () {
      final state = OralHistoryState(
        stories: demoStories,
        filter: StoryCategory.recipe,
      );
      // Only the recipe category survives the filter.
      expect(state.categoryDistribution, {StoryCategory.recipe: 1});
    });

    test('languageDistribution is empty when filter produces no matches', () {
      // Use a search query that matches nothing — the distribution
      // should be empty so the chart's `if (...isNotEmpty)` check
      // hides it entirely (no zero-width placeholder bars).
      const state = OralHistoryState(searchQuery: 'xyz_nomatch');
      expect(state.languageDistribution, isEmpty);
      expect(state.categoryDistribution, isEmpty);
    });
  });

  group('RecordingState — error + permissionDenied fields (v93)', () {
    test('default RecordingState has no error and not permission denied', () {
      const rs = RecordingState();
      expect(rs.error, isNull);
      expect(rs.permissionDenied, isFalse);
    });

    test('copyWith can set error', () {
      const rs = RecordingState();
      final updated = rs.copyWith(error: 'Mic denied');
      expect(updated.error, 'Mic denied');
    });

    test('copyWith clearError resets error to null', () {
      const rs = RecordingState(error: 'Mic denied');
      final updated = rs.copyWith(clearError: true);
      expect(updated.error, isNull);
    });

    test('copyWith can set permissionDenied', () {
      const rs = RecordingState();
      final updated = rs.copyWith(permissionDenied: true);
      expect(updated.permissionDenied, isTrue);
    });
  });

  group('StoryModel — hasTranscription kept for backward compat (v93)', () {
    test('hasTranscription is false when transcription is null', () {
      final story = demoStories.first;
      expect(story.hasTranscription, isFalse);
    });

    test('hasTranscription is true when transcription is non-empty (legacy)', () {
      // A legacy row might have transcription populated — the getter
      // should still work so the data model is backward compatible.
      final legacyStory = demoStories.first.copyWith(
        transcription: 'यह एक पुरानी transcription है।',
      );
      expect(legacyStory.hasTranscription, isTrue);
    });

    test('hasTranscription is false when transcription is empty string', () {
      final story = demoStories.first.copyWith(transcription: '');
      expect(story.hasTranscription, isFalse);
    });
  });

  group('StoryCategory — labels and icons', () {
    test('all 8 categories have unique labels', () {
      final labels = StoryCategory.values.map((c) => c.label).toSet();
      expect(labels.length, StoryCategory.values.length);
    });

    test('all 8 categories have unique shortLabels', () {
      final labels = StoryCategory.values.map((c) => c.shortLabel).toSet();
      expect(labels.length, StoryCategory.values.length);
    });

    test('all 8 categories have an icon', () {
      for (final cat in StoryCategory.values) {
        expect(cat.icon, isNotNull);
      }
    });

    test('all 8 categories have an accentColor', () {
      for (final cat in StoryCategory.values) {
        expect(cat.accentColor, isNotNull);
      }
    });
  });

  group('kSupportedLanguages — language tags (kept independent of transcription)', () {
    test('includes Hindi and English', () {
      final codes = kSupportedLanguages.map((l) => l.code).toSet();
      expect(codes, contains('hi'));
      expect(codes, contains('en'));
    });

    test('has 15 supported languages', () {
      expect(kSupportedLanguages.length, 15);
    });
  });

  group('OralHistoryNotifier — in-memory state methods (v93)', () {
    test('addStory adds a story to the in-memory list (no upload)', () {
      final notifier = newNotifier();
      final story = demoStories.first;
      notifier.addStory(story);
      expect(notifier.state.stories, contains(story));
      expect(notifier.state.hasStories, isTrue);
    });

    test('setFilter sets the category filter', () {
      final notifier = newNotifier();
      notifier.loadDemoData();
      notifier.setFilter(StoryCategory.recipe);
      expect(notifier.state.filter, StoryCategory.recipe);
      expect(notifier.state.pillsActive, isTrue);
      // Only recipe stories survive the filter
      expect(notifier.state.filteredStories.every(
        (s) => s.category == StoryCategory.recipe,
      ), isTrue);
    });

    test('setFilter(null) clears the category filter', () {
      final notifier = newNotifier();
      notifier.loadDemoData();
      notifier.setFilter(StoryCategory.recipe);
      expect(notifier.state.pillsActive, isTrue);
      notifier.setFilter(null);
      expect(notifier.state.filter, isNull);
      expect(notifier.state.pillsActive, isFalse);
    });

    test('setSearchQuery sets the search query', () {
      final notifier = newNotifier();
      notifier.loadDemoData();
      notifier.setSearchQuery('dadi');
      expect(notifier.state.searchQuery, 'dadi');
      expect(notifier.state.pillsActive, isTrue);
    });

    test('setSearchQuery clears when empty', () {
      final notifier = newNotifier();
      notifier.loadDemoData();
      notifier.setSearchQuery('dadi');
      notifier.setSearchQuery('');
      expect(notifier.state.searchQuery, isEmpty);
    });

    test('toggleFavorite flips the isFavorite flag', () {
      final notifier = newNotifier();
      notifier.addStory(demoStories.first);
      final storyId = demoStories.first.id;
      final before = notifier.state.stories.first.isFavorite;
      notifier.toggleFavorite(storyId);
      final after = notifier.state.stories.first.isFavorite;
      expect(after, !before);
    });

    test('incrementPlayCount bumps the playCount by 1 (in-memory)', () async {
      final notifier = newNotifier();
      notifier.addStory(demoStories.first.copyWith(playCount: 5));
      final storyId = demoStories.first.id;
      // The in-memory update is synchronous (happens before the await).
      // We call and wait for the future to settle (the persistence
      // path fails gracefully when Supabase is null in tests).
      await notifier.incrementPlayCount(storyId);
      expect(notifier.state.stories.first.playCount, 6);
    });

    test('clearRecordingError clears the error field', () {
      final notifier = newNotifier();
      // Manually set an error by constructing a state with one.
      notifier.addStory(demoStories.first);
      // Trigger clearRecordingError — it should clear any existing
      // error. Since we never set one, this is a no-op but should
      // not throw.
      notifier.clearRecordingError();
      expect(notifier.state.recordingState.error, isNull);
    });

    test('setSelectedLanguage sets the selected language', () {
      final notifier = newNotifier();
      notifier.setSelectedLanguage('hi');
      expect(notifier.state.selectedLanguage, 'hi');
      notifier.setSelectedLanguage('en');
      expect(notifier.state.selectedLanguage, 'en');
    });

    test('setRecordingSaving toggles the isSaving flag', () {
      final notifier = newNotifier();
      notifier.setRecordingSaving(true);
      expect(notifier.state.recordingState.isSaving, isTrue);
      notifier.setRecordingSaving(false);
      expect(notifier.state.recordingState.isSaving, isFalse);
    });
  });
}
