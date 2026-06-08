// lib/features/social/data/models/family_join_preview_model.dart
//
// DAXELO KINREL — Family Join Preview Model
//
// Used to display family information before a user joins
// via an invite link or QR code.

/// Model representing a family's basic info shown before joining.
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
      isValid: json['valid'] as bool? ?? false,
      isExpired: json['expired'] as bool? ?? false,
    );
  }

  /// Whether the current user can join this family
  bool get canJoin => isValid && !isExpired;
}
