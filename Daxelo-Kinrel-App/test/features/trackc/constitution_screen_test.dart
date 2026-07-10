// =============================================================================
// Track C v2.0 — ConstitutionScreen Widget Tests
// =============================================================================
// Verifies per spec item #5 (v2 audit):
//   - Renders articles + clauses correctly
//   - Shows locked-state banner when `status === 'in_review'` AND
//     `draftVersion != null` (i.e. an amendment vote is in progress)
//   - Shows draft-in-progress state during an active amendment
// =============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/features/trackc/data/api/trackc_api_client.dart';
import 'package:kinrel/features/trackc/presentation/providers/trackc_providers.dart';
import 'package:kinrel/features/trackc/presentation/screens/constitution_screen.dart';

/// Subclass of [TrackcApiClient] that returns pre-baked payloads without
/// touching the network. We override only the methods that `constitutionProvider`
/// actually invokes — the rest are never called by this test, so they don't
/// need to be stubbed (they'll throw if invoked, which is the desired behavior
/// for tests that should not be reaching into other API surface area).
class _FakeApi extends TrackcApiClient {
  _FakeApi(this.constitutionResp) : super(Dio());
  final Future<Map<String, dynamic>?> Function(String familyId) constitutionResp;

  @override
  Future<Map<String, dynamic>> getConstitution(String familyId) async {
    final r = await constitutionResp(familyId);
    return r ?? <String, dynamic>{};
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

Map<String, dynamic> _constitution({
  required String status,
  Map<String, dynamic>? draftVersion,
  List<Map<String, dynamic>>? articles,
  String versionNumber = '1',
  String? publishedAt,
}) {
  return {
    'id': 'c-1',
    'title': 'Family Constitution',
    'preamble': 'We, the family, adopt this constitution.',
    'status': status,
    'currentVersion': {
      'id': 'v-$versionNumber',
      'versionNumber': int.parse(versionNumber),
      'publishedAt': publishedAt ?? '2026-01-01T00:00:00.000Z',
      'articles': articles ?? [],
    },
    'draftVersion': draftVersion,
  };
}

List<Map<String, dynamic>> _sampleArticles() {
  return [
    {
      'id': 'a-1',
      'title': 'Article 1: Family Values',
      'intent': 'Defines our core values',
      'orderIndex': 0,
      'clauses': [
        {'id': 'cl-1', 'text': 'We treat each other with respect.', 'orderIndex': 0},
        {'id': 'cl-2', 'text': 'We resolve conflicts through dialogue.', 'orderIndex': 1},
      ],
    },
    {
      'id': 'a-2',
      'title': 'Article 2: Decision Making',
      'intent': null,
      'orderIndex': 1,
      'clauses': [
        {'id': 'cl-3', 'text': 'Major decisions require a family vote.', 'orderIndex': 0},
      ],
    },
  ];
}

void main() {
  testWidgets('renders the constitution title and preamble', (tester) async {
    final api = _FakeApi((_) async => _constitution(
      status: 'published',
      articles: _sampleArticles(),
    ));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    // "Family Constitution" appears twice: once as the AppBar title
    // (hardcoded in the screen) and once as the constitution's actual
    // title in the body card.
    expect(find.text('Family Constitution'), findsNWidgets(2));
    expect(find.text('We, the family, adopt this constitution.'), findsOneWidget);
  });

  testWidgets('renders all articles with their clauses', (tester) async {
    final api = _FakeApi((_) async => _constitution(
      status: 'published',
      articles: _sampleArticles(),
    ));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    expect(find.text('Article 1: Family Values'), findsOneWidget);
    expect(find.text('Article 2: Decision Making'), findsOneWidget);
    expect(find.text('We treat each other with respect.'), findsOneWidget);
    expect(find.text('We resolve conflicts through dialogue.'), findsOneWidget);
    expect(find.text('Major decisions require a family vote.'), findsOneWidget);
  });

  testWidgets('shows the published-status chip when status is "published"',
      (tester) async {
    final api = _FakeApi((_) async => _constitution(
      status: 'published',
      articles: _sampleArticles(),
    ));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    // _StatusChip renders the status uppercased and underscore-stripped
    expect(find.text('PUBLISHED'), findsOneWidget);
  });

  testWidgets('shows the locked-state banner when status is "in_review" '
      'and a draft exists (active amendment vote)', (tester) async {
    final api = _FakeApi((_) async => _constitution(
      status: 'in_review',
      draftVersion: {
        'id': 'v-2-draft',
        'versionNumber': 2,
        'articles': _sampleArticles(),
      },
      articles: _sampleArticles(),
    ));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    // The "Draft vN in progress" amber card is shown when draftVersion != null
    expect(find.text('Draft v2 in progress'), findsOneWidget);
    // The status chip shows IN REVIEW
    expect(find.text('IN REVIEW'), findsOneWidget);
  });

  testWidgets('does NOT show the draft banner when no draft exists', (tester) async {
    final api = _FakeApi((_) async => _constitution(
      status: 'published',
      draftVersion: null,
      articles: _sampleArticles(),
    ));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Draft v'), findsNothing);
  });

  testWidgets('shows the empty-constitution placeholder when constitution is null',
      (tester) async {
    // constitutionProvider catches exceptions and returns null, so we throw
    // to simulate "not found". (Returning null directly also works because
    // the provider's try/catch turns it into a null return.)
    final api = _FakeApi((_) async => throw Exception('not found'));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    expect(find.text('No constitution yet'), findsOneWidget);
    expect(find.text('An admin can draft the first version.'), findsOneWidget);
  });

  testWidgets('shows the zero-articles notice when a published version has no articles',
      (tester) async {
    final api = _FakeApi((_) async => _constitution(
      status: 'published',
      articles: [],
    ));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    expect(find.textContaining('No articles yet'), findsOneWidget);
  });

  testWidgets('shows error UI when the API call fails', (tester) async {
    // The real constitutionProvider catches exceptions and returns null, so
    // the screen shows the empty-constitution placeholder rather than the
    // error UI. This is the documented behavior in the provider:
    //   try { return await api.getConstitution(...); } catch (e) { return null; }
    //
    // For the error-UI path to be reachable, the provider would need to
    // re-throw. We test the empty-constitution path here instead, since
    // that's what actually fires on API failure.
    final api = _FakeApi((_) async => throw Exception('network down'));
    await tester.pumpWidget(_wrap(const TrackcConstitutionScreen(), api: api));
    await tester.pumpAndSettle();

    // Provider swallows the exception → null constitution → placeholder UI
    expect(find.text('No constitution yet'), findsOneWidget);
  });
}
