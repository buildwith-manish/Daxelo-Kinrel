// integration_test/app_test.dart
//
// DAXELO KINREL — Main Integration Test File (P3-F6)
//
// This file imports and runs all 5 critical path test groups:
//   1. Login Flow
//   2. Create Family
//   3. Add Member
//   4. View Graph
//   5. Share Profile
//
// Run via:
//   flutter test integration_test/app_test.dart
//
// Or run individual test groups:
//   flutter test integration_test/login_flow_test.dart
//   flutter test integration_test/create_family_test.dart
//   etc.

import 'package:integration_test/integration_test.dart';

import 'login_flow_test.dart' as login_flow;
import 'create_family_test.dart' as create_family;
import 'add_member_test.dart' as add_member;
import 'view_graph_test.dart' as view_graph;
import 'share_profile_test.dart' as share_profile;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Group 1: Login Flow ──────────────────────────────────────────
  // Tests: splash → sign-in → valid login → invalid login → sign-up nav
  login_flow.main();

  // ── Group 2: Create Family ───────────────────────────────────────
  // Tests: families tab → create button → fill name → submit → list
  create_family.main();

  // ── Group 3: Add Member ──────────────────────────────────────────
  // Tests: family detail → add member → fill name → relationship → submit
  add_member.main();

  // ── Group 4: View Graph ──────────────────────────────────────────
  // Tests: family detail → graph tab → canvas → node tap
  view_graph.main();

  // ── Group 5: Share Profile ───────────────────────────────────────
  // Tests: profile → share button → share sheet → family share
  share_profile.main();
}
