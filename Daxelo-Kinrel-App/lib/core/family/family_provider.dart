import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../networking/dio_client.dart';
import '../services/supabase_service.dart';
import '../services/analytics_service.dart';
import '../services/graph_layout_service.dart';
import '../../graph/interaction/relationship_validation.dart' show validateRelationship;
import '../database/isar_database.dart';
import '../database/app_database.dart';
import '../database/repositories/offline_family_repository.dart';
import '../database/sync/cache_invalidation.dart';
import '../../features/profile/data/profile_provider.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show FamilyGraphNotifier, familyGraphProvider;

// ── Table name constants (matching Prisma schema PascalCase) ────────
const _kFamilyTable = 'Family';
const _kPersonTable = 'Person';
const _kRelationshipTable = 'Relationship';
const _kFamilyMemberTable = 'FamilyMember';

/// Generate a CUID-like ID for database inserts.
/// Since we use Supabase client directly (not Prisma), we must generate IDs ourselves.
/// Uses Random to avoid duplicate IDs when generating in a tight loop
/// (DateTime.now().microsecond doesn't change between iterations).
String _generateId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random();
  final rand = List.generate(
    16,
    (_) => random.nextInt(36),
  ).map((v) => v.toRadixString(36)).join();
  return 'c$timestamp$rand'.substring(0, 25);
}

/// Extract a human-readable error message from a DioException.
String _extractDioErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    // NestJS often returns { message: "..." } or { error: "..." }
    final msg = data['message'];
    if (msg is String) return msg;
    if (msg is List && msg.isNotEmpty) return msg.first.toString();
    final err = data['error'];
    if (err is String) return err;
  }
  if (data is String && data.isNotEmpty) return data;
  // Fall back to DioException type-based messages
  return switch (e.type) {
    DioExceptionType.connectionTimeout => 'Connection timed out. Please try again.',
    DioExceptionType.sendTimeout => 'Request timed out. Please try again.',
    DioExceptionType.receiveTimeout => 'Server took too long to respond. Please try again.',
    DioExceptionType.connectionError => 'No internet connection. Please try again.',
    _ => 'Something went wrong. Please try again.',
  };
}

// ── Data Models ────────────────────────────────────────────────

class Family {
  const Family({
    required this.id,
    required this.name,
    this.description,
    this.primaryLanguage,
    this.gotra,
    this.originVillage,
    this.createdBy,
    this.createdAt,
    this.familyCode,
    this.avatarUrl,
    this.region,
    this.privacyMode,
    this.isOnboarded = false,
    this.anchorPersonId,
    this.memberCount = 0,
    this.generationCount = 1,
    this.lastActivityAt,
    this.username,
    this.kinFamilyId,
    this.deletedAt,
  });

  factory Family.fromJson(Map<String, dynamic> json) {
    return Family(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unnamed Family',
      description: json['description'] as String?,
      primaryLanguage: json['primaryLanguage'] as String?,
      gotra: json['gotra'] as String?,
      originVillage: json['originVillage'] as String?,
      createdBy: json['createdBy'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      familyCode: json['familyCode'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      region: json['region'] as String?,
      privacyMode: json['privacyMode'] as String?,
      isOnboarded: json['isOnboarded'] as bool? ?? false,
      anchorPersonId: json['anchorPersonId'] as String?,
      memberCount: json['memberCount'] as int? ?? 0,
      generationCount: json['generationCount'] as int? ?? 1,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
      username: json['username'] as String?,
      kinFamilyId: json['kinFamilyId'] as String?,
      deletedAt: json['deletedAt'] != null
          ? DateTime.tryParse(json['deletedAt'].toString())
          : null,
    );
  }

  final String id;
  final String name;
  final String? description;
  final String? primaryLanguage;
  final String? gotra;
  final String? originVillage;
  final String? createdBy;
  final DateTime? createdAt;

  // Graph-First Redesign Fields
  final String? familyCode;
  final String? avatarUrl;
  final String? region;
  final String? privacyMode;
  final bool isOnboarded;
  final String? anchorPersonId;
  final int memberCount;
  final int generationCount;
  final DateTime? lastActivityAt;

  // Username system
  final String? username;

  // KIN Family ID system
  final String? kinFamilyId;

  // Soft-delete support
  final DateTime? deletedAt;

  /// Display-friendly username with @ prefix
  String get displayUsername => username != null ? '@$username' : '';

  /// Convert to JSON map for serialization/caching.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'primaryLanguage': primaryLanguage,
        'gotra': gotra,
        'originVillage': originVillage,
        'createdBy': createdBy,
        'createdAt': createdAt?.toIso8601String(),
        'familyCode': familyCode,
        'avatarUrl': avatarUrl,
        'region': region,
        'privacyMode': privacyMode,
        'isOnboarded': isOnboarded,
        'anchorPersonId': anchorPersonId,
        'memberCount': memberCount,
        'generationCount': generationCount,
        'lastActivityAt': lastActivityAt?.toIso8601String(),
        'username': username,
        'kinFamilyId': kinFamilyId,
        'deletedAt': deletedAt?.toIso8601String(),
      };
}

class Person {
  const Person({
    required this.id,
    required this.familyId,
    required this.name,
    this.gender,
    this.dateOfBirth,
    this.city,
    this.gotra,
    this.isDeceased = false,
    this.deletedAt,
    this.createdAt,
    this.birthYear,
    this.occupation,
    this.privacyLevel,
    this.notes,
    this.sideOfFamily,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.username,
    this.anniversaryDate,
    this.linkedUserId,
  });

  /// The Kinrel user ID linked to this Person, if any.
  /// Non-null means this Person was added via "Find on Kinrel" or has
  /// been claimed by a real Kinrel user. Null means this is a manually-
  /// added placeholder node that only exists in the family tree.
  final String? linkedUserId;

  /// Whether this Person is linked to a real Kinrel user account.
  bool get isLinkedToKinrelUser => linkedUserId != null && linkedUserId!.isNotEmpty;

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unknown',
      gender: json['gender'] as String?,
      linkedUserId: json['linkedUserId']?.toString(),
      dateOfBirth: json['dateOfBirth']?.toString(),
      city: json['city'] as String?,
      gotra: json['gotra'] as String?,
      isDeceased: json['isDeceased'] as bool? ?? false,
      deletedAt: json['deletedAt']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      birthYear: json['birthYear'] as int?,
      occupation: json['occupation'] as String?,
      privacyLevel: json['privacyLevel'] as String?,
      notes: json['notes'] as String?,
      sideOfFamily: json['sideOfFamily'] as String?,
      generationIndex: json['generationIndex'] as int? ?? 0,
      isAnchor: json['isAnchor'] as bool? ?? false,
      photoUrl: json['photoUrl'] as String?,
      username: json['username'] as String?,
      anniversaryDate: json['anniversaryDate']?.toString(),
    );
  }

  final String id;
  final String familyId;
  final String name;
  final String? gender;
  final String? dateOfBirth;
  final String? city;
  final String? gotra;
  final bool isDeceased;
  final String? deletedAt;
  final DateTime? createdAt;

  // Graph-First Redesign Fields
  final int? birthYear;
  final String? occupation;
  final String? privacyLevel;
  final String? notes;
  final String? sideOfFamily;
  final int generationIndex;
  final bool isAnchor;
  final String? photoUrl;

  // Username system
  final String? username;

  /// Anniversary date for couples (stored as ISO date string).
  final String? anniversaryDate;

  /// Display-friendly username with @ prefix
  String get displayUsername => username != null ? '@$username' : '';

  /// Convert to JSON map for serialization/caching.
  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'name': name,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'city': city,
        'gotra': gotra,
        'isDeceased': isDeceased,
        'deletedAt': deletedAt,
        'createdAt': createdAt?.toIso8601String(),
        'birthYear': birthYear,
        'occupation': occupation,
        'privacyLevel': privacyLevel,
        'notes': notes,
        'sideOfFamily': sideOfFamily,
        'generationIndex': generationIndex,
        'isAnchor': isAnchor,
        'photoUrl': photoUrl,
        'username': username,
        'anniversaryDate': anniversaryDate,
        if (linkedUserId != null) 'linkedUserId': linkedUserId,
      };

  /// Convert to GraphPerson for graph visualization.
  /// Uses the first relationship as the relationship label.
  GraphPerson toGraphPerson() {
    return GraphPerson(
      id: id,
      name: name,
      gender: gender,
      generationIndex: generationIndex,
      isAnchor: isAnchor,
      photoUrl: photoUrl,
      isDeceased: isDeceased,
      relationship:
          null, // Relationship is on the Relationship table, not Person
      deletedAt: deletedAt,
    );
  }
}

class FamilyRelationship {
  const FamilyRelationship({
    required this.id,
    required this.familyId,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.direction = 'from',
    this.isActive = true,
    this.label,
    this.createdAt,
  });

  factory FamilyRelationship.fromJson(Map<String, dynamic> json) {
    return FamilyRelationship(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId']?.toString() ?? '',
      fromPersonId: json['fromPersonId']?.toString() ?? '',
      toPersonId: json['toPersonId']?.toString() ?? '',
      relationshipKey: json['relationshipKey'] as String? ?? '',
      direction: json['direction'] as String? ?? 'from',
      isActive: json['isActive'] as bool? ?? true,
      label: json['label'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  final String id;
  final String familyId;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;
  final String direction;
  final bool isActive;
  final String? label;
  final DateTime? createdAt;

  ({String fromId, String toId, String type}) toGraphEdge() {
    return (fromId: fromPersonId, toId: toPersonId, type: relationshipKey);
  }

  /// Convert to JSON map for serialization/caching.
  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'fromPersonId': fromPersonId,
        'toPersonId': toPersonId,
        'relationshipKey': relationshipKey,
        'direction': direction,
        'isActive': isActive,
        'label': label,
        'createdAt': createdAt?.toIso8601String(),
      };
}

class FamilyDetail {
  const FamilyDetail({
    required this.family,
    required this.members,
    required this.relationships,
  });

  final Family family;
  final List<Person> members;
  final List<FamilyRelationship> relationships;
}

/// Lightweight user profile embedded in FamilyMembership from the API.
class MemberUserProfile {
  const MemberUserProfile({
    required this.id,
    this.name,
    this.email,
    this.avatarUrl,
    this.username,
  });

  factory MemberUserProfile.fromJson(Map<String, dynamic> json) {
    return MemberUserProfile(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      username: json['username'] as String?,
    );
  }

  final String id;
  final String? name;
  final String? email;
  final String? avatarUrl;
  final String? username;

  /// Display name: prefers name, then username, then email prefix, then 'Unknown'.
  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (username != null && username!.isNotEmpty) return '@$username';
    if (email != null && email!.isNotEmpty) return email!.split('@').first;
    return 'Unknown';
  }

  /// Initials for avatar (up to 2 characters).
  String get initials {
    final dn = displayName;
    if (dn == 'Unknown') return '?';
    final parts = dn.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return dn[0].toUpperCase();
  }
}

/// Represents a family membership (FamilyMember row) with user ID, role, and optional user profile.
class FamilyMembership {
  const FamilyMembership({
    required this.id,
    required this.familyId,
    required this.userId,
    this.role = 'member',
    this.joinedAt,
    this.user,
  });

