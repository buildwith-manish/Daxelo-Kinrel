// lib/features/family/providers/family_invite_provider.dart
//
// DAXELO KINREL — Family Invite Provider
//
// Manages family invitations with tracking:
//   • Generate invite link: kinrel.app/join/KIN-XXXXXXXX
//   • Share via system share sheet
//   • Copy Family ID to clipboard
//   • Track invite sent (by channel: link, qr_code, direct, whatsapp, sms)
//   • Get invite analytics
//
// Enhancements (Task 4):
//   • InviteRecord model for individual invite tracking
//   • Invite history with status (pending/accepted/rejected)
//   • Invite link expiration & regeneration
//   • Local caching of invite records via Drift ApiCacheEntries
//   • Recent invitees provider
//   • Bulk invite tracking
//   • Invite link click tracking
//   • Invite status stream provider

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

import '../../../core/networking/dio_client.dart';
import '../../../core/services/deep_link_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/database/isar_database.dart';

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// Invite analytics for a family.
class InviteAnalytics {
  const InviteAnalytics({
    this.totalInvitesSent = 0,
    this.accepted = 0,
    this.pending = 0,
    this.rejected = 0,
    this.byChannel = const {},
  });

  factory InviteAnalytics.fromJson(Map<String, dynamic> json) {
    final byChannelRaw = json['byChannel'] as Map<String, dynamic>?;
    final byChannel = <String, int>{};
    if (byChannelRaw != null) {
      byChannelRaw.forEach((key, value) {
        byChannel[key] = (value is int) ? value : int.tryParse(value.toString()) ?? 0;
      });
    }

    return InviteAnalytics(
      totalInvitesSent: _parseInt(json['totalInvitesSent']),
      accepted: _parseInt(json['accepted']),
      pending: _parseInt(json['pending']),
      rejected: _parseInt(json['rejected']),
      byChannel: byChannel,
    );
  }

  final int totalInvitesSent;
  final int accepted;
  final int pending;
  final int rejected;
  final Map<String, int> byChannel;

  /// Empty analytics
  static const empty = InviteAnalytics();

  Map<String, dynamic> toJson() => {
    'totalInvitesSent': totalInvitesSent,
    'accepted': accepted,
    'pending': pending,
    'rejected': rejected,
    'byChannel': byChannel,
  };
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is num) return value.toInt();
  return 0;
}

/// Individual invite record for tracking.
class InviteRecord {
  const InviteRecord({
    required this.id,
    required this.familyId,
    required this.channel,
    required this.status,
    required this.sentAt,
    this.recipientName,
    this.recipientPhone,
    this.acceptedAt,
    this.expiresAt,
  });

