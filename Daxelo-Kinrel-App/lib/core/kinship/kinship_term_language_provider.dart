// lib/core/kinship/kinship_term_language_provider.dart
//
// DAXELO KINREL — Kinship Term Language Provider (2026-10-20)
//
// Separate from localeProvider (the APP UI locale). This controls which
// language the kinship TERMS on the graph are displayed in. Users can
// pick 'auto' (follow app locale) or any code in languageCodeToName.
//
// Persisted to SecureStorage (same pattern as localeProvider).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';
import 'language_code_map.dart';

/// The kinship term language preference.
///
/// Values:
///   'auto' — follow the app's UI locale (default)
///   any key from languageCodeToName (e.g. 'hi', 'ta', 'en')
///
/// Persisted to SecureStorage under key 'kinship_term_language'.
final kinshipTermLanguageProvider = StateNotifierProvider<
    KinshipTermLanguageNotifier, String>((ref) {
  return KinshipTermLanguageNotifier(ref);
});

/// Whether to show the English term beneath the primary kinship term.
///
/// When true (default), nodes show two lines:
///   "Bhabhi"       (primary, bold, large)
///   "Sister-in-law" (secondary, regular, small)
///
/// When false, only the primary term is shown.
///
/// Persisted to SecureStorage under key 'show_english_subtitle'.
final showEnglishSubtitleProvider = StateNotifierProvider<
    ShowEnglishSubtitleNotifier, bool>((ref) {
  return ShowEnglishSubtitleNotifier(ref);
});

/// Resolves the effective kinship term locale code.
///
/// When the preference is 'auto', returns the app locale's language code.
/// Otherwise returns the stored preference.
///
/// Usage:
///   final lang = ref.watch(effectiveKinshipLanguageProvider);
///   // lang == 'hi', 'ta', 'en', etc.
final effectiveKinshipLanguageProvider = Provider<String>((ref) {
  final pref = ref.watch(kinshipTermLanguageProvider);
  if (pref != 'auto') return pref;
  // 'auto' → follow app locale
  // localeProvider is read here (not watched) so this provider only
  // rebuilds when kinshipTermLanguageProvider changes, not on every
  // locale change. The consumer (the label computation) reads both.
  final locale = ref.read(_appLocaleProvider);
  if (locale != null && languageCodeToName.containsKey(locale)) {
    return locale;
  }
  return 'en'; // fallback to English
});

/// A proxy for the app locale so this file doesn't import theme_provider.dart
/// (which would create a circular dependency). The consumer sets this.
final _appLocaleProvider = StateProvider<String?>((ref) => null);

/// Sets the app locale for the 'auto' fallback. Called from main.dart
/// or the app widget when localeProvider changes.
void setAppLocaleForKinship(WidgetRef ref, String? localeCode) {
  ref.read(_appLocaleProvider.notifier).state = localeCode;
}

class KinshipTermLanguageNotifier extends StateNotifier<String> {
  KinshipTermLanguageNotifier(this._ref) : super('auto') {
    _load();
  }

  final Ref _ref;
  static const _key = 'kinship_term_language';

  Future<void> _load() async {
    try {
      final storage = _ref.read(secureStorageProvider);
      final saved = await storage.read(key: _key);
      if (saved != null && saved.isNotEmpty) {
        state = saved;
      }
    } catch (e) {
      debugPrint('⚠️ KinshipTermLanguage: failed to load: $e');
    }
  }

  Future<void> set(String languageCode) async {
    state = languageCode;
    try {
      final storage = _ref.read(secureStorageProvider);
      await storage.write(key: _key, value: languageCode);
    } catch (e) {
      debugPrint('⚠️ KinshipTermLanguage: failed to save: $e');
    }
  }
}

class ShowEnglishSubtitleNotifier extends StateNotifier<bool> {
  ShowEnglishSubtitleNotifier(this._ref) : super(true) {
    _load();
  }

  final Ref _ref;
  static const _key = 'show_english_subtitle';

  Future<void> _load() async {
    try {
      final storage = _ref.read(secureStorageProvider);
      final saved = await storage.read(key: _key);
      if (saved != null) {
        state = saved == 'true';
      }
    } catch (e) {
      debugPrint('⚠️ ShowEnglishSubtitle: failed to load: $e');
    }
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final storage = _ref.read(secureStorageProvider);
      await storage.write(key: _key, value: value.toString());
    } catch (e) {
      debugPrint('⚠️ ShowEnglishSubtitle: failed to save: $e');
    }
  }
}
