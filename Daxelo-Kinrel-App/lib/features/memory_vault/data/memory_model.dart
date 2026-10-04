// lib/features/memory_vault/data/memory_model.dart
//
// DAXELO KINREL — Memory Vault Model (v2 — image + post link + pin)
//
// Backward-compatible extension of the original photo-memory model.
// All new fields are nullable so existing rows (which only have photo_url
// + caption) continue to deserialize without breaking.
//
// New fields (all nullable):
//   - imageUrl / imageStorageKey — cover image in `memory-images` bucket
//   - title / description / location / memoryType — memory metadata
//   - sourcePostId — optional FK back to "FamilyPost" (Feature 6)
//   - isPinnedToVault — vault pin flag (Feature 8)
//
// The legacy `photoUrl` + `caption` fields are preserved for old rows.
// New code uses `imageUrl` for the cover image and `title`/`description`
// for the structured memory text.

/// Represents a single family memory in the Memory Vault + Timeline.
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
    // ── New v2 fields (all nullable for backward compat) ──
    this.imageUrl,
    this.imageStorageKey,
    this.title,
    this.description,
    this.location,
    this.memoryType,
    this.sourcePostId,
    this.isPinnedToVault = false,
  });

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
      // ── New v2 fields ──
      imageUrl: json['image_url'] as String?,
      imageStorageKey: json['image_storage_key'] as String?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      location: json['location'] as String?,
      memoryType: json['memory_type'] as String?,
      sourcePostId: json['source_post_id'] as String?,
      isPinnedToVault: (json['is_pinned_to_vault'] as bool?) ?? false,
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

  /// Unique identifier (UUID from Supabase).
  final String id;

  /// The family this memory belongs to.
  final String familyId;

  /// User ID of the person who uploaded the memory.
  final String uploaderId;

  /// Display name of the uploader (denormalized for fast reads).
  final String uploaderName;

  /// Optional caption (legacy field — pre-v2 memories used this as the
  /// main text). For new memories, prefer `title` + `description`.
  final String? caption;

  /// Public URL of the photo in the legacy `family-memories` bucket.
  /// Kept for backward compat — old rows still load with this.
  final String photoUrl;

  /// Media type — currently always 'photo', future: 'video'.
  final String mediaType;

  /// When the memory was originally taken / occurred (user-selected date).
  final DateTime? takenAt;

  /// IDs of family members tagged in the memory.
  /// Reused as the "members" list per the implementation prompt.
  final List<String> taggedPersonIds;

  /// Server timestamp when the memory was created.
  final DateTime createdAt;

  /// Server timestamp when the memory was last updated.
  final DateTime updatedAt;

  // ── New v2 fields ──────────────────────────────────────────────

  /// Public URL of the cover image in the `memory-images` bucket.
  /// This is the new structured cover image (one image per memory).
  final String? imageUrl;

  /// Storage key for the cover image (so we can DELETE the storage
  /// object when the memory is deleted).
  /// Format: `{familyId}/{memoryId}/image.jpg`
  final String? imageStorageKey;

  /// Short headline / title for the memory.
  final String? title;

  /// Longer story / description text.
  final String? description;

  /// Free-form location string (e.g. "Jaipur").
  final String? location;

  /// Memory type label (festival / birth / marriage / achievement / ...).
  /// Stored as TEXT to keep the schema flexible.
  final String? memoryType;

  /// Optional FK back to "FamilyPost" — set when this memory was
  /// created from a post via the "Save As Memory" flow.
  final String? sourcePostId;

  /// Whether this memory is pinned to the Memory Vault (premium archive).
  final bool isPinnedToVault;

  // ── Computed Getters ─────────────────────────────────────────────

  /// The "best" image URL to display — prefers the new structured
  /// `imageUrl` (cover) over the legacy `photoUrl`. Returns empty
  /// string only when neither is set.
  String get displayImageUrl =>
      (imageUrl != null && imageUrl!.isNotEmpty) ? imageUrl! : photoUrl;

  /// Whether this memory has a usable cover image.
  bool get hasImage => displayImageUrl.isNotEmpty;

  /// The "best" title to display — prefers `title`, falls back to
  /// `caption` (legacy), then to "Untitled Memory".
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    if (caption != null && caption!.trim().isNotEmpty) return caption!.trim();
    return 'Untitled Memory';
  }

  /// The "best" story/description text — prefers `description`,
  /// falls back to `caption` if it differs from the title.
  String? get displayDescription {
    if (description != null && description!.trim().isNotEmpty) {
      return description!.trim();
    }
    // Only use caption as description if it's NOT already used as the title.
    if (caption != null &&
        caption!.trim().isNotEmpty &&
        (title == null || title!.trim().isEmpty) &&
        caption!.trim() != displayTitle) {
      return caption!.trim();
    }
    return null;
  }

  /// Whether this memory was created from a post.
  bool get isFromPost =>
      sourcePostId != null && sourcePostId!.trim().isNotEmpty;

  /// Number of members tagged in this memory.
  int get memberCount => taggedPersonIds.length;

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
        // ── New v2 fields ──
        if (imageUrl != null) 'image_url': imageUrl,
        if (imageStorageKey != null) 'image_storage_key': imageStorageKey,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        if (memoryType != null) 'memory_type': memoryType,
        if (sourcePostId != null) 'source_post_id': sourcePostId,
        'is_pinned_to_vault': isPinnedToVault,
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
    // v2 fields
    String? imageUrl,
    String? imageStorageKey,
    String? title,
    String? description,
    String? location,
    String? memoryType,
    String? sourcePostId,
    bool? isPinnedToVault,
    // nullable-clear flags
    bool clearImageUrl = false,
    bool clearImageStorageKey = false,
    bool clearTitle = false,
    bool clearDescription = false,
    bool clearLocation = false,
    bool clearMemoryType = false,
    bool clearSourcePostId = false,
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
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      imageStorageKey:
          clearImageStorageKey ? null : (imageStorageKey ?? this.imageStorageKey),
      title: clearTitle ? null : (title ?? this.title),
      description: clearDescription ? null : (description ?? this.description),
      location: clearLocation ? null : (location ?? this.location),
      memoryType: clearMemoryType ? null : (memoryType ?? this.memoryType),
      sourcePostId:
          clearSourcePostId ? null : (sourcePostId ?? this.sourcePostId),
      isPinnedToVault: isPinnedToVault ?? this.isPinnedToVault,
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
      'MemoryModel(id: $id, title: $displayTitle, uploader: $uploaderName, pinned: $isPinnedToVault)';
}
