// lib/features/memories/providers/memories_provider.dart
//
// DAXELO KINREL — Memories & Timeline Provider
//
// Family Timeline: chronological events (births, deaths, marriages,
// anniversaries, graduations, achievements, migrations, custom).
// Photo Memories: "On This Day" feature with gallery grouped by person/event.
//
// Orange K-Graph DNA: Timeline gradient (#E8612A → #F59240),
// glow nodes, darkCard (#191B2C) event cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../memory_vault/providers/memory_vault_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Timeline Event Type Enum
// ═══════════════════════════════════════════════════════════════════════

/// Types of events displayed on the family timeline.
enum MemoryEventType {
  birth,
  death,
  marriage,
  anniversary,
  graduation,
  achievement,
  migration,
  festival,
  custom,
}

extension MemoryEventTypeX on MemoryEventType {
  Color get accentColor {
    switch (this) {
      case MemoryEventType.birth:
        return KinrelColors.orange;
      case MemoryEventType.death:
        return KinrelColors.textSilver;
      case MemoryEventType.marriage:
        return KinrelColors.amber;
      case MemoryEventType.anniversary:
        return KinrelColors.gold;
      case MemoryEventType.graduation:
        return KinrelColors.info;
      case MemoryEventType.achievement:
        return KinrelColors.brightGold;
      case MemoryEventType.migration:
        return KinrelColors.success;
      case MemoryEventType.festival:
        return KinrelColors.orange;
      case MemoryEventType.custom:
        return KinrelColors.textDim;
    }
  }

  IconData get icon {
    switch (this) {
      case MemoryEventType.birth:
        return Icons.child_care_rounded;
      case MemoryEventType.death:
        return Icons.auto_awesome_rounded;
      case MemoryEventType.marriage:
        return Icons.favorite_rounded;
      case MemoryEventType.anniversary:
        return Icons.celebration_rounded;
      case MemoryEventType.graduation:
        return Icons.school_rounded;
      case MemoryEventType.achievement:
        return Icons.emoji_events_rounded;
      case MemoryEventType.migration:
        return Icons.flight_takeoff_rounded;
      case MemoryEventType.festival:
        return Icons.festival_rounded;
      case MemoryEventType.custom:
        return Icons.bookmark_rounded;
    }
  }

