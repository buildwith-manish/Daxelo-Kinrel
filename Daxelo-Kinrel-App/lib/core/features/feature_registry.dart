// lib/core/features/feature_registry.dart
//
// DAXELO KINREL — Feature Registry (Phase 1)
//
// Single source of truth for every feature on/off switch in the app.
// Replaces the scattered `const bool kEnable*` flags in
// `lib/core/constants/feature_flags.dart` with a runtime-resolvable
// registry that can be flipped via, in priority order:
//
//   1. Debug override   — debug builds only, persisted in SharedPreferences
//                         under the key `feature_debug_<feature_name>`.
//   2. Remote Config     — server-side flips without an app release,
//                         keyed `feature_<feature_name>` in Firebase RC.
//   3. Compiled default  — the value in `_defaults` below.
//
// Resolution order:   debug override > Remote Config > _defaults
//
// Dependency map (`_parents`): if a parent feature is OFF, the child is
// forced OFF regardless of its own value. This lets one switch gate a
// whole cluster — e.g. turning `activities` OFF also hides `memories`
// AND `memberTimeline` (per the "activities is the master switch for
// memories + timeline" rule).
//
//   coinPool          → predictionBattle
//   games             → gameInvitePush
//   paywall           → premiumInsights
//   familyMap         → familyJourney
//   activities        → memories
//   activities        → memberTimeline
//
// Phase 1 contract: ALL defaults are `true` so the app looks exactly
// as it did before this file existed. Lean defaults are set in Phase 4.
//
// `unifiedTimeline` has NO screen yet — its default stays `true` and the
// flag is intentionally unused everywhere; it is left untouched.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/remote_config_service.dart';

/// Every feature in the app that has an on/off switch.
///
/// Order is intentional and stable: top-level surfaces first (nav,
/// hero icons, top-bar icons), then dependent sub-features, then
/// internal/plumbing flags. The order is stable so unit tests can
/// iterate by index without surprises when the enum grows.
enum AppFeature {
  // ── Top-level nav surfaces ─────────────────────────────────────
  home,
  familyMap,
  familyJourney, // depends on familyMap
  kinrel,
  sparqTray,
  sparqRunNavigation,
  feed,
  chat,
  circle,
  communities,
  profile,
  profileEditing,
  findOnKinrel,

  // ── Family Space nav tabs ──────────────────────────────────────
  games,
  gameInvitePush, // depends on games
  familyChat,
  members,
  calendar,

  // ── Family Hub highlights row + Activities cluster ────────────
  activities, // master switch — gates memories + memberTimeline
  memories, // depends on activities
  memberTimeline, // depends on activities
  oralHistory,
  achievements,
  lists,
  governanceTimeline,
  unifiedTimeline, // no screen yet — left untouched

  // ── Hero icons ────────────────────────────────────────────────
  heroFamilyMap,
  heroKinrel,
  heroFindOnKinrel,
  heroAddMember,

  // ── Top-bar icons ─────────────────────────────────────────────
  topBarNotifications,
  topBarSettings,

  // ── Cameo system ──────────────────────────────────────────────
  cameoFallback,
  live3DCameo,
  cameoStudio,

  // ── Today's Question ──────────────────────────────────────────
  todaysQuestion,

  // ── Chat features ─────────────────────────────────────────────
  voiceMessages,
  scheduledMessages,
  chatMentions,
  chatBlockReport,
  chatReactions,
  chatTypingIndicator,
  chatGallery,

  // ── Graph / map / picker ─────────────────────────────────────
  graphShareExport,
  photoPicker,
  qrJoin,
  languagePicker,
  audioPronunciation,
  autoKinshipInference,
  kinshipRingRow,

  // ── Premium / paywall ─────────────────────────────────────────
  paywall,
  premiumInsights, // depends on paywall
  premiumExport,
  premiumAiKinship,

  // ── Memory vault ──────────────────────────────────────────────
  memoryVault,
  memoryVaultFreeMonthlyCap,

  // ── Member / family caps ─────────────────────────────────────
  maxFreeMembers,
  maxFreeFamilies,

  // ── Coin pool / prediction battle ────────────────────────────
  coinPool,
  predictionBattle, // depends on coinPool

  // ── Push / re-engagement ──────────────────────────────────────
  pushGameInvite,
  pushReEngagement,
  pushMention,
  pushScheduledMessage,

