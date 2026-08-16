// lib/core/family/relationship_permissions.dart
//
// DAXELO KINREL — Relationship Permission Model (v5.12)
//
// Enforces who can create relationships between which people:
//   - Admins/owners can connect ANY two people in the family
//   - Regular members can only create relationships involving THEMSELVES
//
// This is the SINGLE source of truth for client-side permission checks.
// The same rule is enforced server-side via Postgres RLS (see migration
// 20260816030000_relationship_rls_permissions.sql).

/// Returns true if the current user is allowed to create a relationship
/// between [fromPersonId] and [toPersonId].
///
/// Rules:
///   - If [isAdmin] is true (role is 'admin' or 'owner'), always returns true.
///   - If [viewerPersonId] matches [fromPersonId] or [toPersonId], returns true.
///   - Otherwise, returns false (regular member can only connect themselves).
bool canCreateRelationship({
  required bool isAdmin,
  required String? viewerPersonId,
  required String fromPersonId,
  required String toPersonId,
}) {
  // Admins/owners can connect any two people
  if (isAdmin) return true;

  // Regular members can only create relationships involving themselves
  if (viewerPersonId != null) {
    if (viewerPersonId == fromPersonId) return true;
    if (viewerPersonId == toPersonId) return true;
  }

  return false;
}
