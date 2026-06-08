import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/networking/dio_client.dart';
import '../models/family_invite_model.dart';

class FamilyInviteRepository {
  FamilyInviteRepository(this._ref);
  final Ref _ref;

  /// Generate a family invite
  Future<FamilyInviteModel> generateInvite({
    required String familyId,
    int? expiryDays,
    int? maxUses,
  }) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('/families/$familyId/invite', data: {
      if (expiryDays != null) 'expiryDays': expiryDays,
      if (maxUses != null) 'maxUses': maxUses,
    });
    return FamilyInviteModel.fromJson(response.data);
  }

  /// Revoke all active invites for a family
  Future<void> revokeInvites(String familyId) async {
    final dio = _ref.read(dioProvider);
    await dio.post('/families/$familyId/invite/revoke');
  }

  /// Preview a family from a token (no auth required)
  Future<FamilyJoinPreviewModel> previewFamily(String token) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/families/invite/$token/preview');
    return FamilyJoinPreviewModel.fromJson(response.data);
  }

  /// Join a family using a token
  Future<void> joinFamily(String token) async {
    final dio = _ref.read(dioProvider);
    await dio.post('/families/invite/$token/join');
  }

  /// Toggle family visibility (public/private)
  Future<void> toggleVisibility(String familyId, bool isPublic) async {
    final dio = _ref.read(dioProvider);
    await dio.patch('/families/$familyId/visibility', data: {'isPublic': isPublic});
  }

  /// Leave a family
  Future<void> leaveFamily(String familyId) async {
    final dio = _ref.read(dioProvider);
    await dio.delete('/families/$familyId/leave');
  }
}

final familyInviteRepositoryProvider = Provider<FamilyInviteRepository>((ref) {
  return FamilyInviteRepository(ref);
});
