// FamilyInviteModel — token-based family invite with creator tracking
class FamilyInviteModel {
  final String id;
  final String familyId;
  final String token;
  final String creatorId;
  final DateTime? expiresAt;
  final int? maxUses;
  final int useCount;
  final bool active;
  final DateTime createdAt;

  const FamilyInviteModel({
    required this.id,
    required this.familyId,
    required this.token,
    required this.creatorId,
    this.expiresAt,
    this.maxUses,
    this.useCount = 0,
    this.active = true,
    required this.createdAt,
  });

  factory FamilyInviteModel.fromJson(Map<String, dynamic> json) {
    return FamilyInviteModel(
      id: json['id'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      token: json['token'] as String? ?? '',
      creatorId: json['creatorId'] as String? ?? '',
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      maxUses: json['maxUses'] as int?,
      useCount: json['useCount'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyId': familyId,
    'token': token,
    'creatorId': creatorId,
    'expiresAt': expiresAt?.toIso8601String(),
    'maxUses': maxUses,
    'useCount': useCount,
    'active': active,
    'createdAt': createdAt.toIso8601String(),
  };

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get hasUsesLeft => maxUses == null || useCount < maxUses!;
}

/// Preview data shown before joining a family
class FamilyJoinPreviewModel {
  final String familyName;
  final String ownerName;
  final int memberCount;
  final bool isValid;
  final bool isExpired;

  const FamilyJoinPreviewModel({
    required this.familyName,
    required this.ownerName,
    required this.memberCount,
    this.isValid = true,
    this.isExpired = false,
  });

  factory FamilyJoinPreviewModel.fromJson(Map<String, dynamic> json) {
    return FamilyJoinPreviewModel(
      familyName: json['familyName'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      memberCount: json['memberCount'] as int? ?? 0,
      isValid: json['isValid'] as bool? ?? true,
      isExpired: json['isExpired'] as bool? ?? false,
    );
  }
}
