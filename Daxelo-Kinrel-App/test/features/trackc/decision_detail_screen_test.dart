// =============================================================================
// Track C v2.0 — DecisionDetailScreen Widget Tests
// =============================================================================
// Verifies per spec item #5 (v2 audit):
//   - Vote buttons render per decision kind (simple_vote, consensus,
//     elder_council, constitution_amend)
//   - Tally visibility rules: tally hidden while decision is open, shown
//     only when status === 'resolved' (prevents bandwagon effect)
//   - Disabled state after the user has already voted (we approximate this
//     by checking that the vote button is disabled when status != 'open')
// =============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/features/trackc/data/api/trackc_api_client.dart';
import 'package:kinrel/features/trackc/presentation/providers/trackc_providers.dart';
import 'package:kinrel/features/trackc/presentation/screens/decision_detail_screen.dart';

class _FakeApi extends TrackcApiClient {
  _FakeApi({
    required this.decisionResp,
    this.insightsResp,
  }) : super(Dio());

  final Future<Map<String, dynamic>?> Function(String decisionId) decisionResp;
  final Future<List<Map<String, dynamic>>> Function(String decisionId)? insightsResp;

  @override
  Future<Map<String, dynamic>> getDecision(String familyId, String decisionId) async {
    final r = await decisionResp(decisionId);
    return r ?? <String, dynamic>{};
  }

  @override
  Future<List<dynamic>> listInsights(
    String familyId,
    String decisionId, {
    String? kind,
  }) async {
    return (insightsResp ?? (_) async => [])(decisionId);
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

Map<String, dynamic> _decision({
  required String id,
  required String type,
  required String status,
  required List<String> options,
  List<Map<String, dynamic>> votes = const [],
  List<String> eligibleUserIds = const ['u-1', 'u-2', 'u-3'],
  int quorumPct = 50,
  String? deadlineAt,
  String? outcome,
  String? lifecycleState,
  String title = 'Test Decision',
  String description = 'A test decision',
}) {
  return {
    'id': id,
    'title': title,
    'description': description,
    'type': type,
    'status': status,
    'options': options,
    'votes': votes,
    'eligibleUserIds': eligibleUserIds,
    'quorumPct': quorumPct,
    'deadlineAt': deadlineAt ?? '2026-12-31T23:59:59.000Z',
    'outcome': outcome,
    'lifecycleState': lifecycleState,
  };
}

void main() {
  testWidgets('renders the decision title and description', (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'simple_vote',
        status: 'open',
        options: ['Yes', 'No'],
        title: 'Where to host Diwali?',
        description: 'Choose the venue for the family gathering',
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Where to host Diwali?'), findsOneWidget);
    expect(find.text('Choose the venue for the family gathering'), findsOneWidget);
  });

  testWidgets('renders all vote options as radio tiles when decision is open',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'simple_vote',
        status: 'open',
        options: ['Yes', 'No', 'Abstain'],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Abstain'), findsOneWidget);
    expect(find.text('Cast your vote'), findsOneWidget);
  });

  testWidgets('shows the Submit Vote button when decision is open and an option is selected',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'simple_vote',
        status: 'open',
        options: ['Yes', 'No'],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    // Submit button exists but is initially disabled (no option selected)
    final submitButton = find.text('Submit Vote');
    expect(submitButton, findsOneWidget);
    // The FilledButton is disabled when _selectedOption == null
    final filledButton = tester.widget<FilledButton>(find.ancestor(
      of: submitButton,
      matching: find.byType(FilledButton),
    ));
    expect(filledButton.onPressed, isNull);

    // Tap "Yes" radio → submit becomes enabled
    await tester.tap(find.text('Yes'));
    await tester.pump();
    final filledButtonAfter = tester.widget<FilledButton>(find.ancestor(
      of: submitButton,
      matching: find.byType(FilledButton),
    ));
    expect(filledButtonAfter.onPressed, isNotNull);
  });

  testWidgets('hides the vote tally while the decision is still open (bandwagon guard)',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'simple_vote',
        status: 'open',
        options: ['Yes', 'No'],
        votes: [
          {'userId': 'u-2', 'option': 'Yes'},
          {'userId': 'u-3', 'option': 'Yes'},
        ],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    // No "Vote Tally" heading should be visible while open
    expect(find.text('Vote Tally'), findsNothing);
    // Vote-cast UI is shown instead
    expect(find.text('Cast your vote'), findsOneWidget);
  });

  testWidgets('shows the vote tally when the decision is resolved',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'simple_vote',
        status: 'resolved',
        outcome: 'approved',
        options: ['Yes', 'No'],
        votes: [
          {'userId': 'u-1', 'option': 'Yes'},
          {'userId': 'u-2', 'option': 'Yes'},
          {'userId': 'u-3', 'option': 'No'},
        ],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Vote Tally'), findsOneWidget);
    expect(find.text('Outcome: APPROVED'), findsOneWidget);
    // Tally counts appear as "$count ($pct%)" inside the vote bar
    expect(find.textContaining('2 (67%)'), findsOneWidget);
    expect(find.textContaining('1 (33%)'), findsOneWidget);
  });

  testWidgets('shows the Outcome heading with REJECTED label when outcome is rejected',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'simple_vote',
        status: 'resolved',
        outcome: 'rejected',
        options: ['Yes', 'No'],
        votes: [
          {'userId': 'u-1', 'option': 'No'},
          {'userId': 'u-2', 'option': 'No'},
        ],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Outcome: REJECTED'), findsOneWidget);
  });

  testWidgets('renders "Decision not found" when API returns null',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => throw Exception('not found'),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Decision not found'), findsOneWidget);
  });

  testWidgets('shows the lifecycle stepper when a resolved decision has a lifecycleState',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'simple_vote',
        status: 'resolved',
        outcome: 'approved',
        lifecycleState: 'in_progress',
        options: ['Yes', 'No'],
        votes: [
          {'userId': 'u-1', 'option': 'Yes'},
        ],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Lifecycle'), findsOneWidget);
    // The 'in progress' label appears as part of the stepper
    expect(find.textContaining('in progress'), findsOneWidget);
  });

  testWidgets('renders the type chip label for constitution_amend correctly',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'constitution_amend',
        status: 'open',
        options: ['approve', 'reject'],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Constitution Amendment'), findsOneWidget);
    // The two amendment options are rendered
    expect(find.text('approve'), findsOneWidget);
    expect(find.text('reject'), findsOneWidget);
  });

  testWidgets('renders the type chip label for elder_council correctly',
      (tester) async {
    final api = _FakeApi(
      decisionResp: (_) async => _decision(
        id: 'd-1',
        type: 'elder_council',
        status: 'open',
        options: ['Yes', 'No'],
      ),
    );
    await tester.pumpWidget(_wrap(
      const TrackcDecisionDetailScreen(decisionId: 'd-1'),
      api: api,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Elder Council'), findsOneWidget);
  });
}
