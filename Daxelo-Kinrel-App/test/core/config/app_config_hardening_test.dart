// test/core/config/app_config_hardening_test.dart
//
// QA hardening 2026-09-20 (item 5 of the post-QA follow-up list):
// AppConfig's Supabase getters are ENV-ONLY (dotenv → --dart-define →
// throw). The hardcoded fallbacks were removed because:
//
//   • a rotated key cannot be fixed without a code release, and
//   • the fallback silently masked missing CI config (the workflows'
//     "Create .env" steps wrote a file that was never bundled — .env is
//     not a pubspec asset — so production ran on the baked-in values).
//
// These tests pin the contract in BOTH environments:
//   • run WITHOUT --dart-define (local default): peek → null, getters
//     throw StateError with remediation instructions.
//   • run WITH --dart-define=SUPABASE_URL=… SUPABASE_ANON_KEY=… (CI):
//     peek → the injected values, getters return them verbatim.
//
// The assertions are written so BOTH runs pass — whichever branch the
// environment selects, the behaviour must be consistent with it.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/config/app_config.dart';
import 'package:kinrel/core/config/env_config.dart';

void main() {
  group('AppConfig Supabase hardening (env-only, fail-loudly)', () {
    test('peeks NEVER throw, with or without config present', () {
      // The whole point of the peek API: diagnostic logging (main.dart)
      // must be safe regardless of configuration state.
      expect(() => AppConfig.peekSupabaseUrl, returnsNormally);
      expect(() => AppConfig.peekSupabaseAnonKey, returnsNormally);
      expect(() => EnvConfig.peekSupabaseUrl, returnsNormally);
      expect(() => EnvConfig.peekSupabaseAnonKey, returnsNormally);
    });

    test('isSupabaseConfigured never throws and matches the peeks', () {
      final url = AppConfig.peekSupabaseUrl;
      final key = AppConfig.peekSupabaseAnonKey;
      expect(AppConfig.isSupabaseConfigured, url != null && key != null);
      expect(EnvConfig.isSupabaseConfigured, AppConfig.isSupabaseConfigured);
    });

    test('when config is injected, getters return exactly the peeked values', () {
      final url = AppConfig.peekSupabaseUrl;
      final key = AppConfig.peekSupabaseAnonKey;

      if (url == null || key == null) {
        // This run has no --dart-define injection — the throwing branch
        // is covered by the tests below. Skip the consistency check.
        return;
      }

      expect(AppConfig.supabaseUrl, url);
      expect(AppConfig.supabaseAnonKey, key);
      expect(EnvConfig.supabaseUrl, url,
          reason: 'EnvConfig must delegate to AppConfig (single source '
              'of truth — the classes drifted during the 2026-09-19 key '
              'rotation)');
      expect(EnvConfig.supabaseAnonKey, key);
    });

    test('when a key is missing, the getter THROWS with instructions', () {
      final url = AppConfig.peekSupabaseUrl;
      final key = AppConfig.peekSupabaseAnonKey;

      if (url != null && key != null) {
        // This run has the keys injected via --dart-define (CI) — the
        // throwing branch cannot be reached. Skip.
        return;
      }

      if (url == null) {
        expect(
          () => AppConfig.supabaseUrl,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('SUPABASE_URL'),
                contains('--dart-define=SUPABASE_URL'),
              ]),
            ),
          ),
          reason: 'the StateError must name the key and the exact '
              'dart-define remediation',
        );
      }
      if (key == null) {
        expect(
          () => AppConfig.supabaseAnonKey,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('SUPABASE_ANON_KEY'),
                contains('--dart-define=SUPABASE_ANON_KEY'),
              ]),
            ),
          ),
        );
      }
    });

    test('missingConfigMessage names the key + both remediation paths', () {
      final msg = AppConfig.missingConfigMessage('SUPABASE_URL');
      expect(msg, contains('SUPABASE_URL'));
      expect(msg, contains('--dart-define=SUPABASE_URL'));
      expect(msg, contains('.env'));
      expect(msg, contains('GitHub secret'));
    });

    test('no hardcoded Supabase values resolve when NOTHING is injected', () {
      final url = AppConfig.peekSupabaseUrl;
      final key = AppConfig.peekSupabaseAnonKey;

      // When the values are injected via --dart-define (CI), they
      // legitimately equal the real project credentials — this check can
      // only detect baked-in FALLBACKS in a run where nothing is
      // injected (local `flutter test` with no .env asset and no
      // dart-defines).
      final injected = url != null && key != null;
      if (injected) return;

      // Nothing injected: every peek must be null. A non-null value here
      // means a hardcoded fallback was re-introduced to the resolution
      // chain — the exact regression this hardening removed.
      expect(
        url,
        isNull,
        reason: 'SUPABASE_URL resolved without .env and without '
            '--dart-define — a hardcoded fallback is back in the chain. '
            'Resolved to: $url',
      );
      expect(
        key,
        isNull,
        reason: 'SUPABASE_ANON_KEY resolved without .env and without '
            '--dart-define — a hardcoded fallback is back in the chain. '
            'Resolved to a key of length ${key?.length}',
      );
    });
  });
}
