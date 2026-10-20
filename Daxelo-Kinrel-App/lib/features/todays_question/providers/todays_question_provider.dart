// lib/features/todays_question/providers/todays_question_provider.dart
//
// DAXELO KINREL — Phase B — Today's Question provider.
//
// Picks ONE elder + ONE prompt to surface on Home per cycle. The
// selection is DETERMINISTIC (no server, no random) — the same
// (viewer, family, date) always picks the same prompt this week, so
// the card never flits between prompts on every refresh.
//
// Cadence: `kQuestionCadenceDays` (default 7). After the user taps
// "Skip" or successfully saves a recording, the card hides until
// the next cycle (per-family SharedPreferences timestamp).
//
// Selection rules:
//   1. Elder = oldest LIVING person in the family graph who has a
//      kinship path to the viewer (kinship term resolved). Living =
//      isDeceased != true. Oldest = lowest dateOfBirth (or lowest
//      generationIndex when dateOfBirth is null).
//   2. Prompt = the first prompt in stable `themeOrder` order that
//      the elder hasn't answered yet. "Answered" is determined by
//      reading AncestralMemory rows where topic='todaysQuestion'
//      AND userTags contains 'question:<promptId>' AND
//      userTags contains 'elder:<personId>'. If every prompt has
//      been answered, fall back to the first prompt (so the cycle
//      repeats) — never fake "no question".
//   3. If no suitable elder exists (viewer has no living relatives
//      in the family, or no kinship path resolves), the card
//      renders the "Add your first memory" state instead of a
//      fake question.
//
// All inputs are watched via ref.watch so Riverpod auto-rebuilds
// the state when the family graph changes, the language changes,
// or the user records/skips (via the invalidation in
// `markSkipped` / `markAnswered`).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/kinship/kinship_term_providers.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/viewer/viewer_provider.dart';
import '../../../features/family/presentation/providers/family_graph_provider.dart';
import '../domain/interview_prompts_localized.dart';

/// How many days between Today's Question cycles. After "Skip" or
/// saving a recording, the card stays hidden until the next cycle
/// rolls over.
///
/// Single source of truth — the spec says "controlled by one
/// constant". Change this to 1 for daily cadence during dev.
const int kQuestionCadenceDays = 7;

/// Visibility state — what the card should render this cycle.
enum TodaysQuestionVisibility {
  /// No suitable elder exists. The card renders the "Add your first
  /// memory" call-to-action instead of faking a question.
  noElder,

  /// The card is in cooldown — the user already skipped or answered
  /// this cycle. The card hides itself entirely (zero height).
  hidden,

  /// The card should show the question + mic button + Skip.
  visible,
}

/// The picked question for one cycle. Null when no elder exists.
class TodaysQuestionPick {
  const TodaysQuestionPick({
    required this.elderPersonId,
    required this.elderFirstName,
    required this.elderKinshipTerm,
    required this.elderGender,
    required this.promptId,
    required this.promptText,
    required this.relationExplanation,
  });

  final String elderPersonId;
  final String elderFirstName;
  final String elderKinshipTerm;
  final String? elderGender;
  final String promptId;
  final String promptText;
  final String relationExplanation;
}

/// Full state for the Today's Question card.
class TodaysQuestionState {
  const TodaysQuestionState({
    this.visibility = TodaysQuestionVisibility.hidden,
    this.pick,
    this.firstTimeConsentShown = false,
  });

  final TodaysQuestionVisibility visibility;

  /// The picked elder + prompt. Null when visibility == noElder or
  /// when the picker hasn't run yet.
  final TodaysQuestionPick? pick;

  /// Whether the "Recording {term}'s voice: make sure they're okay
  /// with it" notice should be shown on the first recording for
  /// this elder. Stored per-(familyId, elderPersonId) in prefs.
  final bool firstTimeConsentShown;
}

