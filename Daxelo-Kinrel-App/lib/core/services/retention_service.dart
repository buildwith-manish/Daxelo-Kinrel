// lib/core/services/retention_service.dart
//
// DAXELO KINREL — Retention Service (P5-F4)
//
// Tracks user engagement signals via SharedPreferences.
// Used for:
//   - Retention analytics (app opens, graph views, members added)
//   - Local notification scheduling decisions
//   - Debug engagement dashboard
//
// All writes are fire-and-forget — never block the UI.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class RetentionService {
  RetentionService._();

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
      final prefs = await SharedPreferences.getInstance();
      final opens = prefs.getInt(_keyAppOpens) ?? 0;
      await prefs.setInt(_keyAppOpens, opens + 1);
      await prefs.setString(_keyLastOpen, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordAppOpen failed: $e');
    }
  }

  /// Record a graph view event.
  static Future<void> recordGraphView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final views = prefs.getInt(_keyGraphViews) ?? 0;
      await prefs.setInt(_keyGraphViews, views + 1);
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordGraphView failed: $e');
    }
  }

  /// Record a member added event.
  static Future<void> recordMemberAdded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final added = prefs.getInt(_keyMembersAdded) ?? 0;
      await prefs.setInt(_keyMembersAdded, added + 1);
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordMemberAdded failed: $e');
    }
  }

  /// Record an invite link sent event.
  static Future<void> recordInviteSent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sent = prefs.getInt(_keyInviteLinksSent) ?? 0;
      await prefs.setInt(_keyInviteLinksSent, sent + 1);
    } catch (e) {
      debugPrint('⚠️ RetentionService.recordInviteSent failed: $e');
    }
  }

  // ── Read Methods ────────────────────────────────────────────────

  /// Get all engagement stats as a typed map.
  static Future<EngagementStats> getStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return EngagementStats(
        appOpens: prefs.getInt(_keyAppOpens) ?? 0,
        lastOpen: prefs.getString(_keyLastOpen),
        graphViews: prefs.getInt(_keyGraphViews) ?? 0,
        membersAdded: prefs.getInt(_keyMembersAdded) ?? 0,
        inviteLinksSent: prefs.getInt(_keyInviteLinksSent) ?? 0,
      );
    } catch (e) {
      debugPrint('⚠️ RetentionService.getStats failed: $e');
      return EngagementStats();
    }
  }

  /// Check if the user has been inactive for the given number of days.
  static Future<bool> isInactiveForDays(int days) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastOpenStr = prefs.getString(_keyLastOpen);
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
  static Future<int> getMembersAdded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyMembersAdded) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Clear all engagement data (debug only).
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAppOpens);
      await prefs.remove(_keyLastOpen);
      await prefs.remove(_keyGraphViews);
      await prefs.remove(_keyMembersAdded);
      await prefs.remove(_keyInviteLinksSent);
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
