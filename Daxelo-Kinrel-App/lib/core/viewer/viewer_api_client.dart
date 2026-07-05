// lib/core/viewer/viewer_api_client.dart
//
// DAXELO KINREL v2.2 — Viewer API Client
//
// Wraps the NestJS ViewerController endpoints so the Flutter UI can:
//   - Resolve the current viewer's Person ID for a family
//   - Claim a Person node (link the authenticated user to it)
//   - Unlink from a Person node
//   - Invite a recipient by email/phone to claim a Person node
//   - Accept a pending person-link invitation
//
// All endpoints require a real Supabase JWT (injected by the Dio
// auth interceptor in dio_client.dart). The NestJS server enforces
// family membership, ownership, impersonation prevention, and
// duplicate prevention — the client never trusts itself.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../networking/dio_client.dart' show dioProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Response shape for `GET /families/:familyId/viewer`.
class ViewerResolution {
  final String familyId;
  final String? viewerPersonId;
  final String resolution; // "linked" | "anchor" | "none"
  final bool isLinked;

  const ViewerResolution({
    required this.familyId,
    required this.viewerPersonId,
    required this.resolution,
    required this.isLinked,
  });

  factory ViewerResolution.fromJson(Map<String, dynamic> json) {
    return ViewerResolution(
      familyId: json['familyId'] as String,
      viewerPersonId: json['viewerPersonId'] as String?,
      resolution: json['resolution'] as String? ?? 'none',
      isLinked: json['isLinked'] as bool? ?? false,
    );
  }
}

/// Response shape for `POST /families/:familyId/persons/:personId/claim`
/// and `POST /families/:familyId/invitations/:code/accept`.
class PersonLinkResult {
  final String personId;
  final String linkedUserId;
  final DateTime linkedAt;
  final String? invitationCode;

  const PersonLinkResult({
    required this.personId,
    required this.linkedUserId,
    required this.linkedAt,
    this.invitationCode,
  });

  factory PersonLinkResult.fromJson(Map<String, dynamic> json) {
    return PersonLinkResult(
      personId: json['personId'] as String,
      linkedUserId: json['linkedUserId'] as String,
      linkedAt: DateTime.parse(json['linkedAt'] as String),
      invitationCode: json['invitationCode'] as String?,
    );
  }
}

/// Response shape for `POST /families/:familyId/persons/:personId/invite`.
class InvitationResult {
  final String personId;
  final String invitationCode;
  final String? recipientEmail;
  final String? recipientPhone;
  final DateTime expiresAt;
  final DateTime createdAt;

  const InvitationResult({
    required this.personId,
    required this.invitationCode,
    required this.recipientEmail,
    required this.recipientPhone,
    required this.expiresAt,
    required this.createdAt,
  });