/// Picks the elder + prompt for a given family. Watches the family
/// graph, viewer person id, kinship terms, and language so it
/// auto-rebuilds when any of them change.
final todaysQuestionProvider =
    FutureProvider.family<TodaysQuestionState, String>(
  (ref, familyId) async {
    // Watch all upstream inputs so Riverpod auto-rebuilds.
    final viewerAsync = ref.watch(viewerPersonIdProvider(familyId));
    final viewerPersonId = viewerAsync.valueOrNull;
    final graphAsync = ref.watch(familyGraphProvider(familyId));
    final graph = graphAsync.valueOrNull;
    final language = ref.watch(kinshipTermLanguageProvider);
    final termsAsync = ref.watch(kinshipTermsForFamilyProvider(familyId));
    final terms = termsAsync.valueOrNull ?? const <String, KinshipTerm>{};

    if (graph == null || graph.persons.isEmpty) {
      return const TodaysQuestionState(
        visibility: TodaysQuestionVisibility.hidden,
      );
    }

    // ── Cycle gate — hide if the user already acted this cycle ──
    final cycleState = await _readCycleState(familyId);
    if (cycleState.isHiddenThisCycle) {
      return TodaysQuestionState(
        visibility: TodaysQuestionVisibility.hidden,
        firstTimeConsentShown: cycleState.consentShownForElder != null,
      );
    }

    // ── Step 1: pick the oldest living reachable elder ─────────────
    if (viewerPersonId == null || viewerPersonId.isEmpty) {
      return TodaysQuestionState(
        visibility: TodaysQuestionVisibility.noElder,
        firstTimeConsentShown: cycleState.consentShownForElder != null,
      );
    }

    final elders = <_ElderCandidate>[];
    for (final p in graph.persons) {
      final id = p['id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (id == viewerPersonId) continue;
      final isDeceased = (p['isDeceased'] as bool?) ?? false;
      if (isDeceased) continue;
      final term = terms[id];
      if (term == null) continue; // no path to viewer
      final dobStr =
          p['dateOfBirth']?.toString() ?? p['birthDate']?.toString();
      DateTime? dob;
      if (dobStr != null && dobStr.isNotEmpty) {
        dob = DateTime.tryParse(dobStr);
      }
      elders.add(_ElderCandidate(
        personId: id,
        name: p['name']?.toString() ?? 'Relative',
        gender: p['gender']?.toString(),
        generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
        dateOfBirth: dob,
        kinshipTerm: term.primary,
        relationExplanation: term.relationExplanation,
      ));
    }

    if (elders.isEmpty) {
      return TodaysQuestionState(
        visibility: TodaysQuestionVisibility.noElder,
        firstTimeConsentShown: cycleState.consentShownForElder != null,
      );
    }

    // Sort: oldest first. Prefer dateOfBirth (lower = older); fall
    // back to generationIndex (lower = older generation).
    elders.sort((a, b) {
      if (a.dateOfBirth != null && b.dateOfBirth != null) {
        return a.dateOfBirth!.compareTo(b.dateOfBirth!);
      }
      final genCmp = a.generationIndex.compareTo(b.generationIndex);
      if (genCmp != 0) return genCmp;
      return a.name.compareTo(b.name);
    });

    final elder = elders.first;

    // ── Step 2: pick the first prompt the elder hasn't answered ────
    final answeredIds = await _readAnsweredPromptIds(
      ref,
      familyId: familyId,
      elderPersonId: elder.personId,
    );
    String? pickedPromptId;
    for (final promptId in LocalizedInterviewPrompts.allIds) {
      if (!answeredIds.contains(promptId)) {
        pickedPromptId = promptId;
        break;
      }
    }
    // Every prompt answered → cycle back to the first one. Don't
    // fake "no question" — the cycle just repeats.
    pickedPromptId ??= LocalizedInterviewPrompts.allIds.first;

    final prompt = LocalizedInterviewPrompts.byId(pickedPromptId)!;
    final promptText = prompt.forLocale(language);

    final consentShownForThisElder =
        cycleState.consentShownForElder == elder.personId;

    return TodaysQuestionState(
      visibility: TodaysQuestionVisibility.visible,
      pick: TodaysQuestionPick(
        elderPersonId: elder.personId,
        elderFirstName: _firstName(elder.name),
        elderKinshipTerm: elder.kinshipTerm,
        elderGender: elder.gender,
        promptId: prompt.id,
        promptText: promptText,
        relationExplanation: elder.relationExplanation,
      ),
      firstTimeConsentShown: consentShownForThisElder,
    );
  },
  name: 'todaysQuestionProvider',
);

// ═══════════════════════════════════════════════════════════════════════
// Cycle-state side-channels — exposed as top-level functions so the
// card widget (which holds the ref) can call them directly. They
// invalidate todaysQuestionProvider after writing prefs so the next
// read re-runs the picker.
// ═══════════════════════════════════════════════════════════════════════

/// Marks the current cycle as skipped (per-family). Invalidates the
/// provider so the card hides until the next cycle.
Future<void> markTodaysQuestionSkipped(WidgetRef ref, String familyId) async {
  await _writeCycleEnd(familyId, cycleEndReason: 'skipped');
  ref.invalidate(todaysQuestionProvider(familyId));
}

/// Marks the current cycle as answered (per-family) + records that
/// consent was shown for this elder (so the first-time notice
/// doesn't reappear next cycle).
Future<void> markTodaysQuestionAnswered(
  WidgetRef ref,
  String familyId,
  String elderPersonId,
) async {
  await _writeCycleEnd(familyId, cycleEndReason: 'answered');
  await _markConsentShown(familyId, elderPersonId);
  ref.invalidate(todaysQuestionProvider(familyId));
}

/// Clears the cycle-end timestamp so the card re-appears
/// immediately. Used by the card's "show me again" affordance in
/// dev, or if the user wants to retry a skipped cycle.
Future<void> unskipTodaysQuestion(WidgetRef ref, String familyId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('kinrel.todaysQuestion.cycleEnd.$familyId');
  ref.invalidate(todaysQuestionProvider(familyId));
}

/// Records that the first-time consent notice has been shown for a
/// specific elder. Called by the card the first time the user taps
/// the mic button for that elder.
Future<void> recordTodaysQuestionConsentShown(
  String familyId,
  String elderPersonId,
) async {
  await _markConsentShown(familyId, elderPersonId);
}

// ── Cycle state persistence helpers ─────────────────────────────────

Future<_CycleState> _readCycleState(String familyId) async {
  final prefs = await SharedPreferences.getInstance();
  final cycleEndMs =
      prefs.getInt('kinrel.todaysQuestion.cycleEnd.$familyId');
  final consentElder =
      prefs.getString('kinrel.todaysQuestion.consentElder.$familyId');
  final now = DateTime.now().millisecondsSinceEpoch;
  final isHidden = cycleEndMs != null &&
      (now - cycleEndMs) < (kQuestionCadenceDays * 24 * 60 * 60 * 1000);
  return _CycleState(
    cycleEndMs: cycleEndMs,
    isHiddenThisCycle: isHidden,
    consentShownForElder: consentElder,
  );
}

Future<void> _writeCycleEnd(String familyId,
    {required String cycleEndReason}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(
    'kinrel.todaysQuestion.cycleEnd.$familyId',
    DateTime.now().millisecondsSinceEpoch,
  );
  await prefs.setString(
    'kinrel.todaysQuestion.cycleEndReason.$familyId',
    cycleEndReason,
  );
}

Future<void> _markConsentShown(String familyId, String elderPersonId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'kinrel.todaysQuestion.consentElder.$familyId',
    elderPersonId,
  );
}

