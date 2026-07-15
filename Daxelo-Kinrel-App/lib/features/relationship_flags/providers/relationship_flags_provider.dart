// lib/features/relationship_flags/providers/relationship_flags_provider.dart
//
// P9.2g — Non-judgmental relationship-state flags.
//
// ╔══════════════════════════════════════════════════════════════════╗
// ║ VIEWER-PRIVATE ONLY. Hard guarantees:                              ║
// ║                                                                    ║
// ║  • Flags are stored ONLY in the local viewer cache (this          ║
// ║    provider's in-memory state). They are NEVER written to a       ║
// ║    server, NEVER written to Supabase, NEVER included in sync.     ║
// ║  • Setting / changing a flag sends NO notification to anyone —    ║
// ║    not the target person, not other family members, not admins.   ║
// ║  • Flags are NEVER compared. There is no "how does this           ║
// ║    relationship rank against others?" view, no aggregate, no      ║
// ║    leaderboard.                                                    ║
// ║  • Flag labels are deliberately non-judgmental and descriptive    ║
// ║    (e.g. "wanting to reconnect", "needing space"). They describe  ║
// ║    the VIEWER's own intent, never a verdict on the other person.  ║
// ║                                                                    ║
// ║ Constitution / Copy-Audit: no guilt language, no FOMO, no         ║
// ║ surveillance. This feature exists so a viewer can privately        ║
// ║ note their own relational context — the opposite of surveillance. ║
// ╚══════════════════════════════════════════════════════════════════╝

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Descriptive, non-judgmental flags. Each describes the VIEWER's
/// current stance toward the target person — never a label ON the
/// target person.
enum RelationshipFlag {
  /// "I'd like to reach out soon."
  reachingOut,
  /// "I'm giving this relationship some space right now."
  needingSpace,
  /// "I'd like us to reconnect when the moment is right."
  wantToReconnect,
  /// "Things feel steady as they are."
  comfortable,
  /// "I want to remember this person's birthday / an occasion."
  rememberOccasion,
}

/// A neutral, human-readable label for a flag (for the viewer's own UI).
String relationshipFlagLabel(RelationshipFlag f) {
  switch (f) {
    case RelationshipFlag.reachingOut:
      return "I'd like to reach out";
    case RelationshipFlag.needingSpace:
      return "I'm giving this space";
    case RelationshipFlag.wantToReconnect:
      return "I'd like to reconnect";
    case RelationshipFlag.comfortable:
      return 'This feels steady';
    case RelationshipFlag.rememberOccasion:
      return 'Remember an occasion';
  }
}

@immutable
class RelationshipFlagEntry {
  const RelationshipFlagEntry({
    required this.targetPersonId,
    required this.flag,
    required this.notedAt,
    this.note,
  });

  /// The person this flag is ABOUT (from the viewer's perspective).
  /// Only the target id is held — no name, no contact info — so even
  /// the local cache stays minimal.
  final String targetPersonId;
  final RelationshipFlag flag;
  final DateTime notedAt;
  /// Optional private note. Stays on-device.
  final String? note;

  RelationshipFlagEntry copyWith({
    String? targetPersonId,
    RelationshipFlag? flag,
    DateTime? notedAt,
    String? note,
    bool clearNote = false,
  }) {
    return RelationshipFlagEntry(
      targetPersonId: targetPersonId ?? this.targetPersonId,
      flag: flag ?? this.flag,
      notedAt: notedAt ?? this.notedAt,
      note: clearNote ? null : (note ?? this.note),
    );
  }
}

@immutable
class RelationshipFlagsState {
  const RelationshipFlagsState({
    /// Keyed by targetPersonId. A viewer may hold at most one active
    /// flag per target at a time, by design — this prevents building
    /// a "history of grievances" dossier.
    this.entries = const {},
  });

  final Map<String, RelationshipFlagEntry> entries;

  RelationshipFlagEntry? flagFor(String targetPersonId) =>
      entries[targetPersonId];

  RelationshipFlagsState copyWith({
    Map<String, RelationshipFlagEntry>? entries,
  }) {
    return RelationshipFlagsState(entries: entries ?? this.entries);
  }
}

class RelationshipFlagsNotifier
    extends StateNotifier<RelationshipFlagsState> {
  RelationshipFlagsNotifier() : super(const RelationshipFlagsState());

  /// Sets the viewer's private flag for [targetPersonId].
  ///
  /// HARD GUARANTEE: this method performs NO I/O. It does not call any
  /// repository, does not emit any event, does not schedule any
  /// notification. If a future maintainer wires this to sync, that is a
  /// Constitution violation and must be reverted.
  void setFlag(
    String targetPersonId,
    RelationshipFlag flag, {
    String? note,
  }) {
    if (targetPersonId.trim().isEmpty) return;
    final entry = RelationshipFlagEntry(
      targetPersonId: targetPersonId,
      flag: flag,
      notedAt: DateTime.now(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
    );
    final next = Map<String, RelationshipFlagEntry>.of(state.entries);
    next[targetPersonId] = entry;
    state = state.copyWith(entries: next);
  }

  /// Clears the viewer's private flag for [targetPersonId]. Again, no
  /// notification, no audit trail written anywhere off-device.
  void clearFlag(String targetPersonId) {
    final next = Map<String, RelationshipFlagEntry>.of(state.entries)
      ..remove(targetPersonId);
    state = state.copyWith(entries: next);
  }

  /// Clears every flag. Used at the viewer's explicit request only.
  void clearAll() => state = const RelationshipFlagsState();

  /// Intentionally NOT provided: any method that returns a comparison,
  /// ranking, or aggregate across multiple targets. Such a method would
  /// turn a private notepad into a surveillance dashboard, which this
  /// feature is explicitly designed NOT to be.
}