  factory InvitationResult.fromJson(Map<String, dynamic> json) {
    return InvitationResult(
      personId: json['personId'] as String,
      invitationCode: json['invitationCode'] as String,
      recipientEmail: json['recipientEmail'] as String?,
      recipientPhone: json['recipientPhone'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Result shape for `DELETE /families/:familyId/persons/:personId/unlink`.
class UnlinkResult {
  final String personId;
  final bool unlinked;

  const UnlinkResult({
    required this.personId,
    required this.unlinked,
  });

  factory UnlinkResult.fromJson(Map<String, dynamic> json) {
    return UnlinkResult(
      personId: json['personId'] as String,
      unlinked: json['unlinked'] as bool? ?? true,
    );
  }
}

/// Error thrown when the server rejects a viewer operation
/// (e.g. already-claimed profile, expired invitation, not a family
/// member).
class ViewerApiException implements Exception {
  final String message;
  final int? statusCode;

  const ViewerApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ViewerApiException($statusCode): $message';
}

/// Riverpod provider for the [ViewerApiClient].
final viewerApiClientProvider = Provider<ViewerApiClient>((ref) {
  return ViewerApiClient(ref.read(dioProvider));
});

/// HTTP client for the v2.2 Viewer endpoints.
///
/// All methods are async and throw [ViewerApiException] on failure.
/// The caller is responsible for invalidating `viewerPersonIdProvider`
/// and `familyGraphProvider` after a successful claim/unlink/accept
/// so the UI re-fetches from the new viewer's perspective.
class ViewerApiClient {
  ViewerApiClient(this._dio);
  final Dio _dio;

  /// `GET /api/families/:familyId/viewer`
  ///
  /// Returns the viewer Person ID for the authenticated user in the
  /// given family. Resolution: linked → anchor (legacy) → none.
  Future<ViewerResolution> resolveViewer(String familyId) async {
    try {
      final response = await _dio.get('/api/families/$familyId/viewer');
      return ViewerResolution.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    } catch (e) {
      debugPrint('ViewerApiClient.resolveViewer: $e');
      rethrow;
    }
  }

  /// `POST /api/families/:familyId/persons/:personId/claim`
  ///
  /// Links the authenticated user to the Person node. Server enforces:
  ///   - User is a family member
  ///   - Person is not already claimed by another user
  ///   - User is not already linked to a different Person in the family
  Future<PersonLinkResult> claimPerson({
    required String familyId,
    required String personId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/families/$familyId/persons/$personId/claim',
      );
      return PersonLinkResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// `DELETE /api/families/:familyId/persons/:personId/unlink`
  ///
  /// Removes the link. Server enforces: caller is the linked user OR
  /// a family admin/owner. Idempotent if already unlinked.
  Future<UnlinkResult> unlinkPerson({
    required String familyId,
    required String personId,
  }) async {
    try {
      final response = await _dio.delete(
        '/api/families/$familyId/persons/$personId/unlink',
      );
      return UnlinkResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// `POST /api/families/:familyId/persons/:personId/invite`
  ///
  /// Creates a one-time invitation code (7-day TTL). At least one of
  /// [recipientEmail] or [recipientPhone] must be provided. Server
  /// enforces: caller is a family editor+ and the Person is not
  /// already claimed.
  Future<InvitationResult> invitePerson({
    required String familyId,
    required String personId,
    String? recipientName,
    String? recipientEmail,
    String? recipientPhone,
    String? role,
  }) async {
    try {
      final response = await _dio.post(
        '/api/families/$familyId/persons/$personId/invite',
        data: {
          if (recipientName != null) 'recipientName': recipientName,
          if (recipientEmail != null) 'recipientEmail': recipientEmail,
          if (recipientPhone != null) 'recipientPhone': recipientPhone,
          if (role != null) 'role': role,
        },
      );
      return InvitationResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// `POST /api/families/:familyId/invitations/:code/accept`
  ///
  /// Accepts a pending invitation. Server enforces: caller is a family
  /// member, invitation is pending + not expired, target Person is not
  /// already claimed, caller is not already linked to a different
  /// Person in the family.
  Future<PersonLinkResult> acceptInvitation({
    required String familyId,
    required String code,
  }) async {
    try {
      final response = await _dio.post(
        '/api/families/$familyId/invitations/$code/accept',
      );
      return PersonLinkResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// `GET /api/families/:familyId/relationship-path?from=...&to=...`
  ///
  /// Returns the cached or freshly-computed relationship path between
  /// two persons in a family. Used by the Flutter RelationshipEngine
  /// as a server-side fallback for complex paths.
  Future<Map<String, dynamic>> getRelationshipPath({
    required String familyId,
    required String fromPersonId,
    required String toPersonId,
  }) async {
    try {
      final response = await _dio.get(
        '/api/families/$familyId/relationship-path',
        queryParameters: {
          'from': fromPersonId,
          'to': toPersonId,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  ViewerApiException _toException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String message = e.message ?? 'Unknown error';
    if (data is Map<String, dynamic>) {
      message = data['message'] as String? ?? message;
    } else if (data is String) {
      message = data;
    }
    return ViewerApiException(message, statusCode: status);
  }
}