// ── AncestralMemory answered-prompt lookup ──────────────────────────

/// Returns the set of promptIds the given elder has already
/// answered (across ALL cycles — answered prompts never re-surface
/// until every prompt has been answered, then the cycle repeats).
Future<Set<String>> _readAnsweredPromptIds(
  Ref ref, {
  required String familyId,
  required String elderPersonId,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) return const {};
  try {
    final rows = await client
        .from('AncestralMemory')
        .select('userTags')
        .eq('familyId', familyId)
        .eq('topic', 'todaysQuestion')
        .filter('userTags', 'cs', '{"elder:$elderPersonId"}');
    final ids = <String>{};
    for (final row in rows as List) {
      final tags = row['userTags'];
      if (tags is List) {
        for (final t in tags) {
          final s = t.toString();
          if (s.startsWith('question:')) {
            ids.add(s.substring('question:'.length));
          }
        }
      }
    }
    return ids;
  } catch (e) {
    debugPrint('⚠️ TodaysQuestion: answered-lookup failed: $e');
    // On error, assume NO prompts answered — the picker will
    // surface the first prompt. Better than hiding the card.
    return const {};
  }
}

// ── Helpers ─────────────────────────────────────────────────────────

class _CycleState {
  const _CycleState({
    this.cycleEndMs,
    required this.isHiddenThisCycle,
    this.consentShownForElder,
  });

  final int? cycleEndMs;
  final bool isHiddenThisCycle;
  final String? consentShownForElder;
}

class _ElderCandidate {
  const _ElderCandidate({
    required this.personId,
    required this.name,
    required this.gender,
    required this.generationIndex,
    this.dateOfBirth,
    required this.kinshipTerm,
    required this.relationExplanation,
  });

  final String personId;
  final String name;
  final String? gender;
  final int generationIndex;
  final DateTime? dateOfBirth;
  final String kinshipTerm;
  final String relationExplanation;
}

/// Returns the first name (whitespace split, "Relative" fallback).
String _firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'Relative';
  final space = trimmed.indexOf(' ');
  if (space <= 0) return trimmed;
  return trimmed.substring(0, space);
}