  factory InviteRecord.fromJson(Map<String, dynamic> json) {
    return InviteRecord(
      id: json['id'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      channel: json['channel'] as String? ?? 'link',
      status: json['status'] as String? ?? 'pending',
      sentAt: json['sentAt'] != null
          ? DateTime.tryParse(json['sentAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      recipientName: json['recipientName'] as String?,
      recipientPhone: json['recipientPhone'] as String?,
      acceptedAt: json['acceptedAt'] != null
          ? DateTime.tryParse(json['acceptedAt'].toString())
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
    );
  }

  final String id;
  final String familyId;
  final String channel;
  final String status; // pending, accepted, rejected, expired
  final DateTime sentAt;
  final String? recipientName;
  final String? recipientPhone;
  final DateTime? acceptedAt;
  final DateTime? expiresAt;

  /// Display-friendly channel label
  String get channelLabel => switch (channel) {
    'link' => 'Share Link',
    'qr_code' => 'QR Code',
    'direct' => 'Direct Copy',
    'whatsapp' => 'WhatsApp',
    'sms' => 'SMS',
    _ => channel,
  };

  /// Whether this invite has expired
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyId': familyId,
    'channel': channel,
    'status': status,
    'sentAt': sentAt.toIso8601String(),
    'recipientName': recipientName,
    'recipientPhone': recipientPhone,
    'acceptedAt': acceptedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
  };
}

/// Invite link info with expiration and metadata.
class InviteLinkInfo {
  const InviteLinkInfo({
    required this.kinFamilyId,
    required this.url,
    this.expiresAt,
    this.maxUses,
    this.currentUses = 0,
    this.isSingleUse = false,
  });

  final String kinFamilyId;
  final String url;
  final DateTime? expiresAt;
  final int? maxUses;
  final int currentUses;
  final bool isSingleUse;

  /// Whether this invite link has expired
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whether this invite link has reached its usage limit
  bool get isExhausted => maxUses != null && currentUses >= maxUses!;

  /// Whether this invite link is still valid
  bool get isValid => !isExpired && !isExhausted;
}

// ═══════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════

class FamilyInviteState {
  const FamilyInviteState({
    this.isLoading = false,
    this.error,
    this.lastInviteChannel,
    this.recentInvites = const [],
    this.linkInfo,
  });

  final bool isLoading;
  final String? error;
  final String? lastInviteChannel;
  final List<InviteRecord> recentInvites;
  final InviteLinkInfo? linkInfo;

  FamilyInviteState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? lastInviteChannel,
    List<InviteRecord>? recentInvites,
    InviteLinkInfo? linkInfo,
    bool clearLinkInfo = false,
  }) {
    return FamilyInviteState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastInviteChannel: lastInviteChannel ?? this.lastInviteChannel,
      recentInvites: recentInvites ?? this.recentInvites,
      linkInfo: clearLinkInfo ? null : (linkInfo ?? this.linkInfo),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════════════

/// Manages family invitations with tracking.
class FamilyInviteNotifier extends StateNotifier<FamilyInviteState> {
  FamilyInviteNotifier(this._ref) : super(const FamilyInviteState());

  final Ref _ref;
  Dio get _dio => _ref.read(dioProvider);

  /// Generate invite link: kinrel.app/join/KIN-XXXXXXXX
  Future<String> generateInviteLink(String kinFamilyId) async {
    return generateJoinUrl(kinFamilyId);
  }

  /// Generate invite link info with metadata (expiration, usage limits)
  Future<InviteLinkInfo> generateInviteLinkInfo(String kinFamilyId) async {
    final url = await generateInviteLink(kinFamilyId);

    // Try to fetch link metadata from backend
    try {
      final response = await _dio.get(
        '/api/families/family-id/$kinFamilyId/invite-info',
      );
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final info = InviteLinkInfo(
          kinFamilyId: kinFamilyId,
          url: url,
          expiresAt: data['expiresAt'] != null
              ? DateTime.tryParse(data['expiresAt'].toString())
              : null,
          maxUses: data['maxUses'] as int?,
          currentUses: data['currentUses'] as int? ?? 0,
          isSingleUse: data['isSingleUse'] as bool? ?? false,
        );
        state = state.copyWith(linkInfo: info);
        return info;
      }
    } on DioException catch (e) {
      debugPrint('⚠️ generateInviteLinkInfo error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ generateInviteLinkInfo error: $e');
    }

    // Default info without backend data
    final info = InviteLinkInfo(
      kinFamilyId: kinFamilyId,
      url: url,
    );
    state = state.copyWith(linkInfo: info);
    return info;
  }

  /// Regenerate invite link (creates new link, invalidates old one)
  Future<String> regenerateInviteLink(String familyId, String kinFamilyId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Try backend regeneration
      await _dio.post(
        '/api/families/$familyId/invites/regenerate',
        data: {'kinFamilyId': kinFamilyId},
      );
    } on DioException catch (e) {
      debugPrint('⚠️ regenerateInviteLink error: ${e.message}');
      // Non-critical — the link format is deterministic anyway
    } catch (e) {
      debugPrint('⚠️ regenerateInviteLink error: $e');
    }

    state = state.copyWith(isLoading: false);
    return generateJoinUrl(kinFamilyId);
  }

