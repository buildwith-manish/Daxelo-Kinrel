// lib/graph/interaction/relationship_sentence.dart
//
// G1b — the one plain sentence at the top of the relationship info sheet,
// e.g. "Rahul is your uncle (your mother's brother)."
//
// This file does NOT compute a relationship. It READS the already-resolved
// [GraphKinshipPathFocus] (BFS path + StructuralKinshipClassifier label) and
// only words it:
//   • the term  = pathFocus.resolvedRelationshipLabel, in the user's kinship
//                 language via the existing VocabularyTable lookup (English
//                 fallback when the table has no entry);
//   • the chain = the path hops, read with the same inversion table the
//                 classifier input uses ([invertPathStepTypeForTarget]).
//
// All wording comes from [RelationshipSentenceStrings] (backed by ARB keys in
// production, see relationship_sentence_l10n.dart) so this file is pure Dart.

import '../../core/kinship/v4/vocabulary_table.dart' show VocabularyTable;
import 'graph_kinship_path_focus.dart'
    show GraphKinshipPathFocus, invertPathStepTypeForTarget;

/// Role the NEXT person on a path plays relative to the previous one.
enum RelationshipChainRole {
  parent,
  child,
  sibling,
  spouse,
  grandparent,
  grandchild,
}

/// All user-facing wording. Production = ARB via `S`; tests = app_en.arb.
abstract class RelationshipSentenceStrings {
  String self();
  String noPath(String name);
  String unnamed();
  String withTerm(String name, String term, String chain);
  String termOnly(String name, String term);
  String chainOnly(String name, String chain);
  String chainFirst(String relation);
  String chainNext(String chain, String relation);

  /// Plain-English role word, gender-aware when [gender] is known.
  String role(RelationshipChainRole role, String? gender);
}

typedef NativeTermLookup = String? Function(String englishTerm, String locale);

String? _defaultNativeTerm(String englishTerm, String locale) =>
    VocabularyTable.resolveByEnglishTerm(
        englishTerm: englishTerm, locale: locale);

/// Builds the sentence shown at the top of the relationship info sheet.
///
/// [kinshipLanguage] is the raw `kinshipTermLanguageProvider` value
/// (`'auto'` is treated as English, same as the sheet does today).
/// [genderById] maps person id → 'male' / 'female' (others = neutral words).
String buildRelationshipSentence({
  required String viewerPersonId,
  required String targetPersonId,
  required String targetName,
  required GraphKinshipPathFocus? pathFocus,
  required Map<String, String?> genderById,
  required String kinshipLanguage,
  required RelationshipSentenceStrings strings,
  NativeTermLookup nativeTerm = _defaultNativeTerm,
}) {
  if (viewerPersonId == targetPersonId) return strings.self();

  final trimmed = targetName.trim();
  final name = trimmed.isEmpty ? strings.unnamed() : trimmed;

  if (pathFocus == null || pathFocus.steps.length < 2) {
    return strings.noPath(name);
  }

  final chain = _buildChain(pathFocus, genderById, strings);
  final term = _resolveTerm(pathFocus, kinshipLanguage, nativeTerm);

  if (term == null && chain == null) return strings.noPath(name);
  if (term == null) return strings.chainOnly(name, chain!.text);
  if (chain == null) return strings.termOnly(name, term);
  // One hop whose role word IS the term ("your brother"): say it once.
  if (chain.lastWord.toLowerCase() == term.toLowerCase()) {
    return strings.chainOnly(name, chain.text);
  }
  return strings.withTerm(name, term, chain.text);
}

class _Chain {
  const _Chain(this.text, this.lastWord);
  final String text;
  final String lastWord;
}

const _noTermKeys = <String>{'unknown', 'related', 'other', 'self'};

String? _resolveTerm(
  GraphKinshipPathFocus focus,
  String kinshipLanguage,
  NativeTermLookup nativeTerm,
) {
  final label = focus.resolvedRelationshipLabel?.trim();
  final key = focus.resolvedRelationshipKey?.trim().toLowerCase();
  if (label == null || label.isEmpty) return null;
  if (key == null || _noTermKeys.contains(key)) return null;
  if (label.toLowerCase() == 'unknown' || label.toLowerCase() == 'related') {
    return null;
  }
  final lang = kinshipLanguage == 'auto' ? 'en' : kinshipLanguage;
  if (lang != 'en') {
    try {
      final native = nativeTerm(label, lang);
      if (native != null && native.trim().isNotEmpty) return native.trim();
    } catch (_) {
      // fall through to the English label
    }
  }
  return label.toLowerCase();
}

_Chain? _buildChain(
  GraphKinshipPathFocus focus,
  Map<String, String?> genderById,
  RelationshipSentenceStrings strings,
) {
  String? text;
  String lastWord = '';
  for (var i = 1; i < focus.steps.length; i++) {
    final step = focus.steps[i];
    final role = _roleOf(invertPathStepTypeForTarget(step.relationshipType));
    if (role == null) return null; // a hop we cannot put in plain words
    final word = strings.role(role, genderById[step.personId]);
    text = i == 1 ? strings.chainFirst(word) : strings.chainNext(text!, word);
    lastWord = word;
  }
  return text == null ? null : _Chain(text, lastWord);
}

RelationshipChainRole? _roleOf(String inverted) {
  switch (inverted.toLowerCase().trim()) {
    case 'parent':
      return RelationshipChainRole.parent;
    case 'child':
      return RelationshipChainRole.child;
    case 'sibling':
      return RelationshipChainRole.sibling;
    case 'spouse':
      return RelationshipChainRole.spouse;
    case 'grandparent':
      return RelationshipChainRole.grandparent;
    case 'grandchild':
      return RelationshipChainRole.grandchild;
  }
  return null;
}
