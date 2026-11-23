// G1b — unit tests for buildRelationshipSentence.
//
// Pure Dart: no widgets, no Riverpod, no generated l10n. The wording is read
// from lib/l10n/app_en.arb so the test also proves the ARB keys exist and
// carry the placeholders the builder expects.
//
// Lives in test/graph/interaction/ => picked up by `flutter-test-fast`.
// Runtime is milliseconds (no pumpWidget), so it does not move the baseline
// 25-minute timeout.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/graph_kinship_path_focus.dart';
import 'package:kinrel/graph/interaction/relationship_sentence.dart';

class _ArbStrings implements RelationshipSentenceStrings {
  _ArbStrings() : _arb = _load();
  final Map<String, dynamic> _arb;

  static Map<String, dynamic> _load() => jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;

  String _t(String key, [Map<String, String> args = const {}]) {
    var s = _arb[key] as String? ?? (throw StateError('missing ARB key $key'));
    args.forEach((k, v) => s = s.replaceAll('{$k}', v));
    expect(RegExp(r'\{\w+\}').hasMatch(s), isFalse,
        reason: 'unfilled placeholder in $key: $s');
    return s;
  }

  @override
  String self() => _t('relationshipSentenceSelf');
  @override
  String noPath(String name) => _t('relationshipSentenceNoPath', {'name': name});
  @override
  String unnamed() => _t('relationshipSentenceUnnamed');
  @override
  String withTerm(String name, String term, String chain) => _t(
      'relationshipSentenceWithTerm',
      {'name': name, 'term': term, 'chain': chain});
  @override
  String termOnly(String name, String term) =>
      _t('relationshipSentenceTermOnly', {'name': name, 'term': term});
  @override
  String chainOnly(String name, String chain) =>
      _t('relationshipSentenceChainOnly', {'name': name, 'chain': chain});
  @override
  String chainFirst(String relation) =>
      _t('relationshipSentenceChainFirst', {'relation': relation});
  @override
  String chainNext(String chain, String relation) => _t(
      'relationshipSentenceChainNext', {'chain': chain, 'relation': relation});

  @override
  String role(RelationshipChainRole role, String? gender) {
    final g = (gender ?? '').toLowerCase();
    final f = g == 'female', m = g == 'male';
    final word = switch (role) {
      RelationshipChainRole.parent => f ? 'Mother' : m ? 'Father' : 'Parent',
      RelationshipChainRole.child => f ? 'Daughter' : m ? 'Son' : 'Child',
      RelationshipChainRole.sibling => f ? 'Sister' : m ? 'Brother' : 'Sibling',
      RelationshipChainRole.spouse => f ? 'Wife' : m ? 'Husband' : 'Spouse',
      RelationshipChainRole.grandparent =>
        f ? 'Grandmother' : m ? 'Grandfather' : 'Grandparent',
      RelationshipChainRole.grandchild =>
        f ? 'Granddaughter' : m ? 'Grandson' : 'Grandchild',
    };
    return _t('relationshipRole$word');
  }
}

/// Builds a path the way GraphPathFocusNotifier does: `hops` are
/// (personId, name, BFS type) where the BFS type is what the PREVIOUS person
/// IS relative to this one (e.g. viewer is a 'child' of their mother).
GraphKinshipPathFocus _focus(
  List<(String, String, String)> hops, {
  String? key,
  String? label,
}) {
  final steps = <GraphPathFocusStep>[
    const GraphPathFocusStep(
        personId: 'me',
        personName: 'Me',
        relationshipType: '',
        edgeId: null,
        direction: ''),
    for (var i = 0; i < hops.length; i++)
      GraphPathFocusStep(
          personId: hops[i].$1,
          personName: hops[i].$2,
          relationshipType: hops[i].$3,
          edgeId: 'e$i',
          direction: 'to'),
  ];
  return GraphKinshipPathFocus(
    viewerPersonId: 'me',
    targetPersonId: hops.last.$1,
    steps: steps,
    orderedPersonIds: [for (final s in steps) s.personId],
    orderedEdgeIds: [for (final s in steps) if (s.edgeId != null) s.edgeId!],
    resolvedRelationshipKey: key,
    resolvedRelationshipLabel: label,
    resolvedCategory: null,
    graphRevision: 1,
  );
}

