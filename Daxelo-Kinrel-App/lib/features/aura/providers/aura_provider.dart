// lib/features/aura/providers/aura_provider.dart
//
// AURA — Riverpod provider.
//
// Mirrors the structure of lib/features/calendar/providers/calendar_provider.dart:
//   - `AuraState` (immutable state with copyWith)
//   - `AuraNotifier extends StateNotifier<AuraState>`
//   - `StateNotifierProvider.autoDispose.family<_, _, String>` keyed by familyId
//
// Data flow:
//   1. `load()` first reads from the Drift cache (instant offline render).
//   2. Then fetches from Supabase directly (RLS-protected SELECT on
//      "FamilyAura", "MemberAuraRole"). On success it writes through to
//      the Drift cache so the next cold-start can render offline.
//   3. If Supabase returns no row (404 / empty), we surface a `notComputed`
//      flag so the UI can offer a "Recompute" button.
//   4. `recompute()` POSTs to the NestJS /aura/:familyId/recompute endpoint
//      (which runs the heavy graph algorithms server-side and writes the
//      result back to Supabase). After 202, the UI polls `load()` until the
//      new AURA appears.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/services/supabase_service.dart';
import '../data/aura_model.dart';

/// Snapshot of everything the AURA UI needs to render.
class AuraState {
  const AuraState({
    this.aura,
    this.roles = const [],
    this.history = const [],
    this.isLoading = false,
    this.isFromCache = false,
    this.notComputed = false,
    this.isRecomputing = false,
    this.error,
  });

  /// The current AURA payload. `null` until the first successful load
  /// (or if the family has never had AURA computed).
  final AuraModel? aura;

  /// Per-member role glyphs (root/anchor/bridge/weaver/leaf/twin_node).
  final List<RoleGlyph> roles;

  /// Historical AURA snapshots for the timeline widget.
  final List<AuraHistorySnapshot> history;

  /// True while a network fetch or recompute is in flight.
  final bool isLoading;

  /// True when `aura` was loaded from the Drift cache rather than the
  /// network. The UI uses this to show a "Cached — last updated X ago"
  /// hint when offline.
  final bool isFromCache;

  /// True when Supabase confirmed there is no FamilyAura row for this
  /// family yet. The UI offers a "Recompute" button in this state.
  final bool notComputed;

  /// True while waiting for the backend recompute endpoint to return 202.
  final bool isRecomputing;

  /// User-facing error message. `null` when the last operation succeeded.
  final String? error;

