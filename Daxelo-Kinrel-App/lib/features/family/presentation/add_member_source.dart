// lib/features/family/presentation/add_member_source.dart
//
// DAXELO KINREL — Add Member Source Enum + KinrelUser Model
//
// Shared types for the 3-way Add Member flow:
//   1. manual       → Step 1 → 2 → 3 → 4 (full manual entry)
//   2. fromContacts → Contact picker → Step 1 (prefilled) → 2 → 3 → 4
//   3. findOnKinrel → Kinrel search → Step 2 → 3 → 4 (skip Step 1,
//                     link to existing Kinrel profile)
//

/// Tracks how the Add Member flow was initiated so Step 4 (Confirm)
/// knows whether to create a new unlinked person, create a person with
/// contact data, or link to an existing Kinrel profile.
enum AddMemberSource {
  /// Manual entry — all 4 steps, creates a new unlinked Person.
  manual,

  /// From phone contacts — contact picker → Step 1 prefilled → 2 → 3 → 4.
  fromContacts,

  /// Find on Kinrel — Kinrel user search → Step 2 → 3 → 4. Links to
  /// the existing Kinrel user's profile (no duplicate Person entry).
  findOnKinrel,
}

/// A Kinrel user found via the global search RPC.
///
/// Returned by `fn_search_kinrel_users` — represents a registered Kinrel
/// user with a public profile. Used by the "Find on Kinrel" add-member
/// flow to let the user select an existing Kinrel account to add to
/// their family.
class KinrelUser {
  const KinrelUser({
    required this.id,
    required this.name,
    this.username,
    this.email,
    this.avatarUrl,
    this.photoThumb,
    this.bio,
    this.gender,
  });

  /// The user's ID (matches auth.users.id, stored as text in the User table).
  final String id;

  /// Display name.
  final String name;

  /// @username (without the @ prefix).
  final String? username;

  /// Email address (may be null for some users).
  final String? email;

  /// Avatar URL (full-size).
  final String? avatarUrl;

  /// Thumbnail avatar URL (smaller, for list views).
  final String? photoThumb;

  /// Short bio.
  final String? bio;

  /// Gender ('male', 'female', 'other').
  final String? gender;

  /// Parse from the Supabase RPC response row.
  factory KinrelUser.fromJson(Map<String, dynamic> json) {
    return KinrelUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      username: json['username'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      photoThumb: json['photoThumb'] as String?,
      bio: json['bio'] as String?,
      gender: json['gender'] as String?,
    );
  }

  /// Generate a stable 5-digit display ID from the user's ID.
  /// e.g. "KIN-00234" — used for display in search results.
  String get displayId {
    int hash = 0;
    for (int i = 0; i < id.length; i++) {
      hash = (hash * 31 + id.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final index = hash % 100000;
    return 'KIN-${index.toString().padLeft(5, '0')}';
  }

  /// Get initials for avatar fallback.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}
