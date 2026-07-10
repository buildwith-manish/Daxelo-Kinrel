// lib/features/trackc/presentation/providers/trackc_visibility.dart
//
// DAXELO KINREL — Track C UI Visibility Helpers
//
// Provides role- and age-based capability checks for the Flutter UI.
// Used to HIDE (not just disable) UI affordances for actions the current
// user's role/age can't perform.
//
// This mirrors the server-side VisibilityService matrix exactly:
//   - canAct: owner|admin|elder|member AND non-minor → can edit/vote/create
//   - isAdmin: owner|admin → can see raw timeline, raw learning profile
//   - isMinor: age < 18 (fail-open for null DOB)
//
// The UI uses these to hide action buttons. The server enforces the same
// rules independently (defense-in-depth) — the UI hiding is for UX only.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/family/family_provider.dart';
import '../../../../core/services/supabase_service.dart';

/// The minimum age (in years) at which a user is no longer a minor.
const int kMinorAgeThreshold = 18;

/// Pure helper: returns true if the user is a minor (age < 18).
/// Null dateOfBirth → returns false (fail-open, same as server).
bool isMinorByDateOfBirth(DateTime? dateOfBirth) {
  if (dateOfBirth == null) return false;
  final now = DateTime.now();
  int age = now.year - dateOfBirth.year;
  final monthDiff = now.month - dateOfBirth.month;
  if (monthDiff < 0 || (monthDiff == 0 && now.day < dateOfBirth.day)) {
    age--;
  }
  return age < kMinorAgeThreshold;
}

/// Capability flags for the current user in a specific family.
class TrackcCapabilities {
  const TrackcCapabilities({
    this.role,
    this.isMinor = false,
    this.canAct = false,
    this.isAdmin = false,
    this.isViewer = false,
  });

  /// The user's role in the family (null if unknown / not a member).
  final String? role;

  /// Whether the user is a minor (age < 18, fail-open for null DOB).
  final bool isMinor;

  /// Whether the user can perform governance actions (edit/vote/create).
  /// True only for owner|admin|elder|member AND non-minor.
  final bool canAct;

  /// Whether the user has admin-level data access (owner or admin).
  final bool isAdmin;

  /// Whether the user is a viewer (read-only).
  final bool isViewer;

  static const empty = TrackcCapabilities();
}

/// Provider that fetches the current user's dateOfBirth from Supabase.
/// This is a lightweight read — it only fetches the dateOfBirth column.
/// The result is cached by Riverpod so it's only fetched once per session.
final _userDateOfBirthProvider =
    FutureProvider.family<DateTime?, String>((ref, userId) async {
  try {
    final client = ref.read(supabaseProvider);
    if (client == null) return null;
    final result = await client
        .from('User')
        .select('dateOfBirth')
        .eq('id', userId)
        .maybeSingle();
    final dobStr = result?['dateOfBirth'];
    if (dobStr == null) return null;
    return DateTime.tryParse(dobStr.toString());
  } catch (_) {
    return null;
  }
});

/// Provider that computes the current user's Track C capabilities for a
/// given family. Watches:
///   - currentUserFamilyRoleProvider (role)
///   - _userDateOfBirthProvider (dateOfBirth for age check)
///
/// This does NOT make a new membership-fetching call — it reuses the
/// existing family membership provider that is already loaded on the
/// family screen.
final trackcCapabilitiesProvider =
    Provider.family<TrackcCapabilities, String>((ref, familyId) {
  // 1. Get the user's role in this family
  final role = ref.watch(currentUserFamilyRoleProvider(familyId));
  if (role == null) return TrackcCapabilities.empty;

  // 2. Get the user's dateOfBirth (async — use the AsyncValue)
  final currentUserId =
      ref.read(supabaseProvider)?.auth.currentUser?.id;
  DateTime? dateOfBirth;
  if (currentUserId != null) {
    // Read the AsyncValue and extract the data (or null if loading/error)
    final dobAsync = ref.watch(_userDateOfBirthProvider(currentUserId));
    dateOfBirth = dobAsync.maybeWhen(
      data: (dob) => dob,
      orElse: () => null,
    );
  }

  // 3. Compute capabilities
  // While dateOfBirth is loading, fail-open (treat as adult) — the server
  // enforces the real check, so the UI just needs to not block legit users
  // during the brief loading window.
  final isMinor = isMinorByDateOfBirth(dateOfBirth);
  final isAdmin = role == 'owner' || role == 'admin';
  final isViewer = role == 'viewer';
  final canAct = !isViewer && !isMinor &&
      (role == 'owner' || role == 'admin' || role == 'elder' || role == 'member');

  return TrackcCapabilities(
    role: role,
    isMinor: isMinor,
    canAct: canAct,
    isAdmin: isAdmin,
    isViewer: isViewer,
  );
});
