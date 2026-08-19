// lib/features/family/presentation/providers/graph_pending_invitations_provider.dart
//
// DAXELO KINREL — v5.41 Graph Pending Invitations Provider
//
// Provides Riverpod state for the "Pending Invitations" system that
// stores graph-originated invitations BEFORE the invitee accepts.
//
// When a user invites someone from the Family Graph (long-press a node
// → "Invite"), the app calls `fn_create_graph_pending_invitation` which
// stores the invitation in the `GraphPendingInvitation` table WITHOUT
// creating a Person node. This keeps the graph clean — only confirmed
// members appear as nodes.
//
// This provider:
//   • Fetches pending invitations for a family via
//     `fn_get_pending_graph_invitations` RPC
//   • Exposes helpers to create / cancel invitations
//   • Auto-refreshes on Supabase Realtime changes to the
//     GraphPendingInvitation table
//
// The acceptance flow is handled by `fn_accept_graph_invitation` which
// creates the Person + Relationship + reciprocal edge in one atomic
// transaction. The acceptee's app calls that RPC (from the Notifications
// screen or a deep link) — NOT this provider.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';

/// A single pending graph invitation.
class GraphPendingInvitation {
  final String id;
  final String familyId;
  final String inviterUserId;
  final String? inviterName;
  final String targetPersonId;
  final String? targetPersonName;
  final String relationshipKey; // fundamental edge type: 'parent' | 'spouse' | etc.
  final String specificLabelAtoB; // specific label: 'father' | 'brother' | etc.
  final String? recipientName;
  final String? recipientEmail;
  final String? recipientPhone;
  final String? recipientUserId; // v5.44: Kinrel user ID (for Find on Kinrel invites)
  final String status; // 'pending' | 'accepted' | 'declined' | 'cancelled' | 'expired'
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final String? inviteCode;

  const GraphPendingInvitation({
    required this.id,
    required this.familyId,
    required this.inviterUserId,
    this.inviterName,
    required this.targetPersonId,
    this.targetPersonName,
    required this.relationshipKey,
    required this.specificLabelAtoB,
    this.recipientName,
    this.recipientEmail,
    this.recipientPhone,
    this.recipientUserId,
    required this.status,
    this.expiresAt,
    this.createdAt,
    this.inviteCode,
  });

  factory GraphPendingInvitation.fromJson(Map<String, dynamic> json) {
    return GraphPendingInvitation(
      id: json['id'] as String,
      familyId: json['familyId'] as String,
      inviterUserId: json['inviterUserId'] as String,
      inviterName: json['inviterName'] as String?,
      targetPersonId: json['targetPersonId'] as String,
      targetPersonName: json['targetPersonName'] as String?,
      relationshipKey: json['relationshipKey'] as String,
      specificLabelAtoB: json['specificLabelAtoB'] as String,
      recipientName: json['recipientName'] as String?,
      recipientEmail: json['recipientEmail'] as String?,
      recipientPhone: json['recipientPhone'] as String?,
      recipientUserId: json['recipientUserId'] as String?,
      status: json['status'] as String,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      inviteCode: json['inviteCode'] as String?,
    );
  }

  /// Human-readable label for the relationship, e.g. "Father of Manish".
  String get relationshipDescription {
    final label = specificLabelAtoB.replaceAll('_', ' ');
    final target = targetPersonName ?? 'a family member';
    // Capitalize first letter
    final capitalized =
        label.isEmpty ? label : '${label[0].toUpperCase()}${label.substring(1)}';
    return '$capitalized of $target';
  }

  /// Display name for the recipient (name > email > phone > 'Unknown').
  String get recipientDisplayName {
    if (recipientName != null && recipientName!.isNotEmpty) {
      return recipientName!;
    }
    if (recipientEmail != null && recipientEmail!.isNotEmpty) {
      return recipientEmail!;
    }
    if (recipientPhone != null && recipientPhone!.isNotEmpty) {
      return recipientPhone!;
    }
    return 'Unknown recipient';
  }
}