  factory FamilyMembership.fromJson(Map<String, dynamic> json) {
    return FamilyMembership(
      id: json['id']?.toString() ?? '',
      familyId: json['familyId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      role: json['role'] as String? ?? 'member',
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString())
          : null,
      user: json['user'] != null
          ? MemberUserProfile.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  final String id;
  final String familyId;
  final String userId;
  final String role;
  final DateTime? joinedAt;

  /// User profile from the API (may be null if fetched from Supabase fallback).
  final MemberUserProfile? user;

  /// Display-friendly role label (capitalized).
  String get displayRole {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'owner':
        return 'Admin';
      case 'editor':
        return 'Editor';
      case 'viewer':
        return 'Viewer';
      case 'member':
      default:
        return 'Member';
    }
  }

  /// Whether this membership has admin-level privileges.
  bool get isAdmin => role.toLowerCase() == 'admin' || role.toLowerCase() == 'owner';
}

/// Archived family with days-remaining info from the NestJS backend.
class ArchivedFamily {
  const ArchivedFamily({
    required this.family,
    required this.daysRemaining,
  });

  factory ArchivedFamily.fromJson(Map<String, dynamic> json) {
    // The NestJS API wraps the family in a 'family' key:
    //   { family: { id, name, ... }, daysRemaining: 25, archivedAt: "..." }
    // The Drift cache and Supabase fallback return flat family maps:
    //   { id, name, deletedAt: "...", ... }
    // Detect which shape we have by checking for the 'family' key.
    final bool isApiShape = json.containsKey('family') && json['family'] is Map;

    final familyData = isApiShape
        ? json['family'] as Map<String, dynamic>
        : json;

    final int daysRemaining;
    if (isApiShape) {
      daysRemaining = json['daysRemaining'] as int? ?? 30;
    } else {
      // Calculate from deletedAt field (Supabase / Drift flat shape)
      final deletedAtStr = json['deletedAt'] as String?;
      if (deletedAtStr != null) {
        final deletedAt = DateTime.tryParse(deletedAtStr);
        if (deletedAt != null) {
          final permanentDeleteAt = deletedAt.add(const Duration(days: 30));
          final diff = permanentDeleteAt.difference(DateTime.now()).inDays;
          daysRemaining = diff > 0 ? diff : 0;
        } else {
          daysRemaining = 30;
        }
      } else {
        daysRemaining = 30;
      }
    }

    return ArchivedFamily(
      family: Family.fromJson(familyData),
      daysRemaining: daysRemaining,
    );
  }

  final Family family;
  final int daysRemaining;

  /// The date the family was archived.
  DateTime? get archivedAt => family.deletedAt;
}

// ── Archived Families Provider ─────────────────────────────────────

/// Fetches archived (soft-deleted) families for the current user.
///
/// Tracks family IDs that are currently being permanently deleted.
/// Used by the UI to show per-card loading spinners instead of a
/// global loading state that affects all archived family cards.
final deletingFamilyIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Tracks family IDs that are currently being restored from archive.
/// Same per-card loading pattern as deletingFamilyIdsProvider.
final restoringFamilyIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Tracks family IDs that are pending soft-delete (optimistic delete in-flight).
/// This acts as a client-side guard: even if Supabase returns a family that
/// hasn't been soft-deleted yet (race condition before NestJS transaction
/// commits), familyListProvider will filter it out so it doesn't reappear.
final pendingDeleteFamilyIdsProvider = StateProvider<Set<String>>((ref) => {});

/// With offline-first: Returns cached data from Drift immediately if
/// available, then refreshes from Supabase/NestJS in the background.
/// This ensures the archived families list appears within 100ms on
/// app launch, even when the network is slow or unavailable.
final archivedFamiliesProvider =
    FutureProvider<List<ArchivedFamily>>((ref) async {
  // ── Step 1: Try Drift cache first (instant, no network) ──────
  if (IsarDatabase.isInitialized) {
    try {
      final db = ref.read(isarProvider);
      final cachedFamilies = await db.getAllFamilies();
      // Filter for soft-deleted families only (deletedAt != null)
      final archived = cachedFamilies.where((row) {
        if (row.data.isEmpty) return false;
        try {
          final dataMap = json.decode(row.data) as Map<String, dynamic>;
          return dataMap['deletedAt'] != null;
        } catch (_) {
          return false;
        }
      }).toList();

      if (archived.isNotEmpty) {
        final now = DateTime.now();
        final result = archived.map((row) {
          final family = Family.fromJson(
              json.decode(row.data) as Map<String, dynamic>);
          final archivedAt = family.deletedAt ?? now;
          final permanentDeleteAt = archivedAt.add(const Duration(days: 30));
          final daysRemaining = permanentDeleteAt.difference(now).inDays;
          return ArchivedFamily(
            family: family,
            daysRemaining: daysRemaining > 0 ? daysRemaining : 0,
          );
        }).toList();

        // Return cached data immediately; schedule background refresh
        _scheduleArchivedRefresh(ref);
        return result;
      }
    } catch (e) {
      debugPrint('⚠️ archivedFamiliesProvider Drift cache read error: $e');
    }
  }

  // ── Step 2: Query Supabase directly (primary path) ──────────
  // The NestJS backend rejects Supabase JWTs (ES256/HS256 mismatch).
  // Supabase is now the primary path, NestJS is the fallback.
  try {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];

    // v2.2: Real auth only — guard against no session.
    if (client.auth.currentSession == null) return [];

    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    // Approach 1: Get family IDs where user is a member
    final familyIds = <String>{};
    try {
      final memberships = await client
          .from(_kFamilyMemberTable)
          .select('familyId')
          .eq('userId', userId);
      for (final row in (memberships as List)) {
        familyIds.add(row['familyId'] as String);
      }
    } catch (e) {
      debugPrint('⚠️ archivedFamiliesProvider: FamilyMember lookup failed: $e');
    }

    // Approach 2: Also find families where user is the creator (fallback)
    try {
      final createdFamilies = await client
          .from(_kFamilyTable)
          .select('id')
          .eq('createdBy', userId);
      for (final row in (createdFamilies as List)) {
        familyIds.add(row['id'] as String);
      }
    } catch (e) {
      debugPrint('⚠️ archivedFamiliesProvider: createdBy lookup failed: $e');
    }

    if (familyIds.isEmpty) return [];

    // Get archived families (deletedAt is not null)
    final families = await client
        .from(_kFamilyTable)
        .select('*')
        .inFilter('id', familyIds.toList())
        .filter('deletedAt', 'not.is', 'null');

    final now = DateTime.now();
    final result = families.map((json) {
      final family = Family.fromJson(json);
      final archivedAt = family.deletedAt ?? now;
      final permanentDeleteAt = archivedAt.add(const Duration(days: 30));
      final daysRemaining = permanentDeleteAt.difference(now).inDays;
      return ArchivedFamily(
        family: family,
        daysRemaining: daysRemaining > 0 ? daysRemaining : 0,
      );
    }).toList();

    // Cache the result in Drift for future fast loads
    _cacheArchivedFamilies(result);
    return result;
  } catch (e) {
    debugPrint('⚠️ archivedFamiliesProvider Supabase fallback error: $e');
    return [];
  }
});

/// Schedule a background refresh for archived families.
/// Invalidates the provider after a delay, causing a re-fetch from
/// the server. The UI already has cached data, so the refresh is
/// invisible to the user.
void _scheduleArchivedRefresh(Ref ref) {
  Future.delayed(const Duration(seconds: 2), () {
    try {
      ref.invalidate(archivedFamiliesProvider);
    } catch (_) {}
  });
}

/// Cache archived families to Drift for instant loading next time.
void _cacheArchivedFamilies(List<ArchivedFamily> archivedFamilies) {
  if (!IsarDatabase.isInitialized) return;
  try {
    final db = IsarDatabase.instance;
    for (final archived in archivedFamilies) {
      final family = archived.family;
      db.upsertFamily(CachedFamiliesCompanion(
        id: Value(family.id),
        name: Value(family.name),
        data: Value(json.encode(family.toJson())),
        kinFamilyId: Value(family.kinFamilyId),
        username: Value(family.username),
        cachedAt: Value(DateTime.now()),
      )).catchError((e) {
        debugPrint('⚠️ Could not cache archived family: $e');
      });
    }
  } catch (e) {
    debugPrint('⚠️ Could not cache archived families: $e');
  }
}

// ── Providers ──────────────────────────────────────────────────

/// Fetches all families the current user has access to.
/// Uses FamilyMember join table to find families, with createdBy fallback.
///
/// With offline-first: Returns cached data immediately if available,
/// then refreshes from the NestJS API in the background. Falls back to
/// direct Supabase query if the NestJS API is unreachable.
///
/// PERF: This provider is cache-first — it returns cached data from
/// Drift/Isar immediately (if available) and triggers a background
/// network refresh. This reduces cold-start latency from 3-6 seconds
/// (3 sequential Supabase queries) to <100ms on returning users.
///
/// The network fetch uses a single Supabase RPC (`get_user_families`)
/// instead of 3 sequential queries, further reducing latency by 2-4
/// seconds on mobile networks.
final familyListProvider = FutureProvider<List<Family>>((ref) async {
  // FIXED: Watch pending deletes so families being optimistically deleted
  // are filtered out even if Supabase returns stale data before the
  // NestJS soft-delete transaction commits (Bug 3 race condition).
  final pendingDeletes = ref.watch(pendingDeleteFamilyIdsProvider);

  // BUG FIX (families-not-loading-after-login): Watch the current user so
  // the provider auto-rebuilds when auth state changes.
  ref.watch(currentUserProvider);

  final isReady = ref.watch(isSupabaseReadyProvider);

  // ── STEP 1: ALWAYS try cache first (even when Supabase is ready) ──
  // This is the key performance optimization: returning users see their
  // families instantly from the Drift cache, then a background network
  // refresh updates the data if needed.
  if (IsarDatabase.isInitialized) {
    try {
      final repo = ref.read(offlineFamilyRepositoryProvider);
      final cached = await repo.getFamilies();
      final filtered = cached
          .where(
              (f) => f.deletedAt == null && !pendingDeletes.contains(f.id))
          .toList();
      if (filtered.isNotEmpty) {
        // Return cache immediately; schedule background network refresh
        // so the user sees fresh data within a few seconds.
        if (isReady) {
          Future.microtask(() => _refreshFamiliesInBackground(ref));
        }
        return filtered;
      }
    } catch (_) {}
  }

  // ── STEP 2: No cache — fetch from network (first install or cache cleared) ──
  if (!isReady) return [];

  return _fetchFamiliesFromNetwork(ref, pendingDeletes);
});

/// Fetches families from Supabase using a single RPC call.
///
/// Uses `get_user_families(p_user_id)` — a SECURITY DEFINER function
/// that returns all non-deleted families where the user is a member or
/// creator. This replaces 3 sequential Supabase queries (FamilyMember
/// lookup + createdBy lookup + Family.inFilter) with 1 round-trip,
/// reducing latency by 2-4 seconds on mobile networks.
///
/// Falls back to the 3-query approach if the RPC is not available.
Future<List<Family>> _fetchFamiliesFromNetwork(
  Ref ref,
  Set<String> pendingDeletes,
) async {
  try {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];

    // v2.2: Real auth only — guard against no session.
    if (client.auth.currentSession == null) return [];
    final userId = client.auth.currentUser!.id;

    // ── Try the single-RPC call first (fast path) ──
    try {
      final response = await client
          .rpc('get_user_families', params: {'p_user_id': userId})
          .timeout(const Duration(seconds: 10));

      final list = response as List;
      List<Family> result;
      if (list.length > 20) {
        result = await compute(_parseFamilyList, list);
      } else {
        result = list
            .map((json) => Family.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      // Client-side guard — filter out pending-delete families
      if (pendingDeletes.isNotEmpty) {
        result = result.where((f) => !pendingDeletes.contains(f.id)).toList();
      }

      // Save to Isar cache for next cold start
      if (result.isNotEmpty && IsarDatabase.isInitialized) {
        try {
          final repo = ref.read(offlineFamilyRepositoryProvider);
          await repo.saveFamilies(result);
        } catch (e) {
          debugPrint('⚠️ Could not save families to cache: $e');
        }
      }

      return result;
    } catch (e) {
      // RPC failed (e.g., function not deployed) — fall back to 3-query approach
      debugPrint('⚠️ get_user_families RPC failed, falling back to 3 queries: $e');
    }

    // ── Fallback: 3 sequential queries (original approach) ──
    final familyIds = <String>{};

    // 1a. Via FamilyMember
    try {
      final memberRows = await client
          .from('FamilyMember')
          .select('familyId')
          .eq('userId', userId)
          .timeout(const Duration(seconds: 10));
      for (final row in (memberRows as List)) {
        familyIds.add(row['familyId'] as String);
      }
    } catch (e) {
      debugPrint('⚠️ FamilyMember lookup failed, using createdBy fallback: $e');
    }

    // 1b. Via createdBy (fallback for missing FamilyMember entries)
    try {
      final createdFamilies = await client
          .from(_kFamilyTable)
          .select('id')
          .eq('createdBy', userId)
          .timeout(const Duration(seconds: 10));
      for (final row in (createdFamilies as List)) {
        familyIds.add(row['id'] as String);
      }
    } catch (e) {
      debugPrint('⚠️ createdBy lookup failed: $e');
    }

    if (familyIds.isEmpty) return [];

    // 2. Fetch all families by IDs (deduplicated) — includes 'createdBy'
    final response = await client
        .from(_kFamilyTable)
        .select()
        .inFilter('id', familyIds.toList())
        .filter('deletedAt', 'is', null)
        .order('createdAt', ascending: false)
        .timeout(const Duration(seconds: 15));

    final list = response as List;
    List<Family> result;
    if (list.length > 20) {
      result = await compute(_parseFamilyList, list);
    } else {
      result = list
          .map((json) => Family.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    // Client-side guard — filter out pending-delete families
    if (pendingDeletes.isNotEmpty) {
      result = result.where((f) => !pendingDeletes.contains(f.id)).toList();
    }

    // Save to Isar cache for next cold start
    if (result.isNotEmpty && IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        await repo.saveFamilies(result);
      } catch (e) {
        debugPrint('⚠️ Could not save families to cache: $e');
      }
    }

    return result;
  } catch (e) {
    debugPrint('⚠️ familyListProvider error: $e');

    // On network error, try Isar cache as last resort (graceful degradation)
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilies();
        final filtered = cached
            .where(
                (f) => f.deletedAt == null && !pendingDeletes.contains(f.id))
            .toList();
        if (filtered.isNotEmpty) return filtered;
      } catch (_) {}
    }

    // FIX (BUG-empty-list): If offline cache is also empty, rethrow the
    // error instead of returning []. This ensures the UI's .when() handler
    // shows the actual error message instead of a misleading empty list.
    rethrow;
  }
}

/// Refreshes families in the background after returning cached data.
///
/// Called by familyListProvider when it returns cached data — fetches
/// fresh data from the network and updates the cache. Does NOT call
/// ref.invalidateSelf() to avoid an infinite loop (cache → refresh →
/// cache → refresh...). Instead, the fresh data is saved to the Drift
/// cache silently; the user will see it on the next app launch or
/// when another provider invalidates familyListProvider.
Future<void> _refreshFamiliesInBackground(Ref ref) async {
  // Short delay so the UI renders the cached data first
  await Future.delayed(const Duration(milliseconds: 300));
  try {
    final pendingDeletes = ref.read(pendingDeleteFamilyIdsProvider);
    // Fetch fresh data and save to cache (does NOT invalidate the provider)
    await _fetchFamiliesFromNetwork(ref, pendingDeletes);
    debugPrint('✅ Background family refresh complete — cache updated');
  } catch (e) {
    debugPrint('⚠️ Background family refresh failed: $e');
  }
}

/// Fetches a single family with its members.
///
/// Composes data from familyListProvider (already fetched) + members +
/// relationships, avoiding a redundant API call that caused cascading
/// rebuild loops when familyMembersProvider or familyRelationshipsProvider
/// changed state (loading→data) and triggered a re-fetch of the family.
///
/// If the family is not found in the list (e.g., list hasn't loaded yet
/// or user navigated directly via deep link), falls back to a direct
/// Supabase query for that specific family ID.
final familyDetailProvider = FutureProvider.family<FamilyDetail?, String>((
  ref,
  familyId,
) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return null;

  try {
    final client = ref.read(supabaseProvider);
    if (client == null) return null;
    // v2.2: Real auth only — guard against no session.
    if (client.auth.currentSession == null) return null;

    // Try to get family from familyListProvider first (fast path).
    // Use ref.read to prevent cascading rebuilds — familyDetailProvider
    // only needs the current family data, not a rebuild every time the
    // family list changes.
    final familiesAsync = ref.read(familyListProvider);
    Family? family = familiesAsync.valueOrNull?.firstWhere(
      (f) => f.id == familyId,
    );

    // Fallback: if family not in the list (list still loading, or user
    // navigated directly via deep link / notification), fetch it directly.
    if (family == null) {
      debugPrint('🔍 familyDetailProvider: family not in list, fetching directly for ID=$familyId');
      try {
        final response = await client
            .from(_kFamilyTable)
            .select()
            .eq('id', familyId)
            .maybeSingle();
        if (response != null) {
          family = Family.fromJson(response);
        }
      } catch (e) {
        debugPrint('⚠️ familyDetailProvider direct fetch failed: $e');
      }
    }

    if (family == null) return null;

    // Await the future directly so members are always loaded before returning.
    // Using ref.read(...).valueOrNull causes a race condition: it reads the
    // provider before it finishes loading, gets null, and returns empty members.
    // The graph then shows "No Members Yet" even when members exist.
    final members = await ref
        .read(familyMembersProvider(familyId).future)
        .catchError((_) => <Person>[]);

    final relationships = await ref
        .read(familyRelationshipsProvider(familyId).future)
        .catchError((_) => <FamilyRelationship>[]);

    return FamilyDetail(
      family: family,
      members: members,
      relationships: relationships,
    );
  } catch (e) {
    debugPrint('⚠️ familyDetailProvider error: $e');
    return null;
  }
});

