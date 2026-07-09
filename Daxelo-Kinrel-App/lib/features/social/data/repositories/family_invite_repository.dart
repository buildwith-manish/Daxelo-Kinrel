import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgrest/postgrest.dart';
import '../../../../core/config/env_config.dart';
import '../../../../core/networking/dio_client.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/invite_message_builder.dart';
import '../models/family_invite_model.dart';

class FamilyInviteRepository {
  FamilyInviteRepository(this._ref);
  final Ref _ref;

  /// Generate a family invite.
  /// Uses the Supabase RPC fn_generate_family_invite (bypasses the NestJS
  /// backend which currently rejects Supabase JWTs due to ES256/HS256
  /// mismatch).
  ///
  /// The RPC is SECURITY DEFINER so it runs with elevated privileges —
  /// RLS doesn't block the INSERT inside the function. The function:
  ///   1. Validates the caller is a family member (raises P0001 if not)
  ///   2. Generates a random token
  ///   3. INSERTs into FamilyInvite (with correct column names)
  ///   4. RETURN QUERYs the invite details
  ///
  /// If the RPC raises an exception (e.g. "You are not a member of this
  /// family"), the Supabase client throws a PostgrestException — we
  /// catch it and surface the actual error message instead of the
  /// generic "Failed to generate invite".
  Future<FamilyInviteModel> generateInvite({
    required String familyId,
    int? expiryDays,
    int? maxUses,
  }) async {
    final client = _ref.read(supabaseProvider);
    if (client == null || client.auth.currentSession == null) {
      throw Exception('Not signed in. Please restart the app and try again.');
    }

    try {
      final result = await client.rpc(
        'fn_generate_family_invite',
        params: {
          'p_family_id': familyId,
          'p_expiry_days': expiryDays ?? 7,
          'p_max_uses': maxUses ?? 0,
        },
      ).timeout(const Duration(seconds: 15));

      // The RPC returns a TABLE — a list of rows. On success it returns
      // exactly one row. On failure it raises an exception (caught below).
      final rows = (result as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        throw Exception(
          'The invite function returned no rows. This may indicate a '
          'database schema issue — please contact support.',
        );
      }

      final row = rows.first;
      return FamilyInviteModel(
        // The RPC returns "invite_id" (not "id") to avoid PostgREST's
        // "column reference 'id' is ambiguous" error. Fall back to
        // "id" for backward compatibility with older function versions.
        id: (row['invite_id'] ?? row['id']) as String? ?? '',
        familyId: row['family_id'] as String? ?? familyId,
        token: row['token'] as String? ?? '',
        creatorId:
            _ref.read(supabaseProvider)?.auth.currentUser?.id ?? '',
        expiresAt: row['expires_at'] != null
            ? DateTime.tryParse(row['expires_at'].toString())
            : null,
        maxUses: row['max_uses'] as int?,
        useCount: row['current_uses'] as int? ?? 0,
        active: true,
        createdAt: row['created_at'] != null
            ? DateTime.tryParse(row['created_at'].toString()) ??
                DateTime.now()
            : DateTime.now(),
      );
    } on PostgrestException catch (e) {
      // The RPC raised a database-level exception. Surface the actual
      // message (e.g. "You are not a member of this family") instead
      // of the generic "Failed to generate invite".
      throw Exception(_friendlyRpcError(e));
    } on FormatException catch (e) {
      throw Exception('Unexpected response from server: ${e.message}');
    } catch (e) {
      // Network timeout, connection error, etc.
      if (e.toString().contains('Timeout') ||
          e.toString().contains('timeout')) {
        throw Exception(
          'The request timed out. Please check your internet connection '
          'and try again.',
        );
      }
      throw Exception('Could not generate invite: $e');
    }
  }

  /// Convert a PostgrestException from the RPC into a user-friendly
  /// message. The RPC raises P0001 exceptions with human-readable
  /// messages like "You are not a member of this family".
  String _friendlyRpcError(PostgrestException e) {
    final msg = e.message ?? '';
    // P0001 = RAISE EXCEPTION in plpgsql — these are intentional,
    // human-readable validation errors from the function.
    if (e.code == 'P0001' && msg.isNotEmpty) {
      return msg;
    }
    // 42501 = insufficient_privilege — RLS blocked the operation.
    if (e.code == '42501') {
      return 'You do not have permission to create invites for this family. '
          'Ask the family owner to grant you member or admin access.';
    }
    // Fall back to the raw message for anything else.
    return 'Invite generation failed: $msg';
  }

  /// Revoke all active invites for a family.
  /// Uses Supabase directly (bypasses NestJS).
  ///
  /// Note: the FamilyInvite table has NO "updatedAt" column — the
  /// previous version of this method tried to set updatedAt which
  // caused a silent failure. Fixed to only set columns that exist.
  Future<void> revokeInvites(String familyId) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) throw Exception('Not signed in');
    await client
        .from('FamilyInvite')
        .update({
          'active': false,
          'status': 'expired',
        })
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
    await dio.patch('/families/$familyId/visibility',
        data: {'isPublic': isPublic});
  }

  /// Leave a family
  Future<void> leaveFamily(String familyId) async {
    final dio = _ref.read(dioProvider);
    await dio.delete('/families/$familyId/leave');
  }

  /// Generate an invite link and build a pre-filled share message
  /// for direct inviting by phone or email.
  ///
  /// This generates the invite via the same RPC as [generateInvite],
  /// then constructs the invite URL and builds a localized message
  /// using [InviteMessageBuilder]. The caller (UI) opens the native
  /// share sheet with this message pre-filled — the user can then
  /// pick SMS, email, WhatsApp, etc. to send it to their contact.
  ///
  /// Returns a record with the invite URL and the pre-filled message.
  Future<({String inviteUrl, String message})> generateInviteForDirectShare({
    required String familyId,
    required String familyName,
    String langCode = 'en',
  }) async {
    final invite = await generateInvite(familyId: familyId);

    // Build the invite URL — same pattern as the invite screen.
    final inviteUrl =
        '${EnvConfig.appDeepLinkScheme}://join/${invite.token}';

    // Build a localized invite message using the existing
    // InviteMessageBuilder for consistent wording across the app.
    final message = InviteMessageBuilder.build(
      familyName,
      inviteUrl,
      langCode,
    );

    return (inviteUrl: inviteUrl, message: message);
  }
}

final familyInviteRepositoryProvider = Provider<FamilyInviteRepository>((ref) {
  return FamilyInviteRepository(ref);
});
