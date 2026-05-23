import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';
import '../graph/graph_service.dart';

// ── Data Models ────────────────────────────────────────────────

class Family {
  final String id;
  final String name;
  final String? description;
  final String? primaryLanguage;
  final String? gotra;
  final String? originVillage;
  final String? createdBy;
  final DateTime? createdAt;

  const Family({
    required this.id,
    required this.name,
    this.description,
    this.primaryLanguage,
    this.gotra,
    this.originVillage,
    this.createdBy,
    this.createdAt,
  });

  factory Family.fromJson(Map<String, dynamic> json) {
    return Family(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Family',
      description: json['description'] as String?,
      primaryLanguage: json['primary_language'] as String?,
      gotra: json['gotra'] as String?,
      originVillage: json['origin_village'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class Person {
  final String id;
  final String familyId;
  final String name;
  final String? relationshipKey;
  final String? gender;
  final String? dateOfBirth;
  final String? city;
  final String? gotra;
  final bool isDeceased;
  final String? deletedAt;
  final DateTime? createdAt;

  const Person({
    required this.id,
    required this.familyId,
    required this.name,
    this.relationshipKey,
    this.gender,
    this.dateOfBirth,
    this.city,
    this.gotra,
    this.isDeceased = false,
    this.deletedAt,
    this.createdAt,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String? ?? '',
      familyId: json['family_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      relationshipKey: json['relationship_key'] as String?,
      gender: json['gender'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      city: json['city'] as String?,
      gotra: json['gotra'] as String?,
      isDeceased: json['is_deceased'] as bool? ?? false,
      deletedAt: json['deleted_at'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  GraphPerson toGraphPerson() {
    return GraphPerson(
      id: id,
      name: name,
      relationship: relationshipKey,
      generation: 0,
      isDeceased: isDeceased,
      deletedAt: deletedAt,
    );
  }
}

class FamilyRelationship {
  final String id;
  final String familyId;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipType;
  final DateTime? createdAt;

  const FamilyRelationship({
    required this.id,
    required this.familyId,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipType,
    this.createdAt,
  });

  factory FamilyRelationship.fromJson(Map<String, dynamic> json) {
    return FamilyRelationship(
      id: json['id'] as String? ?? '',
      familyId: json['family_id'] as String? ?? '',
      fromPersonId: json['from_person_id'] as String? ?? '',
      toPersonId: json['to_person_id'] as String? ?? '',
      relationshipType: json['relationship_type'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  ({String fromId, String toId, String type}) toGraphEdge() {
    return (fromId: fromPersonId, toId: toPersonId, type: relationshipType);
  }
}

class FamilyDetail {
  final Family family;
  final List<Person> members;
  final List<FamilyRelationship> relationships;

  const FamilyDetail({
    required this.family,
    required this.members,
    required this.relationships,
  });
}

// ── Providers ──────────────────────────────────────────────────

/// Fetches all families the current user has access to
final familyListProvider = FutureProvider<List<Family>>((ref) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return [];

  try {
    final client = ref.watch(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await client
        .from('families')
        .select()
        .eq('created_by', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => Family.fromJson(json as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return [];
  }
});

/// Fetches a single family with its members
final familyDetailProvider =
    FutureProvider.family<FamilyDetail?, String>((ref, familyId) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return null;

  try {
    final client = ref.watch(supabaseProvider);

    // Fetch family
    final familyResponse = await client
        .from('families')
        .select()
        .eq('id', familyId)
        .maybeSingle();

    if (familyResponse == null) return null;
    final family = Family.fromJson(familyResponse);

    // Fetch members
    final members = await ref.watch(familyMembersProvider(familyId).future);

    // Fetch relationships
    final relationships =
        await ref.watch(familyRelationshipsProvider(familyId).future);

    return FamilyDetail(
      family: family,
      members: members,
      relationships: relationships,
    );
  } catch (e) {
    return null;
  }
});

/// Fetches persons in a family
final familyMembersProvider =
    FutureProvider.family<List<Person>, String>((ref, familyId) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return [];

  try {
    final client = ref.watch(supabaseProvider);

    final response = await client
        .from('persons')
        .select()
        .eq('family_id', familyId)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: true);

    return (response as List)
        .map((json) => Person.fromJson(json as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return [];
  }
});

/// Fetches relationships in a family
final familyRelationshipsProvider =
    FutureProvider.family<List<FamilyRelationship>, String>(
        (ref, familyId) async {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return [];

  try {
    final client = ref.watch(supabaseProvider);

    final response = await client
        .from('relationships')
        .select()
        .eq('family_id', familyId)
        .order('created_at', ascending: true);

    return (response as List)
        .map(
            (json) => FamilyRelationship.fromJson(json as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return [];
  }
});

/// Family member count provider
final familyMemberCountProvider =
    FutureProvider.family<int, String>((ref, familyId) async {
  final members = await ref.watch(familyMembersProvider(familyId).future);
  return members.length;
});

/// Create family in Supabase
Future<Family?> createFamily({
  required WidgetRef ref,
  required String name,
  String? description,
  String? primaryLanguage,
  String? gotra,
  String? originVillage,
}) async {
  try {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await client.from('families').insert({
      'name': name,
      if (description != null) 'description': description,
      if (primaryLanguage != null) 'primary_language': primaryLanguage,
      if (gotra != null) 'gotra': gotra,
      if (originVillage != null) 'origin_village': originVillage,
      'created_by': userId,
    }).select().maybeSingle();

    if (response == null) return null;
    ref.invalidate(familyListProvider);
    return Family.fromJson(response);
  } catch (e) {
    return null;
  }
}

/// Create person in Supabase
Future<Person?> createPerson({
  required WidgetRef ref,
  required String familyId,
  required String name,
  String? relationshipKey,
  String? gender,
  String? dateOfBirth,
  String? city,
  String? gotra,
  bool isDeceased = false,
}) async {
  try {
    final client = ref.read(supabaseProvider);

    final response = await client.from('persons').insert({
      'family_id': familyId,
      'name': name,
      if (relationshipKey != null) 'relationship_key': relationshipKey,
      if (gender != null) 'gender': gender,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (city != null) 'city': city,
      if (gotra != null) 'gotra': gotra,
      'is_deceased': isDeceased,
    }).select().maybeSingle();

    if (response == null) return null;
    ref.invalidate(familyMembersProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    return Person.fromJson(response);
  } catch (e) {
    return null;
  }
}

/// Update person in Supabase
Future<Person?> updatePerson({
  required WidgetRef ref,
  required String personId,
  required String familyId,
  required String name,
  String? relationshipKey,
  String? gender,
  String? dateOfBirth,
  String? city,
  String? gotra,
  bool isDeceased = false,
}) async {
  try {
    final client = ref.read(supabaseProvider);

    final response = await client.from('persons').update({
      'name': name,
      if (relationshipKey != null) 'relationship_key': relationshipKey,
      if (gender != null) 'gender': gender,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (city != null) 'city': city,
      if (gotra != null) 'gotra': gotra,
      'is_deceased': isDeceased,
    }).eq('id', personId).select().maybeSingle();

    if (response == null) return null;
    ref.invalidate(familyMembersProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    return Person.fromJson(response);
  } catch (e) {
    return null;
  }
}

/// Delete person (soft delete) in Supabase
Future<bool> deletePerson({
  required WidgetRef ref,
  required String personId,
  required String familyId,
}) async {
  try {
    final client = ref.read(supabaseProvider);

    await client.from('persons').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', personId);

    ref.invalidate(familyMembersProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    return true;
  } catch (e) {
    return false;
  }
}

/// Create relationship in Supabase
Future<FamilyRelationship?> createRelationship({
  required WidgetRef ref,
  required String familyId,
  required String fromPersonId,
  required String toPersonId,
  required String relationshipType,
}) async {
  try {
    final client = ref.read(supabaseProvider);

    final response = await client.from('relationships').insert({
      'family_id': familyId,
      'from_person_id': fromPersonId,
      'to_person_id': toPersonId,
      'relationship_type': relationshipType,
    }).select().maybeSingle();

    if (response == null) return null;
    ref.invalidate(familyRelationshipsProvider(familyId));
    ref.invalidate(familyDetailProvider(familyId));
    return FamilyRelationship.fromJson(response);
  } catch (e) {
    return null;
  }
}
