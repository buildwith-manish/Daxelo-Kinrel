// lib/features/guest_access/providers/guest_access_provider.dart
//
// P9.2d — Guest / limited-access.
//
// Models a guest viewer session: a time-boxed, scope-limited view into
// a family's tree/albums for someone who is not a member (e.g. a
// visiting relative, a researcher the family explicitly invited).
//
// Constitution / Copy-Audit: guests see only what the family scoped.
// We never surface "guest activity" analytics to anyone, never nudge
// the guest to "upgrade", and never extend scope silently — extensions
// require an explicit member action.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a guest is allowed to see. Conservative by default.
enum GuestScope {
  viewTree,
  viewMemories,
  viewAlbums,
  viewCalendar,
}

@immutable
class GuestSession {
  const GuestSession({
    required this.token,
    required this.hostFamilyId,
    required this.hostFamilyName,
    required this.permittedScopes,
    required this.expiresAt,
    required this.issuedAt,
    this.invitedByName,
  });

  final String token;
  final String hostFamilyId;
  final String hostFamilyName;
  final Set<GuestScope> permittedScopes;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String? invitedByName;

  bool get isValid => DateTime.now().isBefore(expiresAt);
  bool can(GuestScope s) => isValid && permittedScopes.contains(s);

  GuestSession copyWith({
    String? token,
    String? hostFamilyId,
    String? hostFamilyName,
    Set<GuestScope>? permittedScopes,
    DateTime? expiresAt,
    DateTime? issuedAt,
    String? invitedByName,
  }) {
    return GuestSession(
      token: token ?? this.token,
      hostFamilyId: hostFamilyId ?? this.hostFamilyId,
      hostFamilyName: hostFamilyName ?? this.hostFamilyName,
      permittedScopes: permittedScopes ?? this.permittedScopes,
      expiresAt: expiresAt ?? this.expiresAt,
      issuedAt: issuedAt ?? this.issuedAt,
      invitedByName: invitedByName ?? this.invitedByName,
    );
  }
}

@immutable
class GuestAccessState {
  const GuestAccessState({
    this.session,
    this.isLoading = false,
    this.error,
  });

  final GuestSession? session;
  final bool isLoading;
  final String? error;

  bool get isGuest => session != null && session!.isValid;
  bool get isExpired => session != null && !session!.isValid;

  GuestAccessState copyWith({
    GuestSession? session,
    bool clearSession = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return GuestAccessState(
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GuestAccessNotifier extends StateNotifier<GuestAccessState> {
  GuestAccessNotifier() : super(const GuestAccessState());

  /// Begins a guest session. Scopes are taken AS-GIVEN from the invite
  /// — this provider never widens them.
  void startSession(GuestSession session) {
    if (!session.permittedScopes.every((s) => s is GuestScope)) {
      state = state.copyWith(error: 'Invalid guest scope set.');
      return;
    }
    state = state.copyWith(session: session, clearError: true);
  }

  /// Honest: a guest cannot self-extend. End the session instead and
  /// let a member re-issue.
  void endSession() {
    state = const GuestAccessState();
  }

  /// Marks the session as expired (e.g. when the UI detects the wall
  /// clock has passed `expiresAt`). No notification is sent.
  void markExpired() {
    final s = state.session;
    if (s == null) return;
    state = state.copyWith(
      session: s.copyWith(expiresAt: DateTime.now()),
    );
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final guestAccessProvider =
    StateNotifierProvider<GuestAccessNotifier, GuestAccessState>(
  (ref) => GuestAccessNotifier(),
);
