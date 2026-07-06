// lib/features/profile/data/profile_provider.dart
//
// DAXELO KINREL — Profile Provider
//
// Manages user profile state, stats, sessions, families,
// invitations, blocked users, and all profile-related API calls
// to the NestJS backend via the shared Dio client.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;

import '../../../core/networking/dio_client.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/database/repositories/offline_profile_repository.dart';

// ════════════════════════════════════════════════════════════════════
// DATA MODELS
// ════════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════════
// PROFILE COMPLETION SCORE
// ════════════════════════════════════════════════════════════════════

/// Profile completion score indicating how complete the user's profile is.
class ProfileCompletionScore {
  const ProfileCompletionScore({
    required this.percentage,
    required this.missingFields,
    required this.suggestions,
  });

  /// Percentage from 0-100.
  final int percentage;

  /// List of field names that are missing.
  final List<String> missingFields;

  /// Human-readable suggestions for improving the profile.
  final List<String> suggestions;

  /// Whether the profile is considered complete (>= 80%).
  bool get isComplete => percentage >= 80;

  /// Whether the profile is minimally complete (>= 50%).
  bool get isMinimal => percentage >= 50;
}

/// User profile data from the NestJS backend.
class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.email,
    this.name,
    this.phone,
    this.avatarUrl,
    this.bio,
    this.dateOfBirth,
    this.gender,
    this.username,
    this.preferredLanguage = 'en',
    this.profileVisibility = 'public',
    this.invitePermission = 'anyone',
    this.twoFactorEnabled = false,
    this.authProvider = 'email',
    this.occupation,
    this.education,
    this.privacySettings,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: _parseString(json['id']),
      email: _parseString(json['email']),
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      dateOfBirth: json['dateOfBirth'] != null
          ? DateTime.tryParse(json['dateOfBirth'].toString())
          : null,
      gender: json['gender'] as String?,
      username: json['username'] as String?,
      preferredLanguage: _parseString(json['preferredLanguage'], fallback: 'en'),
      profileVisibility: _parseString(json['profileVisibility'], fallback: 'public'),
      invitePermission: _parseString(json['invitePermission'], fallback: 'anyone'),
      twoFactorEnabled: _parseBool(json['twoFactorEnabled']),
      authProvider: _parseString(json['authProvider'], fallback: 'email'),
      occupation: json['occupation'] as String?,
      education: json['education'] as String?,
      privacySettings: json['privacySettings'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String id;
  final String email;
  final String? name;
  final String? phone;
  final String? avatarUrl;
  final String? bio;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? username;
  final String preferredLanguage;
  final String profileVisibility;
  final String invitePermission;
  final bool twoFactorEnabled;
  final String authProvider;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── Extended profile fields ─────────────────────────────────────
  /// User's occupation/profession.
  final String? occupation;

  /// User's education level or institution.
  final String? education;

  /// Privacy settings for profile visibility.
  final String? privacySettings;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'phone': phone,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'gender': gender,
    'username': username,
    'preferredLanguage': preferredLanguage,
    'profileVisibility': profileVisibility,
    'invitePermission': invitePermission,
    'twoFactorEnabled': twoFactorEnabled,
    'authProvider': authProvider,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'occupation': occupation,
    'education': education,
    'privacySettings': privacySettings,
  };

  /// Calculate profile completion score.
  /// Each field contributes a specific percentage:
  /// - Avatar (20%), Display name (10%), Username (15%), Bio (10%),
  /// - DOB (10%), Occupation (10%), Education (10%), Phone (5%),
  /// - At least one family (10%)
  ProfileCompletionScore calculateCompletion({int familyCount = 0}) {
    int score = 0;
    final missing = <String>[];
    final suggestionsList = <String>[];

    // Avatar (20%)
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      score += 20;
    } else {
      missing.add('avatar');
      suggestionsList.add('Add a profile photo so family members can recognize you');
    }

    // Display name (10%)
    if (name != null && name!.trim().isNotEmpty) {
      score += 10;
    } else {
      missing.add('name');
      suggestionsList.add('Add your display name to personalize your profile');
    }

    // Username (15%)
    if (username != null && username!.trim().isNotEmpty) {
      score += 15;
    } else {
      missing.add('username');
      suggestionsList.add('Set a username so others can find and tag you');
    }

    // Bio (10%)
    if (bio != null && bio!.trim().isNotEmpty) {
      score += 10;
    } else {
      missing.add('bio');
      suggestionsList.add('Write a short bio to tell your family about yourself');
    }

    // DOB (10%)
    if (dateOfBirth != null) {
      score += 10;
    } else {
      missing.add('dateOfBirth');
      suggestionsList.add('Add your birthday so family can celebrate with you');
    }

    // Occupation (10%)
    if (occupation != null && occupation!.trim().isNotEmpty) {
      score += 10;
    } else {
      missing.add('occupation');
      suggestionsList.add('Add your profession or occupation');
    }

    // Education (10%)
    if (education != null && education!.trim().isNotEmpty) {
      score += 10;
    } else {
      missing.add('education');
      suggestionsList.add('Add your education background');
    }

    // Phone (5%)
    if (phone != null && phone!.trim().isNotEmpty) {
      score += 5;
    } else {
      missing.add('phone');
      suggestionsList.add('Add your phone number for family contact');
    }

    // At least one family (10%)
    if (familyCount > 0) {
      score += 10;
    } else {
      missing.add('family');
      suggestionsList.add('Join or create a family to start building your tree');
    }

    return ProfileCompletionScore(
      percentage: score.clamp(0, 100),
      missingFields: missing,
      suggestions: suggestionsList,
    );
  }
}

/// User statistics summary.
class UserStatsModel {
  const UserStatsModel({
    this.familyTrees = 0,
    this.membersAdded = 0,
    this.relations = 0,
  });

