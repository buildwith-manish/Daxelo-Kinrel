// lib/features/share/providers/share_link_provider.dart
//
// DAXELO KINREL — Share Link Provider (P3-F2)
//
// Riverpod providers for generating shareable deep links.
// Integrates with the DeepLinkService to produce URLs for:
//   • Family profile links (https://kinrel.app/family/:id)
//   • Member profile links (https://kinrel.app/member/:id)
//   • Family graph share links (https://kinrel.app/share/:id)
//   • Invite links (https://kinrel.app/invite/:code)
//
// Also provides the actual sharing functionality via share_plus,
// wrapping the DeepLinkService share functions in a Riverpod-friendly API.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/deep_link_service.dart' as deep_link;
import '../../../core/services/crashlytics_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Share Link Generation Providers
// ═══════════════════════════════════════════════════════════════════════

/// Generates a shareable family profile URL.
/// Returns the full URL string (e.g., https://kinrel.app/family/abc123).
final familyShareLinkProvider = Provider.family<String, String>((ref, familyId) {
  return deep_link.generateFamilyUrl(familyId);
});

/// Generates a shareable member profile URL.
/// Returns the full URL string (e.g., https://kinrel.app/member/xyz789).
final memberShareLinkProvider = Provider.family<String, String>((ref, memberId) {
  return deep_link.generateMemberUrl(memberId);
});

/// Generates a shareable family graph URL.
/// Returns the full URL string (e.g., https://kinrel.app/share/abc123).
final graphShareLinkProvider = Provider.family<String, String>((ref, familyId) {
  return deep_link.generateShareUrl(familyId);
});

/// Generates an invite URL from an invite code.
/// Returns the full URL string (e.g., https://kinrel.app/invite/sharma25).
final inviteShareLinkProvider = Provider.family<String, String>((ref, inviteCode) {
  return deep_link.generateInviteUrl(inviteCode);
});

// ═══════════════════════════════════════════════════════════════════════
// Share Action Providers
// ═══════════════════════════════════════════════════════════════════════

/// Notifier that handles share actions for families and members.
/// Wraps the DeepLinkService share functions with state management
/// to track loading/error states.
class ShareLinkNotifier extends StateNotifier<ShareLinkState> {
  ShareLinkNotifier() : super(const ShareLinkState());

  /// Share a family profile link via the system share sheet.
  Future<void> shareFamily({
    required String familyId,
    required String familyName,
  }) async {
    state = state.copyWith(isSharing: true, lastError: null);
    try {
      await deep_link.shareFamilyLink(
        familyId: familyId,
        familyName: familyName,
      );
      state = state.copyWith(isSharing: false, lastSharedType: 'family');
    } catch (e) {
      logError(e, StackTrace.current, reason: 'Share family link failed');
      state = state.copyWith(isSharing: false, lastError: e.toString());
    }
  }

  /// Share a member profile link via the system share sheet.
  Future<void> shareMember({
    required String memberId,
    required String memberName,
  }) async {
    state = state.copyWith(isSharing: true, lastError: null);
    try {
      await deep_link.shareMemberLink(
        memberId: memberId,
        memberName: memberName,
      );
      state = state.copyWith(isSharing: false, lastSharedType: 'member');
    } catch (e) {
      logError(e, StackTrace.current, reason: 'Share member link failed');
      state = state.copyWith(isSharing: false, lastError: e.toString());
    }
  }

  /// Share a family graph link via the system share sheet.
  Future<void> shareGraph({
    required String familyId,
    required String familyName,
  }) async {
    state = state.copyWith(isSharing: true, lastError: null);
    try {
      await deep_link.shareGraphLink(
        familyId: familyId,
        familyName: familyName,
      );
      state = state.copyWith(isSharing: false, lastSharedType: 'graph');
    } catch (e) {
      logError(e, StackTrace.current, reason: 'Share graph link failed');
      state = state.copyWith(isSharing: false, lastError: e.toString());
    }
  }

  /// Share via WhatsApp with a pre-formatted message.
  Future<void> shareToWhatsApp({
    required String familyId,
    required String familyName,
  }) async {
    state = state.copyWith(isSharing: true, lastError: null);
    try {
      await deep_link.shareViaWhatsApp(
        familyId: familyId,
        familyName: familyName,
      );
      state = state.copyWith(isSharing: false, lastSharedType: 'whatsapp');
    } catch (e) {
      logError(e, StackTrace.current, reason: 'Share via WhatsApp failed');
      state = state.copyWith(isSharing: false, lastError: e.toString());
    }
  }

  /// Share via SMS with a pre-formatted message.
  Future<void> shareToSMS({
    required String familyId,
    required String familyName,
  }) async {
    state = state.copyWith(isSharing: true, lastError: null);
    try {
      await deep_link.shareViaSMS(
        familyId: familyId,
        familyName: familyName,
      );
      state = state.copyWith(isSharing: false, lastSharedType: 'sms');
    } catch (e) {
      logError(e, StackTrace.current, reason: 'Share via SMS failed');
      state = state.copyWith(isSharing: false, lastError: e.toString());
    }
  }

  /// Clear the last error.
  void clearError() {
    state = state.copyWith(lastError: null);
  }
}

/// State for share link operations.
class ShareLinkState {
  const ShareLinkState({
    this.isSharing = false,
    this.lastSharedType,
    this.lastError,
  });

  /// Whether a share operation is in progress.
  final bool isSharing;

  /// The type of the last successfully shared link.
  final String? lastSharedType;

  /// The last error message, if any.
  final String? lastError;

  ShareLinkState copyWith({
    bool? isSharing,
    String? lastSharedType,
    String? lastError,
  }) {
    return ShareLinkState(
      isSharing: isSharing ?? this.isSharing,
      lastSharedType: lastSharedType ?? this.lastSharedType,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Provider for the ShareLinkNotifier.
/// Family-scoped — one notifier per family ID.
final shareLinkProvider =
    StateNotifierProvider.family<ShareLinkNotifier, ShareLinkState, String>((
  ref,
  familyId,
) {
  return ShareLinkNotifier();
});