  /// Share via system share sheet
  Future<void> shareInviteLink(String kinFamilyId, {String familyName = 'Family'}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final url = await generateInviteLink(kinFamilyId);
      final text =
          'You\'re invited to join $familyName on Kinrel! 🧡\n\n'
          'Click the link to join the family tree:\n'
          '🔗 $url\n\n'
          'Or use Family ID: $kinFamilyId\n\n'
          '— Sent via Kinrel by Daxelo';

      AnalyticsService.instance.logShareProfile('family_invite');

      await share_plus.Share.share(
        text,
        subject: 'Family invitation — $familyName on Kinrel',
      );

      state = state.copyWith(isLoading: false, lastInviteChannel: 'link');
    } catch (e) {
      debugPrint('⚠️ shareInviteLink error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Copy Family ID to clipboard
  /// Note: Actual clipboard operation is done in the UI layer.
  /// This method handles tracking only.
  Future<void> copyFamilyId(String kinFamilyId) async {
    // Track the copy as a direct invite
    state = state.copyWith(lastInviteChannel: 'direct');
  }

  /// Track invite sent — creates an InviteRecord locally and persists to backend
  Future<void> trackInviteSent({
    required String familyId,
    required String channel,
    String? recipientName,
    String? recipientPhone,
  }) async {
    // Track locally
    state = state.copyWith(lastInviteChannel: channel);

    // Track via analytics
    AnalyticsService.instance.logShareProfile('invite_$channel');

    // Create a local invite record
    final record = InviteRecord(
      id: 'inv_${DateTime.now().millisecondsSinceEpoch}',
      familyId: familyId,
      channel: channel,
      status: 'pending',
      sentAt: DateTime.now(),
      recipientName: recipientName,
      recipientPhone: recipientPhone,
    );

    // Update local state with new record
    final updatedInvites = [record, ...state.recentInvites];
    state = state.copyWith(recentInvites: updatedInvites);

    // Cache locally in Drift
    await _cacheInviteRecord(record);

    // Try to persist to backend
    try {
      await _dio.post(
        '/api/families/$familyId/invites/track',
        data: {
          'channel': channel,
          if (recipientName != null) 'recipientName': recipientName,
          if (recipientPhone != null) 'recipientPhone': recipientPhone,
        },
      );
    } on DioException catch (e) {
      // Non-critical — don't block the user
      debugPrint('⚠️ trackInviteSent error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ trackInviteSent error: $e');
    }
  }

  /// Track invite link click (when someone opens the invite)
  Future<void> trackInviteClick({
    required String kinFamilyId,
    String? source,
  }) async {
    AnalyticsService.instance.logInviteAccepted(source ?? 'deep_link');

    try {
      await _dio.post(
        '/api/families/family-id/$kinFamilyId/invite-click',
        data: {
          'kinFamilyId': kinFamilyId,
          if (source != null) 'source': source,
        },
      );
    } on DioException catch (e) {
      debugPrint('⚠️ trackInviteClick error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ trackInviteClick error: $e');
    }
  }

  /// Bulk track multiple invites
  Future<void> trackBulkInvites({
    required String familyId,
    required String channel,
    required int count,
  }) async {
    AnalyticsService.instance.logInviteSent(channel);

    for (int i = 0; i < count; i++) {
      final record = InviteRecord(
        id: 'inv_${DateTime.now().millisecondsSinceEpoch}_$i',
        familyId: familyId,
        channel: channel,
        status: 'pending',
        sentAt: DateTime.now(),
      );
      await _cacheInviteRecord(record);
    }

    try {
      await _dio.post(
        '/api/families/$familyId/invites/track-bulk',
        data: {'channel': channel, 'count': count},
      );
    } on DioException catch (e) {
      debugPrint('⚠️ trackBulkInvites error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ trackBulkInvites error: $e');
    }
  }

  /// Get invite analytics
  Future<InviteAnalytics> getInviteAnalytics(String familyId) async {
    // Check local cache first
    final cached = await _getCachedAnalytics(familyId);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/api/families/$familyId/invites/analytics',
      );

      if (response.data is Map<String, dynamic>) {
        final analytics = InviteAnalytics.fromJson(response.data as Map<String, dynamic>);
        // Cache for 5 minutes
        await _cacheAnalytics(familyId, analytics);
        return analytics;
      }
    } on DioException catch (e) {
      debugPrint('⚠️ getInviteAnalytics error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ getInviteAnalytics error: $e');
    }

    return InviteAnalytics.empty;
  }