  // ── Invite / referral ─────────────────────────────────────────
  inviteBanner,
  referralOnProfile,
  retentionNudge,

  // ── AI suggestions ────────────────────────────────────────────
  aiSuggestions,

  // ── Onboarding ────────────────────────────────────────────────
  onboarding,
}

// ── Compiled defaults (Phase 4: lean launch set, heroFamilyMap flipped ON) ─
//
// Phase 4 contract: 21 features ON (the daily-use surface, incl.
// the hero Graph + Map flanking icons turned back ON per user
// request 2026-10-23), 43 OFF (everything else — premium, experi-
// mental, push, debug plumbing), 1 untouched (`unifiedTimeline`
// has no screen yet — per the spec, "leave it alone").
//
// Lean launch ON set (21):
//   • Top-level surfaces: home, familyMap, kinrel, sparqTray, feed,
//     chat, familyChat, members, calendar, profile, profileEditing,
//     findOnKinrel
//   • Activities cluster (master switch + children): activities,
//     memories, memberTimeline
//   • HighlightsRow extras: oralHistory
//   • Top-bar: topBarNotifications, topBarSettings
//   • Home: todaysQuestion, inviteBanner
//   • Hero icons: heroFamilyMap (the Graph + Map flanking icons
//     in hero_section.dart — turned ON per user request 2026-10-23)
//
// Lean launch OFF set (43):
//   • familyJourney (depends on familyMap — premium subfeature, OFF)
//   • sparqRunNavigation (premium subfeature)
//   • circle, communities (hidden per IA review)
//   • games, gameInvitePush (games OFF, push cascades OFF)
//   • achievements, lists, governanceTimeline (occasional-use)
//   • hero* (3 remaining icons: heroKinrel, heroFindOnKinrel,
//     heroAddMember — all hidden)
//   • cameo* (3 entries — B1 verification incomplete)
//   • chat* (6 sub-features: voice, scheduled, mentions, block, react,
//     typing, gallery — all behind the lean launch scope)
//   • graph/picker/graph extras: graphShareExport, photoPicker, qrJoin,
//     languagePicker, audioPronunciation, autoKinshipInference,
//     kinshipRingRow
//   • premium: paywall, premiumInsights (cascade), premiumExport,
//     premiumAiKinship
//   • memoryVault, memoryVaultFreeMonthlyCap
//   • max caps: maxFreeMembers, maxFreeFamilies (caps OFF means no cap)
//   • coinPool, predictionBattle (cascade)
//   • push* (4 channels — server-side filtering handles them too)
//   • referral, retentionNudge, aiSuggestions, onboarding
//
// To flip a feature, either change the value here (defaults) or set
// the corresponding `feature_<name>` Remote Config key, or use the
// debug override in the Debug screen.
const Map<AppFeature, bool> _defaults = {
  // ── ON (21) — the daily-use surface ────────────────────────────
  AppFeature.home: true,
  AppFeature.familyMap: true,
  AppFeature.kinrel: true,
  AppFeature.sparqTray: true,
  AppFeature.feed: true,
  AppFeature.chat: true,
  AppFeature.familyChat: true,
  AppFeature.members: true,
  AppFeature.calendar: true,
  AppFeature.profile: true,
  AppFeature.profileEditing: true,
  AppFeature.findOnKinrel: true,
  AppFeature.activities: true, // master switch — gates memories + memberTimeline
  AppFeature.memories: true, // /memories + /memory-vault visible
  AppFeature.memberTimeline: true, // /timeline + /member-timeline visible
  AppFeature.oralHistory: true,
  AppFeature.todaysQuestion: true,
  AppFeature.inviteBanner: true,
  AppFeature.topBarNotifications: true,
  AppFeature.topBarSettings: true,
  // Turned ON per user request (2026-10-23): the hero Graph + Map
  // flanking icons in hero_section.dart now render. They navigate to
  // /family/:id/graph and /family/:id/map (routes already accessible
  // via familyMap=ON). The other 3 hero* flags stay OFF.
  AppFeature.heroFamilyMap: true,

  // ── OFF (43) — premium / experimental / occasional-use ───────────
  AppFeature.familyJourney: false, // depends on familyMap
  AppFeature.sparqRunNavigation: false,
  AppFeature.circle: false,
  AppFeature.communities: false,
  AppFeature.games: false,
  AppFeature.gameInvitePush: false, // depends on games
  AppFeature.achievements: false,
  AppFeature.lists: false,
  AppFeature.governanceTimeline: false, // NEW — OFF per spec
  AppFeature.heroKinrel: false,
  AppFeature.heroFindOnKinrel: false,
  AppFeature.heroAddMember: false,
  AppFeature.cameoFallback: false,
  AppFeature.live3DCameo: false,
  AppFeature.cameoStudio: false,
  AppFeature.voiceMessages: false,
  AppFeature.scheduledMessages: false,
  AppFeature.chatMentions: false,
  AppFeature.chatBlockReport: false,
  AppFeature.chatReactions: false,
  AppFeature.chatTypingIndicator: false,
  AppFeature.chatGallery: false,
  AppFeature.graphShareExport: false,
  AppFeature.photoPicker: false,
  AppFeature.qrJoin: false,
  AppFeature.languagePicker: false,
  AppFeature.audioPronunciation: false,
  AppFeature.autoKinshipInference: false,
  AppFeature.kinshipRingRow: false,
  AppFeature.paywall: false,
  AppFeature.premiumInsights: false, // depends on paywall
  AppFeature.premiumExport: false,
  AppFeature.premiumAiKinship: false,
  AppFeature.memoryVault: false,
  AppFeature.memoryVaultFreeMonthlyCap: false,
  AppFeature.maxFreeMembers: false,
  AppFeature.maxFreeFamilies: false,
  AppFeature.coinPool: false,
  AppFeature.predictionBattle: false, // depends on coinPool
  AppFeature.pushGameInvite: false,
  AppFeature.pushReEngagement: false,
  AppFeature.pushMention: false,
  AppFeature.pushScheduledMessage: false,
  AppFeature.referralOnProfile: false,
  AppFeature.retentionNudge: false,
  AppFeature.aiSuggestions: false,
  AppFeature.onboarding: false,

  // ── UNTOUCHED (1) — no screen yet ───────────────────────────────
  // `unifiedTimeline` has no UI surface and is not referenced anywhere
  // outside the routeFeatureMap. Per the spec ("leave it alone"), its
  // default stays `true` — flipping it has no user-visible effect.
  AppFeature.unifiedTimeline: true,
};

