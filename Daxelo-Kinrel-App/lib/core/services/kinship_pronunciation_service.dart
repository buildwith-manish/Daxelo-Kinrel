// lib/core/services/kinship_pronunciation_service.dart
//
// DAXELO KINREL — Kinship Pronunciation Service (V2.1 Audio Layer)
//
// Speaks kinship terms aloud via the device's TTS engine. Gated by
// `kEnableAudioPronunciation` in lib/core/constants/feature_flags.dart.
//
// Usage:
//   final service = KinshipPronunciationService();
//   await service.speak('पिता', languageCode: 'hi');
//   await service.speak('Father', languageCode: 'en');
//
// The service lazily initializes FlutterTts on first use, sets the speech
// language to match the requested language code, and falls back to English
// if the device doesn't support the requested language. Safe to call from
// any widget; multiple rapid calls queue onto the platform TTS engine.
//
// When `kEnableAudioPronunciation` is `false`, all public methods are
// no-ops — call sites don't need their own flag check.

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../constants/feature_flags.dart';

/// Maps Daxelo-Kinrel language codes to BCP-47 tags understood by FlutterTts.
const Map<String, String> _kTtsLanguageTags = <String, String>{
  'en': 'en-US',
  'hi': 'hi-IN',
  'bn': 'bn-IN',
  'ta': 'ta-IN',
  'te': 'te-IN',
  'mr': 'mr-IN',
  'gu': 'gu-IN',
  'kn': 'kn-IN',
  'ml': 'ml-IN',
  'pa': 'pa-IN',
};

/// Service for pronouncing kinship terms via the platform TTS engine.
///
/// Singleton-friendly: callers can construct fresh instances cheaply,
/// but the underlying [FlutterTts] is shared via a static field to avoid
/// re-initializing the platform channel on every call.
class KinshipPronunciationService {
  KinshipPronunciationService();

  static FlutterTts? _tts;
  static String? _lastLanguageCode;

  /// Lazily initializes the TTS engine. Returns null if TTS is unavailable
  /// on the current platform (e.g., headless test environment).
  Future<FlutterTts?> _getTts() async {
    if (!kEnableAudioPronunciation) return null;
    if (_tts != null) return _tts;

    try {
      final tts = FlutterTts();
      await tts.setSpeechRate(0.45); // Slightly slower for clarity.
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      _tts = tts;
      return tts;
    } catch (e) {
      debugPrint('⚠️ KinshipPronunciationService init failed: $e');
      return null;
    }
  }

  /// Speaks [text] using the device's TTS engine.
  ///
  /// [languageCode] is a 2-letter ISO 639-1 code (e.g., 'hi', 'en').
  /// Falls back to English if the requested language is unavailable.
  /// No-op when `kEnableAudioPronunciation` is `false`.
  Future<void> speak(String text, {String languageCode = 'en'}) async {
    if (!kEnableAudioPronunciation || text.trim().isEmpty) return;

    final tts = await _getTts();
    if (tts == null) return;

    // Switch language if it changed since the last call.
    if (_lastLanguageCode != languageCode) {
      final tag = _kTtsLanguageTags[languageCode] ?? 'en-US';
      final supported = await tts.isLanguageAvailable(tag);
      await tts.setLanguage(supported == true ? tag : 'en-US');
      _lastLanguageCode = languageCode;
    }

    try {
      await tts.stop();
      await tts.speak(text);
    } catch (e) {
      debugPrint('⚠️ KinshipPronunciationService.speak failed: $e');
    }
  }

  /// Stops any in-progress speech.
  Future<void> stop() async {
    if (!kEnableAudioPronunciation) return;
    final tts = _tts;
    if (tts == null) return;
    try {
      await tts.stop();
    } catch (_) {
      // Best-effort stop.
    }
  }

  /// Releases platform resources. Call from a dispose() lifecycle hook
  /// if the service was held by a long-lived object.
  Future<void> dispose() async {
    final tts = _tts;
    if (tts == null) return;
    try {
      await tts.stop();
    } catch (_) {}
    _tts = null;
    _lastLanguageCode = null;
  }
}
