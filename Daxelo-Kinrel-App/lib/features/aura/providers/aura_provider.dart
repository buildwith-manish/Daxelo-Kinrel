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

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/networking/dio_client.dart';
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

  /// Dio HTTP client — works on all platforms (web + native) without
  /// the dart:io HttpClient crash. The dioProvider already injects the
  /// Supabase JWT via _AuthInterceptor and uses EnvConfig.apiBaseUrl
  /// as the base, so we pass relative paths only.
  Dio get _dio => _ref.read(dioProvider);

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
  /// Strategy (Bug 7 fix: route reads through NestJS /aura/:familyId
  /// so the backend's requireFamilyMembership() check runs on every
  /// read — defense-in-depth on top of RLS):
  ///   1. Read Drift cache first → render instantly (isFromCache=true).
  ///   2. Fetch from NestJS GET /aura/:familyId → render fresh
  ///      (isFromCache=false) and write through to Drift.
  ///   3. If NestJS returns 404 → set notComputed=true.
  ///   4. On NestJS error → keep the cached value (if any) and set error.
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

    // ── Step 2: NestJS fetch (Bug 7 fix) ──────────────────────────────
    // Route through the NestJS /aura/:familyId endpoint so the backend's
    // requireFamilyMembership() check runs on every read. This is
    // defense-in-depth on top of the Supabase RLS policies — if a future
    // RLS change or bug accidentally exposes FamilyAura rows, the NestJS
    // membership check still blocks the read.
    //
    // Falls back to direct Supabase read only if the NestJS endpoint is
    // unreachable (network error / 5xx) AND we have no cached value, so
    // the user still sees something rather than a blank screen.
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        error: state.aura == null ? 'Not signed in' : null,
      );
      return;
    }

    final session = client.auth.currentSession;
    if (session == null) {
      state = state.copyWith(
        isLoading: false,
        error: state.aura == null ? 'Not signed in' : null,
      );
      return;
    }

    try {
      Map<String, dynamic>? auraJson;
      try {
        auraJson = await _fetchViaNestJs(
          path: '/api/aura/$familyId',
          accessToken: session.accessToken,
        );
      } on DioException catch (e) {
        // 404 = AURA not yet computed for this family. Not an error —
        // surface as notComputed=true so the UI shows the "Generate
        // AURA" button.
        if (e.response?.statusCode == 404) {
          auraJson = null;
        } else {
          rethrow;
        }
      }

      if (auraJson == null) {
        // 404 — AURA not yet computed for this family.
        // Bug 11 fix: only set `notComputed = true` if we have NO
        // cached AURA to fall back on. Previously this unconditionally
        // set `notComputed = true` even when a cached AURA was already
        // shown (state.aura != null), which caused the FAB to be
        // hidden (Bug 21) and the user couldn't recompute.
        // When a cache exists, keep showing it and mark `isFromCache`
        // so the UI shows the "offline" banner.
        final hasCache = state.aura != null;
        state = state.copyWith(
          isLoading: false,
          notComputed: !hasCache,
          isFromCache: hasCache,
          // If no cache, clear stale aura so UI shows "Generate AURA".
          clearAura: !hasCache,
        );
        return;
      }

      final model = AuraModel.fromJson(auraJson);

      // Roles + history still come from Supabase directly — the NestJS
      // /aura/:familyId endpoint returns only the current AURA, not the
      // roles or history. The RLS policies on MemberAuraRole +
      // FamilyAuraHistory are the only guard for those reads (they're
      // already family-scoped SELECT policies).
      final roles = await _fetchRoles(client);

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
      debugPrint('⚠️ AURA NestJS fetch failed: $e — falling back to direct Supabase read');
      // ── Fallback: direct Supabase read ───────────────────────────
      // If the NestJS API is unreachable (CORS on web, network error,
      // server down), fall back to reading FamilyAura directly from
      // Supabase. RLS policies on FamilyAura already restrict reads
      // to family members, so this is safe.
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

        final model = _modelFromSupabaseRow(auraRow);
        final roles = await _fetchRoles(client);

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
      } catch (e2) {
        debugPrint('⚠️ AURA Supabase fallback also failed: $e2');
        state = state.copyWith(
          isLoading: false,
          error: state.aura == null ? 'Could not load AURA' : null,
        );
      }
    }
  }

  /// Fetch a JSON object from the NestJS AURA API.
  ///
  /// Returns `null` on 404 (AURA not yet computed). Throws on other
  /// non-2xx statuses or network errors so the caller can fall back
  /// to the Drift cache.
  ///
  /// Uses Dio (not dart:io HttpClient) so it works on Flutter Web —
  /// dart:io's HttpClient throws "Unsupported operation: Platform._version"
  /// on web builds.
  Future<Map<String, dynamic>?> _fetchViaNestJs({
    required String path,
    required String accessToken,
  }) async {
    // The dioProvider's _AuthInterceptor already injects the JWT, but
    // we pass it explicitly too so this works even if the interceptor
    // is bypassed (defensive).
    final response = await _dio.get(
      path,
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );

    // Dio's validateStatus above only accepts 2xx, so a 404 throws
    // a DioException. Catch it here and return null — 404 is the
    // expected "AURA not yet computed" signal.
    // (This catch is in the caller — see load().)
    final decoded = response.data;
    // The NestJS ResponseEnvelopeInterceptor wraps responses in
    // { success, data, timestamp }. Unwrap if present.
    if (decoded is Map<String, dynamic> &&
        decoded.containsKey('success') &&
        decoded.containsKey('data')) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      if (data == null) return null;
    }
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Unexpected AURA API response shape: $decoded');
  }

  /// Load only the historical snapshots (for the timeline widget).
  ///
  /// Bug 10 fix: set `isLoading: true` while the fetch is in flight
  /// (so the UI can show a spinner) and `clearError: true` on success
  /// (so a stale error from an earlier `load()` doesn't persist).
  Future<void> loadHistory() async {
    final client = _client;
    if (client == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final history = await _fetchHistory(client);
      state = state.copyWith(
        history: history,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      debugPrint('⚠️ AURA history fetch failed: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Trigger a backend AURA recompute. Returns 202 immediately; the
  /// caller should poll [load] until the new AURA appears.
  ///
  /// Uses Dio (not dart:io HttpClient) so it works on Flutter Web —
  /// dart:io's HttpClient throws "Unsupported operation: Platform._version"
  /// on web builds. The dioProvider's _AuthInterceptor already injects
  /// the JWT, but we pass it explicitly too (defensive).
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
      final response = await _dio.post(
        '/api/aura/$familyId/recompute',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
          },
          // 202 is the success code — accept it as valid.
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );

      // 202 Accepted = recompute started successfully.
      if (response.statusCode == 202) {
        state = state.copyWith(isRecomputing: false);
        return true;
      }

      // Any other 2xx is unexpected but not an error per se.
      state = state.copyWith(isRecomputing: false);
      return true;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final body = e.response?.data?.toString() ?? e.message ?? '';
      debugPrint('⚠️ AURA recompute failed: $statusCode $body');
      state = state.copyWith(
        isRecomputing: false,
        error: 'Recompute failed ($statusCode): $body',
      );
      return false;
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

  /// Build an [AuraModel] from a raw Supabase FamilyAura row.
  /// Used by the fallback path when the NestJS API is unreachable.
  AuraModel _modelFromSupabaseRow(Map<String, dynamic> row) {
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
