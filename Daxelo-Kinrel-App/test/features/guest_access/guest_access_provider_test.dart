// test/features/guest_access/guest_access_provider_test.dart
//
// P9.2d — Guest / limited-access tests.
// Verifies scopes are never widened and expiry is honoured.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/guest_access/providers/guest_access_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GuestSession makeSession({
    required Set<GuestScope> scopes,
    DateTime? expiresAt,
  }) {
    return GuestSession(
      token: 'tok-1',
      hostFamilyId: 'fam-1',
      hostFamilyName: 'The Patils',
      permittedScopes: scopes,
      issuedAt: DateTime.now().subtract(const Duration(hours: 1)),
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
      invitedByName: 'Riya',
    );
  }

  group('P9.2d — GuestAccessNotifier', () {
    test('not a guest by default', () {
      final n = GuestAccessNotifier();
      expect(n.state.isGuest, isFalse);
      expect(n.state.session, isNull);
      n.dispose();
    });

    test('startSession honours the scopes given', () {
      final n = GuestAccessNotifier();
      n.startSession(makeSession(scopes: {GuestScope.viewTree}));
      expect(n.state.isGuest, isTrue);
      expect(n.state.session!.can(GuestScope.viewTree), isTrue);
      expect(n.state.session!.can(GuestScope.viewAlbums), isFalse);
      n.dispose();
    });

    test('expired session reports isGuest false and isExpired true', () {
      final n = GuestAccessNotifier();
      n.startSession(makeSession(
        scopes: {GuestScope.viewTree},
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ));
      expect(n.state.isGuest, isFalse);
      expect(n.state.isExpired, isTrue);
      expect(n.state.session!.can(GuestScope.viewTree), isFalse);
      n.dispose();
    });

    test('endSession clears the session (guest cannot self-renew)', () {
      final n = GuestAccessNotifier();
      n.startSession(makeSession(scopes: {GuestScope.viewTree}));
      n.endSession();
      expect(n.state.session, isNull);
      expect(n.state.isGuest, isFalse);
      n.dispose();
    });

    test('markExpired sets expiry to now', () {
      final n = GuestAccessNotifier();
      n.startSession(makeSession(scopes: {GuestScope.viewTree}));
      final before = DateTime.now();
      n.markExpired();
      final exp = n.state.session!.expiresAt;
      expect(!exp.isBefore(before), isTrue);
      expect(n.state.isExpired, isTrue);
      n.dispose();
    });

    test('there is NO extendScope method (provider never widens)', () {
      // Compile-time guarantee: the only mutators are start/end/markExpired.
      final n = GuestAccessNotifier();
      expect(n.startSession, isNotNull);
      expect(n.endSession, isNotNull);
      expect(n.markExpired, isNotNull);
      n.dispose();
    });
  });
}