/// AsyncNotifier that fetches + caches pending graph invitations for a family.
class GraphPendingInvitationsNotifier
    extends FamilyAsyncNotifier<List<GraphPendingInvitation>, String> {
  Timer? _debounceTimer;

  @override
  Future<List<GraphPendingInvitation>> build(String familyId) async {
    // Set up realtime subscription to refresh when invitations change
    _setupRealtime(familyId);
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });
    return _fetchPendingInvitations(familyId);
  }

  Future<List<GraphPendingInvitation>> _fetchPendingInvitations(
      String familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return [];

    try {
      final response = await client
          .rpc('fn_get_pending_graph_invitations', params: {
        'p_family_id': familyId,
      }).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>;
      if (result['success'] == true) {
        final invitations = result['invitations'] as List<dynamic>;
        return invitations
            .map((e) =>
                GraphPendingInvitation.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      // Silently fail — the graph should still render even if invitations
      // can't be fetched (e.g. the RPC doesn't exist yet on this DB).
      debugPrint('[graphPendingInvitations] fetch error: $e');
      return [];
    }
  }

  void _setupRealtime(String familyId) {
    final client = ref.read(supabaseProvider);
    if (client == null) return;

    try {
      void invalidateIfNeeded() {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
          ref.invalidateSelf();
        });
      }

      final channel = client
          .channel('graph_pending_invitations_$familyId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'GraphPendingInvitation',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'familyId',
              value: familyId,
            ),
            callback: (_) => invalidateIfNeeded(),
          )
          .subscribe();

      ref.onDispose(() {
        _debounceTimer?.cancel();
        client.removeChannel(channel);
      });
    } catch (e) {
      // Realtime is best-effort — don't crash if it fails
      debugPrint('[graphPendingInvitations] realtime setup error: $e');
    }
  }

  /// Creates a new pending graph invitation.
  /// Returns the invitation ID on success, or null on failure.
  ///
  /// v5.43: Added [recipientUserId] parameter for Find-on-Kinrel invites.
  /// When set, a `graph_invite` notification is sent to that user so they
  /// see the invitation in their Notifications screen.
  Future<String?> createInvitation({
    required String familyId,
    required String targetPersonId,
    required String relationshipKey,
    required String specificLabel,
    String? recipientName,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
  }) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return null;

    try {
      final response = await client.rpc(
        'fn_create_graph_pending_invitation',
        params: {
          'p_family_id': familyId,
          'p_target_person_id': targetPersonId,
          'p_relationship_key': relationshipKey,
          'p_specific_label': specificLabel,
          'p_recipient_name': recipientName,
          'p_recipient_email': recipientEmail,
          'p_recipient_phone': recipientPhone,
          'p_recipient_user_id': recipientUserId,
        },
      ).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>;
      if (result['success'] == true) {
        ref.invalidateSelf();
        return result['invitationId'] as String;
      }
      debugPrint('[graphPendingInvitations] create failed: ${result['error']}');
      return null;
    } catch (e) {
      debugPrint('[graphPendingInvitations] create error: $e');
      return null;
    }
  }

  /// Cancels a pending invitation (called by the inviter).
  Future<bool> cancelInvitation(String invitationId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return false;

    try {
      final response = await client.rpc(
        'fn_cancel_graph_invitation',
        params: {'p_invitation_id': invitationId},
      ).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>;
      if (result['success'] == true) {
        ref.invalidateSelf();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[graphPendingInvitations] cancel error: $e');
      return false;
    }
  }

  /// Accepts a pending invitation (called by the invitee).
  /// This creates the Person + Relationship + reciprocal edge.
  Future<bool> acceptInvitation(String invitationId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return false;

    try {
      final response = await client.rpc(
        'fn_accept_graph_invitation',
        params: {'p_invitation_id': invitationId},
      ).timeout(const Duration(seconds: 15));

      final result = response as Map<String, dynamic>;
      if (result['success'] == true) {
        ref.invalidateSelf();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[graphPendingInvitations] accept error: $e');
      return false;
    }
  }

  /// Declines a pending invitation (called by the invitee).
  Future<bool> declineInvitation(String invitationId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return false;

    try {
      final response = await client.rpc(
        'fn_decline_graph_invitation',
        params: {'p_invitation_id': invitationId},
      ).timeout(const Duration(seconds: 10));

      final result = response as Map<String, dynamic>;
      if (result['success'] == true) {
        ref.invalidateSelf();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[graphPendingInvitations] decline error: $e');
      return false;
    }
  }
}

/// Provider family — keyed by familyId.
final graphPendingInvitationsProvider = AsyncNotifierProvider.family<
    GraphPendingInvitationsNotifier, List<GraphPendingInvitation>, String>(
  GraphPendingInvitationsNotifier.new,
);

/// Convenience provider — returns the count of pending invitations.
final pendingGraphInvitationCountProvider =
    Provider.family<int, String>((ref, familyId) {
  final async = ref.watch(graphPendingInvitationsProvider(familyId));
  return async.valueOrNull?.length ?? 0;
});

/// v5.44: Checks whether a pending invitation exists for a given
/// recipient identifier (Kinrel user ID, email, or phone).
///
/// Returns the matching [GraphPendingInvitation] if one exists, or null.
///
/// Used by:
///   • AddPersonSheet — to block submission and show "Invitation already
///     pending" before the user completes the full flow.
///   • KinrelUserSearchScreen — to show the "Invitation Pending" badge
///     on search results.
GraphPendingInvitation? findPendingInvitationForRecipient(
  List<GraphPendingInvitation> invitations, {
  String? recipientUserId,
  String? recipientEmail,
  String? recipientPhone,
}) {
  if (recipientUserId != null && recipientUserId.isNotEmpty) {
    final match = invitations.where(
      (i) => i.recipientUserId == recipientUserId && i.status == 'pending',
    );
    if (match.isNotEmpty) return match.first;
  }
  if (recipientEmail != null && recipientEmail.isNotEmpty) {
    final match = invitations.where(
      (i) => i.recipientEmail == recipientEmail && i.status == 'pending',
    );
    if (match.isNotEmpty) return match.first;
  }
  if (recipientPhone != null && recipientPhone.isNotEmpty) {
    final match = invitations.where(
      (i) => i.recipientPhone == recipientPhone && i.status == 'pending',
    );
    if (match.isNotEmpty) return match.first;
  }
  return null;
}

/// v5.44: Provider that returns the set of recipient user IDs that have
/// pending invitations in a family. Used by the Find on Kinrel search
/// screen to show the "Invitation Pending" badge.
final pendingInvitationRecipientUserIdsProvider =
    Provider.family<Set<String>, String>((ref, familyId) {
  final async = ref.watch(graphPendingInvitationsProvider(familyId));
  final invitations = async.valueOrNull ?? [];
  return invitations
      .where((i) =>
          i.status == 'pending' &&
          i.recipientUserId != null &&
          i.recipientUserId!.isNotEmpty)
      .map((i) => i.recipientUserId!)
      .toSet();
});
