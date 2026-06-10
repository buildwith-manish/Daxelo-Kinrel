// lib/features/memory_vault/data/memory_model.dart
//
// DAXELO KINREL — Memory Vault Model
//
// Data model for family photo memories stored in the
// `family_memories` Supabase table. Each memory represents
// a photo uploaded to the family-memories Storage bucket
// with optional caption, date taken, and tagged members.

/// Represents a single family memory (photo) in the Memory Vault.
class MemoryModel {
  const MemoryModel({
    required this.id,
    required this.familyId,
    required this.uploaderId,
    required this.uploaderName,
    this.caption,
    required this.photoUrl,
    this.mediaType = 'photo',
    this.takenAt,
    this.taggedPersonIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique identifier (UUID from Supabase).
  final String id;

  /// The family this memory belongs to.
  final String familyId;

  /// User ID of the person who uploaded the memory.
  final String uploaderId;

  /// Display name of the uploader (denormalized for fast reads).
  final String uploaderName;

  /// Optional caption for the photo (max 200 characters).
  final String? caption;

  /// Public URL of the photo in Supabase Storage.
  final String photoUrl;

  /// Media type — currently always 'photo', future: 'video'.
  final String mediaType;

  /// When the photo was originally taken (user-selected date).
  final DateTime? takenAt;

  /// IDs of family members tagged in the photo.
  final List<String> taggedPersonIds;

  /// Server timestamp when the memory was created.
  final DateTime createdAt;

  /// Server timestamp when the memory was last updated.
  final DateTime updatedAt;

  // ── Factory Constructors ──────────────────────────────────────────

  /// Create a MemoryModel from a Supabase row (Map).
  factory MemoryModel.fromJson(Map<String, dynamic> json) {
    return MemoryModel(
      id: json['id'] as String? ?? '',
      familyId: json['family_id'] as String? ?? '',
      uploaderId: json['uploader_id'] as String? ?? '',
      uploaderName: json['uploader_name'] as String? ?? '',
      caption: json['caption'] as String?,
      photoUrl: json['photo_url'] as String? ?? '',
      mediaType: json['media_type'] as String? ?? 'photo',
      takenAt: json['taken_at'] != null
          ? DateTime.tryParse(json['taken_at'].toString())
          : null,
      taggedPersonIds: _parseTaggedIds(json['tagged_person_ids']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Create a placeholder MemoryModel from just an ID.
  /// Used for route navigation where the full object will be resolved.
  factory MemoryModel.placeholder(String memoryId) {
    final now = DateTime.now();
    return MemoryModel(
      id: memoryId,
      familyId: '',
      uploaderId: '',
      uploaderName: '',
      photoUrl: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── Computed Getters ─────────────────────────────────────────────

  /// Whether this memory's takenAt month+day matches today's date.
  /// Used for the "On This Day" feature.
  bool get isOnThisDay {
    if (takenAt == null) return false;
    final now = DateTime.now();
    return takenAt!.month == now.month && takenAt!.day == now.day;
  }

  /// Formatted date string for the takenAt date.
  /// Falls back to createdAt if takenAt is null.
  String get formattedDate {
    final date = takenAt ?? createdAt;
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }

  /// How many years ago this memory was taken (relative to today).
  /// Returns null if takenAt is not set.
  int? get yearsAgo {
    if (takenAt == null) return null;
    final now = DateTime.now();
    int years = now.year - takenAt!.year;
    if (now.month < takenAt!.month ||
        (now.month == takenAt!.month && now.day < takenAt!.day)) {
      years--;
    }
    return years;
  }

  /// Initials derived from the uploader's name.
  String get uploaderInitials {
    if (uploaderName.isEmpty) return '?';
    final parts =
        uploaderName.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  // ── Serialization ────────────────────────────────────────────────

  /// Convert to a JSON map for Supabase inserts/updates.
  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'uploader_id': uploaderId,
        'uploader_name': uploaderName,
        'caption': caption,
        'photo_url': photoUrl,
        'media_type': mediaType,
        'taken_at': takenAt?.toIso8601String(),
        'tagged_person_ids': taggedPersonIds,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  // ── Copy With ────────────────────────────────────────────────────

  /// Create a copy of this model with optional field overrides.
  MemoryModel copyWith({
    String? id,
    String? familyId,
    String? uploaderId,
    String? uploaderName,
    String? caption,
    String? photoUrl,
    String? mediaType,
    DateTime? takenAt,
    List<String>? taggedPersonIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MemoryModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      uploaderId: uploaderId ?? this.uploaderId,
      uploaderName: uploaderName ?? this.uploaderName,
      caption: caption ?? this.caption,
      photoUrl: photoUrl ?? this.photoUrl,
      mediaType: mediaType ?? this.mediaType,
      takenAt: takenAt ?? this.takenAt,
      taggedPersonIds: taggedPersonIds ?? this.taggedPersonIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Parse tagged_person_ids from Supabase.
  /// Supabase returns UUID[] as a List<dynamic>.
  static List<String> _parseTaggedIds(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'MemoryModel(id: $id, caption: $caption, uploader: $uploaderName)';
}
