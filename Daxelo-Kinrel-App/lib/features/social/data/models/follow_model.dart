// FollowModel — represents a follow relationship between users
class FollowModel {
  final String id;
  final String followerId;
  final String followingId;
  final String status; // 'PENDING', 'ACCEPTED', 'REJECTED'
  final DateTime createdAt;
  final DateTime updatedAt;

  const FollowModel({
    required this.id,
    required this.followerId,
    required this.followingId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FollowModel.fromJson(Map<String, dynamic> json) {
    return FollowModel(
      id: json['id'] as String? ?? '',
      followerId: json['followerId'] as String? ?? '',
      followingId: json['followingId'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'followerId': followerId,
    'followingId': followingId,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
