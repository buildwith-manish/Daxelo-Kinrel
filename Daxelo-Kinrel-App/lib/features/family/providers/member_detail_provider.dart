// lib/features/family/providers/member_detail_provider.dart
//
// DAXELO KINREL — Member Detail Provider
//
// Provides MemberDetailModel with real Supabase data.
// Uses offline-first pattern: check Drift cache, then fetch from Supabase.
// Includes personal details, relations, timeline events, and notes.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/services/supabase_service.dart';

// ── Data Models ──────────────────────────────────────────────────────

/// Complete detail model for a family member shown on the Person Detail Screen.
class MemberDetailModel {
  const MemberDetailModel({
    required this.memberId,
    required this.name,
    this.nickname,
    this.gender,
    this.dateOfBirth,
    this.birthplace,
    this.currentCity,
    this.phone,
    this.email,
    this.occupation,
    this.bio,
    this.photoUrl,
    this.kinshipNameToUser,
    this.kinshipPathToUser,
    this.generationNumber = 0,
    this.directConnectionsCount = 0,
    this.isDeceased = false,
    this.relations = const [],
    this.timelineEvents = const [],
    this.notes = const [],
  });

  final String memberId;
  final String name;
  final String? nickname;
  final String? gender;
  final String? dateOfBirth;
  final String? birthplace;
  final String? currentCity;
  final String? phone;
  final String? email;
  final String? occupation;
  final String? bio;
  final String? photoUrl;

  /// Kinship name from user to this member (e.g., "चाचा")
  final String? kinshipNameToUser;

  /// Kinship path from user to this member (e.g., "Father → Brother")
  final String? kinshipPathToUser;

  final int generationNumber;
  final int directConnectionsCount;
  final bool isDeceased;

  final List<MemberRelation> relations;
  final List<TimelineEvent> timelineEvents;
  final List<MemberNote> notes;

