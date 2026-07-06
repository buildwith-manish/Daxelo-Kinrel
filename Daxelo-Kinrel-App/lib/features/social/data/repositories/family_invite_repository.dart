import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/networking/dio_client.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/family_invite_model.dart';

class FamilyInviteRepository {
  FamilyInviteRepository(this._ref);
  final Ref _ref;

  /// Generate a family invite.
  /// Uses the Supabase RPC fn_generate_family_invite (bypasses the NestJS
  /// backend which currently rejects Supabase JWTs due to ES256/HS256
  /// mismatch).
  Future<FamilyInviteModel> generateInvite({
    required String familyId,
    int? expiryDays,
    int? maxUses,
  }) async {
    final client = _ref.read(supabaseProvider);
    if (client == null || client.auth.currentSession == null) {
      throw Exception('Not signed in');
    }

    final result = await client.rpc(
      'fn_generate_family_invite',
      params: {
        'p_family_id': familyId,
        'p_expiry_days': expiryDays ?? 7,
        'p_max_uses': maxUses ?? 0,
      },
    ).timeout(const Duration(seconds: 15));

    final rows = (result as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      throw Exception('Failed to generate invite');
    }

    final row = rows.first;
    return FamilyInviteModel(
      id: row['id'] as String? ?? '',
      familyId: row['family_id'] as String? ?? familyId,
      token: row['token'] as String? ?? '',
      creatorId: _ref.read(supabaseProvider)?.auth.currentUser?.id ?? '',
      expiresAt: row['expires_at'] != null
          ? DateTime.tryParse(row['expires_at'].toString())
          : null,
      maxUses: row['max_uses'] as int?,
      useCount: row['current_uses'] as int? ?? 0,
      active: true,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Revoke all active invites for a family.
  /// Uses Supabase directly (bypasses NestJS).
  Future<void> revokeInvites(String familyId) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) throw Exception('Not signed in');
    await client
        .from('FamilyInvite')
        .update({'active': false, 'status': 'expired', 'updatedAt': DateTime.now().toUtc().toIso8601String()})
        .eq('familyId', familyId)
        .eq('active', true);
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
