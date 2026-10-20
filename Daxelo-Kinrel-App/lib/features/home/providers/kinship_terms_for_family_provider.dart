// lib/features/home/providers/kinship_terms_for_family_provider.dart
//
// DAXELO KINREL — Kinship Terms for Family Provider (2026-10-20)
//
// Returns Map<personId, KinshipTermResult> for every person in the
// family, computed from the viewer's perspective, in the chosen language.
// Computed once per (graph revision, viewer, language). Never per-frame.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kinship/kinship_term_language_provider.dart';
import '../../../core/kinship/v4/vocabulary_table.dart';
import '../../../core/relationship/relationship_engine.dart';
import '../../../core/services/graph_layout_service.dart' show GraphPerson;
import '../../../core/viewer/viewer_provider.dart';
import '../../family/presentation/providers/family_graph_provider.dart';

class KinshipTermResult {
  const KinshipTermResult({
    required this.primary,
    this.secondary,
    this.relationExplanation,
  });
  final String primary;
  final String? secondary;
  final String? relationExplanation;
}

final kinshipTermsForFamilyProvider =
    Provider.family<Map<String, KinshipTermResult>, String>(
        (ref, familyId) {
  final flat = ref.watch(familyGraphProvider(familyId)).valueOrNull;
  if (flat == null) return {};

  final viewerId = ref.watch(viewerPersonIdProvider(familyId)).valueOrNull;
  if (viewerId == null) return {};

  final langPref = ref.watch(kinshipTermLanguageProvider);
  final kinshipLang = langPref == 'auto' ? 'en' : langPref;

  final graphPersons = <GraphPerson>[
    for (final Map<String, dynamic> p in flat.persons)
      if (p['id'] != null)
        GraphPerson(
          id: p['id'] as String,
          name: (p['name'] as String?) ?? '',
          gender: p['gender'] as String?,
          generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
          isAnchor: (p['isAnchor'] as bool?) ?? false,
          photoUrl: p['photoUrl'] as String?,
          isDeceased: (p['isDeceased'] as bool?) ?? false,
        ),
  ];

  final graphRels = <({String fromId, String toId, String type})>[
    for (final Map<String, dynamic> r in flat.relationships)
      if (r['fromPersonId'] != null &&
          r['toPersonId'] != null &&
          r['relationshipKey'] != null)
        (
          fromId: r['fromPersonId'] as String,
          toId: r['toPersonId'] as String,
          type: (r['labelAtoB'] as String?) ??
              r['relationshipKey'] as String,
        ),
  ];

  final engine = RelationshipEngine.instance;
  final result = <String, KinshipTermResult>{};

  for (final p in graphPersons) {
    if (p.id == viewerId) continue;
    final classification = engine.resolveClassification(
      viewerPersonId: viewerId,
      targetPersonId: p.id,
      persons: graphPersons,
      relationships: graphRels,
    );
    if (classification == null) continue;

    final englishLabel = classification.label;
    String primary = englishLabel;
    String? secondary;

    if (kinshipLang != 'en') {
      final nativeTerm = VocabularyTable.resolveByEnglishTerm(
        englishTerm: englishLabel,
        locale: kinshipLang,
      );
      if (nativeTerm != null && nativeTerm.isNotEmpty) {
        primary = nativeTerm;
        secondary = englishLabel;
      }
    }

    result[p.id] = KinshipTermResult(
      primary: primary,
      secondary: secondary,
      relationExplanation: englishLabel,
    );
  }

  return result;
});
