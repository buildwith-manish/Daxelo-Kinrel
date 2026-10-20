// lib/core/kinship/kinship_term_providers.dart
//
// DAXELO KINREL — Kinship Term Providers (Phase A — Home, the Instagram-level idea)
//
// Resolves a viewer's kinship term for EVERY person in a family in the
// viewer's chosen language. Computed once per (family graph revision,
// viewer, language) and cached — never inside a card's build().
//
// Pipeline:
//   1. viewerPersonIdProvider(familyId) → viewer's Person.id
//   2. familyGraphProvider(familyId) → flat graph (persons + relationships)
//   3. compute() in an isolate: RelationshipEngine.resolveClassification
//      runs BFS for every (viewer, target) pair → (key, label). NO I/O —
//      the structural classifier + GraphService BFS are pure data.
//   4. Main isolate enriches with KinshipService.getKinshipTermByLocale
//      → native term (e.g. "Mausi"). KinshipService needs rootBundle,
//      which only works on the main isolate, so step 4 must run here.
//
// Fallback chain (NEVER empty):
//   1. native term in chosen language (KinshipService.getKinshipTermByLocale)
//   2. English label from StructuralClassification.label
//   3. relationshipKey (e.g. "mothers_sister")
//   4. person's own first name
//
// Dependency note: The "native kinship terms" prompt that would have
// added `kinshipTermLanguageProvider`, `showEnglishSubtitleProvider`,
// and the term index over VocabularyTable was NOT merged into the
// graph-layout branch at the time Phase A was started. To stay
// forward-compatible, this file creates the minimum providers under
// the same names so a future merge is drop-in. When the prompt lands,
// the SharedPreferences-backed Notifier here can be replaced by the
// prompt's implementation without touching call sites.

import 'dart:async';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../relationship/relationship_engine.dart';
import '../services/graph_layout_service.dart' show GraphPerson;
import 'kinship_service.dart';
import '../family/family_provider.dart' show familyDetailProvider;
import '../viewer/viewer_provider.dart' show viewerPersonIdProvider;
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show familyGraphProvider;

// ═══════════════════════════════════════════════════════════════════════
// KinshipTerm — the resolved term for one (viewer → target) pair
// ═══════════════════════════════════════════════════════════════════════

/// A resolved kinship term for a (viewer, target) pair.
///
/// [primary] is the bold label shown in the ring row / feed header
/// (e.g. "Mausi", "Nani", "Father"). [secondary] is optional — used
/// for bilingual displays where the user wants the English subtitle
/// under the native term. [relationExplanation] is a plain-language
/// description like "your mother's sister" — used by Phase C in feed
/// card secondary text.
class KinshipTerm {
  const KinshipTerm({
    required this.primary,
    this.secondary,
    required this.relationExplanation,
    this.kinshipKey,
  });

  /// Bold label (native term in chosen language, fallback English, fallback name).
  final String primary;

  /// Optional second-line subtitle (English term when the user wants it
  /// alongside the native term).
  final String? secondary;

  /// Plain-language description (e.g. "your mother's mother").
  final String relationExplanation;

  /// The underlying kinship key (e.g. "maternal_grandmother"). Null for
  /// self / unreachable targets.
  final String? kinshipKey;

  Map<String, dynamic> toJson() => {
        'primary': primary,
        if (secondary != null) 'secondary': secondary,
        'relationExplanation': relationExplanation,
        if (kinshipKey != null) 'kinshipKey': kinshipKey,
      };

  @override
  String toString() =>
      'KinshipTerm(primary: $primary, secondary: $secondary, key: $kinshipKey)';
}

// ═══════════════════════════════════════════════════════════════════════
// Language + subtitle preferences
// (Created here as a minimum stub because the "native kinship terms"
//  prompt that should have added these was NOT merged into graph-layout.)
// ═══════════════════════════════════════════════════════════════════════

const _kLanguagePrefKey = 'kinrel.kinshipTermLanguage';
const _kSubtitlePrefKey = 'kinrel.showEnglishSubtitle';