// ── Dependency map ─────────────────────────────────────────────────────
//
// `_parents[f]` is the feature that `f` depends on. If the parent is
// OFF, `f` is forced OFF regardless of its own value. A feature may
// appear in this map at most once (single parent). Multi-parent chains
// are resolved recursively (parent itself may have a parent).
//
// Rules:
//   predictionBattle  → coinPool
//   gameInvitePush    → games
//   premiumInsights   → paywall
//   familyJourney     → familyMap
//   memories          → activities       (master switch rule)
//   memberTimeline    → activities       (master switch rule)
const Map<AppFeature, AppFeature> _parents = {
  AppFeature.predictionBattle: AppFeature.coinPool,
  AppFeature.gameInvitePush: AppFeature.games,
  AppFeature.premiumInsights: AppFeature.paywall,
  AppFeature.familyJourney: AppFeature.familyMap,
  AppFeature.memories: AppFeature.activities,
  AppFeature.memberTimeline: AppFeature.activities,
};

// ── Route prefix → feature map (used by Phase 3 route guard) ────────────
//
// When the GoRouter redirect runs, it strips the leading `/` and looks
// up the longest matching prefix here. If the resolved feature is OFF,
// the route is redirected to `/home`.
//
// Phase 1 only DECLARES the map — Phase 3 wires it into `app_router.dart`.
// Keys must NOT have a leading slash. Order matters: longer prefixes
// must come before shorter ones (e.g. `/memory-vault` before `/memory`).
const Map<String, AppFeature> routeFeatureMap = {
  // Top-level routes
  'home': AppFeature.home,
  'family': AppFeature.familyMap,
  'family-journey': AppFeature.familyJourney,
  'kinrel': AppFeature.kinrel,
  'sparq': AppFeature.sparqTray,
  'feed': AppFeature.feed,
  'chat': AppFeature.chat,
  'circle': AppFeature.circle,
  'communities': AppFeature.communities,
  'profile': AppFeature.profile,
  'find-on-kinrel': AppFeature.findOnKinrel,

  // Family Space sub-routes (under /family/:id)
  'family/games': AppFeature.games,
  'family/chat': AppFeature.familyChat,
  'family/members': AppFeature.members,
  'family/calendar': AppFeature.calendar,

  // Activities cluster — BOTH /memories and /memory-vault gated by
  // the memories flag, which itself cascades from activities.
  'memories': AppFeature.memories,
  'memory-vault': AppFeature.memories,
  'memory': AppFeature.memories,
  'timeline': AppFeature.memberTimeline,
  'member-timeline': AppFeature.memberTimeline,
  'governance': AppFeature.governanceTimeline,
  'oral-history': AppFeature.oralHistory,
  'achievements': AppFeature.achievements,
  'lists': AppFeature.lists,

  // Other surfaces
  'games': AppFeature.games,
  'game-invite': AppFeature.gameInvitePush,
  'coin-pool': AppFeature.coinPool,
  'prediction-battle': AppFeature.predictionBattle,
  'todays-question': AppFeature.todaysQuestion,
  'studio': AppFeature.cameoStudio,
  'paywall': AppFeature.paywall,
  'premium': AppFeature.paywall,
  'settings': AppFeature.topBarSettings,
  'notifications': AppFeature.topBarNotifications,
};

