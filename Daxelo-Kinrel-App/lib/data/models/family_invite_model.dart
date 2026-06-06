// lib/data/models/family_invite_model.dart
//
// DAXELO KINREL — Family Invite Model
//
// Manages invite link generation and family join previews.

/// Represents a generated family invite link.
class FamilyInviteModel {
  const FamilyInviteModel({
    required this.id,
    required this.familyId,
    required this.token,
    this.expiresAt,
    this.maxUses,
    this.useCount = 0,
    this.isActive = true,
    required this.createdAt,
  });

  factory FamilyInviteModel.fromJson(Map<String, dynamic> json) {
    return FamilyInviteModel(
      id: _parseString(json['id']),
      familyId: _parseString(json['familyId']),
      token: _parseString(json['token']),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      maxUses: json['maxUses'] as int?,
      useCount: _parseInt(json['useCount']),
      isActive: _parseBool(json['isActive'], fallback: true),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String id;
  final String familyId;
  final String token;
  final DateTime? expiresAt;
  final int? maxUses;
  final int useCount;
  final bool isActive;
  final DateTime createdAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isExhausted =>
      maxUses != null && useCount >= maxUses!;

  bool get isValid => isActive && !isExpired && !isExhausted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'familyId': familyId,
        'token': token,
        'expiresAt': expiresAt?.toIso8601String(),
        'maxUses': maxUses,
        'useCount': useCount,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Preview of a family before joining via an invite token.
class FamilyJoinPreviewModel {
  const FamilyJoinPreviewModel({
    required this.familyId,
    required this.familyName,
    required this.ownerName,
    this.familyAvatarUrl,
    this.memberCount = 0,
    this.isValid = true,
    this.isExpired = false,
    this.errorCode,
  });

  factory FamilyJoinPreviewModel.fromJson(Map<String, dynamic> json) {
    return FamilyJoinPreviewModel(
      familyId: _parseString(json['familyId']),
      familyName: _parseString(json['familyName']),
      ownerName: _parseString(json['ownerName']),
      familyAvatarUrl: json['familyAvatarUrl'] as String?,
      memberCount: _parseInt(json['memberCount']),
      isValid: _parseBool(json['isValid'], fallback: true),
      isExpired: _parseBool(json['isExpired']),
      errorCode: json['errorCode'] as String?,
    );
  }

  final String familyId;
  final String familyName;
  final String ownerName;
  final String? familyAvatarUrl;
  final int memberCount;
  final bool isValid;
  final bool isExpired;
  final String? errorCode; // INVITE_EXPIRED | INVITE_MAX_USES_REACHED

  bool get isAlreadyMember => errorCode == 'ALREADY_MEMBER';
  bool get isMaxUsesReached => errorCode == 'INVITE_MAX_USES_REACHED';
  bool get isInviteExpired => errorCode == 'INVITE_EXPIRED' || isExpired;
}

// ── Safe Parsing Helpers ─────────────────────────────────────────

String _parseString(dynamic value, {String fallback = ''}) {
  if (value is String) return value;
  if (value is int || value is num) return value.toString();
  return fallback;
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is num) return value.toInt();
  return 0;
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  return fallback;
}