/// Notifier for the user's chosen kinship-term display language.
///
/// Stored as a locale code ('hi', 'ta', 'ur', 'en', …). Default 'en'.
/// When the user changes this, every `kinshipTermsForFamilyProvider`
/// rebuilds — but only the enrichment step (KinshipService lookup)
/// re-runs; the isolate BFS results are cached per family in
/// RelationshipEngine's in-memory caches, so a language switch on a
/// 715-person family is sub-100ms.
class KinshipTermLanguageNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return 'en';
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_kLanguagePrefKey);
      if (stored != null && stored.isNotEmpty && stored != state) {
        state = stored;
      }
    } catch (e) {
      debugPrint('⚠️ kinshipTermLanguageProvider load: $e');
    }
  }

  Future<void> setLanguage(String localeCode) async {
    if (localeCode.isEmpty) return;
    state = localeCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLanguagePrefKey, localeCode);
    } catch (e) {
      debugPrint('⚠️ kinshipTermLanguageProvider set: $e');
    }
  }
}

/// Notifier controlling whether a small English subtitle is shown
/// under the native kinship term. Default true (the mockup shows
/// "Mausi" bold with "Priya" beneath it, so the subtitle default
/// affects only the second line — when true, the secondary line is
/// the English term; when false, only the first name is shown).
class ShowEnglishSubtitleNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_kSubtitlePrefKey);
      if (stored != null) state = stored;
    } catch (_) {}
  }

  Future<void> setShown(bool shown) async {
    state = shown;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSubtitlePrefKey, shown);
    } catch (_) {}
  }
}

/// User's chosen kinship-term display language (locale code).
/// Replace with the prompt's provider when the native-kinship-terms
/// branch merges — call sites stay identical.
final kinshipTermLanguageProvider =
    NotifierProvider<KinshipTermLanguageNotifier, String>(
  KinshipTermLanguageNotifier.new,
);

