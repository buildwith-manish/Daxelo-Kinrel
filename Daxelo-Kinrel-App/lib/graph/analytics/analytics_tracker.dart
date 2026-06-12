// lib/graph/analytics/analytics_tracker.dart
//
// DAXELO KINREL — Analytics Tracker
//
// Event tracking and performance monitoring for graph-specific analytics.
//
// Batching: all events batched and sent every 30 seconds.
// Critical events (crashes, errors) sent immediately.
// Uses existing AnalyticsService for Firebase delivery.
//
// Dashboard alert thresholds:
//   P95 open > 5s, FPS < 30 → alert
//   DAU drop > 20% WoW → alert
//   Crash > 0.5%, RPC fail > 5% → alert
//   Orphaned > 0, circular > 10 → alert

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/analytics_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// EVENT PRIORITY
// ═══════════════════════════════════════════════════════════════════════

/// Priority levels for analytics events.
///
/// - [normal]: batched and sent every 30 seconds
/// - [high]: batched but flagged for priority processing
/// - [critical]: sent immediately (crashes, fatal errors)
enum EventPriority {
  /// Batched and sent on the normal 30-second cycle.
  normal,

  /// Batched but flagged as high-priority for dashboard alerts.
  high,

  /// Sent immediately — no batching delay.
  critical,
}

// ═══════════════════════════════════════════════════════════════════════
// BATCHED EVENT
// ═══════════════════════════════════════════════════════════════════════

/// Internal representation of a queued analytics event.
class _BatchedEvent {
  /// Firebase event name.
  final String name;

  /// Event parameters.
  final Map<String, Object> params;

  /// Priority level.
  final EventPriority priority;

  /// When this event was created.
  final DateTime createdAt;