/// Fetches persons in a family
///
/// With offline-first: Returns cached data immediately if available,
/// then refreshes from Supabase in the background.
final familyMembersProvider = FutureProvider.family<List<Person>, String>((
  ref,
  familyId,
) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) {
    // Try Isar cache for offline access
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilyMembers(familyId);
        if (cached.isNotEmpty) return cached;
      } catch (_) {}
    }
    return [];
  }

  try {
    // v12 FIX: Query Supabase FIRST, not the offline cache.
    // Same bug as familyRelationshipsProvider — the offline cache
    // could return stale/empty data without throwing, preventing
    // the provider from ever querying Supabase for fresh data.
    final client = ref.read(supabaseProvider);
    if (client == null) return [];

    // Guard against no valid session — RLS will deny queries
    if (client.auth.currentSession == null) return [];

    final response = await client
        .from(_kPersonTable)
        .select()
        .eq('familyId', familyId)
        .filter('deletedAt', 'is', null)
        .order('createdAt', ascending: true)
        .timeout(const Duration(seconds: 15));

    final list = response as List;
    final persons = list.length > 20
        ? await compute(_parsePersonList, list)
        : list
            .map((json) => Person.fromJson(json as Map<String, dynamic>))
            .toList();

    // v12: Update offline cache with fresh data (best-effort)
    if (persons.isNotEmpty && IsarDatabase.isInitialized) {
      try {
        await CacheInvalidation.invalidateFamily(familyId);
      } catch (_) {}
    }

    return persons;
  } catch (e) {
    debugPrint('⚠️ familyMembersProvider error: $e');

    // On network error, try Isar cache
    if (IsarDatabase.isInitialized) {
      try {
        final repo = ref.read(offlineFamilyRepositoryProvider);
        final cached = await repo.getFamilyMembers(familyId);
        if (cached.isNotEmpty) return cached;
      } catch (_) {}
    }

    return [];
  }
});