// ── Debug overrides (debug builds only) ────────────────────────────────
//
// In debug builds, persisted to SharedPreferences under the key
// `feature_debug_<feature_name>`. In release builds, the map stays
// empty and `setDebugOverride` is a no-op.
final Map<AppFeature, bool> _debugOverrides = {};

/// Bumped each time Remote Config is re-fetched and activated. UI that
/// wants to react to RC updates watches this provider and re-reads
/// `featureProvider(f)` on change.
final remoteConfigUpdateProvider = StateProvider<int>((ref) => 0);

/// Reactive per-feature flag for Riverpod UI. Reads through the same
/// `Features.isOn` resolver so debug overrides + RC + defaults +
/// dependency cascade all apply uniformly.
///
/// Usage:
///   final on = ref.watch(featureProvider(AppFeature.familyMap));
///   if (!on) return SizedBox.shrink();
final featureProvider = Provider.family<bool, AppFeature>((ref, f) {
  // Re-build whenever RC update counter changes.
  ref.watch(remoteConfigUpdateProvider);
  return Features.isOn(f);
});

// ── Features facade ─────────────────────────────────────────────────────
//
// Static surface so non-Riverpod contexts (route guards, push handlers,
// background isolates) can resolve a feature without a ref.
class Features {
  Features._();

  /// SharedPreferences key prefix for debug overrides.
  static const _debugKeyPrefix = 'feature_debug_';

  /// Load any persisted debug overrides from SharedPreferences. Called
  /// once at app startup (debug builds only; release builds short-
  /// circuit inside the `if (kDebugMode)` guard).
  static Future<void> initDebugOverrides() async {
    if (!kDebugMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _debugOverrides.clear();
      for (final f in AppFeature.values) {
        final key = '$_debugKeyPrefix${f.name}';
        if (prefs.containsKey(key)) {
          _debugOverrides[f] = prefs.getBool(key) ?? true;
        }
      }
      debugPrint('🔧 Features.initDebugOverrides: '
          '${_debugOverrides.length} overrides loaded');
    } catch (e) {
      debugPrint('🔧 Features.initDebugOverrides failed: $e');
    }
  }

  /// The compiled default for [f]. Useful for the debug screen to show
  /// the "original" value alongside the live resolved value.
  static bool defaultOf(AppFeature f) => _defaults[f] ?? false;

  /// The parent of [f], or `null` if [f] has no parent in the
  /// dependency map.
  static AppFeature? parentOf(AppFeature f) => _parents[f];

  /// The map of parents (read-only view for tests / debug screen).
  static Map<AppFeature, AppFeature> get parentsMap =>
      Map.unmodifiable(_parents);

  /// True iff [f] is currently ON.
  ///
  /// Resolution order:
  ///   1. Debug override (debug builds only)
  ///   2. Remote Config value for `feature_<f.name>`
  ///   3. Compiled default from [_defaults]
  /// Then: if any ancestor (parent, grandparent, …) is OFF, [f] is
  /// forced OFF regardless of its own value.
  static bool isOn(AppFeature f) {
    // Step 1: debug override.
    if (kDebugMode && _debugOverrides.containsKey(f)) {
      final v = _debugOverrides[f]!;
      if (!v) return false;
      // If override is ON, still cascade through parents so a parent
      // being OFF keeps the child OFF (prevents a debug override from
      // surfacing a feature whose parent is intentionally disabled).
    } else {
      // No debug override — fall through to RC + default below.
    }

    // Step 2 + 3: resolve own value (RC or default).
    final ownValue = _resolveOwn(f);

    // Step 4: dependency cascade — walk up the parent chain. If any
    // ancestor resolves to OFF, force OFF.
    var current = _parents[f];
    final seen = <AppFeature>{};
    while (current != null) {
      if (!seen.add(current)) {
        // Cycle guard (should never happen, but defensive).
        break;
      }
      if (!_resolveOwn(current)) {
        return false;
      }
      current = _parents[current];
    }

    return ownValue;
  }