  String get typeLabel {
    switch (this) {
      case MemoryEventType.birth:
        return 'BIRTH';
      case MemoryEventType.death:
        return 'MEMORIAL';
      case MemoryEventType.marriage:
        return 'MARRIAGE';
      case MemoryEventType.anniversary:
        return 'ANNIVERSARY';
      case MemoryEventType.graduation:
        return 'GRADUATION';
      case MemoryEventType.achievement:
        return 'ACHIEVEMENT';
      case MemoryEventType.migration:
        return 'MIGRATION';
      case MemoryEventType.festival:
        return 'FESTIVAL';
      case MemoryEventType.custom:
        return 'CUSTOM';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Related Member (avatar row in event cards)
// ═══════════════════════════════════════════════════════════════════════

/// A family member associated with a memory event.
class MemoryMember {
  const MemoryMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.initials,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? initials;

  /// Returns initials derived from the name if not explicitly set.
  String get displayInitials =>
      initials ??
      (name.isNotEmpty
          ? name
                .split(' ')
                .where((s) => s.isNotEmpty)
                .take(2)
                .map((s) => s[0].toUpperCase())
                .join()
          : '?');
}

// ═══════════════════════════════════════════════════════════════════════
// Memory Event Model
// ═══════════════════════════════════════════════════════════════════════

/// Represents a single event on the family timeline.
class MemoryEvent {
  const MemoryEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    this.description,
    this.members = const [],
    this.photoUrl,
    this.location,
    this.isPinned = false,
  });

  /// Unique identifier.
  final String id;

  /// Event title / headline.
  final String title;

  /// Event type.
  final MemoryEventType type;

  /// Date of the event.
  final DateTime date;

  /// Optional longer description.
  final String? description;

  /// Related family members (displayed as avatar row).
  final List<MemoryMember> members;

  /// Optional photo URL placeholder.
  final String? photoUrl;

  /// Optional location string.
  final String? location;

  /// Whether this event is pinned to the top.
  final bool isPinned;

  // ── Computed Properties ──────────────────────────────────────────

  /// Accent color for the event type.
  Color get accentColor {
    switch (type) {
      case MemoryEventType.birth:
        return KinrelColors.orange; // #E8612A
      case MemoryEventType.death:
        return KinrelColors.textSilver; // #C9B4A8 — solemn
      case MemoryEventType.marriage:
        return KinrelColors.amber; // #F59240
      case MemoryEventType.anniversary:
        return KinrelColors.gold; // #D4AF37
      case MemoryEventType.graduation:
        return KinrelColors.info; // #60A5FA
      case MemoryEventType.achievement:
        return KinrelColors.brightGold; // #FFD700
      case MemoryEventType.migration:
        return KinrelColors.success; // #4CAF7A
      case MemoryEventType.festival:
        return KinrelColors.orange; // #E8612A
      case MemoryEventType.custom:
        return KinrelColors.textDim; // #8A7A72
    }
  }

  /// Icon for the event type.
  IconData get icon {
    switch (type) {
      case MemoryEventType.birth:
        return Icons.child_care_rounded;
      case MemoryEventType.death:
        return Icons.auto_awesome_rounded;
      case MemoryEventType.marriage:
        return Icons.favorite_rounded;
      case MemoryEventType.anniversary:
        return Icons.celebration_rounded;
      case MemoryEventType.graduation:
        return Icons.school_rounded;
      case MemoryEventType.achievement:
        return Icons.emoji_events_rounded;
      case MemoryEventType.migration:
        return Icons.flight_takeoff_rounded;
      case MemoryEventType.festival:
        return Icons.festival_rounded;
      case MemoryEventType.custom:
        return Icons.bookmark_rounded;
    }
  }

  /// Emoji for the event type.
  String get emoji {
    switch (type) {
      case MemoryEventType.birth:
        return '👶';
      case MemoryEventType.death:
        return '🙏';
      case MemoryEventType.marriage:
        return '💍';
      case MemoryEventType.anniversary:
        return '🎉';
      case MemoryEventType.graduation:
        return '🎓';
      case MemoryEventType.achievement:
        return '🏆';
      case MemoryEventType.migration:
        return '✈️';
      case MemoryEventType.festival:
        return '🪔';
      case MemoryEventType.custom:
        return '📌';
    }
  }

  /// Label for the event type badge.
  String get typeLabel {
    switch (type) {
      case MemoryEventType.birth:
        return 'BIRTH';
      case MemoryEventType.death:
        return 'MEMORIAL';
      case MemoryEventType.marriage:
        return 'MARRIAGE';
      case MemoryEventType.anniversary:
        return 'ANNIVERSARY';
      case MemoryEventType.graduation:
        return 'GRADUATION';
      case MemoryEventType.achievement:
        return 'ACHIEVEMENT';
      case MemoryEventType.migration:
        return 'MIGRATION';
      case MemoryEventType.festival:
        return 'FESTIVAL';
      case MemoryEventType.custom:
        return 'CUSTOM';
    }
  }

  /// Formatted date string for display.
  String get formattedDate {
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

  /// Year of the event (for filtering).
  int get year => date.year;

  /// Copy with method.
  MemoryEvent copyWith({
    String? id,
    String? title,
    MemoryEventType? type,
    DateTime? date,
    String? description,
    List<MemoryMember>? members,
    String? photoUrl,
    String? location,
    bool? isPinned,
  }) {
    return MemoryEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      date: date ?? this.date,
      description: description ?? this.description,
      members: members ?? this.members,
      photoUrl: photoUrl ?? this.photoUrl,
      location: location ?? this.location,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// On This Day Memory Model
// ═══════════════════════════════════════════════════════════════════════

/// A photo/memory from the same calendar date in a previous year.
class OnThisDayMemory {
  const OnThisDayMemory({
    required this.id,
    required this.title,
    required this.originalDate,
    required this.yearsAgo,
    this.imageUrl,
    this.description,
    this.members = const [],
    this.groupBy,
  });

  /// Unique identifier.
  final String id;

  /// Title / caption for this memory.
  final String title;

  /// Original date of the memory.
  final DateTime originalDate;

  /// How many years ago this memory occurred.
  final int yearsAgo;

  /// Optional image URL placeholder.
  final String? imageUrl;

  /// Optional description.
  final String? description;

  /// Related family members.
  final List<MemoryMember> members;

  /// Optional grouping key (person name or event type).
  final String? groupBy;

  /// Formatted "X years ago" string. Returns empty string when
  /// [yearsAgo] is 0 (same-year memory) — the "0 years ago" badge reads
  /// awkwardly, so the card UI suppresses it entirely via
  /// `if (memory.yearsAgo > 0)`. This getter also returns empty as a
  /// defensive backstop in case it's used elsewhere without the
  /// conditional check.
  String get yearsAgoLabel {
    if (yearsAgo <= 0) return '';
    return '$yearsAgo ${yearsAgo == 1 ? 'year' : 'years'} ago';
  }

  /// Formatted original date.
  String get formattedDate {
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
    return '${originalDate.day} ${months[originalDate.month]} ${originalDate.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Memories Filter
// ═══════════════════════════════════════════════════════════════════════

/// Filter options for the timeline.
///
/// `showPinnedOnly` is a separate toggle from the year/type/member filters
/// — it is wired to the pin-count badge in the screen header (tapping the
/// badge flips this to true and filters the timeline to pinned memories
/// only). It's tracked separately so that tapping the badge again restores
/// the user's prior year/type/member filter context.
class MemoriesFilter {
  const MemoriesFilter({
    this.selectedYear,
    this.selectedType,
    this.selectedMember,
    this.showPinnedOnly = false,
  });

  /// Filter by year (null = all years).
  final int? selectedYear;

  /// Filter by event type (null = all types).
  final MemoryEventType? selectedType;

  /// Filter by family member name (null = all members).
  final String? selectedMember;

  /// Toggle: show only pinned memories.
  /// Driven by the pin-count badge tap on the screen header.
  final bool showPinnedOnly;

  /// Whether no filters are active (including pinned-only).
  bool get isClear =>
      selectedYear == null &&
      selectedType == null &&
      selectedMember == null &&
      !showPinnedOnly;

  /// Whether any of the three "pill" filters (year/type/member) is active.
  /// Used by the screen to decide whether to show the "Clear filters" link.
  /// `showPinnedOnly` is treated separately (it has its own "view all"
  /// affordance next to the badge).
  bool get pillsActive =>
      selectedYear != null ||
      selectedType != null ||
      selectedMember != null;

  /// Count of active pill filters (0–3). Used for the badge counter.
  int get activePillCount =>
      (selectedYear != null ? 1 : 0) +
      (selectedType != null ? 1 : 0) +
      (selectedMember != null ? 1 : 0);

  MemoriesFilter copyWith({
    int? selectedYear,
    MemoryEventType? selectedType,
    String? selectedMember,
    bool? showPinnedOnly,
    bool clearYear = false,
    bool clearType = false,
    bool clearMember = false,
    bool clearPinnedOnly = false,
  }) {
    return MemoriesFilter(
      selectedYear: clearYear ? null : (selectedYear ?? this.selectedYear),
      selectedType: clearType ? null : (selectedType ?? this.selectedType),
      selectedMember: clearMember
          ? null
          : (selectedMember ?? this.selectedMember),
      showPinnedOnly: clearPinnedOnly ? false : (showPinnedOnly ?? this.showPinnedOnly),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Memories State
// ═══════════════════════════════════════════════════════════════════════

/// State for the memories feature.
class MemoriesState {
  const MemoriesState({
    this.events = const [],
    this.onThisDayMemories = const [],
    this.filter = const MemoriesFilter(),
    this.isLoading = false,
    this.error,
  });

  final List<MemoryEvent> events;
  final List<OnThisDayMemory> onThisDayMemories;
  final MemoriesFilter filter;
  final bool isLoading;
  final String? error;

  // ── Derived Getters ────────────────────────────────────────────────

  /// All available years for filtering.
  List<int> get availableYears {
    final years = events.map((e) => e.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  /// All available member names for filtering.
  List<String> get availableMembers {
    final names = <String>{};
    for (final e in events) {
      for (final m in e.members) {
        names.add(m.name);
      }
    }
    return names.toList()..sort();
  }

  /// Events filtered by the current filter settings.
  List<MemoryEvent> get filteredEvents {
    var result = events.toList();

    // ── Pinned-only filter (driven by the pin-count badge tap) ──────
    // Applied BEFORE the year/type/member filters so the user can
    // combine "show pinned only" with, say, a year filter.
    if (filter.showPinnedOnly) {
      result = result.where((e) => e.isPinned).toList();
    }

    if (filter.selectedYear != null) {
      result = result.where((e) => e.year == filter.selectedYear).toList();
    }
    if (filter.selectedType != null) {
      result = result.where((e) => e.type == filter.selectedType).toList();
    }
    if (filter.selectedMember != null) {
      result = result
          .where((e) => e.members.any((m) => m.name == filter.selectedMember))
          .toList();
    }

    // Pinned events first, then chronological (newest first)
    result.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.date.compareTo(a.date);
    });

    return result;
  }

  /// Whether the family has ANY memories at all (regardless of filters).
  /// Used by the screen to decide between two distinct empty states:
  ///   • `events.isEmpty` → "No memories yet — add your family's first moment"
  ///   • `events.isNotEmpty && filteredEvents.isEmpty` → "No memories
  ///     match your filters — try adjusting or clearing."
  bool get hasMemories => events.isNotEmpty;

  /// Whether the family has any pinned memories. Drives the visibility
  /// of the pin-count badge in the header (the badge is hidden when zero
  /// because there's nothing to filter to).
  bool get hasPinnedMemories => events.any((e) => e.isPinned);

  /// Count of pinned memories (drives the badge counter).
  int get pinnedCount => events.where((e) => e.isPinned).length;

  /// Events grouped by year for sectioned display.
  Map<int, List<MemoryEvent>> get eventsByYear {
    final map = <int, List<MemoryEvent>>{};
    for (final e in filteredEvents) {
      map.putIfAbsent(e.year, () => []).add(e);
    }
    // Sort years descending
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
  }

  /// Whether there are "On This Day" memories.
  bool get hasOnThisDay => onThisDayMemories.isNotEmpty;

  MemoriesState copyWith({
    List<MemoryEvent>? events,
    List<OnThisDayMemory>? onThisDayMemories,
    MemoriesFilter? filter,
    bool? isLoading,
    String? error,
  }) {
    return MemoriesState(
      events: events ?? this.events,
      onThisDayMemories: onThisDayMemories ?? this.onThisDayMemories,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Memories Notifier
// ═══════════════════════════════════════════════════════════════════════

/// State notifier managing the memories list and operations.
///
/// PRODUCTION DEFAULT
/// ──────────────────
/// The notifier starts with an EMPTY state — no demo events are loaded for
/// real families. This is intentional: the seeded "Sharma family" demo
/// data (Aarav's birth, Rajesh & Meera's wedding, Ravi's Padma Shri, etc.)
/// must NEVER appear for a brand-new real family — those families should
/// see the proper "invitation to act" empty state instead.
///
/// Demo data is still available via [loadDemoData] for:
///   • Widget tests (call from setUp)
///   • Debug-mode preview (call from a dev-only entrypoint)
///   • Test family IDs (call after construction if familyId matches a
///     known test fixture)
///
/// See: task audit "Confirm/clear seeded demo data" in the Memories &
/// Timeline brief.
class MemoriesNotifier extends StateNotifier<MemoriesState> {
  MemoriesNotifier() : super(const MemoriesState());

  /// Set the year filter.
  void setYearFilter(int? year) {
    final newFilter = year == null
        ? state.filter.copyWith(clearYear: true)
        : state.filter.copyWith(selectedYear: year);
    state = state.copyWith(filter: newFilter);
  }

  /// Set the event type filter.
  void setTypeFilter(MemoryEventType? type) {
    final newFilter = type == null
        ? state.filter.copyWith(clearType: true)
        : state.filter.copyWith(selectedType: type);
    state = state.copyWith(filter: newFilter);
  }

  /// Set the member filter.
  void setMemberFilter(String? member) {
    final newFilter = member == null
        ? state.filter.copyWith(clearMember: true)
        : state.filter.copyWith(selectedMember: member);
    state = state.copyWith(filter: newFilter);
  }

  /// Toggle the pinned-only filter (driven by the pin-count badge tap).
  /// When toggled ON, the timeline shows only pinned memories; when
  /// toggled OFF, the user's prior year/type/member filters are restored.
  void togglePinnedOnly() {
    final newFilter = state.filter.copyWith(
      showPinnedOnly: !state.filter.showPinnedOnly,
    );
    state = state.copyWith(filter: newFilter);
  }

  /// Clear all pill filters (year/type/member) but leave `showPinnedOnly`
  /// alone — the badge toggle has its own affordance to clear itself.
  void clearFilters() {
    state = state.copyWith(
      filter: MemoriesFilter(
        showPinnedOnly: state.filter.showPinnedOnly,
      ),
    );
  }

  /// Toggle pin on an event.
  void togglePin(String eventId) {
    final updatedEvents = state.events.map((e) {
      if (e.id == eventId) {
        return e.copyWith(isPinned: !e.isPinned);
      }
      return e;
    }).toList();
    // If the user just un-pinned the LAST pinned memory while
    // `showPinnedOnly` was active, the filtered list will go empty.
    // We don't auto-clear the filter — the screen's "no results while
    // pinned-only" empty state handles that UX gracefully with a
    // "No pinned memories — view all" affordance.
    state = state.copyWith(events: updatedEvents);
  }

  /// Add a new memory event.
  void addEvent(MemoryEvent event) {
    state = state.copyWith(events: [...state.events, event]);
  }

  /// Load the demo/seed memory set into the current state.
  ///
  /// This is intended for:
  ///   • Widget tests — call from `setUp` to render with known data
  ///   • Debug-mode preview — call from a dev-only entrypoint
  ///   • Test family IDs — call after construction if the family is a
  ///     known test fixture
  ///
  /// NEVER call this in production code paths for a real family — real
  /// families should see the empty-state invitation-to-act, not someone
  /// else's demo family history.
  void loadDemoData() {
    state = MemoriesState(
      events: demoMemoryEvents,
      onThisDayMemories: demoOnThisDayMemories,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

/// Main memories provider (filter state only — the actual memory list
/// comes from [displayMemoriesProvider] which reads [memoryVaultProvider]).
///
/// Historically this held the full memory list locally (demo data only).
/// The Supabase-backed memory list now lives in `memoryVaultProvider` —
/// this provider retains ONLY the filter state (year/type/member/pinned)
/// so the filter UI (setYearFilter / setTypeFilter / etc.) continues to
/// work without a full migration of the screen.
final memoriesProvider = StateNotifierProvider<MemoriesNotifier, MemoriesState>(
  (ref) {
    return MemoriesNotifier();
  },
);

// ═══════════════════════════════════════════════════════════════════════
// Cross-provider bridge: memoryVaultProvider → memoriesProvider
// ═══════════════════════════════════════════════════════════════════════
//
// BUG HISTORY (the "save not persisting" regression):
//
// The MemoriesScreen was watching `memoriesProvider` (local-only, starts
// empty in production) for its memory list. The actual save flow
// (MemoryCreateScreen → MemoryVaultNotifier.createMemory) writes to
// Supabase `family_memories` table via `memoryVaultProvider` — a DIFFERENT
// provider. The save SUCCEEDS at the DB level (the row is created with
// the correct family_id and uploader_id), but the MemoriesScreen never
// sees it because it reads from a different source that has no real data.
//
// The user would see "nothing happens" (the save succeeds, the form
// pops back, but the timeline still shows "No Memories Yet" because
// memoriesProvider is still empty). The cycling "Ravi received Padma
// Shri" card is the empty-state's ILLUSTRATION (a hardcoded placeholder
// in _AnimatedMemoryPreviewCard), NOT a real memory — but the user
// misinterprets it as leftover demo data, creating the illusion of
// "conflicting state" (a card AND the empty state showing together).
//
// FIX: this derived provider reads the REAL memory list from
// `memoryVaultProvider` (Supabase-backed), converts each `MemoryModel`
// to a `MemoryEvent` (the type the screen's widgets expect), merges with
// the filter state from `memoriesProvider`, and returns a `MemoriesState`
// that the screen can watch directly. Now the screen shows real saved
// memories, the empty state only shows when there are genuinely zero
// memories, and the "Ravi" card only appears as the empty-state
// illustration (never as a real memory alongside the empty state).

/// Converts a [MemoryModel] (Supabase-backed) to a [MemoryEvent] (the
/// type the MemoriesScreen's widgets expect).
///
/// Field mapping:
///   • id → id
///   • title (or displayTitle) → title
///   • memoryType (String, e.g. "Festival") → MemoryEventType enum
///   • takenAt (or createdAt) → date
///   • description → description
///   • displayImageUrl → photoUrl
///   • location → location
///   • isPinnedToVault → isPinned
///   • taggedPersonIds → members (empty for now — IDs without names)
MemoryEvent memoryModelToEvent(dynamic m) {
  // Use dynamic to avoid a circular import (memory_vault_provider imports
  // memories_provider indirectly). We only read fields that exist on
  // MemoryModel.
  final title = (m.title as String?) ?? (m.caption as String?) ?? 'Untitled';
  final memoryTypeStr = m.memoryType as String?;
  final date = m.takenAt as DateTime? ?? m.createdAt as DateTime;
  final photoUrl = (m.imageUrl as String?) ?? (m.photoUrl as String?) ?? '';
  final description = m.description as String?;
  final location = m.location as String?;
  final isPinned = (m.isPinnedToVault as bool?) ?? false;
  final id = m.id as String;

  return MemoryEvent(
    id: id,
    title: title,
    type: _parseMemoryEventType(memoryTypeStr),
    date: date,
    description: description,
    members: const [], // MemoryModel has tagged_person_ids (UUIDs) but
    // not display names — the member filter is hidden by the screen
    // when there are no members with names.
    photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
    location: location,
    isPinned: isPinned,
  );
}

/// Parses a memory-type string (e.g. "Festival", "Birth") into the
/// matching [MemoryEventType] enum value. Returns [MemoryEventType.custom]
/// for unknown/null values (per the spec: "otherwise default to 'Custom'
/// category, consistent with the custom-entry type already visible in
/// the current Timeline implementation").
MemoryEventType _parseMemoryEventType(String? typeStr) {
  if (typeStr == null) return MemoryEventType.custom;
  switch (typeStr.toLowerCase()) {
    case 'birth':
      return MemoryEventType.birth;
    case 'death':
    case 'memorial':
      return MemoryEventType.death;
    case 'marriage':
    case 'wedding':
      return MemoryEventType.marriage;
    case 'anniversary':
      return MemoryEventType.anniversary;
    case 'graduation':
      return MemoryEventType.graduation;
    case 'achievement':
      return MemoryEventType.achievement;
    case 'migration':
      return MemoryEventType.migration;
    case 'festival':
      return MemoryEventType.festival;
    case 'custom':
    default:
      return MemoryEventType.custom;
  }
}

/// Builds the "On This Day" list from a set of [MemoryEvent]s.
///
/// Returns events whose `date` month+day matches today. Sorted by
/// `yearsAgo` descending (most-recent first).
List<OnThisDayMemory> _onThisDayFromEvents(List<MemoryEvent> events) {
  final now = DateTime.now();
  final matches = <OnThisDayMemory>[];
  for (final e in events) {
    if (e.date.month == now.month && e.date.day == now.day) {
      final yearsAgo = now.year - e.date.year;
      matches.add(OnThisDayMemory(
        id: e.id,
        title: e.title,
        originalDate: e.date,
        yearsAgo: yearsAgo,
        imageUrl: e.photoUrl,
        description: e.description,
        members: e.members,
      ));
    }
  }
  // Most recent (smallest yearsAgo) first.
  matches.sort((a, b) => a.yearsAgo.compareTo(b.yearsAgo));
  return matches;
}

/// The display provider the MemoriesScreen watches.
///
/// Returns a [MemoriesState] with:
///   • events — the REAL memory list from [memoryVaultProvider], converted
///     to [MemoryEvent] objects for the screen's widgets.
///   • filter — from [memoriesProvider] (the local filter state).
///   • onThisDayMemories — computed from the real events.
///   • isLoading / error — from [memoryVaultProvider].
///
/// Filter mutations (setYearFilter, setTypeFilter, togglePinnedOnly,
/// clearFilters) go to `memoriesProvider.notifier` — this provider picks
/// up the changes via `ref.watch(memoriesProvider)` and recomputes
/// `filteredEvents` automatically.
///
/// Pin toggles go to `memoryVaultProvider.notifier.togglePinToVault(id)`
/// (the real DB operation) — NOT to `memoriesProvider.notifier.togglePin`
/// (which only updated the local list).
final displayMemoriesProvider = Provider<MemoriesState>((ref) {
  // Watch the vault for the real memory list + loading/error state.
  final vaultState = ref.watch(memoryVaultProvider);
  final localState = ref.watch(memoriesProvider);

  // Convert MemoryModels → MemoryEvents.
  final events = vaultState.memories.map(memoryModelToEvent).toList();
  // Sort newest-first by date (the filteredEvents getter also sorts, but
  // we sort the base list too so availableYears / availableMembers iterate
  // in a predictable order).
  events.sort((a, b) => b.date.compareTo(a.date));

  return MemoriesState(
    events: events,
    onThisDayMemories: _onThisDayFromEvents(events),
    filter: localState.filter,
    isLoading: vaultState.isLoading,
    error: vaultState.error,
  );
});

// ═══════════════════════════════════════════════════════════════════════
// Demo Data — Realistic Indian Family Timeline Events
// ───────────────────────────────────────────────────────────────────────
//
// These constants are PUBLIC so they can be:
//   • Loaded by `MemoriesNotifier.loadDemoData()` in tests/debug
//   • Imported directly by widget tests that want to render the screen
//     with known data
//
// They MUST NOT be used as the default initialization for the notifier —
// real families start empty (see `MemoriesNotifier` doc above).
// ═══════════════════════════════════════════════════════════════════════

/// Demo/seed timeline events — a realistic Indian family ("Sharma")
/// history used for tests and debug preview. NOT loaded by default.
final demoMemoryEvents = <MemoryEvent>[
  // ── 2024 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'migration-arjun-2024',
    title: 'Arjun moved to Bangalore',
    type: MemoryEventType.migration,
    date: DateTime(2024, 11, 15),
    description:
        'Arjun relocated to Bangalore for his new role at Infosys. The family gathered for a farewell dinner in Jaipur.',
    location: 'Bangalore, Karnataka',
    members: [const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS')],
    isPinned: true,
  ),

  MemoryEvent(
    id: 'diwali-2024',
    title: 'Diwali Celebration at Dadi\'s House',
    type: MemoryEventType.festival,
    date: DateTime(2024, 11, 1),
    description:
        'The whole Sharma family gathered for Diwali puja and fireworks. Little Aarav lit his first diya! 🪔',
    location: 'Sharma Haveli, Jaipur',
    members: [
      const MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
    ],
    photoUrl: 'diwali_2024.jpg',
  ),

  MemoryEvent(
    id: 'grad-priya-2024',
    title: 'Priya earned her MBA',
    type: MemoryEventType.graduation,
    date: DateTime(2024, 6, 20),
    description:
        'Priya graduated with an MBA from IIM Ahmedabad. The family is so proud! 🎓',
    location: 'IIM Ahmedabad, Gujarat',
    members: [const MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS')],
  ),

  MemoryEvent(
    id: 'achievement-ravi-2024',
    title: 'Ravi received Padma Shri Award',
    type: MemoryEventType.achievement,
    date: DateTime(2024, 1, 26),
    description:
        'Ravi Sharma was honored with the Padma Shri for his contributions to education in rural Rajasthan. A proud moment for the entire family! 🏅',
    location: 'Rashtrapati Bhavan, New Delhi',
    members: [
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
    isPinned: true,
  ),

  // ── 2023 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'birth-aarav-2023',
    title: 'Aarav Sharma was born',
    type: MemoryEventType.birth,
    date: DateTime(2023, 8, 12),
    description:
        'Welcome to the family, Aarav! Born at 3:42 AM, 3.2 kg. The youngest Sharma has arrived! 👶',
    location: 'Fortis Hospital, Jaipur',
    members: [
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      const MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS'),
      const MemoryMember(id: 'm13', name: 'Aarav Sharma', initials: 'ArS'),
    ],
  ),

  MemoryEvent(
    id: 'marriage-rajesh-meera-2023',
    title: 'Rajesh & Meera\'s Wedding',
    type: MemoryEventType.marriage,
    date: DateTime(2023, 2, 14),
    description:
        'A grand Gujarati-Rajasthani fusion wedding! Baraat with 12 bands, mehndi ceremony, and a 3-day celebration. 💍',
    location: 'JW Marriott, Jaipur',
    members: [
      const MemoryMember(id: 'm5', name: 'Rajesh Patel', initials: 'RP'),
      const MemoryMember(id: 'm4', name: 'Meera Patel', initials: 'MP'),
      const MemoryMember(id: 'm9', name: 'Saroj Devi', initials: 'SD'),
      const MemoryMember(id: 'm12', name: 'Dinesh Patel', initials: 'DP'),
    ],
    photoUrl: 'wedding_rajesh_meera.jpg',
  ),

  MemoryEvent(
    id: 'holi-2023',
    title: 'Holi at the Farmhouse',
    type: MemoryEventType.festival,
    date: DateTime(2023, 3, 8),
    description:
        'Colors, thandai, and dancing! The annual Holi party at the Kukas farmhouse was unforgettable. 🎨',
    location: 'Sharma Farmhouse, Kukas',
    members: [
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
    ],
  ),

  MemoryEvent(
    id: 'grad-neha-2023',
    title: 'Neha graduated from AIIMS',
    type: MemoryEventType.graduation,
    date: DateTime(2023, 5, 28),
    description:
        'Dr. Neha Sharma! Graduated from AIIMS New Delhi with top honors. The family celebrates the newest doctor! 🩺',
    location: 'AIIMS, New Delhi',
    members: [const MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS')],
  ),

  // ── 2022 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'anniversary-sharma-35-2022',
    title: 'Ravi & Sunita — 35th Anniversary',
    type: MemoryEventType.anniversary,
    date: DateTime(2022, 12, 10),
    description:
        'Celebrating 35 years of love and togetherness! A surprise party organized by the kids. 💕',
    location: 'Sharma Residence, Jaipur',
    members: [
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      const MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS'),
    ],
    photoUrl: 'anniversary_35.jpg',
  ),

  MemoryEvent(
    id: 'migration-dinesh-2022',
    title: 'Dinesh Patel moved to London',
    type: MemoryEventType.migration,
    date: DateTime(2022, 9, 5),
    description:
        'Dinesh moved to London for his software engineering role at Barclays. Missing his garba nights in Ahmedabad!',
    location: 'London, UK',
    members: [const MemoryMember(id: 'm12', name: 'Dinesh Patel', initials: 'DP')],
  ),

  MemoryEvent(
    id: 'custom-griha-2022',
    title: 'Griha Pravesh — New Sharma Home',
    type: MemoryEventType.custom,
    date: DateTime(2022, 4, 3),
    description:
        'Housewarming puja at the new Sharma residence in Malviya Nagar. Vastu puja followed by lunch for 200 guests. 🏠🙏',
    location: 'Malviya Nagar, Jaipur',
    members: [
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
  ),

  // ── 2020 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'marriage-arjun-priya-2020',
    title: 'Arjun & Priya\'s Wedding',
    type: MemoryEventType.marriage,
    date: DateTime(2020, 12, 8),
    description:
        'An intimate Rajasthani wedding during challenging times. The pheras were livestreamed for family abroad. 💍',
    location: 'Jai Mahal Palace, Jaipur',
    members: [
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      const MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS'),
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
    photoUrl: 'wedding_arjun_priya.jpg',
  ),

  // ── 2018 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'achievement-sunita-2018',
    title: 'Sunita opened her own clinic',
    type: MemoryEventType.achievement,
    date: DateTime(2018, 7, 1),
    description:
        'Dr. Sunita Sharma opened "Sharma Wellness Clinic" in C-Scheme, Jaipur. 15 years of practice led to this dream! 🏥',
    location: 'C-Scheme, Jaipur',
    members: [const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS')],
  ),

  // ── 2015 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'death-dada-2015',
    title: 'Suresh Kumar Sharma (Dada) passed away',
    type: MemoryEventType.death,
    date: DateTime(2015, 3, 22),
    description:
        'Dada left us peacefully at age 78, surrounded by family. His legacy of kindness and wisdom lives on in all of us. 🙏',
    location: 'Sharma Haveli, Jaipur',
    members: [
      const MemoryMember(id: 'm15', name: 'Suresh Kumar Sharma', initials: 'SKS'),
      const MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
    ],
  ),

  // ── 2012 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'grad-arjun-2012',
    title: 'Arjun graduated from IIT Delhi',
    type: MemoryEventType.graduation,
    date: DateTime(2012, 5, 25),
    description:
        'B.Tech in Computer Science from IIT Delhi. Dadi distributed mithai to the entire mohalla! 🎓',
    location: 'IIT Delhi',
    members: [
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      const MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
    ],
  ),

  // ── 1995 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'birth-neha-1995',
    title: 'Neha Sharma was born',
    type: MemoryEventType.birth,
    date: DateTime(1995, 11, 3),
    description:
        'Welcome Neha! The second child of Ravi and Sunita. Dada said she has her grandmother\'s eyes. 👶',
    location: 'SMS Hospital, Jaipur',
    members: [
      const MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS'),
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
  ),

  // ── 1992 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'birth-arjun-1992',
    title: 'Arjun Sharma was born',
    type: MemoryEventType.birth,
    date: DateTime(1992, 6, 15),
    description:
        'The eldest son of Ravi and Sunita arrives! Dada performed the naming ceremony. 👶',
    location: 'SMS Hospital, Jaipur',
    members: [
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
  ),

  // ── 1987 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'marriage-ravi-sunita-1987',
    title: 'Ravi & Sunita\'s Wedding',
    type: MemoryEventType.marriage,
    date: DateTime(1987, 12, 10),
    description:
        'An arranged marriage that became a love story. The baraat came from Jodhpur with 200 guests. 💍',
    location: 'Jodhpur, Rajasthan',
    members: [
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      const MemoryMember(id: 'm15', name: 'Suresh Kumar Sharma', initials: 'SKS'),
      const MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
    ],
    photoUrl: 'wedding_ravi_sunita_1987.jpg',
  ),
];

// ═══════════════════════════════════════════════════════════════════════
// Demo "On This Day" Memories
// ───────────────────────────────────────────────────────────────────────
//
// Demo data for tests/debug only — NOT loaded by default. See the
// `MemoriesNotifier` doc above.
// ═══════════════════════════════════════════════════════════════════════

final _now = DateTime.now();

/// Demo "On This Day" memories — used for tests and debug preview.
/// NOT loaded by default for real families.
final demoOnThisDayMemories = <OnThisDayMemory>[
  OnThisDayMemory(
    id: 'otd-1',
    title: 'Diwali at Dadi\'s House',
    originalDate: DateTime(2020, 11, 14),
    yearsAgo: _now.year - 2020,
    description:
        'A quieter Diwali during the pandemic, but the family video call lit up the night! 🪔',
    groupBy: 'Festival',
    members: [
      const MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
    ],
  ),

  OnThisDayMemory(
    id: 'otd-2',
    title: 'Priya\'s Mehndi Ceremony',
    originalDate: DateTime(2020, 12, 7),
    yearsAgo: _now.year - 2020,
    description:
        'Beautiful mehndi designs and the ladies sang traditional wedding songs. 💕',
    groupBy: 'Priya Sharma',
    members: [const MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS')],
  ),

  OnThisDayMemory(
    id: 'otd-3',
    title: 'Arjun\'s first day at Infosys',
    originalDate: DateTime(2012, 7, 16),
    yearsAgo: _now.year - 2012,
    description:
        'Nervous but excited — Arjun joined Infosys as a software engineer. The beginning of a great career! 💼',
    groupBy: 'Arjun Sharma',
    members: [const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS')],
  ),

  OnThisDayMemory(
    id: 'otd-4',
    title: 'Family trip to Udaipur',
    originalDate: DateTime(2018, 11, 10),
    yearsAgo: _now.year - 2018,
    description:
        'The whole Sharma clan at Lake Pichola. A magical sunset boat ride! 🏰',
    groupBy: 'Family Trip',
    members: [
      const MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      const MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      const MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      const MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS'),
    ],
  ),

  OnThisDayMemory(
    id: 'otd-5',
    title: 'Nani\'s 70th Birthday Surprise',
    originalDate: DateTime(2016, 3, 15),
    yearsAgo: _now.year - 2016,
    description:
        'A surprise party for Nani Saroj! She was so happy she cried. The cake had 70 candles! 🎂',
    groupBy: 'Saroj Devi',
    members: [
      const MemoryMember(id: 'm9', name: 'Saroj Devi', initials: 'SD'),
      const MemoryMember(id: 'm4', name: 'Meera Patel', initials: 'MP'),
    ],
  ),
];