/// Whether to show a small English subtitle under the native kinship
/// term. Replace with the prompt's provider when it merges.
final showEnglishSubtitleProvider =
    NotifierProvider<ShowEnglishSubtitleNotifier, bool>(
  ShowEnglishSubtitleNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════
// Isolate payload types
//
// `compute()` requires values that can be copied across isolate
// boundaries. We use plain Map<String, dynamic> + Lists so the data
// survives the round-trip without depending on classes that hold
// closures or main-isolate singletons.
// ═══════════════════════════════════════════════════════════════════════

class _IsolateInput {
  _IsolateInput({
    required this.viewerPersonId,
    required this.persons,
    required this.relationships,
  });

  final String? viewerPersonId;

  /// Persons as Maps with at least {id, name, gender?}.
  final List<Map<String, dynamic>> persons;

  /// Relationships as Maps with at least {fromId, toId, type}.
  final List<Map<String, dynamic>> relationships;
}

/// Top-level isolate entry point. Must be a top-level function so
/// `compute()` can spawn it in a fresh isolate.
///
/// Returns Map<personId, Map<String, dynamic>> where the inner map is:
///   {'key': String?, 'label': String?, 'explanation': String?}
///
/// The main isolate then enriches with native terms via
/// KinshipService.getKinshipTermByLocale (rootBundle is main-isolate
/// only — the isolate cannot load kinship JSON itself).
///
/// This function ONLY uses pure data classes (GraphPerson as a Map,
/// RelationshipEngine's structural fallback, StructuralKinshipClassifier).
/// It does NOT touch KinshipService, rootBundle, or any Riverpod
/// provider — all of which are main-isolate-bound.
Map<String, Map<String, String?>> _computeStructuralClassifications(
  _IsolateInput input,
) {
  final result = <String, Map<String, String?>>{};

  // Convert primitive maps back into the typed records
  // RelationshipEngine expects. GraphPerson is a plain data class with
  // a public constructor — safe to instantiate inside the isolate.
  final persons = <GraphPerson>[];
  for (final p in input.persons) {
    final id = p['id']?.toString();
    if (id == null || id.isEmpty) continue;
    persons.add(GraphPerson(
      id: id,
      name: p['name']?.toString() ?? 'Unknown',
      gender: p['gender']?.toString(),
    ));
  }
  final relationships = <({String fromId, String toId, String type})>[];
  for (final r in input.relationships) {
    final fromId = r['fromId']?.toString() ?? r['fromPersonId']?.toString();
    final toId = r['toId']?.toString() ?? r['toPersonId']?.toString();
    final type = r['type']?.toString() ??
        r['relationshipKey']?.toString() ??
        'related';
    if (fromId == null || toId == null || fromId.isEmpty || toId.isEmpty) {
      continue;
    }
    relationships.add((fromId: fromId, toId: toId, type: type));
  }

  final engine = RelationshipEngine.instance;

  for (final target in persons) {
    if (target.id == input.viewerPersonId) continue; // self → null

    final classification = engine.resolveClassification(
      viewerPersonId: input.viewerPersonId,
      targetPersonId: target.id,
      persons: persons,
      relationships: relationships,
    );

    if (classification == null) {
      // No path from viewer to target — store nulls so the caller can
      // fall back to the person's name. Never store an empty map.
      result[target.id] = {
        'key': null,
        'label': null,
        'explanation': _explainNoPath(),
      };
      continue;
    }

    result[target.id] = {
      'key': classification.key,
      'label': classification.label,
      'explanation': _buildExplanation(classification.key, classification.label),
    };
  }

  return result;
}

String _explainNoPath() => 'relative';

/// Builds a plain-language explanation like "your mother's mother".
/// Phase C will replace this with a call to ExplanationEngine.explain()
/// when KinshipSignature is cheaply derivable; for Phase A a short,
/// readable English string is enough for the feed card secondary line.
String _buildExplanation(String? key, String? label) {
  if (key == null || key.isEmpty) {
    return label != null && label.isNotEmpty ? 'your $label' : 'relative';
  }
  // Heuristic: keys use snake_case compounds like 'mothers_sister'.
  // Convert to "your mother's sister" by inserting apostrophes on the
  // first token of each pair. Falls back to label when the pattern
  // doesn't match (e.g. 'paternal_grandfather' → label "Grandfather").
  final parts = key.split('_');
  if (parts.length == 1) {
    return label != null && label.isNotEmpty
        ? 'your ${label.toLowerCase()}'
        : 'your $key';
  }
  // Two-part keys → "your {first}'s {second}".
  if (parts.length == 2) {
    final first = parts[0];
    final second = parts[1];
    return "your ${first}'s $second";
  }
  // Three-part+ keys → fall back to label to avoid a garbled chain.
  return label != null && label.isNotEmpty
      ? 'your ${label.toLowerCase()}'
      : 'your $key';
}

// ═══════════════════════════════════════════════════════════════════════
// kinshipTermsForFamilyProvider
// ═══════════════════════════════════════════════════════════════════════

/// Resolves kinship terms for every person in a family, from the
/// viewer's perspective, in the viewer's chosen language.
///
/// Returns Map<personId, KinshipTerm>. Callers should look up by the
/// target's Person.id. For feed posts whose author is identified by
/// `authorId` (which is the Person.id for member_joined / connection_added
/// posts, or the user's auth id for posts authored by the current
/// user), use [kinshipTermForFeedPostProvider] below which resolves
/// the authorId to a personId first.
///
/// Recomputes only when:
///   - viewerPersonId changes (auth switch, viewer resolution)
///   - family graph data changes (member added / relationship added)
///   - language preference changes
///
/// All of those are watched via ref.watch, so Riverpod auto-caches
/// and auto-invalidates this provider.
final kinshipTermsForFamilyProvider =
    FutureProvider.family<Map<String, KinshipTerm>, String>(
  (ref, familyId) async {
    // Watch all inputs so Riverpod rebuilds on any change.
    final viewerAsync = ref.watch(viewerPersonIdProvider(familyId));
    final viewerPersonId = viewerAsync.valueOrNull;
    final graphAsync = ref.watch(familyGraphProvider(familyId));
    final language = ref.watch(kinshipTermLanguageProvider);
    final showSubtitle = ref.watch(showEnglishSubtitleProvider);

    final graph = graphAsync.valueOrNull;
    if (graph == null) return const {};
    if (graph.persons.isEmpty) return const {};
    // No viewer → can't resolve kinship. Return empty map; the UI
    // falls back to first names.
    if (viewerPersonId == null || viewerPersonId.isEmpty) {
      return const {};
    }

    // Build the isolate payload — primitive Maps only (closures and
    // main-isolate singletons are NOT SendPort-serializable).
    final isolateInput = _IsolateInput(
      viewerPersonId: viewerPersonId,
      persons: graph.persons
          .map((p) => <String, dynamic>{
                'id': p['id'],
                'name': p['name'],
                'gender': p['gender'],
              })
          .toList(growable: false),
      relationships: graph.relationships
          .map((r) => <String, dynamic>{
                'fromId': r['fromPersonId'],
                'toId': r['toPersonId'],
                'type': r['relationshipKey'],
              })
          .toList(growable: false),
    );

    // Run the heavy BFS + structural classification off the UI thread.
    // On a 715-person family this is ~500k BFS operations — would
    // drop frames if run on the main isolate.
    Map<String, Map<String, String?>> structural;
    try {
      structural = await compute(
        _computeStructuralClassifications,
        isolateInput,
      );
    } catch (e) {
      debugPrint('⚠️ kinshipTermsForFamilyProvider isolate failed: $e');
      return const {};
    }

    // Enrich with native terms on the main isolate. KinshipService
    // loads its JSON via rootBundle (a platform channel) — the
    // spawned isolate has no platform-channel access, so this step
    // must run here.
    final kinship = KinshipService.instance;
    final result = <String, KinshipTerm>{};

    // Look up the viewer's own name for the "You" entry (not in the
    // map — self returns null in resolveClassification).
    String? viewerName;
    try {
      final detailAsync = ref.read(familyDetailProvider(familyId));
      final detail = detailAsync.valueOrNull;
      if (detail != null) {
        for (final m in detail.members) {
          if (m.id == viewerPersonId) {
            viewerName = m.name;
            break;
          }
        }
      }
    } catch (_) {}

    for (final person in graph.persons) {
      final personId = person['id']?.toString();
      if (personId == null || personId.isEmpty) continue;
      final personName = person['name']?.toString() ?? 'Relative';
      final firstName = _firstName(personName);

      // Self — never produced by the structural computation. Skip.
      if (personId == viewerPersonId) continue;

      final entry = structural[personId];
      final key = entry?['key'];
      final label = entry?['label'];
      final explanation = entry?['explanation'] ?? 'relative';

      String primary;
      String? secondary;

      if (key != null && key.isNotEmpty && kinship.isLoaded) {
        final native = kinship.getKinshipTermByLocale(key, language);
        if (native != null && native.isNotEmpty) {
          primary = native;
        } else if (label != null && label.isNotEmpty) {
          primary = label;
        } else {
          primary = firstName;
        }
      } else if (label != null && label.isNotEmpty) {
        primary = label;
      } else if (key != null && key.isNotEmpty) {
        primary = key;
      } else {
        primary = firstName;
      }

      // Secondary subtitle: when showEnglishSubtitleProvider is true,
      // show the English label beneath the native term (matches the
      // mockup's "Mausi" bold + "Priya" small pattern — but with
      // subtitle preference, the small line is the English term,
      // not the first name). When false, secondary is null so the
      // caller can render the first name on its own.
      if (showSubtitle && label != null && label.isNotEmpty && primary != label) {
        secondary = label;
      }

      result[personId] = KinshipTerm(
        primary: primary,
        secondary: secondary,
        relationExplanation: explanation,
        kinshipKey: key,
      );
    }

    return result;
  },
  name: 'kinshipTermsForFamilyProvider',
);

// ═══════════════════════════════════════════════════════════════════════
// Feed-post term resolver
//
// Phase C will need to look up the kinship term for a feed post's
// AUTHOR (and ABOUT person). Feed posts reference authors by their
// Person.id (member_joined / connection_added) — so the lookup is
// the same as kinshipTermsForFamilyProvider, just keyed off the
// post's familyId instead of the currently-selected family.
// ═══════════════════════════════════════════════════════════════════════

/// Looks up the kinship term for a single person within a family.
///
/// Convenience wrapper so feed cards don't have to select-then-lookup
/// out of the full Map. Returns null when the family isn't loaded
/// yet or the person isn't reachable from the viewer — the caller
/// should fall back to the post's `authorName`.
final kinshipTermForPersonProvider =
    FutureProvider.family<KinshipTerm?, ({String familyId, String personId})>(
  (ref, args) async {
    final terms = await ref.watch(
      kinshipTermsForFamilyProvider(args.familyId).future,
    );
    return terms[args.personId];
  },
  name: 'kinshipTermForPersonProvider',
);

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Returns the first name from a full name (whitespace split).
String _firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'Relative';
  final space = trimmed.indexOf(' ');
  if (space <= 0) return trimmed;
  return trimmed.substring(0, space);
}

/// Re-export the helper so widgets can produce the same first-name
/// fallback the provider uses (single source of truth for the rules).
String kinrelFirstName(String fullName) => _firstName(fullName);
