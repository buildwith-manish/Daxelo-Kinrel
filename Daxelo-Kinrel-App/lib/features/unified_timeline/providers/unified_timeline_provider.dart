// lib/features/unified_timeline/providers/unified_timeline_provider.dart
//
// P7.4d — Unified family timeline.
// Merges: graph events (born, married, deceased), calendar events,
// memory photos. Reuses existing providers — no new data fetches.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The type of timeline event.
enum TimelineEventType {
  birth,
  marriage,
  death,
  calendar,
  memory,
  milestone,
}

/// A single unified timeline event.
@immutable
class UnifiedTimelineEvent {
  const UnifiedTimelineEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.title,
    this.subtitle,
    this.personId,
    this.personName,
    this.photoUrl,
    this.route,
  });

  final String id;
  final TimelineEventType type;
  final DateTime date;
  final String title;
  final String? subtitle;
  final String? personId;
  final String? personName;
  final String? photoUrl;
  final String? route;

  /// Color for the event type (for the timeline color-coding).
  int get colorValue {
    switch (type) {
      case TimelineEventType.birth:
        return 0xFF10B981; // green
      case TimelineEventType.marriage:
        return 0xFFEC4899; // pink
      case TimelineEventType.death:
        return 0xFF6B7280; // grey
      case TimelineEventType.calendar:
        return 0xFF3B82F6; // blue
      case TimelineEventType.memory:
        return 0xFFF59240; // amber
      case TimelineEventType.milestone:
        return 0xFFE8612A; // ember
    }
  }
}

/// State of the unified timeline.
@immutable
class UnifiedTimelineState {
  const UnifiedTimelineState({
    this.events = const [],
    this.isLoading = false,
    this.error,
  });

  final List<UnifiedTimelineEvent> events;
  final bool isLoading;
  final String? error;

  /// Events sorted by date (most recent first).
  List<UnifiedTimelineEvent> get sortedEvents =>
      List.from(events)..sort((a, b) => b.date.compareTo(a.date));

  UnifiedTimelineState copyWith({
    List<UnifiedTimelineEvent>? events,
    bool? isLoading,
    String? error,
  }) {
    return UnifiedTimelineState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Controller for the unified timeline.
/// Merges data from existing providers — no new data fetches.
class UnifiedTimelineController extends StateNotifier<UnifiedTimelineState> {
  UnifiedTimelineController() : super(const UnifiedTimelineState());

  /// Merges events from multiple sources.
  void mergeEvents(List<UnifiedTimelineEvent> allEvents) {
    state = state.copyWith(events: allEvents);
  }

  /// Adds a single event.
  void addEvent(UnifiedTimelineEvent event) {
    state = state.copyWith(events: [...state.events, event]);
  }

  /// Filters events by type.
  List<UnifiedTimelineEvent> filterByType(TimelineEventType type) {
    return state.sortedEvents.where((e) => e.type == type).toList();
  }
}

final unifiedTimelineProvider =
    StateNotifierProvider<UnifiedTimelineController, UnifiedTimelineState>(
  (ref) => UnifiedTimelineController(),
);
