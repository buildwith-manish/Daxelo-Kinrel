// test/features/kinship_pronunciation/kinship_pronunciation_provider_test.dart
//
// P9.2c — Kinship pronunciation tests.
// Verifies honest behaviour when no audio is available.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/kinship_pronunciation/providers/kinship_pronunciation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2c — KinshipPronunciationNotifier', () {
    test('select does NOT auto-play', () {
      final n = KinshipPronunciationNotifier();
      n.select(const KinshipPronunciation(
        term: 'Dadi',
        phonetic: 'DAA-dee',
        languageCode: 'hi',
        audioUrl: 'https://example.com/dadi.mp3',
      ));
      expect(n.state.current?.term, 'Dadi');
      expect(n.state.isPlaying, isFalse);
      n.dispose();
    });

    test('play with audio sets isPlaying', () {
      final n = KinshipPronunciationNotifier();
      n.select(const KinshipPronunciation(
        term: 'Dadi',
        phonetic: 'DAA-dee',
        languageCode: 'hi',
        audioUrl: 'asset://dadi.mp3',
      ));
      n.play();
      expect(n.state.isPlaying, isTrue);
      expect(n.state.playbackError, isNull);
      n.dispose();
    });

    test('play WITHOUT audio is honest: does not fake playback', () {
      final n = KinshipPronunciationNotifier();
      n.select(const KinshipPronunciation(
        term: 'Chitappa',
        phonetic: 'CHI-tup-paa',
        languageCode: 'ta',
        audioUrl: null,
      ));
      n.play();
      expect(n.state.isPlaying, isFalse);
      expect(n.state.playbackError, isNotNull);
      // Honest copy mentions the phonetic guide, not a fake success.
      expect(n.state.playbackError!.toLowerCase(), contains('phonetic'));
      n.dispose();
    });

    test('stop records the term in recentlyPlayed (bounded)', () {
      final n = KinshipPronunciationNotifier();
      n.select(const KinshipPronunciation(
        term: 'Dadi',
        phonetic: 'DAA-dee',
        languageCode: 'hi',
        audioUrl: 'asset://dadi.mp3',
      ));
      n.play();
      n.stop();
      expect(n.state.recentlyPlayed, hasLength(1));
      expect(n.state.recentlyPlayed.first.term, 'Dadi');
      n.dispose();
    });

    test('recentlyPlayed de-duplicates by term', () {
      final n = KinshipPronunciationNotifier();
      const pron = KinshipPronunciation(
        term: 'Dadi',
        phonetic: 'DAA-dee',
        languageCode: 'hi',
        audioUrl: 'asset://dadi.mp3',
      );
      n.select(pron);
      n.play();
      n.stop();
      n.select(pron);
      n.play();
      n.stop();
      expect(n.state.recentlyPlayed.where((p) => p.term == 'Dadi'), hasLength(1));
      n.dispose();
    });

    test('clear resets everything', () {
      final n = KinshipPronunciationNotifier();
      n.select(const KinshipPronunciation(
        term: 'Dadi',
        phonetic: 'DAA-dee',
        languageCode: 'hi',
        audioUrl: 'asset://dadi.mp3',
      ));
      n.clear();
      expect(n.state.current, isNull);
      expect(n.state.recentlyPlayed, isEmpty);
      n.dispose();
    });

    test('hasAudio reflects url presence', () {
      const withAudio = KinshipPronunciation(
        term: 'A',
        phonetic: 'A',
        languageCode: 'hi',
        audioUrl: 'x',
      );
      const without = KinshipPronunciation(
        term: 'A',
        phonetic: 'A',
        languageCode: 'hi',
        audioUrl: null,
      );
      expect(withAudio.hasAudio, isTrue);
      expect(without.hasAudio, isFalse);
    });
  });
}