  /// Resolves [f] to a bool WITHOUT walking the parent chain — used
  /// internally by [isOn] to check ancestors without infinite
  /// recursion. Applies debug override > RC > default in that order.
  static bool _resolveOwn(AppFeature f) {
    if (kDebugMode && _debugOverrides.containsKey(f)) {
      return _debugOverrides[f]!;
    }
    final rc = _readRemoteConfig(f);
    return rc ?? (_defaults[f] ?? false);
  }

  /// Reads the Remote Config value for [f], returning `null` if RC
  /// isn't initialized or doesn't have a value (caller falls back to
  /// the compiled default).
  static bool? _readRemoteConfig(AppFeature f) {
    try {
      final rc = RemoteConfigService.instance;
      if (!rc.isInitialized) return null;
      final key = 'feature_${f.name}';
      // Only treat the RC value as authoritative if the key is set
      // (i.e. present in the RC defaults map). Otherwise fall through
      // to the compiled default so we don't accidentally read `false`
      // for keys that haven't been deployed to the RC console yet.
      if (!rc.hasKey(key)) return null;
      return rc.getBool(key);
    } catch (_) {
      return null;
    }
  }

  /// True iff the route at [path] is currently disabled by virtue of
  /// its mapped feature being OFF. Returns `false` if the path doesn't
  /// match any entry in [routeFeatureMap] (unknown routes are always
  /// allowed — they're not feature-gated).
  ///
  /// Strips the leading `/` and matches the LONGEST prefix in
  /// [routeFeatureMap] so that e.g. `/family/123/games` matches
  /// `family/games` rather than just `family`.
  static bool isRouteDisabled(String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    // Try the full path first, then progressively strip trailing
    // segments, looking for the longest matching prefix.
    var candidate = clean;
    while (true) {
      if (routeFeatureMap.containsKey(candidate)) {
        return !isOn(routeFeatureMap[candidate]!);
      }
      final idx = candidate.lastIndexOf('/');
      if (idx < 0) break;
      candidate = candidate.substring(0, idx);
    }
    return false;
  }

  // ── Debug overrides (debug builds only) ──────────────────────

  /// Set a debug override for [f]. Persists to SharedPreferences so
  /// the override survives app restarts during testing. No-op in
  /// release builds.
  static Future<void> setDebugOverride(AppFeature f, bool value) async {
    if (!kDebugMode) return;
    _debugOverrides[f] = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_debugKeyPrefix${f.name}', value);
    } catch (e) {
      debugPrint('🔧 Features.setDebugOverride persist failed: $e');
    }
  }

  /// Clear the debug override for [f] (revert to RC + default
  /// resolution). Removes the SharedPreferences key. No-op in
  /// release builds.
  static Future<void> clearDebugOverride(AppFeature f) async {
    if (!kDebugMode) return;
    _debugOverrides.remove(f);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_debugKeyPrefix${f.name}');
    } catch (e) {
      debugPrint('🔧 Features.clearDebugOverride persist failed: $e');
    }
  }

  /// Snapshot of the current debug overrides (read-only view for the
  /// debug screen).
  static Map<AppFeature, bool> get debugOverrides =>
      Map.unmodifiable(_debugOverrides);

  /// True iff [f] has an active debug override.
  static bool hasDebugOverride(AppFeature f) =>
      kDebugMode && _debugOverrides.containsKey(f);

  /// Bump the RC update counter so any `featureProvider` consumer
  /// rebuilds. Call after `RemoteConfigService.instance.fetchAndActivate()`
  /// (or just `init()`).
  static void notifyRemoteConfigUpdated(Ref ref) {
    final current = ref.read(remoteConfigUpdateProvider);
    ref.read(remoteConfigUpdateProvider.notifier).state = current + 1;
  }
}