  factory UserStatsModel.fromJson(Map<String, dynamic> json) {
    return UserStatsModel(
      familyTrees: _parseInt(json['familyTrees']),
      membersAdded: _parseInt(json['membersAdded']),
      relations: _parseInt(json['relations']),
    );
  }

  final int familyTrees;
  final int membersAdded;
  final int relations;
}

/// Active session for the current user.
class SessionModel {
  const SessionModel({
    required this.id,
    this.deviceName,
    this.deviceType = 'unknown',
    this.location,
    required this.lastActiveAt,
    this.isCurrentDevice = false,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: _parseString(json['id']),
      deviceName: json['deviceName'] as String?,
      deviceType: _parseString(json['deviceType'], fallback: 'unknown'),
      location: json['location'] as String?,
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.tryParse(json['lastActiveAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isCurrentDevice: _parseBool(json['isCurrentDevice']),
    );
  }

  final String id;
  final String? deviceName;
  final String deviceType;
  final String? location;
  final DateTime lastActiveAt;
  final bool isCurrentDevice;
}

/// Family tree node for the "My Family Trees" list.
class FamilyTreeNode {
  const FamilyTreeNode({
    required this.id,
    required this.name,
    this.username,
    this.role = 'member',
    this.memberCount = 0,
    this.kinFamilyId,
  });

  factory FamilyTreeNode.fromJson(Map<String, dynamic> json) {
    return FamilyTreeNode(
      id: _parseString(json['id']),
      name: _parseString(json['name']),
      username: json['username'] as String?,
      role: _parseString(json['role'], fallback: 'member'),
      memberCount: _parseInt(json['memberCount']),
      kinFamilyId: json['kinFamilyId'] as String?,
    );
  }

  final String id;
  final String name;
  final String? username;
  final String role;
  final int memberCount;

  /// KIN Family ID — unique identifier for the family (e.g. "KIN-ABC123").
  /// Auto-generated by the backend via GET /api/families/:id/family-id.
  final String? kinFamilyId;
}

/// Invitation to join a family.
class InvitationModel {
  const InvitationModel({
    required this.id,
    required this.familyName,
    this.familyAvatar,
    required this.inviterName,
    this.inviterUsername,
    this.status = 'pending',
    required this.createdAt,
  });

  factory InvitationModel.fromJson(Map<String, dynamic> json) {
    return InvitationModel(
      id: _parseString(json['id']),
      familyName: _parseString(json['familyName']),
      familyAvatar: json['familyAvatar'] as String?,
      inviterName: _parseString(json['inviterName']),
      inviterUsername: json['inviterUsername'] as String?,
      status: _parseString(json['status'], fallback: 'pending'),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String id;
  final String familyName;
  final String? familyAvatar;
  final String inviterName;
  final String? inviterUsername;
  final String status;
  final DateTime createdAt;
}

/// A blocked user.
class BlockedUserModel {
  const BlockedUserModel({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });

  factory BlockedUserModel.fromJson(Map<String, dynamic> json) {
    return BlockedUserModel(
      id: _parseString(json['id']),
      name: _parseString(json['name']),
      username: json['username'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
}

// ════════════════════════════════════════════════════════════════════
// 2FA SETUP RESPONSE
// ════════════════════════════════════════════════════════════════════

/// Response from the 2FA setup endpoint.
class TwoFASetupResponse {
  const TwoFASetupResponse({required this.secret, required this.qrCodeUrl});

  factory TwoFASetupResponse.fromJson(Map<String, dynamic> json) {
    return TwoFASetupResponse(
      secret: json['secret'] as String? ?? '',
      qrCodeUrl: json['qrCodeUrl'] as String? ?? '',
    );
  }

  final String secret;
  final String qrCodeUrl;
}

// ════════════════════════════════════════════════════════════════════
// PROFILE STATE
// ════════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════════
// SAFE PARSING HELPERS
// ════════════════════════════════════════════════════════════════════

/// Safely parse a value that might be String or int into int.
/// Backend may return numeric fields as strings (e.g. "5" instead of 5).
int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is num) return value.toInt();
  return 0;
}

/// Safely parse a value that might be int or String into String.
/// Backend may return string IDs as integers.
String _parseString(dynamic value, {String fallback = ''}) {
  if (value is String) return value;
  if (value is int || value is num) return value.toString();
  return fallback;
}

/// Safely parse a bool that might come as int, String, or bool.
bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  return fallback;
}

/// Extract the user object from an API response.
/// The NestJS backend returns { "user": { ... } } but the Flutter
/// code expects the user object directly.
Map<String, dynamic> _extractUserData(Map<String, dynamic> response) {
  // If the response has a top-level 'user' key, unwrap it
  if (response.containsKey('user') && response['user'] is Map) {
    return (response['user'] as Map).cast<String, dynamic>();
  }
  // Otherwise assume the response IS the user object
  return response;
}

class ProfileState {
  const ProfileState({
    this.profile,
    this.stats,
    this.isLoading = false,
    this.error,
    this.sessions = const [],
    this.families = const [],
    this.invitations = const [],
    this.blockedUsers = const [],
    this.profileCompletion,
  });

  final ProfileModel? profile;
  final UserStatsModel? stats;
  final bool isLoading;
  final String? error;
  final List<SessionModel> sessions;
  final List<FamilyTreeNode> families;
  final List<InvitationModel> invitations;
  final List<BlockedUserModel> blockedUsers;

  /// Cached profile completion score.
  final ProfileCompletionScore? profileCompletion;

  ProfileState copyWith({
    ProfileModel? profile,
    bool clearProfile = false,
    UserStatsModel? stats,
    bool clearStats = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<SessionModel>? sessions,
    List<FamilyTreeNode>? families,
    List<InvitationModel>? invitations,
    List<BlockedUserModel>? blockedUsers,
    ProfileCompletionScore? profileCompletion,
    bool clearCompletion = false,
  }) {
    return ProfileState(
      profile: clearProfile ? null : (profile ?? this.profile),
      stats: clearStats ? null : (stats ?? this.stats),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      sessions: sessions ?? this.sessions,
      families: families ?? this.families,
      invitations: invitations ?? this.invitations,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      profileCompletion: clearCompletion ? null : (profileCompletion ?? this.profileCompletion),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// PROFILE NOTIFIER
// ════════════════════════════════════════════════════════════════════

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier(this._ref) : super(const ProfileState());

  final Ref _ref;

  // ── Helper: get the configured Dio client ──────────────────────
  Dio get _dio => _ref.read(dioProvider);

  // ── Profile Completion ──────────────────────────────────────────

  /// Calculate and cache the profile completion score.
  ProfileCompletionScore calculateProfileCompletion() {
    final profile = state.profile;
    if (profile == null) {
      const empty = ProfileCompletionScore(
        percentage: 0,
        missingFields: ['profile'],
        suggestions: ['Complete your profile to get started'],
      );
      state = state.copyWith(profileCompletion: empty);
      return empty;
    }

    final score = profile.calculateCompletion(
      familyCount: state.families.length,
    );
    state = state.copyWith(profileCompletion: score);
    return score;
  }

  // ── Extended Profile Fields ─────────────────────────────────────

  /// Load extended profile fields (occupation, education, privacy) from backend.
  Future<Map<String, dynamic>?> loadExtendedProfile() async {
    try {
      final response = await _dio.get('/api/users/me/extended');
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } on DioException catch (e) {
      debugPrint('⚠️ loadExtendedProfile error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ loadExtendedProfile error: $e');
    }
    return null;
  }

  // ── Profile Field Validation ────────────────────────────────────

  /// Validate profile fields before saving.
  /// Returns a map of field name → error message. Empty map means valid.
  Map<String, String> validateProfileFields(Map<String, dynamic> data) {
    final errors = <String, String>{};

    // Username validation
    if (data.containsKey('username')) {
      final username = data['username'] as String? ?? '';
      if (username.isNotEmpty) {
        if (username.length < 3) {
          errors['username'] = 'Username must be at least 3 characters';
        } else if (username.length > 30) {
          errors['username'] = 'Username must be at most 30 characters';
        } else if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
          errors['username'] = 'Username can only contain letters, numbers, and underscores';
        }
      }
    }

    // Name validation
    if (data.containsKey('name')) {
      final name = data['name'] as String? ?? '';
      if (name.isNotEmpty && name.length > 100) {
        errors['name'] = 'Name must be at most 100 characters';
      }
    }

    // Bio validation
    if (data.containsKey('bio')) {
      final bio = data['bio'] as String? ?? '';
      if (bio.length > 500) {
        errors['bio'] = 'Bio must be at most 500 characters';
      }
    }

    // Phone validation
    if (data.containsKey('phone')) {
      final phone = data['phone'] as String? ?? '';
      if (phone.isNotEmpty && !RegExp(r'^\+?[0-9\s\-\(\)]{7,20}$').hasMatch(phone)) {
        errors['phone'] = 'Please enter a valid phone number';
      }
    }

    // Occupation validation
    if (data.containsKey('occupation')) {
      final occupation = data['occupation'] as String? ?? '';
      if (occupation.length > 100) {
        errors['occupation'] = 'Occupation must be at most 100 characters';
      }
    }

    // Education validation
    if (data.containsKey('education')) {
      final education = data['education'] as String? ?? '';
      if (education.length > 200) {
        errors['education'] = 'Education must be at most 200 characters';
      }
    }

    // Date of birth validation
    if (data.containsKey('dateOfBirth')) {
      final dobStr = data['dateOfBirth']?.toString();
      if (dobStr != null && dobStr.isNotEmpty) {
        final dob = DateTime.tryParse(dobStr);
        if (dob == null) {
          errors['dateOfBirth'] = 'Invalid date format';
        } else if (dob.isAfter(DateTime.now())) {
          errors['dateOfBirth'] = 'Date of birth cannot be in the future';
        }
      }
    }

    return errors;
  }

  // ── Load Profile ───────────────────────────────────────────────

  Future<void> loadProfile() async {
    try {
    state = state.copyWith(isLoading: true, clearError: true);

    // v2.2: Real auth only — guard against no session. Try offline cache
    // first, then give up gracefully.
    final client = _ref.read(supabaseProvider);
    if (client?.auth.currentSession == null) {
      // No session — try offline cache, then give up gracefully
      if (IsarDatabase.isInitialized) {
        try {
          final repo = _ref.read(offlineProfileRepositoryProvider);
          final profile = await repo.getProfile();
          if (profile != null) {
            state = state.copyWith(profile: profile, isLoading: false);
            return;
          }
        } catch (_) {}
      }
      state = state.copyWith(isLoading: false);
      return;
    }

    // ── Supabase-first approach ──────────────────────────────────────
    // The NestJS backend currently rejects Supabase JWTs (ES256 vs HS256
    // signing mismatch). Use Supabase directly as the primary path.
    // The NestJS API call is kept as a secondary fallback for when the
    // Supabase User table query fails (e.g. RLS issues on new accounts).

    await _loadProfileFromSupabase();

    // Also try to load stats
    loadStats();

    // Try offline cache as secondary fallback if Supabase returned nothing
    if (state.profile == null && IsarDatabase.isInitialized) {
      await _tryOfflineProfile();
    }

    // Load related data in the background
    loadFamilies();
    loadInvitations();
    } catch (e) {
      debugPrint('🔴 loadProfile top-level error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Try to load profile from offline Isar cache.
  /// Returns true if a cached profile was found and set in state.
  Future<bool> _tryOfflineProfile() async {
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        final profile = await repo.getProfile();
        if (profile != null) {
          state = state.copyWith(profile: profile, isLoading: false);
          debugPrint('📦 loadProfile: Using offline cached profile');
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ Offline profile load failed: $e');
      }
    }
    return false;
  }

  // ── Load Stats ─────────────────────────────────────────────────

  Future<void> loadStats() async {
    // v2.2: Real auth only — guard against no session.
    final client = _ref.read(supabaseProvider);
    if (client?.auth.currentSession == null) {
      // No session — try offline cache, then give up gracefully
      if (IsarDatabase.isInitialized) {
        try {
          final repo = _ref.read(offlineProfileRepositoryProvider);
          final stats = await repo.getStats();
          if (stats != null) {
            state = state.copyWith(stats: stats);
            return;
          }
        } catch (_) {}
      }
      return;
    }

    // ── Supabase-first: compute stats directly from Supabase tables ──
    // The NestJS backend rejects Supabase JWTs (ES256/HS256 mismatch).
    try {
      await _loadStatsFromSupabase();
    } catch (e) {
      debugPrint('⚠️ loadStats error, trying offline cache: $e');
      await _tryOfflineStats();
    }
  }

  /// Try to load stats from offline Isar cache.
  /// Returns true if cached stats were found and set in state.
  Future<bool> _tryOfflineStats() async {
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        final stats = await repo.getStats();
        if (stats != null) {
          state = state.copyWith(stats: stats);
          debugPrint('📦 loadStats: Using offline cached stats');
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ Offline stats load failed: $e');
      }
    }
    return false;
  }

  Future<void> _loadStatsFromSupabase() async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;

      // v2.2: Real auth only — no mock user fallback.
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      // Query family member count (table name must match Supabase: PascalCase)
      final familyMembers = await client
          .from('FamilyMember')
          .select('id, familyId')
          .eq('userId', userId);

      // SAFELY extract family IDs — Supabase may return familyId as
      // String or int depending on the column type. Use _parseString
      // to handle both cases without type casting errors.
      final familyIds = <String>{};
      try {
        for (final row in (familyMembers as List)) {
          final familyId = _parseString(row['familyId']);
          if (familyId.isNotEmpty) {
            familyIds.add(familyId);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Family ID extraction failed: $e');
      }

      // ✅ FIX: Also find families where user is the creator
      // (fallback for missing FamilyMember entries, matching familyListProvider logic)
      try {
        final createdFamilies = await client
            .from('Family')
            .select('id')
            .eq('createdBy', userId)
            .filter('deletedAt', 'is', null);
        for (final row in (createdFamilies as List)) {
          final familyId = _parseString(row['id']);
          if (familyId.isNotEmpty) {
            familyIds.add(familyId);
          }
        }
      } catch (e) {
        debugPrint('⚠️ createdBy fallback lookup failed: $e');
      }

      // ✅ FIX: Count distinct families (not FamilyMember rows)
      // A user could theoretically have duplicate FamilyMember entries
      final familyTreeCount = familyIds.length;

      // Query persons in user's families
      // ✅ FIX: Filter out soft-deleted persons (deletedAt IS NULL)
      // to match the NestJS backend behavior which also excludes deleted persons
      int personCount = 0;
      try {
        if (familyIds.isNotEmpty) {
          final persons = await client
              .from('Person')
              .select('id')
              .inFilter('familyId', familyIds.toList())
              .filter('deletedAt', 'is', null);
          personCount = (persons as List).length;
        }
      } catch (e) {
        debugPrint('⚠️ Person count query failed: $e');
      }

      // Query relationships in user's families
      // ✅ FIX: Filter out inactive relationships (isActive = true)
      // to match the NestJS backend behavior which also excludes inactive relationships
      int relationshipCount = 0;
      try {
        if (familyIds.isNotEmpty) {
          final relationships = await client
              .from('Relationship')
              .select('id')
              .inFilter('familyId', familyIds.toList())
              .eq('isActive', true);
          relationshipCount = (relationships as List).length;
        }
      } catch (e) {
        debugPrint('⚠️ Relationship count query failed: $e');
      }

      state = state.copyWith(
        stats: UserStatsModel(
          familyTrees: familyTreeCount,
          membersAdded: personCount,
          relations: relationshipCount,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ loadStatsFromSupabase error: $e');
      // Leave stats as default (0s) — don't crash
    }
  }

  // ── Load Profile from Supabase Auth (Fallback) ──────────────────

  /// Creates a basic profile from Supabase Auth user data when the
  /// NestJS backend is unreachable or returns auth errors.
  /// This prevents the app from showing a blank/crashed state.
  Future<void> _loadProfileFromSupabase() async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final user = client.auth.currentUser;
      if (user == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      // Query the User table directly for the full profile
      try {
        final response = await client
            .from('User')
            .select()
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));

        if (response != null) {
          final profile = ProfileModel(
            id: response['id'] as String? ?? user.id,
            email: response['email'] as String? ?? user.email ?? '',
            name: response['name'] as String? ??
                user.userMetadata?['name'] as String? ??
                user.email?.split('@')[0],
            phone: response['phone'] as String?,
            avatarUrl: response['avatarUrl'] as String?,
            bio: response['bio'] as String?,
            dateOfBirth: response['dateOfBirth'] != null
                ? DateTime.tryParse(response['dateOfBirth'].toString())
                : null,
            gender: response['gender'] as String?,
            username: response['username'] as String?,
            preferredLanguage: response['preferredLanguage'] as String? ?? 'en',
            profileVisibility: response['profileVisibility'] as String? ?? 'public',
            invitePermission: response['invitePermission'] as String? ?? 'anyone',
            twoFactorEnabled: response['twoFactorEnabled'] as bool? ?? false,
            createdAt: response['createdAt'] != null
                ? DateTime.tryParse(response['createdAt'].toString()) ?? DateTime.now()
                : DateTime.tryParse(user.createdAt) ?? DateTime.now(),
            updatedAt: DateTime.now(),
          );
          state = state.copyWith(profile: profile, isLoading: false);
          debugPrint('✅ loadProfile: Loaded from Supabase User table');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ loadProfileFromSupabase: User table query failed: $e');
      }

      // Fallback: build profile from auth user metadata only
      final profile = ProfileModel(
        id: user.id,
        email: user.email ?? '',
        name: user.userMetadata?['name'] as String? ??
            user.userMetadata?['full_name'] as String? ??
            user.email?.split('@')[0],
        phone: user.userMetadata?['phone'] as String?,
        avatarUrl: user.userMetadata?['avatar_url'] as String?,
        username: user.userMetadata?['username'] as String?,
        preferredLanguage: user.userMetadata?['preferred_language'] as String? ?? 'en',
        profileVisibility: user.userMetadata?['profileVisibility'] as String? ?? 'public',
        invitePermission: user.userMetadata?['invitePermission'] as String? ?? 'anyone',
        twoFactorEnabled: user.appMetadata['twoFactorEnabled'] as bool? ?? false,
        createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      state = state.copyWith(profile: profile, isLoading: false);
      debugPrint('✅ loadProfile: Using Supabase auth metadata (User table not available)');
    } catch (e) {
      debugPrint('⚠️ loadProfileFromSupabase error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  // ── Update Profile (Optimistic with Rollback) ─────────────────
  //
  // WhatsApp-style: update local state immediately, fire API in
  // background. On failure, roll back to the previous state.
  // No loading spinner is shown for this action.

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    // Save previous state for rollback
    final previousProfile = state.profile;

    // v2.2: Real auth only — guard against no session.
    final client = _ref.read(supabaseProvider);
    if (client?.auth.currentSession == null) {
      // No session — apply optimistically but don't call API
      if (state.profile != null) {
        final optimisticProfile = ProfileModel(
          id: state.profile!.id,
          email: state.profile!.email,
          name: data['name'] as String? ?? state.profile!.name,
          phone: data['phone'] as String? ?? state.profile!.phone,
          avatarUrl: data['avatarUrl'] as String? ?? state.profile!.avatarUrl,
          bio: data['bio'] as String? ?? state.profile!.bio,
          dateOfBirth: data['dateOfBirth'] != null
              ? DateTime.tryParse(data['dateOfBirth'].toString())
              : state.profile!.dateOfBirth,
          gender: data['gender'] as String? ?? state.profile!.gender,
          username: data['username'] as String? ?? state.profile!.username,
          preferredLanguage:
              data['preferredLanguage'] as String? ??
                  state.profile!.preferredLanguage,
          profileVisibility:
              data['profileVisibility'] as String? ??
                  state.profile!.profileVisibility,
          invitePermission:
              data['invitePermission'] as String? ??
                  state.profile!.invitePermission,
          twoFactorEnabled:
              data['twoFactorEnabled'] as bool? ??
                  state.profile!.twoFactorEnabled,
          authProvider: state.profile!.authProvider,
          createdAt: state.profile!.createdAt,
          updatedAt: DateTime.now(),
        );
        state = state.copyWith(profile: optimisticProfile, clearError: true);
      }
      return true;
    }

    // ── Optimistic update: apply changes to local state immediately ──
    if (state.profile != null) {
      final optimisticProfile = ProfileModel(
        id: state.profile!.id,
        email: state.profile!.email,
        name: data['name'] as String? ?? state.profile!.name,
        phone: data['phone'] as String? ?? state.profile!.phone,
        avatarUrl: data['avatarUrl'] as String? ?? state.profile!.avatarUrl,
        bio: data['bio'] as String? ?? state.profile!.bio,
        dateOfBirth: data['dateOfBirth'] != null
            ? DateTime.tryParse(data['dateOfBirth'].toString())
            : state.profile!.dateOfBirth,
        gender: data['gender'] as String? ?? state.profile!.gender,
        username: data['username'] as String? ?? state.profile!.username,
        preferredLanguage:
            data['preferredLanguage'] as String? ??
                state.profile!.preferredLanguage,
        profileVisibility:
            data['profileVisibility'] as String? ??
                state.profile!.profileVisibility,
        invitePermission:
            data['invitePermission'] as String? ??
                state.profile!.invitePermission,
        twoFactorEnabled:
            data['twoFactorEnabled'] as bool? ??
                state.profile!.twoFactorEnabled,
        authProvider: state.profile!.authProvider,
        createdAt: state.profile!.createdAt,
        updatedAt: DateTime.now(),
      );
      state = state.copyWith(profile: optimisticProfile, clearError: true);
    }

    // ── Update directly via Supabase ──────────────────────────────────
    // The NestJS backend's PATCH /api/users/me endpoint currently rejects
    // Supabase JWTs because Supabase has migrated to ES256 signing while
    // the NestJS jwt.strategy.ts still uses HS256 verification. Rather than
    // requiring a server redeploy, we update the User table directly via
    // Supabase (which the Flutter client already has full RLS-authenticated
    // access to). The User table's RLS policy allows each user to UPDATE
    // their own row.
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null || client.auth.currentSession == null) {
        throw Exception('No Supabase session');
      }
      final userId = client.auth.currentUser!.id;

      // Build the update payload with the same field mappings as the
      // NestJS backend (users.service.ts updateProfile).
      final Map<String, dynamic> updateData = {};
      if (data.containsKey('name')) {
        updateData['name'] = (data['name'] as String).trim();
      }
      if (data.containsKey('phone')) {
        final phone = (data['phone'] as String).trim();
        updateData['phone'] = phone.isEmpty ? null : phone;
      }
      if (data.containsKey('username')) {
        final username = (data['username'] as String).trim().toLowerCase();
        updateData['username'] = username.isEmpty ? null : username;
      }
      if (data.containsKey('bio')) {
        final bio = (data['bio'] as String).trim();
        updateData['bio'] = bio.isEmpty ? null : bio;
      }
      if (data.containsKey('dateOfBirth')) {
        final dob = data['dateOfBirth'] as String?;
        updateData['dateOfBirth'] = dob != null ? DateTime.tryParse(dob)?.toUtc() : null;
      }
      if (data.containsKey('gender')) {
        updateData['gender'] = (data['gender'] as String?)?.isNotEmpty == true
            ? data['gender']
            : null;
      }
      if (data.containsKey('avatarUrl')) {
        updateData['avatarUrl'] = data['avatarUrl'];
      }
      if (data.containsKey('preferredLanguage')) {
        updateData['preferredLanguage'] = data['preferredLanguage'];
      }
      if (data.containsKey('profileVisibility')) {
        updateData['profileVisibility'] = data['profileVisibility'];
      }
      if (data.containsKey('invitePermission')) {
        updateData['invitePermission'] = data['invitePermission'];
      }
      updateData['updatedAt'] = DateTime.now().toUtc().toIso8601String();

      // Check for unique constraint on username BEFORE updating
      if (updateData.containsKey('username') && updateData['username'] != null) {
        final existing = await client
            .from('User')
            .select('id')
            .eq('username', updateData['username'])
            .neq('id', userId)
            .limit(1);
        if (existing != null && existing.isNotEmpty) {
          throw Exception('Username "${updateData['username']}" is already taken');
        }
      }

      await client.from('User').update(updateData).eq('id', userId);

      // Reload profile from Supabase to get the persisted state
      await loadProfile();
      return true;
    } catch (e) {
      // ── Rollback: restore previous profile on failure ──
      debugPrint('⚠️ Supabase profile update failed: $e');
      state = state.copyWith(
        profile: previousProfile,
        error: e.toString(),
      );
      return false;
    }
  }

  // ── Upload Avatar ──────────────────────────────────────────────

  Future<bool> uploadAvatar(String filePath) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Try Supabase Storage first
      final client = _ref.read(supabaseProvider);
      if (client != null) {
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          final fileExtension = filePath.split('.').last;
          final storagePath = 'avatars/$userId/profile.$fileExtension';

          // Upload to Supabase Storage
          await client.storage.from('avatars').upload(
            storagePath,
            File(filePath),
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$fileExtension',
            ),
          );

          // Get public URL
          final avatarUrl =
              client.storage.from('avatars').getPublicUrl(storagePath);

          // Persist the avatar URL to Supabase Auth user metadata
          // so it survives app restarts (even when backend is down)
          try {
            await client.auth.updateUser(
              UserAttributes(data: {'avatar_url': avatarUrl}),
            );
          } catch (e) {
            debugPrint('⚠️ Failed to persist avatar URL to user metadata: $e');
          }

          // Also persist to the User table via Supabase (bypasses NestJS
          // which currently rejects Supabase JWTs due to ES256/HS256 mismatch)
          try {
            final sbClient = _ref.read(supabaseProvider);
            if (sbClient != null && sbClient.auth.currentSession != null) {
              await sbClient
                  .from('User')
                  .update({
                    'avatarUrl': avatarUrl,
                    'updatedAt': DateTime.now().toUtc().toIso8601String(),
                  })
                  .eq('id', sbClient.auth.currentUser!.id);
            }
          } catch (e) {
            debugPrint('⚠️ Failed to persist avatar URL to Supabase: $e');
          }

          // Update profile with new avatar URL
          if (state.profile != null) {
            state = state.copyWith(
              profile: ProfileModel(
                id: state.profile!.id,
                email: state.profile!.email,
                name: state.profile!.name,
                phone: state.profile!.phone,
                avatarUrl: avatarUrl,
                bio: state.profile!.bio,
                dateOfBirth: state.profile!.dateOfBirth,
                gender: state.profile!.gender,
                username: state.profile!.username,
                preferredLanguage: state.profile!.preferredLanguage,
                profileVisibility: state.profile!.profileVisibility,
                invitePermission: state.profile!.invitePermission,
                twoFactorEnabled: state.profile!.twoFactorEnabled,
                authProvider: state.profile!.authProvider,
                createdAt: state.profile!.createdAt,
                updatedAt: DateTime.now(),
              ),
              isLoading: false,
            );
          } else {
            state = state.copyWith(isLoading: false);
          }
          return true;
        }
      }

      // Fallback to backend API
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath),
      });
      final response = await _dio.put(
        '/api/users/me/avatar',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final profile = ProfileModel.fromJson(
        _extractUserData(response.data as Map<String, dynamic>),
      );
      state = state.copyWith(profile: profile, isLoading: false);
      return true;
    } on StorageException catch (e) {
      // ✅ FIX (BUG-11): Don't crash if 'avatars' bucket doesn't exist in Supabase
      debugPrint('⚠️ Avatar upload failed (bucket not found): ${e.message}');
      state = state.copyWith(isLoading: false);
      return false;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to upload avatar';
      state = state.copyWith(isLoading: false, error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  // ── Change Password ────────────────────────────────────────────

  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Try Supabase Auth first (works even when backend is down)
      final client = _ref.read(supabaseProvider);
      if (client != null) {
        // Supabase requires re-authentication before password change
        // Update the user's password directly
        await client.auth.updateUser(
          UserAttributes(password: newPassword),
        );
        state = state.copyWith(isLoading: false);
        return true;
      }

      // Fallback to backend API
      await _dio.post(
        '/api/auth/change-password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to change password';
      state = state.copyWith(isLoading: false, error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  // ── Check Username ─────────────────────────────────────────────

  Future<Map<String, dynamic>?> checkUsername(String username) async {
    try {
      final response = await _dio.get(
        '/api/users/check-username',
        queryParameters: {'username': username},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('⚠️ checkUsername error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('⚠️ checkUsername error: $e');
      return null;
    }
  }

  // ── Set Username ───────────────────────────────────────────────

  Future<bool> setUsername(String username) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _dio.patch(
        '/api/users/me/username',
        data: {'username': username},
      );
      final profile = ProfileModel.fromJson(
        _extractUserData(response.data as Map<String, dynamic>),
      );
      state = state.copyWith(profile: profile, isLoading: false);
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Failed to set username';
      state = state.copyWith(isLoading: false, error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  // ── Two-Factor Authentication ──────────────────────────────────

  Future<TwoFASetupResponse?> setup2FA() async {
    try {
      final response = await _dio.post('/api/auth/2fa/setup');
      return TwoFASetupResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Failed to setup 2FA';
      state = state.copyWith(error: message.toString());
      return null;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> verify2FA(String code) async {
    try {
      await _dio.post('/api/auth/2fa/verify', data: {'code': code});
      // Refresh profile to update twoFactorEnabled flag
      await loadProfile();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Failed to verify 2FA';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> disable2FA(String password) async {
    try {
      await _dio.delete('/api/auth/2fa', data: {'password': password});
      // Refresh profile to update twoFactorEnabled flag
      await loadProfile();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Failed to disable 2FA';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Sessions ───────────────────────────────────────────────────

  Future<void> loadSessions() async {
    // v2.2: Real auth only — guard against no session.
    final client = _ref.read(supabaseProvider);
    if (client?.auth.currentSession == null) {
      // No session — return empty sessions
      state = state.copyWith(sessions: []);
      return;
    }

    try {
      final response = await _dio.get('/api/auth/sessions');

      // Defensive: handle both array response and wrapped object response
      List<dynamic> listData;
      if (response.data is List) {
        listData = response.data as List;
      } else if (response.data is Map) {
        final map = response.data as Map;
        // Try common wrapper keys
        listData = (map['sessions'] ?? map['data'] ?? map['items'] ?? []) as List;
      } else {
        listData = [];
      }

      final list = listData
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(sessions: list);
    } on DioException catch (e) {
      debugPrint('⚠️ loadSessions error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ loadSessions error: $e');
    }
  }

  Future<bool> revokeSession(String sessionId) async {
    try {
      await _dio.delete('/api/auth/sessions/$sessionId');
      // Refresh sessions list
      await loadSessions();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to revoke session';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> revokeAllOtherSessions() async {
    try {
      await _dio.delete('/api/auth/sessions/all-except-current');
      // Refresh sessions list
      await loadSessions();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to revoke sessions';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Families ───────────────────────────────────────────────────

  Future<void> loadFamilies() async {
    // v2.2: Real auth only — guard against no session.
    final client = _ref.read(supabaseProvider);
    if (client?.auth.currentSession == null) {
      state = state.copyWith(families: []);
      return;
    }

    try {
      final response = await _dio.get('/api/users/me/families');

      // Defensive: handle both array and wrapped object response
      List<dynamic> listData;
      if (response.data is List) {
        listData = response.data as List;
      } else if (response.data is Map) {
        final map = response.data as Map;
        listData = (map['families'] ?? map['data'] ?? map['items'] ?? []) as List;
      } else {
        listData = [];
      }

      final list = listData
          .map((e) => FamilyTreeNode.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(families: list);
    } on DioException catch (e) {
      debugPrint('⚠️ loadFamilies error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ loadFamilies error: $e');
    }
  }

  /// Leave a family by its ID. Returns `true` on success.
  Future<bool> leaveFamily(String familyId) async {
    try {
      await _dio.delete('/api/families/$familyId/leave');
      // Refresh the families list
      await loadFamilies();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to leave family';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Fetch KIN Family IDs for all families.
  /// For each family that doesn't have a kinFamilyId, calls
  /// GET /api/families/:id/family-id to auto-generate missing KIN IDs.
  /// Updates the families list with the fetched kinFamilyId values.
  Future<void> loadFamilyIds() async {
    try {
      final response = await _dio.get('/api/users/me/families');
      final families = (response.data as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();

      // For each family that doesn't have a kinFamilyId, fetch/generate one
      final updatedFamilies = <FamilyTreeNode>[];
      for (final familyData in families) {
        final familyId = familyData['id']?.toString() ?? '';
        var kinFamilyId = familyData['kinFamilyId'] as String?;

        if (kinFamilyId == null || kinFamilyId.isEmpty) {
          try {
            final idResponse = await _dio.get('/api/families/$familyId/family-id');
            kinFamilyId = idResponse.data?['kinFamilyId'] as String?;
          } catch (e) {
            debugPrint('⚠️ Failed to fetch KIN ID for family $familyId: $e');
          }
        }

        updatedFamilies.add(FamilyTreeNode(
          id: familyId,
          name: familyData['name']?.toString() ?? 'Unnamed',
          username: familyData['username'] as String?,
          role: familyData['role']?.toString() ?? 'member',
          memberCount: familyData['memberCount'] as int? ?? 0,
          kinFamilyId: kinFamilyId,
        ));
      }

      // Update families list with KIN IDs included
      state = state.copyWith(families: updatedFamilies);
    } on DioException catch (e) {
      debugPrint('⚠️ loadFamilyIds error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ loadFamilyIds error: $e');
    }
  }

  // ── Invitations ────────────────────────────────────────────────

  Future<void> loadInvitations() async {
    // v2.2: Real auth only — guard against no session.
    final client = _ref.read(supabaseProvider);
    if (client?.auth.currentSession == null) {
      state = state.copyWith(invitations: []);
      return;
    }

    try {
      final response = await _dio.get('/api/users/me/invitations');

      // Defensive: handle both array and wrapped object response
      List<dynamic> listData;
      if (response.data is List) {
        listData = response.data as List;
      } else if (response.data is Map) {
        final map = response.data as Map;
        listData = (map['invitations'] ?? map['data'] ?? map['items'] ?? []) as List;
      } else {
        listData = [];
      }

      final list = listData
          .map((e) => InvitationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(invitations: list);
    } on DioException catch (e) {
      debugPrint('⚠️ loadInvitations error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ loadInvitations error: $e');
    }
  }

  Future<bool> acceptInvitation(String id) async {
    try {
      await _dio.post('/api/invitations/$id/accept');
      // Refresh invitations and families
      await loadInvitations();
      await loadFamilies();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to accept invitation';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> declineInvitation(String id) async {
    try {
      await _dio.post('/api/invitations/$id/decline');
      // Refresh invitations
      await loadInvitations();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to decline invitation';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Blocked Users ──────────────────────────────────────────────

  Future<void> loadBlockedUsers() async {
    // v2.2: Real auth only — guard against no session.
    final client = _ref.read(supabaseProvider);
    if (client?.auth.currentSession == null) {
      state = state.copyWith(blockedUsers: []);
      return;
    }

    try {
      final response = await _dio.get('/api/users/me/blocked');
      final list = (response.data as List)
          .map((e) => BlockedUserModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(blockedUsers: list);
    } on DioException catch (e) {
      debugPrint('⚠️ loadBlockedUsers error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ loadBlockedUsers error: $e');
    }
  }

  Future<bool> unblockUser(String userId) async {
    try {
      await _dio.delete('/api/users/me/blocked/$userId');
      // Refresh blocked users list
      await loadBlockedUsers();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Failed to unblock user';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Data Export ────────────────────────────────────────────────

  Future<bool> requestDataExport() async {
    try {
      await _dio.post('/api/users/me/data-export');
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to request data export';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Delete Account ─────────────────────────────────────────────

  Future<bool> deleteAccount(String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _dio.delete('/api/users/me', data: {'password': password});
      // Sign out after account deletion
      await logout();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to delete account';
      state = state.copyWith(isLoading: false, error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  // ── Export Family Tree ─────────────────────────────────────────

  Future<bool> exportFamilyTree(String familyId, String format) async {
    try {
      await _dio.post(
        '/api/families/$familyId/export',
        data: {'format': format},
      );
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to export family tree';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Support Ticket ─────────────────────────────────────────────

  Future<bool> submitSupportTicket(Map<String, dynamic> data) async {
    try {
      await _dio.post('/api/support/tickets', data: data);
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to submit ticket';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Quiet Hours ────────────────────────────────────────────────

  Future<bool> updateQuietHours(String start, String end, bool enabled) async {
    try {
      await _dio.put(
        '/api/users/me/quiet-hours',
        data: {'start': start, 'end': end, 'enabled': enabled},
      );
      // Refresh profile to reflect updated quiet hours
      await loadProfile();
      return true;
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to update quiet hours';
      state = state.copyWith(error: message.toString());
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Logout ─────────────────────────────────────────────────────

  Future<void> logout() async {
    // Get userId BEFORE signing out (auth is cleared by signOut())
    String? userId;
    try {
      final client = _ref.read(supabaseProvider);
      userId = client?.auth.currentUser?.id;
    } catch (_) {}

    try {
      // Notify backend to invalidate session
      await _dio.post('/api/auth/logout');
    } catch (_) {
      // Continue with local sign-out even if backend call fails
    }

    try {
      // Sign out from Supabase (clears local session)
      final authService = _ref.read(authServiceProvider);
      await authService.signOut();
    } catch (_) {
      // Ignore sign-out errors
    }

    // Clear Isar cache on logout
    if (IsarDatabase.isInitialized) {
      try {
        // Clear only THIS user's cached families (not all users on device)
        if (userId != null) {
          await IsarDatabase.clearFamiliesForUser(userId);
        }
        // Clear all other cache (profiles, persons, relationships, etc.)
        await IsarDatabase.clearCache(includePendingOps: true);
      } catch (_) {}
    }

    // Clear all profile state
    state = const ProfileState();
  }
}

// ════════════════════════════════════════════════════════════════════
// PROVIDER
// ════════════════════════════════════════════════════════════════════

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>((
  ref,
) {
  return ProfileNotifier(ref);
});

// ── Computed Providers (Zero Rebuild Optimizations) ────────────────

/// Computed: whether profile is loading
final profileIsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(profileProvider).isLoading;
});

/// Computed: profile name only
final profileNameProvider = Provider<String?>((ref) {
  return ref.watch(profileProvider).profile?.name;
});

/// Computed: profile avatar URL only
final profileAvatarUrlProvider = Provider<String?>((ref) {
  return ref.watch(profileProvider).profile?.avatarUrl;
});

/// Computed: profile stats
final profileStatsProvider = Provider<UserStatsModel?>((ref) {
  return ref.watch(profileProvider).stats;
});

/// Computed: pending invitation count
final pendingInvitationCountProvider = Provider<int>((ref) {
  return ref
      .watch(profileProvider)
      .invitations
      .where((i) => i.status == 'pending')
      .length;
});