  AuraState copyWith({
    AuraModel? aura,
    List<RoleGlyph>? roles,
    List<AuraHistorySnapshot>? history,
    bool? isLoading,
    bool? isFromCache,
    bool? notComputed,
    bool? isRecomputing,
    String? error,
    bool clearError = false,
    bool clearAura = false,
    bool clearNotComputed = false,
  }) =>
      AuraState(
        aura: clearAura ? null : (aura ?? this.aura),
        roles: roles ?? this.roles,
        history: history ?? this.history,
        isLoading: isLoading ?? this.isLoading,
        isFromCache: isFromCache ?? this.isFromCache,
        notComputed: clearNotComputed ? false : (notComputed ?? this.notComputed),
        isRecomputing: isRecomputing ?? this.isRecomputing,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuraNotifier extends StateNotifier<AuraState> {
  AuraNotifier(this._ref, this.familyId) : super(const AuraState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);

  /// Returns the Drift database if initialized, or null on web/first-run.
  /// All Drift calls are guarded so the provider still works in
  /// Supabase-only mode (e.g. on Flutter Web where Drift is skipped).
  AppDatabase? get _db {
    if (!IsarDatabase.isInitialized) return null;
    try {
      return IsarDatabase.instance;
    } catch (_) {
      return null;
    }
  }

  /// Load the AURA payload for [familyId].
  ///
  /// Strategy:
  ///   1. Read Drift cache first → render instantly (isFromCache=true).
  ///   2. Fetch from Supabase → render fresh (isFromCache=false) and
  ///      write through to Drift.
  ///   3. If Supabase returns no row → set notComputed=true.
  ///   4. On Supabase error → keep the cached value (if any) and set error.
  Future<void> load({bool includeHistory = false}) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearNotComputed: true,
    );

    // ── Step 1: Drift cache read ──────────────────────────────────────
    final db = _db;
    if (db != null) {
      try {
        final cached = await db.getCachedAura(familyId);
        if (cached != null && cached.data.isNotEmpty) {
          final model = AuraModel.decode(cached.data);
          final roles = _decodeRoles(cached.rolesJson);
          state = state.copyWith(
            aura: model,
            roles: roles,
            isFromCache: true,
            isLoading: false,
          );
        }
      } catch (e) {
        debugPrint('⚠️ AURA Drift cache read failed: $e');
      }
    }

    // ── Step 2: Supabase fetch ────────────────────────────────────────
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        error: state.aura == null ? 'Not signed in' : null,
      );
      return;
    }

    try {
      final auraRow = await client
          .from('FamilyAura')
          .select()
          .eq('familyId', familyId)
          .maybeSingle();

      if (auraRow == null) {
        state = state.copyWith(
          isLoading: false,
          notComputed: true,
          isFromCache: false,
        );
        return;
      }

      final model = _modelFromRow(auraRow);
      final roles = await _fetchRoles(client);

      // Write through to Drift cache.
      await _writeCache(model, roles);

      var history = const <AuraHistorySnapshot>[];
      if (includeHistory) {
        history = await _fetchHistory(client);
      }

      state = state.copyWith(
        aura: model,
        roles: roles,
        history: history,
        isLoading: false,
        isFromCache: false,
        clearNotComputed: true,
      );
    } catch (e) {
      debugPrint('⚠️ AURA Supabase fetch failed: $e');
      state = state.copyWith(
        isLoading: false,
        error: '$e',
      );
    }
  }

  /// Load only the historical snapshots (for the timeline widget).
  Future<void> loadHistory() async {
    final client = _client;
    if (client == null) return;
    try {
      final history = await _fetchHistory(client);
      state = state.copyWith(history: history);
    } catch (e) {
      debugPrint('⚠️ AURA history fetch failed: $e');
    }
  }

  /// Trigger a backend AURA recompute. Returns 202 immediately; the
  /// caller should poll [load] until the new AURA appears.
  ///
  /// Uses the NestJS REST API at AppConfig.apiBaseUrl (the Render service).
  /// We use dart:io HttpClient so we don't need to add http/dio packages
  /// just for this one POST.
  Future<bool> recompute() async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }

    final session = client.auth.currentSession;
    if (session == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }

    state = state.copyWith(isRecomputing: true, clearError: true);
    try {
      final url = Uri.parse(
        '${AppConfig.apiBaseUrl}/aura/$familyId/recompute',
      );
      final httpClient = HttpClient();
      try {
        final request = await httpClient.postUrl(url);
        request.headers.set('Authorization', 'Bearer ${session.accessToken}');
        request.headers.contentType = ContentType.json;
        final response = await request.close();
        // 202 Accepted = recompute started successfully.
        // 401 / 403 = auth issue → surface to user.
        // 404 = family not found or user not a member.
        if (response.statusCode == 202) {
          state = state.copyWith(isRecomputing: false);
          return true;
        }
        final body = await response.transform(const Utf8Decoder()).join();
        state = state.copyWith(
          isRecomputing: false,
          error: 'Recompute failed (${response.statusCode}): $body',
        );
        return false;
      } finally {
        httpClient.close();
      }
    } catch (e) {
      debugPrint('⚠️ AURA recompute failed: $e');
      state = state.copyWith(
        isRecomputing: false,
        error: '$e',
      );
      return false;
    }
  }

  /// Clear the local cache for this family. Used when the user leaves
  /// a family or signs out.
  Future<void> clearCache() async {
    final db = _db;
    if (db == null) return;
    try {
      await db.deleteCachedAura(familyId);
    } catch (e) {
      debugPrint('⚠️ AURA cache delete failed: $e');
    }
  }

  // ── Internal helpers ────────────────────────────────────────────────

  /// Build an [AuraModel] from a Supabase FamilyAura row.
  /// The row's column names match the migration in
  /// supabase/migrations/20260708010000_create_aura_tables.sql.
  AuraModel _modelFromRow(Map<String, dynamic> row) {
    // Re-shape the flat Supabase row into the nested JSON shape that
    // AuraModel.fromJson expects (matches the NestJS /aura/:familyId
    // response envelope).
    final json = <String, dynamic>{
      'familyId': row['familyId'],
      'symbol': {
        'ringCount': row['ringCount'],
        'spokeCount': row['spokeCount'],
        'innerPatternType': row['innerPatternType'],
        'outerRingRadiusPct': row['outerRingRadiusPct'],
        'patternComplexity': row['patternComplexity'],
        'primaryColorHex': row['primaryColorHex'],
        'secondaryColorHex': row['secondaryColorHex'],
        'accentColorHex': row['accentColorHex'],
        'pulseSpeedMs': row['pulseSpeedMs'],
      },
      'archetype': {
        'key': row['archetypeKey'],
        'confidence': row['archetypeConfidence'],
      },
      'metrics': {
        'memberCount': row['memberCount'],
        'generationDepth': row['generationDepth'],
        'edgeCount': row['edgeCount'],
        'clusteringCoefficient': row['clusteringCoefficient'],
        'graphDiameter': row['graphDiameter'],
        'avgDegree': row['avgDegree'],
        'distinctLineages': row['distinctLineages'],
        'languageDistribution': row['languageDistribution'],
        'maxBetweennessNode': row['maxBetweennessNode'],
        'rootNode': row['rootNode'],
      },
      'computedAt': row['computedAt'],
      'updatedAt': row['updatedAt'],
    };
    return AuraModel.fromJson(json);
  }

  Future<List<RoleGlyph>> _fetchRoles(SupabaseClient client) async {
    try {
      final rows = await client
          .from('MemberAuraRole')
          .select()
          .eq('familyId', familyId);
      return rows
          .map((r) => RoleGlyph.fromJson(r))
          .toList(growable: false);
    } catch (e) {
      debugPrint('⚠️ AURA roles fetch failed: $e');
      return const [];
    }
  }

  Future<List<AuraHistorySnapshot>> _fetchHistory(
      SupabaseClient client) async {
    try {
      final rows = await client
          .from('FamilyAuraHistory')
          .select()
          .eq('familyId', familyId)
          .order('capturedAt', ascending: true);
      return rows
          .map((r) => AuraHistorySnapshot.fromJson(r))
          .toList(growable: false);
    } catch (e) {
      debugPrint('⚠️ AURA history fetch failed: $e');
      return const [];
    }
  }

  Future<void> _writeCache(AuraModel model, List<RoleGlyph> roles) async {
    final db = _db;
    if (db == null) return;
    try {
      final rolesJson = jsonEncode(roles.map((r) => r.toJson()).toList());
      await db.upsertCachedAura(
        CachedAurasCompanion(
          familyId: Value(model.familyId.isEmpty ? familyId : model.familyId),
          data: Value(model.encode()),
          rolesJson: Value(rolesJson),
          cachedAt: Value(DateTime.now()),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ AURA cache write failed: $e');
    }
  }

  List<RoleGlyph> _decodeRoles(String rolesJson) {
    if (rolesJson.isEmpty) return const [];
    try {
      final decoded = jsonDecode(rolesJson);
      if (decoded is! List) return const [];
      return decoded
          .map((r) =>
              RoleGlyph.fromJson(r as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('⚠️ AURA roles cache decode failed: $e');
      return const [];
    }
  }
}

/// Per-family AURA provider. Auto-disposed when the last listener goes
/// away (matches the calendar_provider pattern).
final auraProvider =
    StateNotifierProvider.autoDispose.family<AuraNotifier, AuraState, String>(
  (ref, familyId) => AuraNotifier(ref, familyId),
);

/// Convenience lookup: the role glyph for a specific member, or null if
/// AURA hasn't been computed yet or the member has no role row.
final memberRoleGlyphProvider =
    Provider.autoDispose.family<RoleGlyph?, String>((ref, familyIdAndMemberId) {
  // Encoding: "familyId|memberId" — keeps it as a single string for
  // family-of-provider simplicity. Callers use the helper below.
  final parts = familyIdAndMemberId.split('|');
  if (parts.length != 2) return null;
  final familyId = parts[0];
  final memberId = parts[1];
  final state = ref.watch(auraProvider(familyId));
  for (final r in state.roles) {
    if (r.memberId == memberId) return r;
  }
  return null;
});

/// Helper to build the key for [memberRoleGlyphProvider].
String memberRoleKey(String familyId, String memberId) =>
    '$familyId|$memberId';