/// Fetches relationships in a family
///
/// With offline-first: Returns cached data immediately if available,
/// then refreshes from Supabase in the background.
final familyRelationshipsProvider =
    FutureProvider.family<List<FamilyRelationship>, String>((
      ref,
      familyId,
    ) async {
      final isReady = ref.watch(isSupabaseReadyProvider);
      if (!isReady) {
        // Try Isar cache for offline access
        if (IsarDatabase.isInitialized) {
          try {
            final repo = ref.read(offlineFamilyRepositoryProvider);
            final cached = await repo.getFamilyRelationships(familyId);
            if (cached.isNotEmpty) return cached;
          } catch (_) {}
        }
        return [];
      }

      // v12 FIX: Query Supabase FIRST, not the offline cache.
      // The previous code tried the offline Isar cache first and only
      // fell back to Supabase if the cache threw an exception. But if
      // the cache returned an empty/stale list (no exception), the
      // provider returned that stale data — never querying Supabase.
      // This meant newly created relationships never appeared.
      try {
        final client = ref.read(supabaseProvider);
        if (client == null) return [];

        // Guard against no valid session — RLS will deny queries
        if (client.auth.currentSession == null) return [];

        final response = await client
            .from(_kRelationshipTable)
            .select()
            .eq('familyId', familyId)
            .eq('isActive', true)
            .order('createdAt', ascending: true)
            .timeout(const Duration(seconds: 15));

        final list = response as List;
        if (list.length > 20) {
          return compute(_parseRelationshipList, list);
        }
        final relationships = list
            .map(
              (json) =>
                  FamilyRelationship.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        // v12: If Supabase returned data, update the offline cache
        // (best-effort — the cache will also be updated by background sync)
        if (relationships.isNotEmpty && IsarDatabase.isInitialized) {
          try {
            // Cache invalidation triggers a background refresh of the
            // offline cache, so we don't need to manually upsert here.
            await CacheInvalidation.invalidateFamily(familyId);
          } catch (_) {}
        }

        return relationships;
      } catch (e) {
        debugPrint('⚠️ familyRelationshipsProvider error: $e');

        // On network error, try Isar cache
        if (IsarDatabase.isInitialized) {
          try {
            final repo = ref.read(offlineFamilyRepositoryProvider);
            final cached = await repo.getFamilyRelationships(familyId);
            if (cached.isNotEmpty) return cached;
          } catch (_) {}
        }

        return [];
      }
    });

/// Family member count provider
/// Uses ref.read instead of ref.watch to prevent cascading rebuilds when
/// familyMembersProvider is invalidated by socket events. With ref.watch,
/// every invalidation of familyMembersProvider(id) triggers a rebuild of
/// familyMemberCountProvider(id), which can cascade into UI rebuilds that
/// re-read familyMembersProvider, creating an infinite loop on the main thread.
/// With ref.read, the count only updates when this provider's dependencies
/// (familyDetailProvider or familyListProvider) rebuild, not on every
/// individual member invalidation from socket events.
final familyMemberCountProvider = Provider.family<int, String>((ref, familyId) {
  // Watch familyMembersProvider to rebuild when members change
  final membersAsync = ref.watch(familyMembersProvider(familyId));
  return membersAsync.valueOrNull?.length ?? 0;
});

/// Fetches FamilyMember rows for a given family — used to determine user roles.
/// Returns a list of [FamilyMembership] objects with userId and role.
final familyMembershipsProvider =
    FutureProvider.family<List<FamilyMembership>, String>((ref, familyId) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return [];

  try {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];
    if (client.auth.currentSession == null) return [];

    // Supabase-first: query FamilyMember table directly (bypasses NestJS
    // which rejects Supabase JWTs due to ES256/HS256 mismatch).
    try {
      final response = await client
          .from(_kFamilyMemberTable)
          .select()
          .eq('familyId', familyId);

      return (response as List)
          .map((json) =>
              FamilyMembership.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ familyMembershipsProvider Supabase error: $e');
      // Last resort: try NestJS API (will likely 401)
      try {
        final dio = ref.read(dioProvider);
        final apiResponse = await dio.get('/api/families/$familyId/members');
        if (apiResponse.statusCode == 200 && apiResponse.data is List) {
          return (apiResponse.data as List)
              .map((json) =>
                  FamilyMembership.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
      return [];
    }
  } catch (e) {
    debugPrint('⚠️ familyMembershipsProvider error: $e');
    return [];
  }
});

/// Computes the current user's role in a given family.
/// Returns the role string (e.g. 'admin', 'editor', 'member', 'viewer')
/// or null if the user is not a member or data is unavailable.
final currentUserFamilyRoleProvider =
    Provider.family<String?, String>((ref, familyId) {
  final membershipsAsync = ref.watch(familyMembershipsProvider(familyId));
  final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
  if (currentUserId == null) return null;

  final memberships = membershipsAsync.valueOrNull;
  if (memberships == null) return null;

  final userMembership = memberships
      .where((m) => m.userId == currentUserId)
      .firstOrNull;
  return userMembership?.role;
});

// ── Computed Providers (Zero Rebuild Optimizations) ────────────────

/// Computed: family list count — widgets showing count don't rebuild on item update
final familyListCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(familyListProvider).whenData((list) => list.length);
});

/// Computed: whether family list is loading
final familyListIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(familyListProvider).isLoading;
});

/// Computed: whether family list has error
final familyListErrorProvider = Provider<Object?>((ref) {
  return ref.watch(familyListProvider).error;
});

/// Create family via NestJS API (atomically creates Family + FamilyMember)
Future<Family> createFamily({
  required WidgetRef ref,
  required String name,
  String? description,
  String? primaryLanguage,
  String? gotra,
  String? originVillage,
  String? region,
  String? privacyMode,
  String? username,
  String? photoUrl,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }
  // v2.2: Real auth only — no mock user fallback.
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    throw Exception('You must be signed in to create a family.');
  }

  // ════════════════════════════════════════════════════════════════════
  // v18 (2026-06-19): SUPABASE DIRECT INSERT — skip NestJS API entirely.
  // ════════════════════════════════════════════════════════════════════
  // The previous implementation used the NestJS API which:
  //   1. Cold-starts on Render free tier (30-60s timeout)
  //   2. Creates FamilyMember with role='admin' (should be 'owner')
  //   3. Bypasses the _fn_after_family_insert trigger (Prisma doesn't
  //      fire DB triggers)
  //
  // Direct Supabase insert:
  //   1. Is fast (<500ms)
  //   2. Fires the _fn_after_family_insert trigger which creates
  //      FamilyMember with role='owner' automatically
  //   3. The 'owner' role passes the Person INSERT RLS policy
  // ════════════════════════════════════════════════════════════════════

  // Generate a CUID-style ID for the Family
  final familyId = _generateId();

  // Build the insert payload
  final insertData = <String, dynamic>{
    'id': familyId,
    'name': name,
    'primaryLanguage': primaryLanguage ?? 'en',
    'privacyMode': privacyMode ?? 'private',
    'createdBy': userId,
    'memberCount': 0,
    'lastActivityAt': DateTime.now().toUtc().toIso8601String(),
  };
  if (description != null) insertData['description'] = description;
  if (gotra != null) insertData['gotra'] = gotra;
  if (originVillage != null) insertData['originVillage'] = originVillage;
  if (region != null) insertData['region'] = region;
  if (username != null) insertData['username'] = username;
  if (photoUrl != null) insertData['avatarUrl'] = photoUrl;

  // Step 1: INSERT the Family row
  // The _fn_after_family_insert trigger will automatically create a
  // FamilyMember row with role='owner' for the creator.
  late final Map<String, dynamic> response;
  try {
    response = await client
        .from('Family')
        .insert(insertData)
        .select()
        .single()
        .timeout(const Duration(seconds: 15));
  } on PostgrestException catch (e) {
    debugPrint('[createFamily] Supabase INSERT failed: ${e.message}');
    if (e.code == '42501') {
      throw Exception(
        'Permission denied. You must be signed in to create a family.',
      );
    } else if (e.code == '23505') {
      throw Exception('A family with this username already exists. Please try a different username.');
    }
    throw Exception('Could not create the family: ${e.message}');
  } on TimeoutException {
    throw Exception(
      'The database is taking too long to respond. Please check your '
      'internet connection and try again.',
    );
  } catch (e) {
    debugPrint('[createFamily] Unexpected error: $e');
    throw Exception('Could not create the family. Please try again. ($e)');
  }

  final family = Family.fromJson(response);
  debugPrint('[createFamily] Family created: ${family.id} (${family.name})');

  // Step 2: Verify the FamilyMember was created by the trigger
  // (best-effort — if it wasn't, create it manually)
  try {
    final memberCheck = await client
        .from('FamilyMember')
        .select('id')
        .eq('familyId', family.id)
        .eq('userId', userId)
        .timeout(const Duration(seconds: 5));

    if (memberCheck.isEmpty) {
      debugPrint('[createFamily] Trigger did not create FamilyMember — creating manually');
      await client
          .from('FamilyMember')
          .insert({
            'id': _generateId(),
            'familyId': family.id,
            'userId': userId,
            'role': 'owner',
            'joinedAt': DateTime.now().toUtc().toIso8601String(),
          })
          .timeout(const Duration(seconds: 5));
    }
  } catch (e) {
    debugPrint('[createFamily] FamilyMember verification/creation failed (non-fatal): $e');
  }

  ref.invalidate(familyListProvider);

  // Invalidate the Isar cache for the family list
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamilyList();
    } catch (_) {}
  }

  // Refresh profile stats
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  AnalyticsService.instance.logFamilyCreated();

  return family;
}