  /// Computed age from dateOfBirth
  int? get age {
    if (dateOfBirth == null || dateOfBirth!.isEmpty) return null;
    try {
      final dob = DateTime.parse(dateOfBirth!);
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  /// Serialize to JSON for Drift caching.
  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'name': name,
        'nickname': nickname,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'birthplace': birthplace,
        'currentCity': currentCity,
        'phone': phone,
        'email': email,
        'occupation': occupation,
        'bio': bio,
        'photoUrl': photoUrl,
        'kinshipNameToUser': kinshipNameToUser,
        'kinshipPathToUser': kinshipPathToUser,
        'generationNumber': generationNumber,
        'directConnectionsCount': directConnectionsCount,
        'isDeceased': isDeceased,
        'relations': relations.map((r) => r.toJson()).toList(),
        'timelineEvents': timelineEvents.map((e) => e.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  /// Deserialize from JSON (Drift cache).
  factory MemberDetailModel.fromJson(Map<String, dynamic> json) {
    return MemberDetailModel(
      memberId: json['memberId'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      nickname: json['nickname'] as String?,
      gender: json['gender'] as String?,
      dateOfBirth: json['dateOfBirth'] as String?,
      birthplace: json['birthplace'] as String?,
      currentCity: json['currentCity'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      occupation: json['occupation'] as String?,
      bio: json['bio'] as String?,
      photoUrl: json['photoUrl'] as String?,
      kinshipNameToUser: json['kinshipNameToUser'] as String?,
      kinshipPathToUser: json['kinshipPathToUser'] as String?,
      generationNumber: json['generationNumber'] as int? ?? 0,
      directConnectionsCount: json['directConnectionsCount'] as int? ?? 0,
      isDeceased: json['isDeceased'] as bool? ?? false,
      relations: (json['relations'] as List?)
              ?.map((r) => MemberRelation.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      timelineEvents: (json['timelineEvents'] as List?)
              ?.map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      notes: (json['notes'] as List?)
              ?.map((n) => MemberNote.fromJson(n as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// A relation connected to the member.
class MemberRelation {
  const MemberRelation({
    required this.memberId,
    required this.name,
    this.photoUrl,
    this.kinshipName,
    this.gender,
  });

  final String memberId;
  final String name;
  final String? photoUrl;

  /// Kinship name from the current member to this relation (e.g., "बेटा")
  final String? kinshipName;
  final String? gender;

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'name': name,
        'photoUrl': photoUrl,
        'kinshipName': kinshipName,
        'gender': gender,
      };

  factory MemberRelation.fromJson(Map<String, dynamic> json) {
    return MemberRelation(
      memberId: json['memberId'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      photoUrl: json['photoUrl'] as String?,
      kinshipName: json['kinshipName'] as String?,
      gender: json['gender'] as String?,
    );
  }
}

/// A timeline event for the member.
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.title,
    required this.date,
    this.description,
    this.eventType = TimelineEventType.milestone,
  });

  final String id;
  final String title;
  final String date;
  final String? description;
  final TimelineEventType eventType;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date,
        'description': description,
        'eventType': eventType.name,
      };

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      date: json['date'] as String? ?? '',
      description: json['description'] as String?,
      eventType: TimelineEventType.values.firstWhere(
        (e) => e.name == json['eventType'],
        orElse: () => TimelineEventType.milestone,
      ),
    );
  }
}

/// Timeline event types.
enum TimelineEventType {
  birth,
  marriage,
  education,
  career,
  milestone,
  travel,
  family,
  memorial,
}

/// A personal note about the member.
class MemberNote {
  const MemberNote({
    required this.id,
    required this.content,
    required this.createdAt,
    this.author = 'You',
  });

  final String id;
  final String content;
  final String createdAt;
  final String author;

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'createdAt': createdAt,
        'author': author,
      };

  factory MemberNote.fromJson(Map<String, dynamic> json) {
    return MemberNote(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      author: json['author'] as String? ?? 'You',
    );
  }
}

// ── Table name constant (matching Prisma schema PascalCase) ────────
const _kPersonTable = 'Person';
const _kRelationshipTable = 'Relationship';

// ── Provider ──────────────────────────────────────────────────────────

/// Provider that fetches member detail by personId.
/// Uses offline-first pattern: check Drift cache first,
/// then fetch from Supabase if not found or stale.
final memberDetailProvider = FutureProvider.family<MemberDetailModel, String>((
  ref,
  personId,
) async {
  // 1. Try Drift cache first
  if (IsarDatabase.isInitialized) {
    try {
      final db = IsarDatabase.instance;
      final cached = await db.getPerson(personId);
      if (cached != null) {
        final data = _jsonDecode(cached.data);
        // Check if cache is stale (older than 30 minutes)
        final cachedAt = cached.cachedAt;
        final age = DateTime.now().difference(cachedAt);
        if (age.inMinutes < 30) {
          // Fresh enough — return cached data
          try {
            return MemberDetailModel.fromJson(data);
          } catch (_) {
            // If cached model can't be parsed, fall through to network
          }
        }
        // Stale — refresh in background but still return cache
        _refreshInBackground(ref, personId);
        try {
          return MemberDetailModel.fromJson(data);
        } catch (_) {
          // Fall through to network
        }
      }
    } catch (e) {
      debugPrint('⚠️ memberDetailProvider cache read error: $e');
    }
  }

  // 2. Fetch from Supabase
  return _fetchFromSupabase(ref, personId);
});

/// Refresh member detail in the background without blocking the UI.
void _refreshInBackground(Ref ref, String personId) {
  _fetchFromSupabase(ref, personId).catchError((e) {
    debugPrint('⚠️ Background member detail refresh failed: $e');
    return MemberDetailModel(
      memberId: personId,
      name: 'Unknown',
    );
  });
}

/// Fetch member detail from Supabase and cache in Drift.
Future<MemberDetailModel> _fetchFromSupabase(
  Ref ref,
  String personId,
) async {
  final client = ref.read(supabaseProvider);
  if (client == null) {
    throw Exception('Database is not connected.');
  }

  // 1. Fetch the person record
  final personResponse = await client
      .from(_kPersonTable)
      .select()
      .eq('id', personId)
      .filter('deletedAt', 'is', null)
      .maybeSingle();

  if (personResponse == null) {
    throw Exception('Person not found.');
  }

  final personData = personResponse;
  final familyId = personData['familyId']?.toString() ?? '';

  // 2. Fetch relationships involving this person in the same family
  List<Map<String, dynamic>> relationshipRows = [];
  try {
    final relResponse = await client
        .from(_kRelationshipTable)
        .select()
        .eq('familyId', familyId)
        .eq('isActive', true);
    relationshipRows = (relResponse as List)
        .map((r) => r as Map<String, dynamic>)
        .toList();
  } catch (e) {
    debugPrint('⚠️ memberDetailProvider: Failed to fetch relationships: $e');
  }

  // 3. Find relationships involving this person
  final relatedPersonIds = <String>{};
  final memberRelations = <MemberRelation>[];

  for (final rel in relationshipRows) {
    final fromId = rel['fromPersonId']?.toString() ?? '';
    final toId = rel['toPersonId']?.toString() ?? '';

    if (fromId == personId) {
      // This person is the source — the related person is toId
      relatedPersonIds.add(toId);
    } else if (toId == personId) {
      // This person is the target — the related person is fromId
      relatedPersonIds.add(fromId);
    }
  }

  // 4. Fetch related person details
  final relatedPersons = <String, Map<String, dynamic>>{};
  if (relatedPersonIds.isNotEmpty) {
    try {
      final personsResponse = await client
          .from(_kPersonTable)
          .select()
          .inFilter('id', relatedPersonIds.toList())
          .filter('deletedAt', 'is', null);
      for (final p in (personsResponse as List)) {
        final pData = p as Map<String, dynamic>;
        final pid = pData['id']?.toString() ?? '';
        relatedPersons[pid] = pData;
      }
    } catch (e) {
      debugPrint('⚠️ memberDetailProvider: Failed to fetch related persons: $e');
    }
  }

  // 5. Build MemberRelation list
  for (final rel in relationshipRows) {
    final fromId = rel['fromPersonId']?.toString() ?? '';
    final toId = rel['toPersonId']?.toString() ?? '';
    final relKey = rel['relationshipKey'] as String? ?? '';
    final label = rel['label'] as String?;

    String? relatedId;
    String? kinshipName;

    if (fromId == personId) {
      relatedId = toId;
      // Person is the source — relationshipKey describes how person relates to toId
      kinshipName = label ?? relKey;
    } else if (toId == personId) {
      relatedId = fromId;
      // Person is the target — relationshipKey describes how fromId relates to person
      // The inverse is how person relates to fromId
      kinshipName = label ?? _getInverseLabel(relKey);
    }

    if (relatedId != null && relatedPersons.containsKey(relatedId)) {
      final rData = relatedPersons[relatedId]!;
      memberRelations.add(MemberRelation(
        memberId: relatedId,
        name: rData['name'] as String? ?? 'Unknown',
        photoUrl: rData['photoUrl'] as String?,
        kinshipName: kinshipName,
        gender: rData['gender'] as String?,
      ));
    }
  }

  // 6. Check for kinship path from current user to this person
  String? kinshipNameToUser;
  String? kinshipPathToUser;
  final userId = client.auth.currentUser?.id;
  if (userId != null && IsarDatabase.isInitialized) {
    try {
      final db = IsarDatabase.instance;
      final cachedPath = await db.getRelationshipPath(familyId, userId, personId);
      if (cachedPath != null) {
        kinshipNameToUser = cachedPath.kinshipTerm ?? cachedPath.kinshipTermHindi;
        kinshipPathToUser = _jsonDecode(cachedPath.path).toString();
      }
    } catch (_) {}
  }

  // 7. Build timeline events from person data
  final timelineEvents = <TimelineEvent>[];
  final name = personData['name'] as String? ?? 'Unknown';
  final dateOfBirth = personData['dateOfBirth']?.toString();

  if (dateOfBirth != null && dateOfBirth.isNotEmpty) {
    timelineEvents.add(TimelineEvent(
      id: '${personId}_birth',
      title: 'Born',
      date: dateOfBirth,
      eventType: TimelineEventType.birth,
    ));
  }

  // 8. Build MemberDetailModel
  final detail = MemberDetailModel(
    memberId: personId,
    name: name,
    nickname: personData['username'] as String?,
    gender: personData['gender'] as String?,
    dateOfBirth: dateOfBirth,
    birthplace: null, // Not in Person schema
    currentCity: personData['city'] as String?,
    phone: null, // Not directly in Person schema
    email: null, // Not directly in Person schema
    occupation: personData['occupation'] as String?,
    bio: personData['notes'] as String?,
    photoUrl: personData['photoUrl'] as String?,
    kinshipNameToUser: kinshipNameToUser,
    kinshipPathToUser: kinshipPathToUser,
    generationNumber: personData['generationIndex'] as int? ?? 0,
    directConnectionsCount: memberRelations.length,
    isDeceased: personData['isDeceased'] as bool? ?? false,
    relations: memberRelations,
    timelineEvents: timelineEvents,
    notes: const [], // Notes not in current schema
  );

  // 9. Cache in Drift
  if (IsarDatabase.isInitialized) {
    try {
      final db = IsarDatabase.instance;
      await db.upsertPerson(CachedPersonsCompanion(
        id: Value(personId),
        familyId: Value(familyId),
        name: Value(name),
        data: Value(_jsonEncode(detail.toJson())),
        cachedAt: Value(DateTime.now()),
      ));
    } catch (e) {
      debugPrint('⚠️ memberDetailProvider: Failed to cache: $e');
    }
  }

  return detail;
}

// ── Helpers ──────────────────────────────────────────────────────────

/// Simple inverse relationship label mapping.
/// Used when the person is the target of a relationship.
String? _getInverseLabel(String relKey) {
  const inverseMap = <String, String>{
    'father': 'child',
    'mother': 'child',
    'parent': 'child',
    'child': 'parent',
    'son': 'parent',
    'daughter': 'parent',
    'brother': 'sibling',
    'sister': 'sibling',
    'sibling': 'sibling',
    'spouse': 'spouse',
    'husband': 'wife',
    'wife': 'husband',
    'grandfather': 'grandchild',
    'grandmother': 'grandchild',
    'grandparent': 'grandchild',
    'grandchild': 'grandparent',
    'uncle': 'nephew/niece',
    'aunt': 'nephew/niece',
    'nephew': 'uncle/aunt',
    'niece': 'uncle/aunt',
    'cousin': 'cousin',
  };
  return inverseMap[relKey.toLowerCase()] ?? relKey;
}

Map<String, dynamic> _jsonDecode(String data) {
  return json.decode(data) as Map<String, dynamic>;
}

String _jsonEncode(Map<String, dynamic> data) {
  return json.encode(data);
}
