// lib/core/services/retention_service.dart
//
// DAXELO KINREL — Retention Service (P5-F4)
//
// Tracks user engagement signals in the Hive 'engagement' box
// (already opened in main.dart). Used for:
//   - Retention analytics (app opens, graph views, members added)
//   - Local notification scheduling decisions
//   - Debug engagement dashboard
//
// All writes are fire-and-forget — never block the UI.

// Hive removed — using Drift via IsarDatabase
import '../database/isar_database.dart';
import 'package:flutter/foundation.dart';

class RetentionService {
  RetentionService._();

  static const _boxName = 'engagement';

  // ── Key Constants ───────────────────────────────────────────────
  static const _keyAppOpens = 'app_opens';
  static const _keyLastOpen = 'last_open';
  static const _keyGraphViews = 'graph_views';
  static const _keyMembersAdded = 'members_added';
  static const _keyInviteLinksSent = 'invite_links_sent';

  // ── Record Methods ──────────────────────────────────────────────

  /// Record an app open event.
  /// Increments app_opens counter and updates last_open timestamp.
  static Future<void> recordAppOpen() async {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      final opens = box.get(_keyAppOpens, defaultValue: 0) as int;
      await box.put(_keyAppOpens, opens + 1);
      await box.put(_keyLastOpen, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordAppOpen failed: $e');
    }
  }

  /// Record a graph view event.
  static Future<void> recordGraphView() async {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      final views = box.get(_keyGraphViews, defaultValue: 0) as int;
      await box.put(_keyGraphViews, views + 1);
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordGraphView failed: $e');
    }
  }

  /// Record a member added event.
  static Future<void> recordMemberAdded() async {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      final added = box.get(_keyMembersAdded, defaultValue: 0) as int;
      await box.put(_keyMembersAdded, added + 1);
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordMemberAdded failed: $e');
    }
  }

  /// Record an invite link sent event.
  static Future<void> recordInviteSent() async {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      final sent = box.get(_keyInviteLinksSent, defaultValue: 0) as int;
      await box.put(_keyInviteLinksSent, sent + 1);
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordInviteSent failed: $e');
    }
  }

  // ── Read Methods ────────────────────────────────────────────────

  /// Get all engagement stats as a typed map.
  static EngagementStats getStats() {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      return EngagementStats(
        appOpens: box.get(_keyAppOpens, defaultValue: 0) as int,
        lastOpen: box.get(_keyLastOpen) as String?,
        graphViews: box.get(_keyGraphViews, defaultValue: 0) as int,
        membersAdded: box.get(_keyMembersAdded, defaultValue: 0) as int,
        inviteLinksSent: box.get(_keyInviteLinksSent, defaultValue: 0) as int,
      );
    } catch (e) {
      debugPrint('⚠️ RetentionService.getStats failed: $e');
      return EngagementStats();
    }
  }

  /// Check if the user has been inactive for the given number of days.
  static bool isInactiveForDays(int days) {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      final lastOpenStr = box.get(_keyLastOpen) as String?;
      if (lastOpenStr == null) return true;

      final lastOpen = DateTime.tryParse(lastOpenStr);
      if (lastOpen == null) return true;

      final now = DateTime.now();
      final diff = now.difference(lastOpen).inDays;
      return diff >= days;
    } catch (_) {
      return false;
    }
  }

  /// Get the member count from engagement tracking.
  static int getMembersAdded() {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      return box.get(_keyMembersAdded, defaultValue: 0) as int;
    } catch (_) {
      return 0;
    }
  }

  /// Clear all engagement data (debug only).
  static Future<void> clearAll() async {
    try {
      // Hive.box replaced with Drift — uses IsarDatabase.instance
      await box.clear();
      debugPrint('🗑️ RetentionService: All engagement data cleared');
    } catch (e) {
      debugPrint('⚠️ RetentionService.clearAll failed: $e');
    }
  }
}

/// Typed engagement stats returned by [RetentionService.getStats].
class EngagementStats {
  const EngagementStats({
    this.appOpens = 0,
    this.lastOpen,
    this.graphViews = 0,
    this.membersAdded = 0,
    this.inviteLinksSent = 0,
  });

  final int appOpens;
  final String? lastOpen;
  final int graphViews;
  final int membersAdded;
  final int inviteLinksSent;

  /// Parse lastOpen to DateTime, returns null if unavailable.
  DateTime? get lastOpenDateTime =>
      lastOpen != null ? DateTime.tryParse(lastOpen!) : null;

  @override
  String toString() =>
      'EngagementStats(opens: $appOpens, lastOpen: $lastOpen, '
      'graphViews: $graphViews, membersAdded: $membersAdded, '
      'inviteLinksSent: $inviteLinksSent)';
}
