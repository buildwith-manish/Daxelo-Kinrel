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
  };
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
  });

  factory FamilyTreeNode.fromJson(Map<String, dynamic> json) {
    return FamilyTreeNode(
      id: _parseString(json['id']),
      name: _parseString(json['name']),
      username: json['username'] as String?,
      role: _parseString(json['role'], fallback: 'member'),
      memberCount: _parseInt(json['memberCount']),
    );
  }

  final String id;
  final String name;
  final String? username;
  final String role;
  final int memberCount;
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
  });

  final ProfileModel? profile;
  final UserStatsModel? stats;
  final bool isLoading;
  final String? error;
  final List<SessionModel> sessions;
  final List<FamilyTreeNode> families;
  final List<InvitationModel> invitations;
  final List<BlockedUserModel> blockedUsers;

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

  // ── Load Profile ───────────────────────────────────────────────

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true, clearError: true);

    // Try offline-first repository first if Isar is initialized
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        final profile = await repo.getProfile();
        if (profile != null) {
          state = state.copyWith(profile: profile, isLoading: false);
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Offline profile load failed, trying API: $e');
      }
    }

    // Fallback to direct API call (original behavior)
    try {
      final response = await _dio.get('/api/users/me');
      final profile = ProfileModel.fromJson(
        _extractUserData(response.data as Map<String, dynamic>),
      );
      state = state.copyWith(profile: profile, isLoading: false);
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Failed to load profile';
      state = state.copyWith(isLoading: false, error: message.toString());
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Load Stats ─────────────────────────────────────────────────

  Future<void> loadStats() async {
    // Try offline-first repository first if Isar is initialized
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        final stats = await repo.getStats();
        if (stats != null) {
          state = state.copyWith(stats: stats);
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Offline stats load failed, trying API: $e');
      }
    }

    // Fallback to direct API call (original behavior)
    try {
      final response = await _dio.get('/api/users/me/stats');
      final stats = UserStatsModel.fromJson(
        response.data as Map<String, dynamic>,
      );
      state = state.copyWith(stats: stats);
    } on DioException catch (e) {
      debugPrint('⚠️ loadStats backend error, trying Supabase: ${e.message}');
      await _loadStatsFromSupabase();
    } catch (e) {
      debugPrint('⚠️ loadStats error, trying Supabase: $e');
      await _loadStatsFromSupabase();
    }
  }

  Future<void> _loadStatsFromSupabase() async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;

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

      // Query persons in user's families
      int personCount = 0;
      try {
        if (familyIds.isNotEmpty) {
          final persons = await client
              .from('Person')
              .select('id')
              .inFilter('familyId', familyIds.toList());
          personCount = (persons as List).length;
        }
      } catch (e) {
        debugPrint('⚠️ Person count query failed: $e');
      }

      // Query relationships in user's families
      int relationshipCount = 0;
      try {
        if (familyIds.isNotEmpty) {
          final relationships = await client
              .from('Relationship')
              .select('id')
              .inFilter('familyId', familyIds.toList());
          relationshipCount = (relationships as List).length;
        }
      } catch (e) {
        debugPrint('⚠️ Relationship count query failed: $e');
      }

      state = state.copyWith(
        stats: UserStatsModel(
          familyTrees: (familyMembers as List).length,
          membersAdded: personCount,
          relations: relationshipCount,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ loadStatsFromSupabase error: $e');
      // Leave stats as default (0s) — don't crash
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

    // ── Fire API call in background ──

    // Try offline-first repository first if Isar is initialized
    if (IsarDatabase.isInitialized) {
      try {
        final repo = _ref.read(offlineProfileRepositoryProvider);
        final success = await repo.updateProfile(data);
        if (success) {
          // Reload profile to get the updated cached data
          await loadProfile();
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ Offline profile update failed, trying API: $e');
      }
    }

    // Fallback to direct API call (original behavior)
    try {
      final response = await _dio.patch('/api/users/me', data: data);
      final profile = ProfileModel.fromJson(
        _extractUserData(response.data as Map<String, dynamic>),
      );
      state = state.copyWith(profile: profile);
      return true;
    } on DioException catch (e) {
      // ── Rollback: restore previous profile on failure ──
      final message =
          e.response?.data?['message'] ??
          e.message ??
          'Failed to update profile';
      state = state.copyWith(
        profile: previousProfile,
        error: message.toString(),
      );
      return false;
    } catch (e) {
      // ── Rollback on any other error ──
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

          // Also try to persist to the backend via API
          try {
            await _dio.patch('/api/users/me', data: {'avatarUrl': avatarUrl});
          } catch (e) {
            debugPrint('⚠️ Failed to persist avatar URL to backend: $e');
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
    try {
      final response = await _dio.get('/api/auth/sessions');
      final list = (response.data as List)
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
    try {
      final response = await _dio.get('/api/users/me/families');
      final list = (response.data as List)
          .map((e) => FamilyTreeNode.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(families: list);
    } on DioException catch (e) {
      debugPrint('⚠️ loadFamilies error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ loadFamilies error: $e');
    }
  }

  // ── Invitations ────────────────────────────────────────────────

  Future<void> loadInvitations() async {
    try {
      final response = await _dio.get('/api/users/me/invitations');
      final list = (response.data as List)
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
