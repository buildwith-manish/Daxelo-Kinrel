// lib/features/chat/data/models/online_member.dart
//
// Extracted from lib/features/chat/providers/chat_provider.dart (Phase 0
// refactor — zero behavior change). Re-exported by chat_provider.dart so
// no existing import changes.

/// A member of the family chat — used for the header presence roster +
/// the online-count badge. `isOnline` is driven by the PresenceHeartbeat
/// (see lib/features/presence/last_seen_provider.dart).
class OnlineMember {
  const OnlineMember({
    required this.id,
    required this.name,
    required this.initials,
    this.isOnline = false,
  });

  final String id;
  final String name;
  final String initials;
  final bool isOnline;

  OnlineMember copyWith({
    String? id,
    String? name,
    String? initials,
    bool? isOnline,
  }) {
    return OnlineMember(
      id: id ?? this.id,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
