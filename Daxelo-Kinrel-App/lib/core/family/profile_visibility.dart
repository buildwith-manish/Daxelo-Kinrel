// lib/core/family/profile_visibility.dart
//
// DAXELO KINREL — Three-Tier Profile Visibility (v5.21)
//
// Defines the viewer tiers and the resolver that determines which tier
// a viewer falls into for a given target person.
//
// TIERS:
//   owner     — viewer IS the target person (viewing own profile)
//   connected — viewer and target share a family membership
//   public    — everyone else (strangers, logged-out users)
//
// MINOR SAFETY (Part 3):
//   A minor (PersonPrivacySetting.minorFlag=true OR under 18 by DOB)
//   is NEVER reachable at 'public' tier, regardless of any setting.
//   This is enforced server-side (check_permissions RPC) AND
//   client-side (resolveViewerTier returns 'connected' max for minors
//   when the viewer is in the same family, 'denied' otherwise).

import 'family_provider.dart' show Person;

/// The three visibility tiers for profile viewing.
enum ProfileViewerTier {
  /// Viewer IS the target person — full access, all fields, all tabs.
  owner,

  /// Viewer shares a family with the target — current full experience,
  /// respecting per-field show* flags.
  connected,

  /// Stranger / non-family member — name, photo, public bio only.
  /// No kinship ring, no generation, no Relations/Timeline/Notes tabs.
  public,

  /// Access denied (blocked user, or minor viewed by public stranger).
  denied,
}

/// Field-level visibility map derived from PersonPrivacySetting.
/// Used by the profile widget to decide which fields to render.
class ProfileFieldVisibility {
  const ProfileFieldVisibility({
    this.showDob = false,
    this.showAge = false,
    this.showAddress = false,
    this.showPhone = false,
    this.showEmail = false,
    this.showBloodGroup = false,
    this.showAnniversary = false,
    this.showOccupation = false,
    this.showEducation = false,
  });

  final bool showDob;
  final bool showAge;
  final bool showAddress;
  final bool showPhone;
  final bool showEmail;
  final bool showBloodGroup;
  final bool showAnniversary;
  final bool showOccupation;
  final bool showEducation;

  /// Default for 'public' tier — everything hidden unless explicitly
  /// opted in via PersonPrivacySetting.
  static const public = ProfileFieldVisibility();

  /// Default for 'connected' tier — most fields visible (respecting
  /// per-field show* flags from PersonPrivacySetting).
  static const connected = ProfileFieldVisibility(
    showDob: true,
    showAge: true,
    showOccupation: true,
    showEducation: true,
  );

  /// Default for 'owner' tier — everything visible.
  static const owner = ProfileFieldVisibility(
    showDob: true,
    showAge: true,
    showAddress: true,
    showPhone: true,
    showEmail: true,
    showBloodGroup: true,
    showAnniversary: true,
    showOccupation: true,
    showEducation: true,
  );
}

/// Resolves the viewer's tier for a given target person.
///
/// This is a PURE function — it takes already-fetched data and returns
/// the tier. The caller is responsible for fetching the family membership
/// data and the PersonPrivacySetting (if needed for minor checks).
///
/// Parameters:
/// - [viewerPersonId] — the viewer's linked Person ID (null if not linked)
/// - [targetPersonId] — the target person being viewed
/// - [viewerFamilyIds] — set of family IDs the viewer is a member of
/// - [targetFamilyId] — the family ID of the target person
/// - [isMinor] — whether the target person is a minor (from
///   PersonPrivacySetting.minorFlag OR computed from dateOfBirth)
/// - [isBlocked] — whether the viewer is blocked by the target
///
/// Returns:
/// - [ProfileViewerTier.owner] if viewer == target
/// - [ProfileViewerTier.denied] if blocked
/// - [ProfileViewerTier.denied] if target is minor AND viewer is not
///   in the same family (minors are never visible to public strangers)
/// - [ProfileViewerTier.connected] if viewer and target share a family
/// - [ProfileViewerTier.public] otherwise
ProfileViewerTier resolveViewerTier({
  required String? viewerPersonId,
  required String targetPersonId,
  required Set<String> viewerFamilyIds,
  required String? targetFamilyId,
  required bool isMinor,
  required bool isBlocked,
}) {
  // Owner: viewing own profile
  if (viewerPersonId == targetPersonId) {
    return ProfileViewerTier.owner;
  }

  // Blocked: always denied
  if (isBlocked) {
    return ProfileViewerTier.denied;
  }

  // Check if viewer shares a family with the target
  final sharesFamily = targetFamilyId != null &&
      viewerFamilyIds.contains(targetFamilyId);

  // Minor safety: a minor is NEVER reachable at 'public' tier.
  // If the viewer is not in the same family, deny access entirely.
  if (isMinor && !sharesFamily) {
    return ProfileViewerTier.denied;
  }

  if (sharesFamily) {
    return ProfileViewerTier.connected;
  }

  // If the target is a minor, they should never be 'public' —
  // but we already returned 'denied' above if !sharesFamily.
  // If we reach here, the target is NOT a minor (or is a minor but
  // the viewer IS in the same family — handled by 'connected' above).
  return ProfileViewerTier.public;
}

/// Computes whether a person is a minor based on dateOfBirth.
///
/// Returns true if the person is under 18 years old.
/// Returns false if dateOfBirth is null or the person is 18+.
bool isMinorByDateOfBirth(DateTime? dateOfBirth) {
  if (dateOfBirth == null) return false;
  final now = DateTime.now();
  final age = now.year - dateOfBirth.year;
  // Adjust if birthday hasn't occurred yet this year
  final birthdayThisYear = DateTime(dateOfBirth.year + age, dateOfBirth.month, dateOfBirth.day);
  final actualAge = birthdayThisYear.isAfter(now) ? age - 1 : age;
  return actualAge < 18;
}

/// Computes the field visibility for a given tier.
///
/// Owner: everything visible.
/// Connected: most fields visible (respecting per-field show* flags
///   from PersonPrivacySetting — pass them in via [overrides]).
/// Public: nothing visible unless explicitly opted in.
/// Denied: nothing (the widget should not render at all).
ProfileFieldVisibility computeFieldVisibility({
  required ProfileViewerTier tier,
  ProfileFieldVisibility? overrides,
}) {
  switch (tier) {
    case ProfileViewerTier.owner:
      return overrides ?? ProfileFieldVisibility.owner;
    case ProfileViewerTier.connected:
      return overrides ?? ProfileFieldVisibility.connected;
    case ProfileViewerTier.public:
      return overrides ?? ProfileFieldVisibility.public;
    case ProfileViewerTier.denied:
      return ProfileFieldVisibility.public; // Nothing visible
  }
}
