// integration_test/test_runner.dart
//
// DAXELO KINREL — Integration Test Runner (P3-F6)
//
// Entry point for running all integration tests via:
//   flutter test integration_test/test_runner.dart
//
// This file is designed to be the single command entry point
// for CI/CD pipelines and local development testing.
//
// Test Groups:
//   1. Login Flow      — Authentication critical path
//   2. Create Family    — Family creation critical path
//   3. Add Member       — Member addition critical path
//   4. View Graph       — Graph visualization critical path
//   5. Share Profile    — Sharing critical path
//
// Prerequisites:
//   - A running device/emulator (Android/iOS)
//   - Flutter 3.41.5 / Dart 3.11.3
//   - For full E2E: Supabase backend with test credentials
//
// Environment Variables (optional):
//   - KINREL_TEST_EMAIL     — Test account email (default: test@kinrel.app)
//   - KINREL_TEST_PASSWORD  — Test account password (default: Test123456!)
//
// NOTE: Without a real Supabase backend, login-dependent tests will
// show warnings but will NOT fail. The tests are designed to be
// resilient and verify UI flow rather than API success.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_test.dart' as app_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Print a header for the test run
  debugPrint('');
  debugPrint('═══════════════════════════════════════════════════════════');
  debugPrint('  DAXELO KINREL — Integration Test Suite (P3-F6)');
  debugPrint('═══════════════════════════════════════════════════════════');
  debugPrint('');
  debugPrint('  Test Groups:');
  debugPrint('    1. Login Flow      — Splash → Sign-in → Auth');
  debugPrint('    2. Create Family   — Families tab → Create → Submit');
  debugPrint('    3. Add Member      — Family detail → Add → Relationship');
  debugPrint('    4. View Graph      — Graph tab → Canvas → Node tap');
  debugPrint('    5. Share Profile   — Profile → Share → Share sheet');
  debugPrint('');
  debugPrint('  Run: flutter test integration_test/test_runner.dart');
  debugPrint('');
  debugPrint('═══════════════════════════════════════════════════════════');
  debugPrint('');

  // Run all test groups
  app_tests.main();
}
