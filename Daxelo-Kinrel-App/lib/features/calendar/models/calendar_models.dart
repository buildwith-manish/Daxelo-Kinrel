// lib/features/calendar/models/calendar_models.dart

import 'dart:convert';

enum EventCategory {
  birthday,
  anniversary,
  wedding,
  engagement,
  babyShower,
  pregnancy,
  graduation,
  school,
  sports,
  familyDinner,
  reunion,
  vacation,
  festival,
  medical,
  memorial,
  custom;

  String get label => switch (this) {
    birthday => 'Birthday',
    anniversary => 'Anniversary',
    wedding => 'Wedding',
    engagement => 'Engagement',
    babyShower => 'Baby Shower',
    pregnancy => 'Pregnancy Due',
    graduation => 'Graduation',
    school => 'School Event',
    sports => 'Sports',
    familyDinner => 'Family Dinner',
    reunion => 'Family Reunion',
    vacation => 'Trip',
    festival => 'Festival',
    medical => 'Doctor Appointment',
    memorial => 'Memorial',
    custom => 'Custom Event',
  };

  String get icon => switch (this) {
    birthday => '🎂',
    anniversary => '💍',
    wedding => '💒',
    engagement => '💖',
    babyShower => '👶',
    pregnancy => '🤰',
    graduation => '🎓',
    school => '🏫',
    sports => '🏆',
    familyDinner => '🍽',
    reunion => '🤝',
    vacation => '✈️',
    festival => '🎉',
    medical => '🏥',
    memorial => '🕯️',
    custom => '❤️',
  };

  int get colorValue => switch (this) {
    birthday => 0xFFE8612A,
    anniversary => 0xFFD4AF37,
    wedding => 0xFFEC4899,
    engagement => 0xFFF472B6,
    babyShower => 0xFF60A5FA,
    pregnancy => 0xFF34D399,
    graduation => 0xFF8B5CF6,
    school => 0xFF06B6D4,
    sports => 0xFF10B981,
    familyDinner => 0xFFF59E0B,
    reunion => 0xFF10B981,
    vacation => 0xFFF59E0B,
    festival => 0xFFEF4444,
    medical => 0xFF3B82F6,
    memorial => 0xFF64748B,
    custom => 0xFFEC4899,
  };
}

enum RSVPStatus { going, maybe, notGoing, pending }

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.familyId,
    required this.createdBy,
    this.personId,
    required this.title,
    this.description,
    required this.category,
    required this.eventDate,
    this.endDate,
    this.location,
    this.locationUrl,
    this.isAllDay = true,
    this.isRecurring = false,
    this.recurrenceRule,
    this.recurrenceEndDate,
    this.notes,
    this.attachments = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String createdBy;
  final String? personId;
  final String title;
  final String? description;
  final EventCategory category;
  final DateTime eventDate;
  final DateTime? endDate;
  final String? location;
  final String? locationUrl;
  final bool isAllDay;
  final bool isRecurring;
  final String? recurrenceRule;
  final DateTime? recurrenceEndDate;
  final String? notes;
  final List<EventAttachment> attachments;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] ?? '',
      familyId: json['familyId'] ?? '',
      createdBy: json['createdBy'] ?? '',
      personId: json['personId'],
      title: json['title'] ?? '',
      description: json['description'],
      category: _parseCategory(json['category']),
      eventDate: DateTime.tryParse(json['eventDate'] ?? '') ?? DateTime.now(),
      endDate: json['endDate'] != null ? DateTime.tryParse(json['endDate']) : null,
      location: json['location'],
      locationUrl: json['locationUrl'],
      isAllDay: json['isAllDay'] ?? true,
      isRecurring: json['isRecurring'] ?? false,
      recurrenceRule: json['recurrenceRule'],
      recurrenceEndDate: json['recurrenceEndDate'] != null ? DateTime.tryParse(json['recurrenceEndDate']) : null,
      notes: json['notes'],
      attachments: (json['attachments'] as List?)?.map((a) => EventAttachment.fromJson(a as Map<String, dynamic>)).toList() ?? [],
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyId': familyId,
    'createdBy': createdBy,
    'personId': personId,
    'title': title,
    'description': description,
    'category': category.name,
    'eventDate': eventDate.toIso8601String().split('T')[0],
    'endDate': endDate?.toIso8601String().split('T')[0],
    'location': location,
    'locationUrl': locationUrl,
    'isAllDay': isAllDay,
    'isRecurring': isRecurring,
    'recurrenceRule': recurrenceRule,
    'recurrenceEndDate': recurrenceEndDate?.toIso8601String().split('T')[0],
    'notes': notes,
    'attachments': jsonEncode(attachments.map((a) => a.toJson()).toList()),
    'metadata': jsonEncode(metadata),
  };

  static EventCategory _parseCategory(String? s) {
    return EventCategory.values.firstWhere(
      (c) => c.name == s,
      orElse: () => EventCategory.custom,
    );
  }

  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final event = DateTime(eventDate.year, eventDate.month, eventDate.day);
    return event.difference(today).inDays;
  }

  bool get isToday => daysUntil == 0;
  bool get isPast => daysUntil < 0;
  bool get isUpcoming => daysUntil >= 0;
  bool get isWithinWeek => daysUntil >= 0 && daysUntil <= 7;

  String get countdownLabel {
    if (isToday) return 'Today';
    if (daysUntil == 1) return 'Tomorrow';
    if (daysUntil < 0) return '${-daysUntil}d ago';
    if (daysUntil <= 7) return 'In ${daysUntil}d';
    if (daysUntil <= 30) return 'In ${daysUntil}d';
    return '${(daysUntil / 7).round()}w left';
  }

  bool get isMilestoneBirthday {
    if (category != EventCategory.birthday) return false;
    // Check if the person turns 18, 21, 30, 50, 60, 75, or 100
    // This would need the birth year — for now, flag all birthdays
    return false;
  }
}

class EventAttachment {
  const EventAttachment({required this.type, required this.url, required this.name});
  final String type; // photo, document, link
  final String url;
  final String name;

  factory EventAttachment.fromJson(Map<String, dynamic> json) => EventAttachment(
    type: json['type'] ?? 'link',
    url: json['url'] ?? '',
    name: json['name'] ?? '',
  );

  Map<String, dynamic> toJson() => {'type': type, 'url': url, 'name': name};
}

class EventRSVP {
  const EventRSVP({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.status,
    required this.respondedAt,
  });
  final String id;
  final String eventId;
  final String userId;
  final String userName;
  final RSVPStatus status;
  final DateTime respondedAt;

  factory EventRSVP.fromJson(Map<String, dynamic> json) => EventRSVP(
    id: json['id'] ?? '',
    eventId: json['eventId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Member',
    status: _parseStatus(json['status']),
    respondedAt: DateTime.tryParse(json['respondedAt'] ?? '') ?? DateTime.now(),
  );

  static RSVPStatus _parseStatus(String? s) {
    return RSVPStatus.values.firstWhere(
      (st) => st.name == s,
      orElse: () => RSVPStatus.pending,
    );
  }
}

class EventComment {
  const EventComment({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    required this.comment,
    required this.createdAt,
  });
  final String id;
  final String eventId;
  final String userId;
  final String userName;
  final String comment;
  final DateTime createdAt;

  factory EventComment.fromJson(Map<String, dynamic> json) => EventComment(
    id: json['id'] ?? '',
    eventId: json['eventId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Member',
    comment: json['comment'] ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}