  /// Get recent invite records for a family
  Future<List<InviteRecord>> getRecentInvites(String familyId) async {
    // Try local cache first
    final cached = await _getCachedInviteRecords(familyId);
    if (cached.isNotEmpty) return cached;

    try {
      final response = await _dio.get(
        '/api/families/$familyId/invites',
        queryParameters: {'limit': 20, 'sort': 'desc'},
      );

      if (response.data is List) {
        final records = (response.data as List)
            .map((json) => InviteRecord.fromJson(json as Map<String, dynamic>))
            .toList();

        // Cache records locally
        for (final record in records) {
          await _cacheInviteRecord(record);
        }

        state = state.copyWith(recentInvites: records);
        return records;
      }
    } on DioException catch (e) {
      debugPrint('⚠️ getRecentInvites error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ getRecentInvites error: $e');
    }

    return state.recentInvites;
  }

  /// Update invite status (e.g., when someone accepts)
  Future<void> updateInviteStatus({
    required String inviteId,
    required String status,
  }) async {
    // Update local state
    final updatedInvites = state.recentInvites.map((invite) {
      if (invite.id == inviteId) {
        return InviteRecord(
          id: invite.id,
          familyId: invite.familyId,
          channel: invite.channel,
          status: status,
          sentAt: invite.sentAt,
          recipientName: invite.recipientName,
          recipientPhone: invite.recipientPhone,
          acceptedAt: status == 'accepted' ? DateTime.now() : invite.acceptedAt,
          expiresAt: invite.expiresAt,
        );
      }
      return invite;
    }).toList();

    state = state.copyWith(recentInvites: updatedInvites);

    try {
      await _dio.patch(
        '/api/families/invites/$inviteId/status',
        data: {'status': status},
      );
    } on DioException catch (e) {
      debugPrint('⚠️ updateInviteStatus error: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ updateInviteStatus error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Local Caching (Drift ApiCacheEntries)
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _cacheInviteRecord(InviteRecord record) async {
    if (!IsarDatabase.isInitialized) return;
    try {
      final db = IsarDatabase.instance;
      final key = 'invite_record:${record.familyId}:${record.id}';
      await db.cacheApiEntry(
        key,
        jsonEncode(record.toJson()),
        expiresIn: const Duration(days: 30),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to cache invite record: $e');
    }
  }

  Future<List<InviteRecord>> _getCachedInviteRecords(String familyId) async {
    if (!IsarDatabase.isInitialized) return [];
    try {
      final db = IsarDatabase.instance;
      final allEntries = await db.getCachedApiEntriesWithPrefix('invite_record:$familyId:');
      return allEntries
          .map((jsonStr) {
            try {
              return InviteRecord.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<InviteRecord>()
          .toList()
        ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    } catch (e) {
      debugPrint('⚠️ Failed to get cached invite records: $e');
      return [];
    }
  }

  Future<void> _cacheAnalytics(String familyId, InviteAnalytics analytics) async {
    if (!IsarDatabase.isInitialized) return;
    try {
      final db = IsarDatabase.instance;
      await db.cacheApiEntry(
        'invite_analytics:$familyId',
        jsonEncode(analytics.toJson()),
        expiresIn: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to cache invite analytics: $e');
    }
  }

  Future<InviteAnalytics?> _getCachedAnalytics(String familyId) async {
    if (!IsarDatabase.isInitialized) return null;
    try {
      final db = IsarDatabase.instance;
      final cached = await db.getCachedApiEntry('invite_analytics:$familyId');
      if (cached != null) {
        return InviteAnalytics.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get cached invite analytics: $e');
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Family invite notifier provider
final familyInviteProvider =
    StateNotifierProvider<FamilyInviteNotifier, FamilyInviteState>((ref) {
  return FamilyInviteNotifier(ref);
});

/// Invite analytics provider — fetches analytics for a given family
final inviteAnalyticsProvider =
    FutureProvider.family<InviteAnalytics, String>((ref, familyId) async {
  final notifier = ref.read(familyInviteProvider.notifier);
  return notifier.getInviteAnalytics(familyId);
});

/// Recent invitees provider — fetches recent invite records for a given family
final recentInviteesProvider =
    FutureProvider.family<List<InviteRecord>, String>((ref, familyId) async {
  final notifier = ref.read(familyInviteProvider.notifier);
  return notifier.getRecentInvites(familyId);
});

/// Invite link info provider — generates and returns invite link metadata
final inviteLinkInfoProvider =
    FutureProvider.family<InviteLinkInfo, String>((ref, kinFamilyId) async {
  final notifier = ref.read(familyInviteProvider.notifier);
  return notifier.generateInviteLinkInfo(kinFamilyId);
});