  const _BatchedEvent({
    required this.name,
    required this.params,
    required this.priority,
    required this.createdAt,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// ANALYTICS TRACKER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks graph-specific analytics events with 30-second batching.
///
/// Events are categorized by priority:
///   - Normal: batched and sent every 30 seconds
///   - High: batched but flagged for alerting (P95, engine fallback)
///   - Critical: sent immediately (crashes)
///
/// Usage:
/// ```dart
/// final tracker = ref.read(analyticsTrackerProvider);
/// tracker.trackNodeClick('member-123', 'father', 1);
/// tracker.trackGraphOpenTime(1200, 45, true);
/// tracker.trackGraphCrash('StateError', stackTrace, 45);
/// ```
class AnalyticsTracker {
  AnalyticsTracker(this._analyticsService);

  final AnalyticsService _analyticsService;

  /// Queue of batched events waiting to be sent.
  final List<_BatchedEvent> _eventQueue = [];

  /// Timer for the 30-second batching cycle.
  Timer? _batchTimer;

  /// Whether the tracker has been disposed.
  bool _isDisposed = false;

  // ── Event Name Constants ───────────────────────────────────────────

  static const String _eventNodeClick = 'graph_node_click';
  static const String _eventBranchExpand = 'graph_branch_expand';
  static const String _eventSearchQuery = 'graph_search_query';
  static const String _eventFilterApplied = 'graph_filter_applied';
  static const String _eventCameraFocus = 'graph_camera_focus';
  static const String _eventGraphOpenTime = 'graph_open_time';
  static const String _eventSimulationFps = 'graph_simulation_fps';
  static const String _eventMemoryUsage = 'graph_memory_usage';
  static const String _eventGraphCrash = 'graph_crash';
  static const String _eventEngineFallback = 'graph_engine_fallback';
  static const String _eventOnboardingStep = 'graph_onboarding_step';

  // ── Parameter Name Constants ───────────────────────────────────────

  static const String _paramMemberId = 'member_id';
  static const String _paramRelationshipType = 'relationship_type';
  static const String _paramDisclosureLevel = 'disclosure_level';
  static const String _paramBranchType = 'branch_type';
  static const String _paramNodesRevealedCount = 'nodes_revealed_count';
  static const String _paramLoadTimeMs = 'load_time_ms';
  static const String _paramQueryLength = 'query_length';
  static const String _paramResultCount = 'result_count';
  static const String _paramResponseTimeMs = 'response_time_ms';
  static const String _paramFilterType = 'filter_type';
  static const String _paramNodesBefore = 'nodes_visible_before';
  static const String _paramNodesAfter = 'nodes_visible_after';
  static const String _paramTargetMemberId = 'target_member_id';
  static const String _paramAnimationDurationMs = 'animation_duration_ms';
  static const String _paramTotalMs = 'total_ms';
  static const String _paramNodeCount = 'node_count';
  static const String _paramCacheHit = 'cache_hit';
  static const String _paramFps = 'fps';
  static const String _paramAlphaValue = 'alpha_value';
  static const String _paramTotalMb = 'total_mb';
  static const String _paramGraphMb = 'graph_mb';
  static const String _paramCacheMb = 'cache_mb';
  static const String _paramExceptionType = 'exception_type';
  static const String _paramStackTrace = 'stack_trace';
  static const String _paramFromTier = 'from_tier';
  static const String _paramToTier = 'to_tier';
  static const String _paramReason = 'reason';
  static const String _paramStepNumber = 'step_number';

  // ── Initialization ─────────────────────────────────────────────────

  /// Starts the 30-second batching timer.
  void _ensureTimerRunning() {
    if (_batchTimer != null && _batchTimer!.isActive) return;

    _batchTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      flush();
    });
  }

  // ── Event Tracking Methods ─────────────────────────────────────────

  /// Tracks a node click event.
  ///
  /// [memberId]: the clicked member's ID
  /// [relationshipType]: the relationship type key (e.g., 'father')
  /// [disclosureLevel]: the current disclosure level (0-5)
  void trackNodeClick(
    String memberId,
    String relationshipType,
    int disclosureLevel,
  ) {
    _enqueue(
      name: _eventNodeClick,
      params: {
        _paramMemberId: memberId,
        _paramRelationshipType: relationshipType,
        _paramDisclosureLevel: disclosureLevel,
      },
      priority: EventPriority.normal,
    );
  }

  /// Tracks a branch expand event.
  ///
  /// [memberId]: the expanded member's ID
  /// [branchType]: type of branch (e.g., 'parent', 'child')
  /// [nodesRevealed]: count of newly revealed nodes
  /// [loadTimeMs]: time taken to load the branch in milliseconds
  void trackBranchExpand(
    String memberId,
    String branchType,
    int nodesRevealed,
    int loadTimeMs,
  ) {
    _enqueue(
      name: _eventBranchExpand,
      params: {
        _paramMemberId: memberId,
        _paramBranchType: branchType,
        _paramNodesRevealedCount: nodesRevealed,
        _paramLoadTimeMs: loadTimeMs,
      },
      priority: EventPriority.normal,
    );
  }

  /// Tracks a search query event.
  ///
  /// [queryLength]: length of the search query string
  /// [resultCount]: number of results returned
  /// [responseTimeMs]: time taken for the search in milliseconds
  void trackSearchQuery(
    int queryLength,
    int resultCount,
    int responseTimeMs,
  ) {
    _enqueue(
      name: _eventSearchQuery,
      params: {
        _paramQueryLength: queryLength,
        _paramResultCount: resultCount,
        _paramResponseTimeMs: responseTimeMs,
      },
      priority: EventPriority.normal,
    );
  }

  /// Tracks a filter applied event.
  ///
  /// [filterType]: type of filter applied (e.g., 'relationship', 'generation')
  /// [nodesBefore]: visible node count before the filter
  /// [nodesAfter]: visible node count after the filter
  void trackFilterApplied(
    String filterType,
    int nodesBefore,
    int nodesAfter,
  ) {
    _enqueue(
      name: _eventFilterApplied,
      params: {
        _paramFilterType: filterType,
        _paramNodesBefore: nodesBefore,
        _paramNodesAfter: nodesAfter,
      },
      priority: EventPriority.normal,
    );
  }

  /// Tracks a camera focus event.
  ///
  /// [targetMemberId]: the member ID the camera focused on
  /// [animationDurationMs]: duration of the focus animation in ms
  void trackCameraFocus(
    String targetMemberId,
    int animationDurationMs,
  ) {
    _enqueue(
      name: _eventCameraFocus,
      params: {
        _paramTargetMemberId: targetMemberId,
        _paramAnimationDurationMs: animationDurationMs,
      },
      priority: EventPriority.normal,
    );
  }

  /// Tracks the total time to open and render the graph.
  ///
  /// [totalMs]: total open time in milliseconds
  /// [nodeCount]: number of nodes in the graph
  /// [cacheHit]: whether the layout was served from cache
  void trackGraphOpenTime(
    int totalMs,
    int nodeCount,
    bool cacheHit,
  ) {
    _enqueue(
      name: _eventGraphOpenTime,
      params: {
        _paramTotalMs: totalMs,
        _paramNodeCount: nodeCount,
        _paramCacheHit: cacheHit,
      },
      priority: EventPriority.high,
    );
  }

  /// Tracks simulation FPS performance.
  ///
  /// [fps]: current frames per second
  /// [nodeCount]: number of nodes being simulated
  /// [alphaValue]: current simulation alpha (energy) value
  void trackSimulationFps(
    double fps,
    int nodeCount,
    double alphaValue,
  ) {
    _enqueue(
      name: _eventSimulationFps,
      params: {
        _paramFps: fps.round(),
        _paramNodeCount: nodeCount,
        _paramAlphaValue: alphaValue.roundToDouble(),
      },
      priority: EventPriority.normal,
    );
  }

  /// Tracks memory usage metrics.
  ///
  /// [totalMb]: total memory used in MB
  /// [graphMb]: memory used by graph data in MB
  /// [cacheMb]: memory used by caches in MB
  void trackMemoryUsage(
    double totalMb,
    double graphMb,
    double cacheMb,
  ) {
    _enqueue(
      name: _eventMemoryUsage,
      params: {
        _paramTotalMb: totalMb.roundToDouble(),
        _paramGraphMb: graphMb.roundToDouble(),
        _paramCacheMb: cacheMb.roundToDouble(),
      },
      priority: EventPriority.normal,
    );
  }

  /// Tracks a graph crash event.
  ///
  /// CRITICAL: sent immediately, not batched.
  ///
  /// [exceptionType]: the exception class name
  /// [stackTrace]: the stack trace string (truncated to 500 chars)
  /// [nodeCount]: number of nodes at time of crash
  void trackGraphCrash(
    String exceptionType,
    String stackTrace,
    int nodeCount,
  ) {
    // Truncate stack trace to avoid oversized event payloads
    final truncatedStack = stackTrace.length > 500
        ? stackTrace.substring(0, 500)
        : stackTrace;

    _sendImmediate(
      name: _eventGraphCrash,
      params: {
        _paramExceptionType: exceptionType,
        _paramStackTrace: truncatedStack,
        _paramNodeCount: nodeCount,
      },
    );
  }

  /// Tracks an engine fallback event (tier downgrade).
  ///
  /// [fromTier]: the engine tier being fallen back FROM
  /// [toTier]: the engine tier being fallen back TO
  /// [nodeCount]: number of nodes in the graph
  /// [reason]: reason for the fallback
  void trackEngineFallback(
    String fromTier,
    String toTier,
    int nodeCount,
    String reason,
  ) {
    _enqueue(
      name: _eventEngineFallback,
      params: {
        _paramFromTier: fromTier,
        _paramToTier: toTier,
        _paramNodeCount: nodeCount,
        _paramReason: reason,
      },
      priority: EventPriority.high,
    );
  }

  /// Tracks an onboarding step completion event.
  ///
  /// [stepNumber]: which onboarding step was completed (1-4)
  void trackOnboardingStepCompleted(int stepNumber) {
    _enqueue(
      name: _eventOnboardingStep,
      params: {
        _paramStepNumber: stepNumber,
      },
      priority: EventPriority.normal,
    );
  }

  // ── Queue Management ───────────────────────────────────────────────

  /// Adds an event to the batch queue.
  void _enqueue({
    required String name,
    required Map<String, Object> params,
    required EventPriority priority,
  }) {
    if (_isDisposed) return;

    _eventQueue.add(_BatchedEvent(
      name: name,
      params: params,
      priority: priority,
      createdAt: DateTime.now(),
    ));

    _ensureTimerRunning();
  }

  /// Sends a critical event immediately without batching.
  void _sendImmediate({
    required String name,
    required Map<String, Object> params,
  }) {
    if (_isDisposed) return;

    try {
      _analyticsService.logEvent(name, params);
    } catch (e) {
      debugPrint('[AnalyticsTracker] Immediate send failed: $e');
    }
  }

  /// Flushes all batched events immediately.
  ///
  /// Called automatically every 30 seconds by the batch timer,
  /// or manually when the user needs events sent right away.
  void flush() {
    if (_isDisposed || _eventQueue.isEmpty) return;

    final eventsToSend = List<_BatchedEvent>.from(_eventQueue);
    _eventQueue.clear();

    for (final event in eventsToSend) {
      try {
        _analyticsService.logEvent(event.name, event.params);
      } catch (e) {
        debugPrint('[AnalyticsTracker] Failed to send event '
            '${event.name}: $e');
      }
    }
  }

  /// Disposes the tracker: flushes remaining events and cancels the timer.
  void dispose() {
    _isDisposed = true;
    flush();
    _batchTimer?.cancel();
    _batchTimer = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Riverpod provider for the [AnalyticsTracker].
///
/// Depends on the existing [AnalyticsService] for Firebase delivery.
final analyticsTrackerProvider = Provider<AnalyticsTracker>((ref) {
  final analyticsService = ref.watch(analyticsServiceProvider);
  final tracker = AnalyticsTracker(analyticsService);

  ref.onDispose(() {
    tracker.dispose();
  });

  return tracker;
});
