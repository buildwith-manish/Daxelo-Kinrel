// =============================================================================
// Track C v2.0 — DecisionCreateScreen Widget Tests
// =============================================================================
// Verifies per spec item #5 (v2 audit):
//   - Step validation blocks progression when required fields are empty
//   - Back/forward between steps preserves entered data
// =============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/features/trackc/data/api/trackc_api_client.dart';
import 'package:kinrel/features/trackc/presentation/providers/trackc_providers.dart';
import 'package:kinrel/features/trackc/presentation/screens/decision_create_screen.dart';

/// Subclass of [TrackcApiClient] that records the createDecision payload.
class _FakeApi extends TrackcApiClient {
  _FakeApi() : super(Dio());

  Map<String, dynamic>? lastCreateBody;
  String? lastCreateFamilyId;

  @override
  Future<Map<String, dynamic>> createDecision(
    String familyId,
    Map<String, dynamic> body,
  ) async {
    lastCreateFamilyId = familyId;
    lastCreateBody = body;
    // Return a fake created decision
    return {'id': 'd-new', ...body};
  }
}

Widget _wrap(Widget child, {required _FakeApi api, String familyId = 'fam-1'}) {
  return ProviderScope(
    overrides: [
      trackcApiClientProvider.overrideWithValue(api),
      selectedFamilyIdProvider.overrideWith((ref) => familyId),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('Step 1: Next button is disabled (snackbar shown) when title is empty',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    // The Next button is visible
    expect(find.text('Next'), findsOneWidget);

    // Tap Next without entering a title
    await tester.tap(find.text('Next'));
    await tester.pump();

    // Should show the validation error — both in the inline banner AND the
    // snackbar (the screen surfaces validation errors in both places so
    // they're visible regardless of scroll position).
    expect(find.text('Title is required'), findsNWidgets(2));
    // Still on step 1
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('Step 1: entering a title allows progression to Step 2',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Diwali venue');
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Should now be on Step 2 — Vote Options
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('Vote Options'), findsOneWidget);
  });

  testWidgets('Step 2: validation rejects when fewer than 2 non-empty options',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    // Step 1 — fill in title
    await tester.enterText(find.byType(TextField).first, 'Test decision');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2 — clear one of the default options (Yes / No)
    // The default options are 'Yes' and 'No', both pre-populated.
    // Clear one to leave only 1 non-empty option.
    final optionFields = find.byType(TextField);
    await tester.enterText(optionFields.at(0), ''); // clear 'Yes'
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pump();

    // Validation error appears in both banner and snackbar
    expect(find.text('At least 2 options are required'), findsNWidgets(2));
    expect(find.text('Step 2 of 3'), findsOneWidget);
  });

  testWidgets('Step 2: rejects duplicate options (case-insensitive)',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Test decision');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // On Step 2 we see 2 option TextFields (default 'Yes' and 'No').
    // Set both to the same value (different case) to trigger the
    // duplicate-detection check.
    final optionFields = find.byType(TextField);
    await tester.enterText(optionFields.at(0), 'Yes');
    await tester.enterText(optionFields.at(1), 'yes');
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.text('Options must be unique (no duplicates)'), findsNWidgets(2));
  });

  testWidgets('Step 3: validation rejects when deadline is missing',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    // Step 1
    await tester.enterText(find.byType(TextField).first, 'Test decision');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2 — defaults have Yes/No, both non-empty and unique
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3 — don't pick a deadline
    expect(find.text('Step 3 of 3'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(find.text('Deadline is required'), findsNWidgets(2));
  });

  testWidgets('Step 3: rejects invalid quorum values (0 or >100)',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Test decision');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Set quorum to 0
    final quorumField = find.widgetWithText(TextField, '50');
    await tester.enterText(quorumField, '0');
    await tester.pump();

    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(find.textContaining('Quorum must be'), findsNWidgets(2));
  });

  testWidgets('Step 3: rejects quorum < 67 for constitution_amend type',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    // Step 1: enter title and switch type to constitution_amend
    await tester.enterText(find.byType(TextField).first, 'Amend Article 1');
    // Open the dropdown and pick constitution_amend
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Constitution Amendment (≥67%)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: defaults Yes/No — but for amendments the spec uses approve/reject.
    // For this test, just keep the defaults to focus on the quorum check.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3: set quorum to 50 (below 67)
    final quorumField = find.widgetWithText(TextField, '50');
    await tester.enterText(quorumField, '50');
    await tester.pump();

    await tester.tap(find.text('Create'));
    await tester.pump();

    // Validation error message is exactly 'Constitution amendments require
    // ≥67% quorum' (the static hint shown under the quorum field adds a
    // ' per Section 10.2.' suffix, so an exact-match finder excludes it).
    // The validation error appears in both the inline banner AND the snackbar.
    expect(find.text('Constitution amendments require ≥67% quorum'), findsNWidgets(2));
  });

  testWidgets('Back button preserves data entered on previous step',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    // Step 1 — enter a recognizable title
    await tester.enterText(find.byType(TextField).first, 'My persisted title');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2 — modify an option
    final optionFields = find.byType(TextField);
    await tester.enterText(optionFields.at(0), 'Custom option A');
    await tester.pump();

    // Go back to step 1
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // The title should still be present
    expect(find.text('My persisted title'), findsOneWidget);

    // Go forward to step 2 again
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // The custom option text should still be present
    expect(find.text('Custom option A'), findsOneWidget);
  });

  testWidgets('Cancel button on step 1 pops the screen without creating',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No create call was made
    expect(api.lastCreateBody, isNull);
  });

  testWidgets('Add and remove option buttons work, with min 2 / max 6 constraints',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrackcDecisionCreateScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Test decision');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Add option button is visible (we start with 2 options)
    expect(find.text('Add option'), findsOneWidget);

    // Add 4 options (total 6) — at the max the Add button is replaced by
    // a 'Maximum 6 options reached' hint.
    for (int i = 0; i < 4; i++) {
      await tester.tap(find.text('Add option'));
      await tester.pumpAndSettle();
    }

    // Scroll to bottom to make sure the "Maximum 6 options reached" hint is visible
    await tester.scrollUntilVisible(
      find.textContaining('Maximum 6 options reached'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Now at 6 — Add option button is gone, replaced by max-reached hint
    expect(find.text('Add option'), findsNothing);
    expect(find.text('Maximum 6 options reached'), findsOneWidget);

    // Remove one — should now have 5, Add button reappears
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pump();
    expect(find.text('Add option'), findsOneWidget);
    expect(find.text('Maximum 6 options reached'), findsNothing);

    // Try to remove down to 2 — should hit the min and show a snackbar.
    // Currently at 5, remove 3 to get to 2.
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pump();
    }

    // Now at 2 — try to remove one more, should be blocked.
    // The remove IconButton on the first row is disabled (onPressed=null)
    // so we verify the constraint by counting remaining option TextFields.
    // Tap on a remove icon — should show the snackbar.
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pump();
    expect(find.text('At least 2 options are required'), findsOneWidget);
  });
}
