// lib/features/family/data/relationship_label_provider.dart
//
// DAXELO KINREL — Relationship-Aware Sender Labels (v139)
//
// Resolves the kinship label between the currently logged-in viewer
// and any other family member — e.g. "Chacha", "Bhaiya", "Nani".
// This is Kinrel's #1 differentiator: every message in the family
// group chat shows the sender's relationship to the viewer, pulled
// from the K-Graph.
//
// How it works:
//   1. Find the Person record linked to the current user (linkedUserId
//      == auth.currentUser.id)
//   2. Find a FamilyRelationship edge FROM that person TO the sender's
//      Person record
//   3. Format the relationshipKey as a human-readable label
//      (e.g. "fathers_younger_brother" → "fathers younger brother")
//
// If no relationship edge exists (e.g. the sender hasn't been linked
// to a Person yet, or no relationship was created), returns null and
// the UI falls back to the sender's display name only.
//
// Viewer-specific: the label changes based on who is logged in. If
// user A views a message from user B, they might see "Chacha". If
// user C views the same message, they might see "Bhaiya".

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';

/// Resolves the relationship label for a given (familyId, senderUserId)
/// pair from the viewer's perspective. Returns null if no relationship
/// is found.
///
/// Example: if the viewer is "Rahul" and the sender is Rahul's father's
/// younger brother, this returns "fathers younger brother" (or the
/// raw key if no prettifier is applied).
///
/// The label is viewer-specific — it depends on who is logged in.
final relationshipLabelProvider = Provider.family<String?, ({String familyId, String senderUserId})>(
  (ref, params) {
    final client = ref.read(supabaseProvider);
    if (client == null) return null;

    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId == null) return null;

    // Get family detail (includes Person members + relationships)
    final detailAsync = ref.watch(familyDetailProvider(params.familyId));
    final detail = detailAsync.valueOrNull;
    if (detail == null) return null;

    // Find the viewer's Person record (linked to their auth user ID)
    final viewerPerson = detail.members.firstWhere(
      (p) => p.linkedUserId == currentUserId,
      orElse: () => const Person(
        id: '',
        familyId: '',
        name: '',
      ),
    );
    if (viewerPerson.id.isEmpty) return null;

    // Find the sender's Person record
    final senderPerson = detail.members.firstWhere(
      (p) => p.linkedUserId == params.senderUserId,
      orElse: () => const Person(
        id: '',
        familyId: '',
        name: '',
      ),
    );
    if (senderPerson.id.isEmpty) return null;

    // Find a relationship edge FROM viewer TO sender
    // (the edge's relationshipKey describes what the TO person is TO
    // the FROM person — e.g. from=me, to=my father's brother, key="uncle")
    final relationship = detail.relationships.firstWhere(
      (r) => r.fromPersonId == viewerPerson.id && r.toPersonId == senderPerson.id,
      orElse: () => const FamilyRelationship(
        id: '',
        familyId: '',
        fromPersonId: '',
        toPersonId: '',
        relationshipKey: '',
      ),
    );

    if (relationship.relationshipKey.isEmpty) return null;

    // Format the key as a human-readable label.
    // "fathers_younger_brother" → "fathers younger brother"
    // "elder_brother" → "elder brother"
    // "uncle" → "uncle"
    return _formatRelationshipLabel(relationship.relationshipKey);
  },
);

/// Formats a raw relationshipKey into a human-readable label.
///
/// Examples:
///   "father" → "Father"
///   "elder_brother" → "Elder Brother"
///   "fathers_younger_brother" → "Fathers Younger Brother"
///
/// The caller can further prettify this (e.g. "fathers younger brother"
/// → "Chacha" via a cultural map) — for now we return the prettified
/// underscore-removed version with title case.
String _formatRelationshipLabel(String key) {
  // Replace underscores with spaces
  final words = key.replaceAll('_', ' ').split(' ');
  // Title-case each word
  final titled = words.map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1);
  }).join(' ');
  return titled;
}
