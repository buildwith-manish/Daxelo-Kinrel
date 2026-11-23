// lib/graph/interaction/relationship_sentence_l10n.dart
//
// G1b — binds [RelationshipSentenceStrings] to the generated `S` class.
// Needs `flutter gen-l10n` to have been run after the new ARB keys
// (relationshipSentence* / relationshipRole*) were added to app_en.arb.

import '../../l10n/app_localizations.dart';
import 'relationship_sentence.dart';

class SRelationshipSentenceStrings implements RelationshipSentenceStrings {
  const SRelationshipSentenceStrings(this.l10n);
  final S l10n;

  @override
  String self() => l10n.relationshipSentenceSelf;
  @override
  String noPath(String name) => l10n.relationshipSentenceNoPath(name);
  @override
  String unnamed() => l10n.relationshipSentenceUnnamed;
  @override
  String withTerm(String name, String term, String chain) =>
      l10n.relationshipSentenceWithTerm(name, term, chain);
  @override
  String termOnly(String name, String term) =>
      l10n.relationshipSentenceTermOnly(name, term);
  @override
  String chainOnly(String name, String chain) =>
      l10n.relationshipSentenceChainOnly(name, chain);
  @override
  String chainFirst(String relation) =>
      l10n.relationshipSentenceChainFirst(relation);
  @override
  String chainNext(String chain, String relation) =>
      l10n.relationshipSentenceChainNext(chain, relation);

  @override
  String role(RelationshipChainRole role, String? gender) {
    final g = (gender ?? '').toLowerCase();
    final female = g == 'female' || g == 'f';
    final male = g == 'male' || g == 'm';
    switch (role) {
      case RelationshipChainRole.parent:
        return female
            ? l10n.relationshipRoleMother
            : male
                ? l10n.relationshipRoleFather
                : l10n.relationshipRoleParent;
      case RelationshipChainRole.child:
        return female
            ? l10n.relationshipRoleDaughter
            : male
                ? l10n.relationshipRoleSon
                : l10n.relationshipRoleChild;
      case RelationshipChainRole.sibling:
        return female
            ? l10n.relationshipRoleSister
            : male
                ? l10n.relationshipRoleBrother
                : l10n.relationshipRoleSibling;
      case RelationshipChainRole.spouse:
        return female
            ? l10n.relationshipRoleWife
            : male
                ? l10n.relationshipRoleHusband
                : l10n.relationshipRoleSpouse;
      case RelationshipChainRole.grandparent:
        return female
            ? l10n.relationshipRoleGrandmother
            : male
                ? l10n.relationshipRoleGrandfather
                : l10n.relationshipRoleGrandparent;
      case RelationshipChainRole.grandchild:
        return female
            ? l10n.relationshipRoleGranddaughter
            : male
                ? l10n.relationshipRoleGrandson
                : l10n.relationshipRoleGrandchild;
    }
  }
}
