// lib/data/repositories/family_invite_repository.dart
//
// DAXELO KINREL — Family Invite Repository
//
// Handles family invite link generation, revocation, preview, and
// member management operations.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/dio_client.dart';
import '../models/family_invite_model.dart';

/// Abstract interface for family invite operations.
abstract class FamilyInviteRepository {
  Future<FamilyInviteModel> generateInviteLink(
    String familyId, {
    int? expiresInDays,
    int? maxUses,
  });

  Future<void> revokeInviteLinks(String familyId);
  Future<FamilyJoinPreviewModel> previewJoin(String token);
  Future<void> joinFamily(String token);
  Future<void> leaveFamily(String familyId);
  Future<void> removeMember(String familyId, String userId);
  Future<void> changeMemberRole(String familyId, String userId, String role);
  Future<void> transferOwnership(String familyId, String userId);
  Future<void> updateFamilyPrivacy(String familyId, {required bool isPublic});
}

/// Concrete implementation using the Dio HTTP client.
class FamilyInviteRepositoryImpl implements FamilyInviteRepository {
  FamilyInviteRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<FamilyInviteModel> generateInviteLink(
    String familyId, {
    int? expiresInDays,
    int? maxUses,
  }) async {
    final response = await _dio.post(
      '/v1/families/$familyId/invites',
      data: {
        if (expiresInDays != null) 'expiresInDays': expiresInDays,
        if (maxUses != null) 'maxUses': maxUses,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('data')) {
      return FamilyInviteModel.fromJson(
        data['data'] as Map<String, dynamic>,
      );
    }
    if (data is Map<String, dynamic>) {
      return FamilyInviteModel.fromJson(data);
    }
    throw Exception('Invalid response generating invite link');
  }

  @override
  Future<void> revokeInviteLinks(String familyId) async {
    await _dio.delete('/v1/families/$familyId/invites');
  }

  @override
  Future<FamilyJoinPreviewModel> previewJoin(String token) async {
    final response = await _dio.get('/v1/families/invite/$token/preview');
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('data')) {
      return FamilyJoinPreviewModel.fromJson(
        data['data'] as Map<String, dynamic>,
      );
    }
    if (data is Map<String, dynamic>) {
      return FamilyJoinPreviewModel.fromJson(data);
    }
    throw Exception('Invalid response previewing invite');
  }

  @override
  Future<void> joinFamily(String token) async {
    await _dio.post('/v1/families/invite/$token/join');
  }

  @override
  Future<void> leaveFamily(String familyId) async {
    await _dio.post('/v1/families/$familyId/leave');
  }

  @override
  Future<void> removeMember(String familyId, String userId) async {
    await _dio.delete('/v1/families/$familyId/members/$userId');
  }

  @override
  Future<void> changeMemberRole(
    String familyId,
    String userId,
    String role,
  ) async {
    await _dio.patch(
      '/v1/families/$familyId/members/$userId/role',
      data: {'role': role},
    );
  }

  @override
  Future<void> transferOwnership(String familyId, String userId) async {
    await _dio.post(
      '/v1/families/$familyId/transfer-ownership',
      data: {'newOwnerId': userId},
    );
  }

  @override
  Future<void> updateFamilyPrivacy(
    String familyId, {
    required bool isPublic,
  }) async {
    await _dio.patch(
      '/v1/families/$familyId/privacy',
      data: {'isPublic': isPublic},
    );
  }
}

/// Provider for the family invite repository.
final familyInviteRepositoryProvider = Provider<FamilyInviteRepository>((ref) {
  return FamilyInviteRepositoryImpl(ref.read(dioProvider));
});