/// Create person via NestJS API (atomically creates Person + increments memberCount)
Future<Person> createPerson({
  required WidgetRef ref,
  required String familyId,
  required String name,
  String? gender,
  String? dateOfBirth,
  String? anniversaryDate,
  String? city,
  String? gotra,
  bool isDeceased = false,
  int? birthYear,
  bool isAnchor = false,
  /// Optional: the Supabase auth user ID to link this Person to.
  /// When set, the Person node is marked as "claimed" by this user —
  /// it shows in the Members section, doesn't show a "Pending" badge,
  /// and can be used for viewer-perspective kinship calculations.
  /// The create family flow passes this for the creator's own Person.
  String? linkedUserId,
  /// v94 (EDGE BUG FIX): When false, skips clearing the graph cache +
  /// invalidating familyGraphProvider. Used by createPersonOptimistic
  /// when a relationship will follow immediately — prevents a
  /// Person-only intermediate graph state. Default true.
  bool refreshGraph = true,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // v5 (2026-06-18): SUPABASE DIRECT INSERT IS NOW THE PRIMARY PATH.
  // ════════════════════════════════════════════════════════════════════
  // The previous implementation tried the NestJS API first (with a 10s
  // timeout) and fell back to Supabase on failure. BUT the Dio
  // RetryInterceptor retries receiveTimeout 3 more times (1s + 2s + 4s
  // delays), so the user waited 40+ seconds before the fallback kicked
  // in — leading to "Server took too long to respond" errors.
  //
  // The NestJS API is on Render free tier (cold starts 30-60s) and adds
  // no value for this operation — it just does INSERT Person + UPDATE
  // Family.memberCount in a transaction. We can do the same with two
  // Supabase calls (Person INSERT + Family UPDATE), which is fast and
  // reliable. The non-atomicity is acceptable: if the Family UPDATE
  // fails, the memberCount is just stale until the next time it's
  // refreshed (it's a denormalized cache field, not source of truth).
  //
  // The NestJS API is still used for other operations that genuinely
  // need server-side logic (auth, notifications, etc.) — just not for
  // simple Person creation.
  // ════════════════════════════════════════════════════════════════════

  // Guard against no valid session — RLS will deny the INSERT.
  if (client.auth.currentSession == null) {
    throw Exception(
      'You must be signed in to add a family member. Please restart the app.',
    );
  }

  // Build the insert payload.
  // CRITICAL: The Person table has a NOT NULL `id` column with NO
  // database default. Prisma normally generates CUIDs client-side;
  // when inserting via Supabase REST API (bypassing Prisma), we MUST
  // generate the ID ourselves. Without this, the INSERT fails with
  // "null value in column id violates not-null constraint".
  //
  // NOTE: Do NOT set `visibility` here — it has a CHECK constraint
  // that only allows 'public', 'family_only', 'private'. The NestJS
  // backend doesn't set it either (it sets `privacyLevel` instead,
  // which defaults to 'family' via Prisma). Leaving `visibility` NULL
  // is fine (the column is nullable).
  final insertData = <String, dynamic>{
    'id': _generateId(),  // Generate CUID-style ID client-side
    'familyId': familyId,
    'name': name,
    'gender': gender ?? 'male',
    'isDeceased': isDeceased,
    'isAnchor': isAnchor,
    'privacyLevel': 'family',  // Matches Prisma schema default
  };

  // ── Link the Person to the creator's auth account ────────────────
  // When the family creator adds themselves, we set linkedUserId to
  // their Supabase auth user ID. This marks the Person node as
  // "claimed" (isLinkedToKinrelUser = true) so it:
  //   - Shows in the Members section (not filtered out as unclaimed)
  //   - Doesn't show a "Pending" badge on the graph node
  //   - Can be used for viewer-perspective kinship calculations
  // We only set this when the caller passes linkedUserId explicitly
  // (the create family flow does this for the creator's own Person).
  if (linkedUserId != null && linkedUserId!.isNotEmpty) {
    insertData['linkedUserId'] = linkedUserId;
  }

  if (dateOfBirth != null && dateOfBirth.isNotEmpty) {
    insertData['dateOfBirth'] = dateOfBirth;
  }
  if (anniversaryDate != null && anniversaryDate.isNotEmpty) {
    insertData['anniversaryDate'] = anniversaryDate;
  }
  if (city != null) insertData['city'] = city;
  if (gotra != null) insertData['gotra'] = gotra;
  if (birthYear != null) insertData['birthYear'] = birthYear;

  // ── Step 1: INSERT the Person row via Supabase ────────────────────
  // Use a generous 15s timeout. Supabase REST API typically responds
  // in <500ms; 15s is a safety net for slow networks.
  late final Map<String, dynamic> response;
  try {
    response = await client
        .from('Person')
        .insert(insertData)
        .select()
        .single()
        .timeout(const Duration(seconds: 15));
  } on PostgrestException catch (e) {
    debugPrint('[createPerson] Supabase INSERT failed: ${e.message}');
    debugPrint('[createPerson] RLS denied? code=${e.code} hint=${e.hint}');
    // Distinguish common RLS / schema errors for the user.
    if (e.code == '42501') {
      throw Exception(
        'Permission denied. You may not have permission to add members to this family. '
        'Please ask the family owner to grant you access.',
      );
    } else if (e.code == '23505') {
      throw Exception('A person with this name already exists in the family.');
    } else if (e.code == '23503') {
      throw Exception('The selected family does not exist.');
    }
    throw Exception('Could not save the new member: ${e.message}');
  } on TimeoutException {
    throw Exception(
      'The database is taking too long to respond. Please check your '
      'internet connection and try again.',
    );
  } catch (e) {
    debugPrint('[createPerson] Unexpected INSERT error: $e');
    throw Exception('Could not save the new member. Please try again. ($e)');
  }

  final person = Person.fromJson(response);
  debugPrint('[createPerson] Supabase INSERT succeeded for ${person.id}');

  // ── Step 2: Update Family.memberCount + lastActivityAt (best-effort) ──
  // This is non-atomic with Step 1, but that's OK — memberCount is a
  // denormalized cache field. If it's stale, the next family refresh
  // will recompute it. We don't fail the whole operation if this fails.
  try {
    // Count FamilyMember rows (simple, no special count() API needed).
    final memberRows = await client
        .from('FamilyMember')
        .select('id')
        .eq('familyId', familyId)
        .timeout(const Duration(seconds: 5));
    final memberCount = (memberRows as List).length;

    await client
        .from('Family')
        .update({
          'memberCount': memberCount,
          'lastActivityAt': DateTime.now().toUtc().toIso8601String(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', familyId)
        .timeout(const Duration(seconds: 5));
    debugPrint('[createPerson] Family.memberCount updated to $memberCount');
  } catch (e) {
    // Best-effort — don't fail the person creation over a stale counter.
    debugPrint('[createPerson] Family.memberCount update failed (non-fatal): $e');
  }

  // ── Step 3: If this person is the anchor, update Family.anchorPersonId ──
  // v26 BUG-FIX: Always check if Family.anchorPersonId is null when adding
  // a new person. If it is, set it to the FIRST person in the family
  // (preferring this new person if isAnchor=true, otherwise the oldest
  // existing person). This prevents the data-inconsistency state where
  // Person.isAnchor=true but Family.anchorPersonId stays null, which
  // caused the blank-graph bug in Example Manish and 15 other families
  // found in the production DB.
  try {
    final familyRow = await client
        .from('Family')
        .select('anchorPersonId')
        .eq('id', familyId)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));

    final currentAnchorId = familyRow?['anchorPersonId'] as String?;

    if (currentAnchorId == null || currentAnchorId.isEmpty) {
      // Family has no anchor — pick the right person to become the anchor.
      String newAnchorId;
      if (isAnchor) {
        // This new person is the anchor (e.g., family creator) — use them.
        newAnchorId = person.id;
      } else {
        // Fall back: use the oldest existing non-deleted Person in the family.
        final existing = await client
            .from('Person')
            .select('id')
            .eq('familyId', familyId)
            .isFilter('deletedAt', null)
            .order('createdAt', ascending: true)
            .limit(1)
            .timeout(const Duration(seconds: 5));
        if (existing is List && existing.isNotEmpty) {
          newAnchorId = existing.first['id'] as String;
          // Also mark them as isAnchor=true so Person and Family stay consistent.
          await client
              .from('Person')
              .update({'isAnchor': true})
              .eq('id', newAnchorId)
              .timeout(const Duration(seconds: 5));
        } else {
          newAnchorId = person.id;
        }
      }

      await client
          .from('Family')
          .update({'anchorPersonId': newAnchorId})
          .eq('id', familyId)
          .timeout(const Duration(seconds: 5));
      debugPrint('[createPerson] Backfilled Family.anchorPersonId = $newAnchorId');
    } else if (isAnchor) {
      // Family already has an anchor but the caller marked this new person
      // as anchor (e.g., family creator re-claiming anchor). Update it.
      await client
          .from('Family')
          .update({'anchorPersonId': person.id})
          .eq('id', familyId)
          .timeout(const Duration(seconds: 5));
      debugPrint('[createPerson] Updated Family.anchorPersonId = ${person.id}');
    }
  } catch (e) {
    debugPrint('[createPerson] anchorPersonId update failed (non-fatal): $e');
  }

  // ── Step 4: Invalidate all providers so the UI refreshes immediately ──
  ref.invalidate(familyMembersProvider(familyId));
  ref.invalidate(familyDetailProvider(familyId));

  // v94 (EDGE BUG FIX): Only clear the graph cache when this is a
  // standalone Person creation. When `refreshGraph` is false, the
  // caller is performing a compound Person+Relationship mutation and
  // will refresh the graph once after the relationship succeeds.
  if (refreshGraph) {
    try {
      FamilyGraphNotifier.clearCache(familyId);
      ref.invalidate(familyGraphProvider(familyId));
    } catch (e) {
      debugPrint('[createPerson] graph provider invalidate failed: $e');
    }
  }

  // Invalidate the Isar cache for this family.
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // Refresh profile stats (member count badge, etc.).
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  // Analytics + retention tracking (best-effort).
  AnalyticsService.instance.logMemberAdded(gender ?? 'unknown');
  try {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('members_added') ?? 0;
    await prefs.setInt('members_added', count + 1);
  } catch (_) {}

  return person;
}

/// Update person in Supabase with retry for cold starts
Future<Person> updatePerson({
  required WidgetRef ref,
  required String personId,
  required String familyId,
  required String name,
  String? gender,
  String? dateOfBirth,
  String? anniversaryDate,
  String? city,
  String? gotra,
  bool isDeceased = false,
  int? birthYear,
  bool isAnchor = false,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  final response = await withRetry(
    () => client
        .from(_kPersonTable)
        .update({
          'name': name,
          if (gender != null) 'gender': gender,
          if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
          if (anniversaryDate != null) 'anniversaryDate': anniversaryDate,
          if (city != null) 'city': city,
          if (gotra != null) 'gotra': gotra,
          'isDeceased': isDeceased,
          if (birthYear != null) 'birthYear': birthYear,
          'isAnchor': isAnchor,
          'updatedAt': DateTime.now().toIso8601String(),
        })
        .eq('id', personId)
        .select()
        .maybeSingle(),
    operationName: 'Update person',
  );

  if (response == null) {
    throw Exception('Failed to update person — no data returned from server.');
  }
  ref.invalidate(familyMembersProvider(familyId));
  // familyDetailProvider auto-rebuilds via ref.watch on familyMembersProvider

  // ✅ RELEASE-READY FIX: invalidate graph provider + clear cache
  // so name/gender/photo changes reflect in the family graph immediately.
  FamilyGraphNotifier.clearCache(familyId);
  ref.invalidate(familyGraphProvider(familyId));

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after person update
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  return Person.fromJson(response);
}

/// Archive (soft-delete) a family for 30 days.
///
/// Calls `DELETE /api/families/:familyId` on the NestJS backend,
/// which now archives the family instead of permanently deleting it.
/// The family can be restored within 30 days before it is
/// permanently deleted.
///
/// Throws an exception if the API call fails.
Future<void> deleteFamily({
  required ProviderContainer container,
  required String familyId,
}) async {
  // FIX: Skip NestJS API entirely — it's on Render free tier and
  // cold-starts in 10-30s, causing TimeoutException. Go straight
  // to Supabase direct update which is fast and reliable.
  final client = container.read(supabaseProvider);
  if (client == null) {
    throw Exception(
        'Database is not connected. Please restart the app and try again.');
  }

  // v2.2: Real auth only — guard against no session.
  if (client.auth.currentSession == null) {
    throw Exception('You must be signed in to delete a family.');
  }

  final now = DateTime.now().toIso8601String();

  // 1. Soft-delete all persons in this family
  try {
    await client
        .from(_kPersonTable)
        .update({'deletedAt': now, 'updatedAt': now})
        .eq('familyId', familyId)
        .filter('deletedAt', 'is', null)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('⚠️ Could not soft-delete persons: $e');
    // Continue — the family soft-delete is the important one
  }

  // 2. Soft-delete the family itself
  await client
      .from(_kFamilyTable)
      .update({'deletedAt': now, 'updatedAt': now})
      .eq('id', familyId)
      .timeout(const Duration(seconds: 10));

  // Invalidate providers to refresh UI
  container.invalidate(familyListProvider);
  container.invalidate(familyMembersProvider(familyId));
  container.invalidate(familyRelationshipsProvider(familyId));
  container.invalidate(archivedFamiliesProvider);
  // familyDetailProvider auto-rebuilds via ref.watch on above providers

  // FIXED: Do NOT call CacheInvalidation.invalidateFamily() or
  // invalidateFamilyList() here — these delete Drift rows or clear the
  // entire cache, which destroys the "mark as archived" data that
  // deleteFamilyOptimistic() carefully set. They also force a full
  // Supabase re-fetch that can bring back old archived families.
  //
  // Instead, the Drift cache already has the family marked with deletedAt
  // (set by deleteFamilyOptimistic before this function is called), so
  // the providers will correctly filter it out on the next read.
  //
  // We only invalidate API cache entries to prevent stale server responses.
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateApiCache('/families/$familyId');
      await CacheInvalidation.invalidateApiCache('/families/archived');
      await CacheInvalidation.invalidateApiCache('family_list');
    } catch (_) {}
  }

  // Refresh profile stats after family archival
  try {
    await container.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

/// Restore an archived family.
///
/// Calls `POST /api/families/:familyId/restore` on the NestJS backend.
/// The family will reappear in the active family list.
///
/// Throws an exception if the API call fails.
Future<void> restoreFamily({
  required ProviderContainer container,
  required String familyId,
}) async {
  // Supabase-first: Restore directly (bypasses NestJS which rejects Supabase JWTs)
  bool restored = false;
  final client = container.read(supabaseProvider);
  if (client == null) {
    throw Exception('Database is not connected. Please restart the app and try again.');
  }
  try {
    await withRetry(
        () => client.rpc('restore_family', params: {'p_family_id': familyId}),
        operationName: 'Restore family (RPC fallback)',
      );
    } catch (e) {
      // If RPC doesn't exist yet, fall back to sequential updates
      debugPrint('⚠️ RPC restore_family failed, falling back to sequential updates: $e');
      // Clear deletedAt on persons
      try {
        await withRetry(
          () => client
              .from(_kPersonTable)
              .update({'deletedAt': null, 'updatedAt': DateTime.now().toIso8601String()})
              .eq('familyId', familyId)
              .not('deletedAt', 'is', null),
          operationName: 'Restore family persons (fallback)',
        );
      } catch (e2) {
        debugPrint('⚠️ Could not restore persons: $e2');
      }

      // Clear deletedAt on the family itself
      await withRetry(
        () => client
            .from(_kFamilyTable)
            .update({'deletedAt': null, 'lastActivityAt': DateTime.now().toIso8601String(), 'updatedAt': DateTime.now().toIso8601String()})
            .eq('id', familyId),
        operationName: 'Restore family (fallback)',
      );
      restored = true;
    }

  // Invalidate providers to refresh UI
  container.invalidate(familyListProvider);
  container.invalidate(familyMembersProvider(familyId));
  container.invalidate(familyRelationshipsProvider(familyId));
  container.invalidate(archivedFamiliesProvider);

  // FIXED: Do NOT call CacheInvalidation.invalidateFamily() or
  // invalidateFamilyList() — these delete Drift rows or clear the entire
  // cache. restoreFamilyOptimistic() already clears deletedAt in Drift,
  // so the providers will correctly show the family as active.
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateApiCache('/families/$familyId');
      await CacheInvalidation.invalidateApiCache('/families/archived');
      await CacheInvalidation.invalidateApiCache('family_list');
    } catch (_) {}
  }

  // Refresh profile stats
  try {
    await container.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

/// Permanently delete an archived family.
///
/// Calls `DELETE /api/families/:familyId/permanent` on the NestJS backend.
/// This action **cannot be undone** — the family and all its data
/// will be permanently removed.
///
/// Throws an exception if the API call fails.
Future<void> permanentDeleteFamily({
  required ProviderContainer container,
  required String familyId,
}) async {
  final client = container.read(supabaseProvider);
  if (client == null) {
    throw Exception('Database is not connected. Please restart the app.');
  }

  // v2.2: Real auth only — guard against no session.
  if (client.auth.currentSession == null) {
    throw Exception('You must be signed in to permanently delete a family.');
  }

  // Mark this family as "deleting" for per-card loading spinner
  container.read(deletingFamilyIdsProvider.notifier).update(
        (ids) => {...ids, familyId},
      );

  try {
    // Direct Supabase RPC — single atomic delete
    await client
        .rpc('delete_family_forever', params: {'p_family_id': familyId})
        .timeout(const Duration(seconds: 10));

    // Refresh UI
    container.invalidate(familyListProvider);
    container.invalidate(familyMembersProvider(familyId));
    container.invalidate(familyRelationshipsProvider(familyId));
    container.invalidate(archivedFamiliesProvider);

    // Invalidate the Isar cache
    if (IsarDatabase.isInitialized) {
      try {
        // For permanent delete, we DO want to remove the Drift row
        // since the family no longer exists on the server.
        await CacheInvalidation.invalidateFamily(familyId);
        // FIXED: Don't clear ALL families from Drift — only the deleted one
        // was removed above. Clearing everything causes old families to
        // reappear from the Supabase re-fetch.
        await CacheInvalidation.invalidateApiCache('/families/archived');
        await CacheInvalidation.invalidateApiCache('family_list');
      } catch (_) {}
    }

    // Refresh profile stats
    try {
      await container.read(profileProvider.notifier).loadStats();
    } catch (_) {}
  } finally {
    // Always remove from deleting set, even on error
    container.read(deletingFamilyIdsProvider.notifier).update(
          (ids) => ids.difference({familyId}),
        );
  }
}

/// Delete person (soft delete) in Supabase with retry for cold starts
Future<void> deletePerson({
  required WidgetRef ref,
  required String personId,
  required String familyId,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  final now = DateTime.now().toIso8601String();

  // FIX: Use direct Supabase calls with timeouts instead of withRetry.
  // withRetry adds 1s + 2s + 4s delays on failure, causing the total
  // delete time to exceed 15s → TimeoutException.
  await client
      .from(_kPersonTable)
      .update({'deletedAt': now, 'updatedAt': now})
      .eq('id', personId)
      .timeout(const Duration(seconds: 10));

  // Deactivate all relationships involving this person.
  try {
    await client
        .from('Relationship')
        .update({'isActive': false, 'updatedAt': now})
        .or('fromPersonId.eq.$personId,toPersonId.eq.$personId')
        .timeout(const Duration(seconds: 10));
    debugPrint('[deletePerson] Deactivated relationships for $personId');
  } catch (e) {
    debugPrint('[deletePerson] Could not deactivate relationships (non-fatal): $e');
  }

  ref.invalidate(familyMembersProvider(familyId));
  // familyDetailProvider auto-rebuilds via ref.watch on familyMembersProvider

  // ✅ RELEASE-READY FIX: invalidate graph provider + clear cache
  // so the deleted person disappears from the family graph immediately.
  FamilyGraphNotifier.clearCache(familyId);
  ref.invalidate(familyGraphProvider(familyId));

  // ✅ FIX: Decrement Family.memberCount in Supabase
  // The NestJS backend decrements memberCount when a person is deleted.
  // We must do the same when deleting via Flutter direct Supabase writes.
  // Note: Supabase PostgREST does NOT support { 'decrement': 1 } Prisma syntax.
  // We must read the current count and then write the decremented value.
  try {
    final familyData = await withRetry(
      () => client
          .from(_kFamilyTable)
          .select('memberCount')
          .eq('id', familyId)
          .maybeSingle(),
      operationName: 'Read memberCount for decrement',
    );
    if (familyData != null) {
      final currentCount = (familyData['memberCount'] as int?) ?? 0;
      await withRetry(
        () => client
            .from(_kFamilyTable)
            .update({
              'memberCount': currentCount > 0 ? currentCount - 1 : 0,
              'lastActivityAt': DateTime.now().toIso8601String(),
              'updatedAt': DateTime.now().toIso8601String(),
            })
            .eq('id', familyId),
        operationName: 'Decrement memberCount',
      );
    }
  } catch (e) {
    debugPrint('⚠️ Could not decrement memberCount: $e');
  }

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after person deletion
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

/// Create relationship in Supabase with retry for cold starts.
///
/// ✅ FIX: Now creates BIDIRECTIONAL relationships — both the forward
/// relationship (A is father of B) AND the inverse relationship
/// (B is child of A). The NestJS backend does the same. Previously,
/// only the forward direction was created, causing:
/// - Incomplete relationship graph (half the edges missing)
/// - Relationship count showing half the expected value
/// - Path finding failing between some persons
Future<FamilyRelationship> createRelationship({
  required WidgetRef ref,
  required String familyId,
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
  Map<String, dynamic>? customColors,
  String? customDisplayName,
  /// v94 (EDGE BUG FIX): When false, skips clearing the graph cache +
  /// invalidating familyGraphProvider. The caller (compound mutation)
  /// will perform ONE authoritative graph refresh after this returns.
  /// Default true preserves standalone-relationship-creation behavior.
  bool refreshGraph = true,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  // v98 (Phase 7): Validate the relationship BEFORE writing to Supabase.
  // Fetch existing edges for validation (self-link, duplicate, cycle).
  try {
    final existingRels = await client
        .from('Relationship')
        .select('id, "fromPersonId", "toPersonId", "relationshipKey"')
        .eq('familyId', familyId)
        .timeout(const Duration(seconds: 10));
    final existingEdges = <({String fromId, String toId, String edgeId, String relationshipKey})>[
      for (final r in existingRels)
        (
          fromId: (r['fromPersonId'] ?? '').toString(),
          toId: (r['toPersonId'] ?? '').toString(),
          edgeId: (r['id'] ?? '').toString(),
          relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
        ),
    ];
    final validation = validateRelationship(
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
      relationshipKey: relationshipKey,
      existingEdges: existingEdges,
    );
    if (validation.isError) {
      throw Exception(validation.message);
    }
    // Warnings are logged but do not block — the user may confirm.
    if (validation.isWarning) {
      debugPrint('[CREATE-REL] ⚠️ Validation warning: ${validation.message}');
    }
  } catch (e) {
    if (e is Exception && e.toString().contains('self_relationship') ||
        e.toString().contains('duplicate_relationship') ||
        e.toString().contains('circular_parentage') ||
        e.toString().contains('duplicate_parent')) {
      rethrow; // Validation error — block the write.
    }
    // Network error fetching existing edges — log and continue
    // (validation is best-effort, not a hard gate).
    debugPrint('[CREATE-REL] Validation fetch failed (non-blocking): $e');
  }

  // v83: If custom colors are provided, save them to CustomKinshipConfig
  if (customColors != null && customDisplayName != null) {
    try {
      final configId = _generateId();
      final userId = client.auth.currentUser?.id;
      await client.from('CustomKinshipConfig').insert({
        'id': configId,
        'familyId': familyId,
        'relationshipKey': relationshipKey,
        'displayName': customDisplayName,
        'nodeColor': customColors['nodeColor'],
        'lineColor': customColors['lineColor'],
        'lineType': customColors['lineType'],
        'dotType': customColors['dotType'],
        'createdBy': userId?.toString(),
      }).timeout(const Duration(seconds: 10));
      debugPrint('[CREATE-REL] ✅ CustomKinshipConfig saved (id=$configId)');
    } catch (e) {
      debugPrint('[CREATE-REL] ⚠️ CustomKinshipConfig save failed (non-fatal): $e');
    }
  }

  final forwardRelId = _generateId();
  final inverseRelId = _generateId();
  final now = DateTime.now().toIso8601String();

  // ✅ FIX: Look up the inverse relationship key
  // e.g., "father" → "child", "husband" → "wife", "brother" → "sibling"
  //
  // v2.2 FIX: If the relationshipKey is NOT in the inverse map (i.e., it's
  // one of the 5,299 extended kinship types like "paternal_uncle" or
  // "fathers_younger_brothers_son"), we SKIP the inverse edge creation
  // entirely. Storing the same key for both directions creates
  // conflicting generation offsets in the layout engine — the forward
  // edge says "uncle is -1 gen" and the inverse edge also says "uncle
  // is -1 gen" (instead of "nephew is +1 gen"), which causes the BFS
  // to assign wrong generations.
  //
  // The layout engine builds bidirectional adjacency from each stored
  // edge (it adds both forward and reverse entries), so skipping the
  // inverse row does NOT break traversal — the BFS can still walk in
  // both directions via the forward edge's reverse entry.
  //
  // v86 FIX: STOP creating inverse relationship rows entirely.
  //
  // Previously, createRelationship created BOTH:
  //   forward: from: newPerson, to: anchor, key: 'father'
  //   inverse: from: anchor, to: newPerson, key: 'child'
  //
  // This caused TWO bugs:
  //   1. "Parent shows Son" — the BFS found the inverse edge first
  //      (from: anchor, to: newPerson, key: 'child') and classified
  //      the new person as 'child' (Son), not 'parent' (Father).
  //   2. Duplicate edges — the EdgeDeduplicator collapsed the pair
  //      but sometimes picked the inverse edge's key, giving the
  //      wrong color.
  //
  // The fix: create ONLY the forward edge. The BFS adjacency list
  // (GraphService.buildAdjacencyList) automatically adds a reverse
  // entry for every edge, so traversal still works in both directions.
  // The inverse key is computed dynamically by RelationshipEngine
  // when needed, so no data is lost.
  //
  // This also simplifies the _relationCategories logic — there's only
  // ONE edge per pair, always pointing from newPerson → anchor with
  // the user-selected key. No more inverse confusion.
  final inverseKey = _relationshipInverseMap[relationshipKey];
  final hasKnownInverse = false; // v86: NEVER create inverse edge

  debugPrint('[CREATE-REL] === START createRelationship ===');
  debugPrint('[CREATE-REL] familyId: $familyId');
  debugPrint('[CREATE-REL] fromPersonId: $fromPersonId');
  debugPrint('[CREATE-REL] toPersonId: $toPersonId');
  debugPrint('[CREATE-REL] relationshipKey: $relationshipKey');
  debugPrint('[CREATE-REL] inverseKey: ${inverseKey ?? "UNKNOWN (skipping inverse)"}');
  debugPrint('[CREATE-REL] forwardRelId: $forwardRelId');
  debugPrint('[CREATE-REL] inverseRelId: $inverseRelId');
  debugPrint('[CREATE-REL] auth.currentSession: ${client.auth.currentSession != null ? "present" : "NULL"}');
  if (client.auth.currentSession == null) {
    debugPrint('[CREATE-REL] ❌ No session — RLS will deny the INSERT');
    throw Exception(
      'You must be signed in to create a relationship. Please restart the app.',
    );
  }

  // 1. Create the forward relationship
  // v82 FIX: Re-added .select().maybeSingle() — the previous v75 fix
  // removed it to avoid timeouts, but on Flutter Web the insert without
  // .select() can return before the row is actually committed, causing
  // the graph refresh to fetch 0 relationships (the row isn't there yet).
  // The .select() forces the client to wait for the row to be readable.
  Map<String, dynamic>? response;
  try {
    debugPrint('[CREATE-REL] Inserting forward relationship...');
    response = await client
        .from(_kRelationshipTable)
        .insert({
          'id': forwardRelId,
          'familyId': familyId,
          'fromPersonId': fromPersonId,
          'toPersonId': toPersonId,
          'relationshipKey': relationshipKey,
          'relationshipType': relationshipKey,
          'direction': 'from',
          'isActive': true,
          'customColors': customColors, // v83: null for standard, JSON for custom
          'createdAt': now,
          'updatedAt': now,
        })
        .select()
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    debugPrint('[CREATE-REL] ✅ Forward INSERT succeeded (id=$forwardRelId, response=$response)');
  } on PostgrestException catch (e) {
    debugPrint('[CREATE-REL] ❌ Forward INSERT PostgrestException: code=${e.code} message=${e.message} hint=${e.hint} details=${e.details}');
    rethrow;
  } catch (e, stack) {
    debugPrint('[CREATE-REL] ❌ Forward INSERT failed: $e');
    debugPrint('[CREATE-REL] Stack: $stack');
    rethrow;
  }

  // v94 (EDGE BUG FIX): Do NOT fabricate a success response when the
  // INSERT returns null. The previous "assuming success" pattern masked
  // real failures (RLS denials that returned empty, network hiccups,
  // Supabase eventual-consistency delays) — the user saw "Welcome to
  // the family!" but no edge row existed in the DB, so the edge never
  // rendered. Now we verify the row is readable via a targeted SELECT;
  // if it's not, we throw so the caller's error handling fires.
  if (response == null) {
    debugPrint(
        '[CREATE-REL] ⚠️ Forward INSERT returned null — verifying via SELECT');
    try {
      final verified = await client
          .from(_kRelationshipTable)
          .select(
            'id, "familyId", "fromPersonId", "toPersonId", '
            '"relationshipKey", "relationshipType", "isActive"',
          )
          .eq('id', forwardRelId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (verified != null) {
        debugPrint('[CREATE-REL] ✅ Verified relationship row exists via SELECT');
        response = verified;
      } else {
        // The INSERT did not persist a readable row. This is a real
        // failure — throw so the caller shows an error instead of
        // silently leaving an orphan node.
        throw Exception(
          'Relationship creation failed: the INSERT did not persist a '
          'readable row (id=$forwardRelId). This may be an RLS denial '
          'or a database constraint violation. The Person was created '
          'but no edge exists.',
        );
      }
    } on PostgrestException catch (e) {
      debugPrint('[CREATE-REL] ❌ Verification SELECT failed: ${e.message}');
      throw Exception(
        'Relationship creation could not be verified: ${e.message}',
      );
    } on TimeoutException {
      throw Exception(
        'Relationship creation timed out during verification. '
        'The edge may or may not exist — please refresh the graph.',
      );
    }
  }
  debugPrint('[CREATE-REL] ✅ Forward relationship created with id: ${response['id']}');

  // 2. Create the inverse relationship (best-effort, only if known)
  //
  // v2.2 FIX: Only create the inverse if we have a KNOWN inverse key.
  // For extended kinship types (5,299 of 5,359), the inverse is not in
  // _relationshipInverseMap. Previously, the code stored the SAME key
  // for both directions — which caused the layout engine to assign
  // wrong generations (the inverse edge would say "uncle is -1" when
  // it should say "nephew is +1", creating conflicting BFS offsets).
  //
  // Now we skip the inverse entirely for unknown keys. The layout's
  // adjacency list handles bidirectional traversal via the forward
  // edge's auto-generated reverse entry.
  if (hasKnownInverse) {
    try {
      debugPrint('[CREATE-REL] Inserting inverse relationship (key=$inverseKey)...');
      await client.from(_kRelationshipTable).insert({
        'id': inverseRelId,
        'familyId': familyId,
        'fromPersonId': toPersonId,
        'toPersonId': fromPersonId,
        'relationshipKey': inverseKey,
        'relationshipType': inverseKey,
        'direction': 'from',
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
      }).select().maybeSingle().timeout(const Duration(seconds: 10));
      debugPrint('[CREATE-REL] ✅ Inverse relationship created');
    } on PostgrestException catch (e) {
      // Best-effort — inverse creation failure shouldn't block the user
      debugPrint('[CREATE-REL] ⚠️ Inverse INSERT PostgrestException (non-fatal): code=${e.code} message=${e.message}');
    } catch (e) {
      // Best-effort — inverse creation failure shouldn't block the user
      debugPrint('[CREATE-REL] ⚠️ Could not create inverse relationship (non-fatal): $e');
    }
  } else {
    debugPrint('[CREATE-REL] ⏭️ Skipping inverse creation — key "$relationshipKey" not in inverse map (extended kinship). '
        'Layout engine will handle bidirectional traversal via the forward edge.');
  }

  // 3. Update Family.lastActivityAt
  try {
    await withRetry(
      () => client
          .from(_kFamilyTable)
          .update({
            'lastActivityAt': now,
            'updatedAt': now,
          })
          .eq('id', familyId),
      operationName: 'Update family activity timestamp',
    );
  } catch (e) {
    debugPrint('⚠️ Could not update family activity: $e');
  }

  ref.invalidate(familyRelationshipsProvider(familyId));
  // familyDetailProvider auto-rebuilds via ref.watch on familyRelationshipsProvider

  // v94 (EDGE BUG FIX): Only clear the graph cache + invalidate the
  // graph provider when this is a standalone relationship creation.
  // When `refreshGraph` is false, the caller is performing a compound
  // Person+Relationship mutation and will perform ONE authoritative
  // graph refresh + optimistic upsert after this returns. Clearing
  // here would destroy the cache that the caller needs for the
  // optimistic upsert, and would trigger a Person-only intermediate
  // refetch that could race with the edge-containing state.
  if (refreshGraph) {
    FamilyGraphNotifier.clearCache(familyId);
    ref.invalidate(familyGraphProvider(familyId));
  }

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // ✅ FIX: Refresh profile stats after relationship creation
  // Without this, the profile screen still shows old Relations count
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}

  return FamilyRelationship.fromJson(response);
}

// ── Extended Relationship Functions ────────────────────────────────

/// Inverse relationship mapping for creating bidirectional links.
/// When "A is father of B", we also need "B is child of A".
const Map<String, String> _relationshipInverseMap = {
  'father': 'child',
  'mother': 'child',
  'parent': 'child',
  'child': 'parent',
  'son': 'parent',
  'daughter': 'parent',
  'brother': 'sibling',
  'sister': 'sibling',
  'sibling': 'sibling',
  'elder_brother': 'younger_sibling',
  'younger_brother': 'elder_sibling',
  'elder_sister': 'younger_sibling',
  'younger_sister': 'elder_sibling',
  'spouse': 'spouse',
  'husband': 'wife',
  'wife': 'husband',
  'grandfather': 'grandchild',
  'grandmother': 'grandchild',
  'grandparent': 'grandchild',
  'grandchild': 'grandparent',
  'grandson': 'grandparent',
  'granddaughter': 'grandparent',
  'uncle': 'nephew_or_niece',
  'aunt': 'nephew_or_niece',
  'nephew': 'uncle_or_aunt',
  'niece': 'uncle_or_aunt',
  'cousin': 'cousin',
  'father_in_law': 'child_in_law',
  'mother_in_law': 'child_in_law',
  'son_in_law': 'parent_in_law',
  'daughter_in_law': 'parent_in_law',
  'brother_in_law': 'sibling_in_law',
  'sister_in_law': 'sibling_in_law',
  'step_father': 'step_child',
  'step_mother': 'step_child',
  'step_brother': 'step_sibling',
  'step_sister': 'step_sibling',
  'stepfather': 'stepchild',
  'stepmother': 'stepchild',
  // Compound relationships (father's side)
  'fathers_brother': 'nephew_or_niece',
  'fathers_sister': 'nephew_or_niece',
  'fathers_younger_brother': 'nephew_or_niece',
  'fathers_elder_brother': 'nephew_or_niece',
  'fathers_younger_brothers_wife': 'nephew_or_nieces_spouse',
  'fathers_elder_brothers_wife': 'nephew_or_nieces_spouse',
  'fathers_younger_brothers_son': 'cousin',
  'fathers_younger_brothers_daughter': 'cousin',
  'fathers_elder_brothers_son': 'cousin',
  'fathers_elder_brothers_daughter': 'cousin',
  'paternal_grandfather': 'grandchild',
  'paternal_grandmother': 'grandchild',
  // Compound relationships (mother's side)
  'mothers_brother': 'nephew_or_niece',
  'mothers_sister': 'nephew_or_niece',
  'mothers_brothers_wife': 'nephew_or_nieces_spouse',
  'mothers_brothers_son': 'cousin',
  'mothers_brothers_daughter': 'cousin',
  'mothers_sisters_husband': 'nephew_or_nieces_spouse',
  'mothers_sisters_son': 'cousin',
  'mothers_sisters_daughter': 'cousin',
  'maternal_grandfather': 'grandchild',
  'maternal_grandmother': 'grandchild',
  // In-laws
  'husbands_father': 'child_in_law',
  'husbands_mother': 'child_in_law',
  'husbands_elder_brother': 'sibling_in_law',
  'husbands_elder_brothers_wife': 'sibling_in_law',
  'husbands_younger_brother': 'sibling_in_law',
  'husbands_younger_brothers_wife': 'sibling_in_law',
  'husbands_sister': 'sibling_in_law',
  'wives_father': 'child_in_law',
  'wives_mother': 'child_in_law',
  'wives_brother': 'sibling_in_law',
  'wives_sister': 'sibling_in_law',
  // Grandchildren
  'sons_son': 'grandparent',
  'sons_daughter': 'grandparent',
  'daughters_son': 'grandparent',
  'daughters_daughter': 'grandparent',
  // Nephew/Niece
  'brothers_son': 'uncle_or_aunt',
  'brothers_daughter': 'uncle_or_aunt',
  'sisters_son': 'uncle_or_aunt',
  'sisters_daughter': 'uncle_or_aunt',
};

/// Get the inverse relationship type.
/// E.g., "father" → "child", "wife" → "husband"
String getInverseRelationshipType(String relationshipType) {
  final normalized = relationshipType.toLowerCase().trim();
  return _relationshipInverseMap[normalized] ?? normalized;
}

/// Create a bidirectional relationship between two persons.
///
/// When Person A has relationship X to Person B, this also creates
/// the inverse relationship from Person B to Person A.
///
/// E.g., If B is "father" of A, then A is "child" of B.
Future<FamilyRelationship> createRelationshipBetween({
  required WidgetRef ref,
  required String familyId,
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
}) async {
  // 1. Create the primary relationship (fromPerson → toPerson)
  final primary = await createRelationship(
    ref: ref,
    familyId: familyId,
    fromPersonId: fromPersonId,
    toPersonId: toPersonId,
    relationshipKey: relationshipKey,
  );

  // 2. Create the inverse relationship (toPerson → fromPerson)
  final inverseType = getInverseRelationshipType(relationshipKey);
  if (inverseType != relationshipKey ||
      relationshipKey == 'spouse' ||
      relationshipKey == 'cousin' ||
      relationshipKey == 'sibling') {
    try {
      await createRelationship(
        ref: ref,
        familyId: familyId,
        fromPersonId: toPersonId,
        toPersonId: fromPersonId,
        relationshipKey: inverseType,
      );
    } catch (e) {
      // If inverse creation fails, the primary is still valid.
      debugPrint('⚠️ Failed to create inverse relationship: $e');
    }
  }

  // 3. Return the primary relationship
  return primary;
}

/// Get relationship suggestions for a person based on their
/// existing relationships. Suggests common ones they're missing.
List<String> getSuggestedRelationships(
  Person person,
  List<Person> existingMembers,
) {
  final existing = <String>{};

  final suggestions = <String>[];

  const commonRelationships = [
    'father',
    'mother',
    'brother',
    'sister',
    'husband',
    'wife',
    'son',
    'daughter',
    'grandfather',
    'grandmother',
    'uncle',
    'aunt',
    'cousin',
  ];

  for (final rel in commonRelationships) {
    if (!existing.contains(rel)) {
      suggestions.add(rel);
    }
  }

  return suggestions;
}

/// Join a family by its shareable family code.
///
/// 1. Looks up the family by familyCode
/// 2. Adds the current user as a FamilyMember
/// 3. Returns the family
Future<Family> joinFamilyByCode(WidgetRef ref, String familyCode) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    throw Exception('You must be signed in to join a family.');
  }

  // 1. Look up family by code
  final familyResponse = await withRetry(
    () => client
        .from(_kFamilyTable)
        .select()
        .eq('familyCode', familyCode)
        .maybeSingle(),
    operationName: 'Lookup family by code',
  );

  if (familyResponse == null) {
    throw Exception('Family not found. Please check the code and try again.');
  }

  final family = Family.fromJson(familyResponse);

  // 2. Check if already a member
  if (family.createdBy == userId) {
    return family; // Already a member (creator)
  }

  // 3. Add user as a family member
  try {
    await withRetry(
      () => client.rpc('add_family_member', params: {
        'p_family_id': family.id,
        'p_user_id': userId,
        'p_role': 'member',
      }),
      operationName: 'Join family (RPC)',
    );
  } catch (e) {
    // If RPC fails, fall back to direct insert
    final errStr = e.toString();
    if (!errStr.contains('duplicate') && !errStr.contains('already exists')) {
      debugPrint('⚠️ RPC add_family_member failed, trying direct insert: $e');
      try {
        await withRetry(
          () => client.from(_kFamilyMemberTable).insert({
            'id': _generateId(),
            'familyId': family.id,
            'userId': userId,
            'role': 'member',
            'joinedAt': DateTime.now().toIso8601String(),
          }),
          operationName: 'Join family (direct)',
        );
      } catch (e2) {
        final errStr2 = e2.toString();
        if (!errStr2.contains('duplicate') && !errStr2.contains('already exists')) {
          rethrow;
        }
      }
    }
  }

  ref.invalidate(familyListProvider);

  // Invalidate the Isar cache for the family list
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamilyList();
    } catch (_) {}
  }

  // P5-F1: Track family join
  AnalyticsService.instance.logFamilyJoined('invite_code');

  return family;
}

/// Update family fields in Supabase with retry for cold starts.
///
/// Only non-null fields are sent to the server; null parameters are
/// left unchanged on the server side. This matches the NestJS backend's
/// PATCH behaviour.
Future<Family> updateFamily({
  required WidgetRef ref,
  required String familyId,
  String? name,
  String? description,
  String? primaryLanguage,
  String? gotra,
  String? originVillage,
  String? region,
  String? privacyMode,
  String? username,
  String? avatarUrl,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  // Build the update map — only include fields that are explicitly provided
  final updates = <String, dynamic>{
    'updatedAt': DateTime.now().toIso8601String(),
  };
  if (name != null) updates['name'] = name;
  if (description != null) updates['description'] = description;
  if (primaryLanguage != null) updates['primaryLanguage'] = primaryLanguage;
  if (gotra != null) updates['gotra'] = gotra;
  if (originVillage != null) updates['originVillage'] = originVillage;
  if (region != null) updates['region'] = region;
  if (privacyMode != null) updates['privacyMode'] = privacyMode;
  if (username != null) updates['username'] = username;
  if (avatarUrl != null) updates['avatarUrl'] = avatarUrl;

  final response = await withRetry(
    () => client
        .from(_kFamilyTable)
        .update(updates)
        .eq('id', familyId)
        .select()
        .maybeSingle(),
    operationName: 'Update family',
  );

  if (response == null) {
    throw Exception('Failed to update family — no data returned from server.');
  }

  ref.invalidate(familyListProvider);
  ref.invalidate(familyDetailProvider(familyId));

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  return Family.fromJson(response);
}

/// Delete (deactivate) a relationship in Supabase.
///
/// Sets `isActive = false` on both the forward and inverse relationships.
/// This matches the NestJS backend's soft-delete behaviour for relationships.
Future<void> deleteRelationship({
  required WidgetRef ref,
  required String relationshipId,
  required String familyId,
}) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception(
      'Database is not connected. Please restart the app and try again.',
    );
  }

  final now = DateTime.now().toIso8601String();

  // 1. Look up the relationship to find the inverse
  final relData = await withRetry(
    () => client
        .from(_kRelationshipTable)
        .select()
        .eq('id', relationshipId)
        .maybeSingle(),
    operationName: 'Lookup relationship for delete',
  );

  // 2. Deactivate the forward relationship
  await withRetry(
    () => client.from(_kRelationshipTable).update({
      'isActive': false,
      'updatedAt': now,
    }).eq('id', relationshipId),
    operationName: 'Deactivate relationship',
  );

  // 3. Deactivate the inverse relationship (best-effort)
  if (relData != null) {
    final fromPersonId = relData['fromPersonId'] as String?;
    final toPersonId = relData['toPersonId'] as String?;
    if (fromPersonId != null && toPersonId != null) {
      try {
        await withRetry(
          () => client
              .from(_kRelationshipTable)
              .update({
                'isActive': false,
                'updatedAt': now,
              })
              .eq('familyId', familyId)
              .eq('fromPersonId', toPersonId)
              .eq('toPersonId', fromPersonId)
              .neq('id', relationshipId),
          operationName: 'Deactivate inverse relationship',
        );
      } catch (e) {
        debugPrint('⚠️ Could not deactivate inverse relationship: $e');
      }
    }
  }

  // 4. Update Family.lastActivityAt
  try {
    await withRetry(
      () => client
          .from(_kFamilyTable)
          .update({
            'lastActivityAt': now,
            'updatedAt': now,
          })
          .eq('id', familyId),
      operationName: 'Update family activity timestamp',
    );
  } catch (e) {
    debugPrint('⚠️ Could not update family activity: $e');
  }

  ref.invalidate(familyRelationshipsProvider(familyId));
  ref.invalidate(familyDetailProvider(familyId));

  // ✅ RELEASE-READY FIX: invalidate the graph provider + clear its
  // in-memory cache so the deleted edge disappears immediately.
  // (See createRelationship for the full rationale.)
  FamilyGraphNotifier.clearCache(familyId);
  ref.invalidate(familyGraphProvider(familyId));

  // Invalidate the Isar cache for this family
  if (IsarDatabase.isInitialized) {
    try {
      await CacheInvalidation.invalidateFamily(familyId);
    } catch (_) {}
  }

  // Refresh profile stats
  try {
    await ref.read(profileProvider.notifier).loadStats();
  } catch (_) {}
}

// ── Top-level parsing functions for compute() ──────────────────────
// These must be top-level functions (not closures or class methods)
// because Dart's compute() requires them for spawning isolates.

/// Parse a list of JSON objects into [Family] objects.
/// Used by [familyListProvider] via compute() for large lists (> 20 items).
List<Family> _parseFamilyList(List<dynamic> jsonList) {
  return jsonList
      .map((json) => Family.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Parse a list of JSON objects into [Person] objects.
/// Used by [familyMembersProvider] via compute() for large lists (> 20 items).
List<Person> _parsePersonList(List<dynamic> jsonList) {
  return jsonList
      .map((json) => Person.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Parse a list of JSON objects into [FamilyRelationship] objects.
/// Used by [familyRelationshipsProvider] via compute() for large lists (> 20 items).
List<FamilyRelationship> _parseRelationshipList(List<dynamic> jsonList) {
  return jsonList
      .map((json) => FamilyRelationship.fromJson(json as Map<String, dynamic>))
      .toList();
}
