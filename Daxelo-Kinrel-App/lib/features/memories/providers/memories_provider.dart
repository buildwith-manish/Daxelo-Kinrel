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
        return KinrelColors.orange;       // #E8612A
      case MemoryEventType.death:
        return KinrelColors.textSilver;   // #C9B4A8 — solemn
      case MemoryEventType.marriage:
        return KinrelColors.amber;        // #F59240
      case MemoryEventType.anniversary:
        return KinrelColors.gold;         // #D4AF37
      case MemoryEventType.graduation:
        return KinrelColors.info;         // #60A5FA
      case MemoryEventType.achievement:
        return KinrelColors.brightGold;   // #FFD700
      case MemoryEventType.migration:
        return KinrelColors.success;      // #4CAF7A
      case MemoryEventType.festival:
        return KinrelColors.orange;       // #E8612A
      case MemoryEventType.custom:
        return KinrelColors.textDim;      // #8A7A72
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
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

  /// Formatted "X years ago" string.
  String get yearsAgoLabel => '$yearsAgo ${yearsAgo == 1 ? 'year' : 'years'} ago';

  /// Formatted original date.
  String get formattedDate {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${originalDate.day} ${months[originalDate.month]} ${originalDate.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Memories Filter
// ═══════════════════════════════════════════════════════════════════════

/// Filter options for the timeline.
class MemoriesFilter {
  const MemoriesFilter({
    this.selectedYear,
    this.selectedType,
    this.selectedMember,
  });

  /// Filter by year (null = all years).
  final int? selectedYear;

  /// Filter by event type (null = all types).
  final MemoryEventType? selectedType;

  /// Filter by family member name (null = all members).
  final String? selectedMember;

  /// Whether no filters are active.
  bool get isClear => selectedYear == null && selectedType == null && selectedMember == null;

  MemoriesFilter copyWith({
    int? selectedYear,
    MemoryEventType? selectedType,
    String? selectedMember,
    bool clearYear = false,
    bool clearType = false,
    bool clearMember = false,
  }) {
    return MemoriesFilter(
      selectedYear: clearYear ? null : (selectedYear ?? this.selectedYear),
      selectedType: clearType ? null : (selectedType ?? this.selectedType),
      selectedMember: clearMember ? null : (selectedMember ?? this.selectedMember),
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
    final years = events.map((e) => e.year).toSet().toList()..sort((a, b) => b.compareTo(a));
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

    if (filter.selectedYear != null) {
      result = result.where((e) => e.year == filter.selectedYear).toList();
    }
    if (filter.selectedType != null) {
      result = result.where((e) => e.type == filter.selectedType).toList();
    }
    if (filter.selectedMember != null) {
      result = result.where((e) =>
          e.members.any((m) => m.name == filter.selectedMember)).toList();
    }

    // Pinned events first, then chronological (newest first)
    result.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.date.compareTo(a.date);
    });

    return result;
  }

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
class MemoriesNotifier extends StateNotifier<MemoriesState> {
  MemoriesNotifier() : super(MemoriesState(
    events: _demoEvents,
    onThisDayMemories: _demoOnThisDay,
  ));

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

  /// Clear all filters.
  void clearFilters() {
    state = state.copyWith(
      filter: const MemoriesFilter(),
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
    state = state.copyWith(events: updatedEvents);
  }

  /// Add a new memory event.
  void addEvent(MemoryEvent event) {
    state = state.copyWith(events: [...state.events, event]);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════

/// Main memories provider.
final memoriesProvider =
    StateNotifierProvider<MemoriesNotifier, MemoriesState>((ref) {
  return MemoriesNotifier();
});

// ═══════════════════════════════════════════════════════════════════════
// Demo Data — Realistic Indian Family Timeline Events
// ═══════════════════════════════════════════════════════════════════════

final _demoEvents = <MemoryEvent>[
  // ── 2024 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'migration-arjun-2024',
    title: 'Arjun moved to Bangalore',
    type: MemoryEventType.migration,
    date: DateTime(2024, 11, 15),
    description: 'Arjun relocated to Bangalore for his new role at Infosys. The family gathered for a farewell dinner in Jaipur.',
    location: 'Bangalore, Karnataka',
    members: [
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
    ],
    isPinned: true,
  ),

  MemoryEvent(
    id: 'diwali-2024',
    title: 'Diwali Celebration at Dadi\'s House',
    type: MemoryEventType.festival,
    date: DateTime(2024, 11, 1),
    description: 'The whole Sharma family gathered for Diwali puja and fireworks. Little Aarav lit his first diya! 🪔',
    location: 'Sharma Haveli, Jaipur',
    members: [
      MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
    ],
    photoUrl: 'diwali_2024.jpg',
  ),

  MemoryEvent(
    id: 'grad-priya-2024',
    title: 'Priya earned her MBA',
    type: MemoryEventType.graduation,
    date: DateTime(2024, 6, 20),
    description: 'Priya graduated with an MBA from IIM Ahmedabad. The family is so proud! 🎓',
    location: 'IIM Ahmedabad, Gujarat',
    members: [
      MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS'),
    ],
  ),

  MemoryEvent(
    id: 'achievement-ravi-2024',
    title: 'Ravi received Padma Shri Award',
    type: MemoryEventType.achievement,
    date: DateTime(2024, 1, 26),
    description: 'Ravi Sharma was honored with the Padma Shri for his contributions to education in rural Rajasthan. A proud moment for the entire family! 🏅',
    location: 'Rashtrapati Bhavan, New Delhi',
    members: [
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
    isPinned: true,
  ),

  // ── 2023 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'birth-aarav-2023',
    title: 'Aarav Sharma was born',
    type: MemoryEventType.birth,
    date: DateTime(2023, 8, 12),
    description: 'Welcome to the family, Aarav! Born at 3:42 AM, 3.2 kg. The youngest Sharma has arrived! 👶',
    location: 'Fortis Hospital, Jaipur',
    members: [
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS'),
      MemoryMember(id: 'm13', name: 'Aarav Sharma', initials: 'ArS'),
    ],
  ),

  MemoryEvent(
    id: 'marriage-rajesh-meera-2023',
    title: 'Rajesh & Meera\'s Wedding',
    type: MemoryEventType.marriage,
    date: DateTime(2023, 2, 14),
    description: 'A grand Gujarati-Rajasthani fusion wedding! Baraat with 12 bands, mehndi ceremony, and a 3-day celebration. 💍',
    location: 'JW Marriott, Jaipur',
    members: [
      MemoryMember(id: 'm5', name: 'Rajesh Patel', initials: 'RP'),
      MemoryMember(id: 'm4', name: 'Meera Patel', initials: 'MP'),
      MemoryMember(id: 'm9', name: 'Saroj Devi', initials: 'SD'),
      MemoryMember(id: 'm12', name: 'Dinesh Patel', initials: 'DP'),
    ],
    photoUrl: 'wedding_rajesh_meera.jpg',
  ),

  MemoryEvent(
    id: 'holi-2023',
    title: 'Holi at the Farmhouse',
    type: MemoryEventType.festival,
    date: DateTime(2023, 3, 8),
    description: 'Colors, thandai, and dancing! The annual Holi party at the Kukas farmhouse was unforgettable. 🎨',
    location: 'Sharma Farmhouse, Kukas',
    members: [
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
    ],
  ),

  MemoryEvent(
    id: 'grad-neha-2023',
    title: 'Neha graduated from AIIMS',
    type: MemoryEventType.graduation,
    date: DateTime(2023, 5, 28),
    description: 'Dr. Neha Sharma! Graduated from AIIMS New Delhi with top honors. The family celebrates the newest doctor! 🩺',
    location: 'AIIMS, New Delhi',
    members: [
      MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS'),
    ],
  ),

  // ── 2022 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'anniversary-sharma-35-2022',
    title: 'Ravi & Sunita — 35th Anniversary',
    type: MemoryEventType.anniversary,
    date: DateTime(2022, 12, 10),
    description: 'Celebrating 35 years of love and togetherness! A surprise party organized by the kids. 💕',
    location: 'Sharma Residence, Jaipur',
    members: [
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS'),
    ],
    photoUrl: 'anniversary_35.jpg',
  ),

  MemoryEvent(
    id: 'migration-dinesh-2022',
    title: 'Dinesh Patel moved to London',
    type: MemoryEventType.migration,
    date: DateTime(2022, 9, 5),
    description: 'Dinesh moved to London for his software engineering role at Barclays. Missing his garba nights in Ahmedabad!',
    location: 'London, UK',
    members: [
      MemoryMember(id: 'm12', name: 'Dinesh Patel', initials: 'DP'),
    ],
  ),

  MemoryEvent(
    id: 'custom-griha-2022',
    title: 'Griha Pravesh — New Sharma Home',
    type: MemoryEventType.custom,
    date: DateTime(2022, 4, 3),
    description: 'Housewarming puja at the new Sharma residence in Malviya Nagar. Vastu puja followed by lunch for 200 guests. 🏠🙏',
    location: 'Malviya Nagar, Jaipur',
    members: [
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
  ),

  // ── 2020 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'marriage-arjun-priya-2020',
    title: 'Arjun & Priya\'s Wedding',
    type: MemoryEventType.marriage,
    date: DateTime(2020, 12, 8),
    description: 'An intimate Rajasthani wedding during challenging times. The pheras were livestreamed for family abroad. 💍',
    location: 'Jai Mahal Palace, Jaipur',
    members: [
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS'),
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
    photoUrl: 'wedding_arjun_priya.jpg',
  ),

  // ── 2018 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'achievement-sunita-2018',
    title: 'Sunita opened her own clinic',
    type: MemoryEventType.achievement,
    date: DateTime(2018, 7, 1),
    description: 'Dr. Sunita Sharma opened "Sharma Wellness Clinic" in C-Scheme, Jaipur. 15 years of practice led to this dream! 🏥',
    location: 'C-Scheme, Jaipur',
    members: [
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
  ),

  // ── 2015 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'death-dada-2015',
    title: 'Suresh Kumar Sharma (Dada) passed away',
    type: MemoryEventType.death,
    date: DateTime(2015, 3, 22),
    description: 'Dada left us peacefully at age 78, surrounded by family. His legacy of kindness and wisdom lives on in all of us. 🙏',
    location: 'Sharma Haveli, Jaipur',
    members: [
      MemoryMember(id: 'm15', name: 'Suresh Kumar Sharma', initials: 'SKS'),
      MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
    ],
  ),

  // ── 2012 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'grad-arjun-2012',
    title: 'Arjun graduated from IIT Delhi',
    type: MemoryEventType.graduation,
    date: DateTime(2012, 5, 25),
    description: 'B.Tech in Computer Science from IIT Delhi. Dadi distributed mithai to the entire mohalla! 🎓',
    location: 'IIT Delhi',
    members: [
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
    ],
  ),

  // ── 1995 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'birth-neha-1995',
    title: 'Neha Sharma was born',
    type: MemoryEventType.birth,
    date: DateTime(1995, 11, 3),
    description: 'Welcome Neha! The second child of Ravi and Sunita. Dada said she has her grandmother\'s eyes. 👶',
    location: 'SMS Hospital, Jaipur',
    members: [
      MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS'),
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
  ),

  // ── 1992 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'birth-arjun-1992',
    title: 'Arjun Sharma was born',
    type: MemoryEventType.birth,
    date: DateTime(1992, 6, 15),
    description: 'The eldest son of Ravi and Sunita arrives! Dada performed the naming ceremony. 👶',
    location: 'SMS Hospital, Jaipur',
    members: [
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
    ],
  ),

  // ── 1987 ──────────────────────────────────────────────────────────
  MemoryEvent(
    id: 'marriage-ravi-sunita-1987',
    title: 'Ravi & Sunita\'s Wedding',
    type: MemoryEventType.marriage,
    date: DateTime(1987, 12, 10),
    description: 'An arranged marriage that became a love story. The baraat came from Jodhpur with 200 guests. 💍',
    location: 'Jodhpur, Rajasthan',
    members: [
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      MemoryMember(id: 'm15', name: 'Suresh Kumar Sharma', initials: 'SKS'),
      MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
    ],
    photoUrl: 'wedding_ravi_sunita_1987.jpg',
  ),
];

// ═══════════════════════════════════════════════════════════════════════
// Demo "On This Day" Memories
// ═══════════════════════════════════════════════════════════════════════

final _now = DateTime.now();

final _demoOnThisDay = <OnThisDayMemory>[
  OnThisDayMemory(
    id: 'otd-1',
    title: 'Diwali at Dadi\'s House',
    originalDate: DateTime(2020, 11, 14),
    yearsAgo: _now.year - 2020,
    description: 'A quieter Diwali during the pandemic, but the family video call lit up the night! 🪔',
    groupBy: 'Festival',
    members: [
      MemoryMember(id: 'm6', name: 'Kamla Sharma', initials: 'KS'),
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
    ],
  ),

  OnThisDayMemory(
    id: 'otd-2',
    title: 'Priya\'s Mehndi Ceremony',
    originalDate: DateTime(2020, 12, 7),
    yearsAgo: _now.year - 2020,
    description: 'Beautiful mehndi designs and the ladies sang traditional wedding songs. 💕',
    groupBy: 'Priya Sharma',
    members: [
      MemoryMember(id: 'm2', name: 'Priya Sharma', initials: 'PS'),
    ],
  ),

  OnThisDayMemory(
    id: 'otd-3',
    title: 'Arjun\'s first day at Infosys',
    originalDate: DateTime(2012, 7, 16),
    yearsAgo: _now.year - 2012,
    description: 'Nervous but excited — Arjun joined Infosys as a software engineer. The beginning of a great career! 💼',
    groupBy: 'Arjun Sharma',
    members: [
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
    ],
  ),

  OnThisDayMemory(
    id: 'otd-4',
    title: 'Family trip to Udaipur',
    originalDate: DateTime(2018, 11, 10),
    yearsAgo: _now.year - 2018,
    description: 'The whole Sharma clan at Lake Pichola. A magical sunset boat ride! 🏰',
    groupBy: 'Family Trip',
    members: [
      MemoryMember(id: 'm7', name: 'Ravi Sharma', initials: 'RS'),
      MemoryMember(id: 'm8', name: 'Sunita Sharma', initials: 'SS'),
      MemoryMember(id: 'm1', name: 'Arjun Sharma', initials: 'AS'),
      MemoryMember(id: 'm14', name: 'Neha Sharma', initials: 'NS'),
    ],
  ),

  OnThisDayMemory(
    id: 'otd-5',
    title: 'Nani\'s 70th Birthday Surprise',
    originalDate: DateTime(2016, 3, 15),
    yearsAgo: _now.year - 2016,
    description: 'A surprise party for Nani Saroj! She was so happy she cried. The cake had 70 candles! 🎂',
    groupBy: 'Saroj Devi',
    members: [
      MemoryMember(id: 'm9', name: 'Saroj Devi', initials: 'SD'),
      MemoryMember(id: 'm4', name: 'Meera Patel', initials: 'MP'),
    ],
  ),
];