void main() {
  final strings = _ArbStrings();
  const genders = <String, String?>{
    'me': 'male',
    'mum': 'female',
    'dad': 'male',
    'mamaji': 'male',
    'chachaji': 'male',
    'sis': 'female',
    'bro': 'male',
    'wife': 'female',
    'fil': 'male',
  };

  String build(
    GraphKinshipPathFocus? focus, {
    String target = 'Target',
    String lang = 'auto',
    String targetId = 'x',
    String viewer = 'me',
    NativeTermLookup? native,
  }) =>
      buildRelationshipSentence(
        viewerPersonId: viewer,
        targetPersonId: targetId,
        targetName: target,
        pathFocus: focus,
        genderById: genders,
        kinshipLanguage: lang,
        strings: strings,
        nativeTerm: native ?? (_, __) => null,
      );

  test('parent: one hop says it once, no brackets', () {
    final f = _focus([('mum', 'Asha', 'child')], key: 'mother', label: 'Mother');
    expect(build(f, target: 'Asha', targetId: 'mum'), 'Asha is your mother.');
  });

  test('sibling: one hop', () {
    final f = _focus([('bro', 'Ravi', 'sibling')], key: 'brother', label: 'Brother');
    expect(build(f, target: 'Ravi', targetId: 'bro'), 'Ravi is your brother.');
  });

  test('mama (mother\'s brother), English fallback keeps the chain', () {
    final f = _focus(
        [('mum', 'Asha', 'child'), ('mamaji', 'Rahul', 'sibling')],
        key: 'uncle', label: 'Uncle');
    expect(build(f, target: 'Rahul', targetId: 'mamaji'),
        "Rahul is your uncle (your mother's brother).");
  });

  test('mama, Hindi selected: native term + same plain chain', () {
    final f = _focus(
        [('mum', 'Asha', 'child'), ('mamaji', 'Rahul', 'sibling')],
        key: 'uncle', label: 'Uncle');
    expect(
        build(f,
            target: 'Rahul',
            targetId: 'mamaji',
            lang: 'hi',
            native: (en, loc) => (en == 'Uncle' && loc == 'hi') ? 'Mama' : null),
        "Rahul is your Mama (your mother's brother).");
  });

  test('chacha (father\'s brother), Hindi selected', () {
    final f = _focus(
        [('dad', 'Vijay', 'child'), ('chachaji', 'Sunil', 'sibling')],
        key: 'uncle', label: 'Uncle');
    expect(
        build(f,
            target: 'Sunil',
            targetId: 'chachaji',
            lang: 'hi',
            native: (_, __) => 'Chacha'),
        "Sunil is your Chacha (your father's brother).");
  });

  test('in-law: wife\'s father', () {
    final f = _focus(
        [('wife', 'Meera', 'spouse'), ('fil', 'Om', 'child')],
        key: 'father_in_law', label: 'Father-in-law');
    expect(build(f, target: 'Om', targetId: 'fil'),
        "Om is your father-in-law (your wife's father).");
  });

  test('no path: says so in words, never empty or a code', () {
    final s = build(null, target: 'Kiran', targetId: 'k');
    expect(s, "We can't work out how you and Kiran are related yet.");
    expect(s, isNot(contains('unknown')));
  });

  test('self: "This is you."', () {
    expect(build(null, viewer: 'me', targetId: 'me'), 'This is you.');
  });

  test('path exists but term unknown: chain only', () {
    final f = _focus(
        [('mum', 'Asha', 'child'), ('mamaji', 'Rahul', 'sibling')],
        key: 'unknown', label: 'Unknown');
    expect(build(f, target: 'Rahul', targetId: 'mamaji'),
        "Rahul is your mother's brother.");
  });

  test('hop we cannot word: term only, no half-built chain', () {
    final f = _focus([('mum', 'Asha', 'weird_type'), ('mamaji', 'Rahul', 'sibling')],
        key: 'uncle', label: 'Uncle');
    expect(build(f, target: 'Rahul', targetId: 'mamaji'), 'Rahul is your uncle.');
  });

  test('blank name uses the ARB fallback, never an empty string', () {
    final s = build(null, target: '  ', targetId: 'k');
    expect(s, startsWith("We can't work out how you and This person"));
  });
}
