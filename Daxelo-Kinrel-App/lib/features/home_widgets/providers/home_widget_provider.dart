// lib/features/home_widgets/providers/home_widget_provider.dart
//
// P9.2e — Home-screen widgets.
//
// Exposes the set of home-screen widget kinds the app can pin and the
// user's current pinned selection. This provider is about *which*
// widgets are pinned and how often they may refresh — it does not
// itself render or push. Refresh intervals are clamped to a small,
// battery-friendly minimum.
//
// Constitution / Copy-Audit: no engagement metrics. Widgets surface
// neutral factual content (next occasion, today's brief). No "you
// haven't checked the app" widget text.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kind of home-screen widget. Stable string token for the platform channel.
enum HomeWidgetKind {
  upcomingOccasion,
  dailyBrief,
  familyNote,
  kinrelSymbol,
}

/// Minimum refresh interval the platform will honour (battery-friendly).
const Duration kMinWidgetRefresh = Duration(minutes: 30);

@immutable
class HomeWidgetConfig {
  const HomeWidgetConfig({
    required this.id,
    required this.kind,
    required this.title,
    required this.refreshInterval,
    this.subtitle = '',
  });

  final String id;
  final HomeWidgetKind kind;
  final String title;
  final String subtitle;
  final Duration refreshInterval;

  HomeWidgetConfig copyWith({
    String? id,
    HomeWidgetKind? kind,
    String? title,
    String? subtitle,
    Duration? refreshInterval,
  }) {
    return HomeWidgetConfig(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      refreshInterval: refreshInterval ?? this.refreshInterval,
    );
  }
}

@immutable
class HomeWidgetState {
  const HomeWidgetState({
    this.availableKinds = const [
      HomeWidgetKind.upcomingOccasion,
      HomeWidgetKind.dailyBrief,
      HomeWidgetKind.familyNote,
      HomeWidgetKind.kinrelSymbol,
    ],
    this.pinned = const [],
    this.error,
  });

  final List<HomeWidgetKind> availableKinds;
  final List<HomeWidgetConfig> pinned;
  final String? error;

  HomeWidgetState copyWith({
    List<HomeWidgetKind>? availableKinds,
    List<HomeWidgetConfig>? pinned,
    String? error,
    bool clearError = false,
  }) {
    return HomeWidgetState(
      availableKinds: availableKinds ?? this.availableKinds,
      pinned: pinned ?? this.pinned,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HomeWidgetNotifier extends StateNotifier<HomeWidgetState> {
  HomeWidgetNotifier() : super(const HomeWidgetState());

  int _counter = 0;

  /// Pins a widget. [refreshInterval] is clamped to the battery-friendly
  /// minimum so the platform never gets a runaway poller.
  void pin({
    required HomeWidgetKind kind,
    required String title,
    String subtitle = '',
    Duration refreshInterval = const Duration(minutes: 60),
  }) {
    if (title.trim().isEmpty) {
      state = state.copyWith(error: 'Widget needs a title.');
      return;
    }
    final clamped = refreshInterval < kMinWidgetRefresh
        ? kMinWidgetRefresh
        : refreshInterval;
    final config = HomeWidgetConfig(
      id: 'widget-${_counter++}',
      kind: kind,
      title: title.trim(),
      subtitle: subtitle.trim(),
      refreshInterval: clamped,
    );
    state = state.copyWith(pinned: [...state.pinned, config], clearError: true);
  }

  void unpin(String id) {
    state = state.copyWith(
      pinned: state.pinned.where((w) => w.id != id).toList(),
    );
  }

  void updateRefreshInterval(String id, Duration interval) {
    final clamped =
        interval < kMinWidgetRefresh ? kMinWidgetRefresh : interval;
    state = state.copyWith(
      pinned: [
        for (final w in state.pinned)
          if (w.id == id) w.copyWith(refreshInterval: clamped) else w,
      ],
    );
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final homeWidgetProvider =
    StateNotifierProvider<HomeWidgetNotifier, HomeWidgetState>(
  (ref) => HomeWidgetNotifier(),
);
