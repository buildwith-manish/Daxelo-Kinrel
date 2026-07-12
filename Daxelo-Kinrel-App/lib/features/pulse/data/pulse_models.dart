// lib/features/pulse/data/pulse_models.dart
//
// DAXELO KINREL — Pulse + Pitru + emotional attachment data models
//
// Pure Dart models for all the new backend features. JSON-serializable,
// no Flutter dependencies (so they can be unit-tested standalone).
//
// These mirror the TypeScript types in server/src/pulse/brief-types.ts
// and the API response shapes from the NestJS controllers.

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
// PULSE — Daily Brief
// ═══════════════════════════════════════════════════════════════════════════

enum BriefItemType {
  needYou,
  birthday,
  feedHighlight,
  weather,
  memoryOrbit,
  onThisDay,
}

extension BriefItemTypeX on BriefItemType {
  static BriefItemType fromString(String s) {
    switch (s) {
      case 'need_you': return BriefItemType.needYou;
      case 'birthday': return BriefItemType.birthday;
      case 'feed_highlight': return BriefItemType.feedHighlight;
      case 'weather': return BriefItemType.weather;
      case 'memory_orbit': return BriefItemType.memoryOrbit;
      case 'on_this_day': return BriefItemType.onThisDay;
      default: return BriefItemType.feedHighlight;
    }
  }

  String get emoji {
    switch (this) {
      case BriefItemType.needYou: return '💜';
      case BriefItemType.birthday: return '🎂';
      case BriefItemType.feedHighlight: return '📸';
      case BriefItemType.weather: return '🌧️';
      case BriefItemType.memoryOrbit: return '👵';
      case BriefItemType.onThisDay: return '🔮';
    }
  }
}

class BriefItem {
  final String id;
  final BriefItemType itemType;
  final int priority;
  final String title;
  final String body;
  final String actionLabel;
  final String actionType;
  final Map<String, dynamic> actionData;
  final String? targetPersonId;
  final String? targetUserId;
  final double? relevanceScore;
  final DateTime? interactedAt;
  final String? interactionType;
  final DateTime createdAt;

  BriefItem({
    required this.id,
    required this.itemType,
    required this.priority,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.actionType,
    required this.actionData,
    this.targetPersonId,
    this.targetUserId,
    this.relevanceScore,
    this.interactedAt,
    this.interactionType,
    required this.createdAt,
  });

  factory BriefItem.fromJson(Map<String, dynamic> j) => BriefItem(
    id: j['id'] as String,
    itemType: BriefItemTypeX.fromString(j['itemType'] as String),
    priority: j['priority'] as int,
    title: j['title'] as String,
    body: j['body'] as String,
    actionLabel: j['actionLabel'] as String,
    actionType: j['actionType'] as String,
    actionData: (j['actionData'] as Map<String, dynamic>?) ?? {},
    targetPersonId: j['targetPersonId'] as String?,
    targetUserId: j['targetUserId'] as String?,
    relevanceScore: (j['relevanceScore'] as num?)?.toDouble(),
    interactedAt: j['interactedAt'] != null ? DateTime.parse(j['interactedAt'] as String) : null,
    interactionType: j['interactionType'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

class DailyBrief {
  final String id;
  final String userId;
  final String familyId;
  final String briefDate; // YYYY-MM-DD
  final String greeting;
  final String familyArchetype;
  final String languageCode;
  final Map<String, dynamic> content;
  final DateTime generatedAt;
  final DateTime? deliveredAt;
  final DateTime? viewedAt;
  final DateTime? interactedAt;
  final int interactionCount;
  final int callsInitiated;
  final int messagesSent;
  final int memoriesViewed;
  final int karmaEarned;
  final List<BriefItem> items;

  DailyBrief({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.briefDate,
    required this.greeting,
    required this.familyArchetype,
    required this.languageCode,
    required this.content,
    required this.generatedAt,
    this.deliveredAt,
    this.viewedAt,
    this.interactedAt,
    required this.interactionCount,
    required this.callsInitiated,
    required this.messagesSent,
    required this.memoriesViewed,
    required this.karmaEarned,
    required this.items,
  });

  factory DailyBrief.fromJson(Map<String, dynamic> j) => DailyBrief(
    id: j['id'] as String,
    userId: j['userId'] as String,
    familyId: j['familyId'] as String,
    briefDate: j['briefDate'] as String,
    greeting: j['greeting'] as String,
    familyArchetype: j['familyArchetype'] as String? ?? 'unknown',
    languageCode: j['languageCode'] as String? ?? 'en',
    content: (j['content'] as Map<String, dynamic>?) ?? {},
    generatedAt: DateTime.parse(j['generatedAt'] as String),
    deliveredAt: j['deliveredAt'] != null ? DateTime.parse(j['deliveredAt'] as String) : null,
    viewedAt: j['viewedAt'] != null ? DateTime.parse(j['viewedAt'] as String) : null,
    interactedAt: j['interactedAt'] != null ? DateTime.parse(j['interactedAt'] as String) : null,
    interactionCount: j['interactionCount'] as int? ?? 0,
    callsInitiated: j['callsInitiated'] as int? ?? 0,
    messagesSent: j['messagesSent'] as int? ?? 0,
    memoriesViewed: j['memoriesViewed'] as int? ?? 0,
    karmaEarned: j['karmaEarned'] as int? ?? 0,
    items: ((j['items'] as List?) ?? [])
        .map((e) => BriefItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  String? get summary => content['summary'] as String?;
}

// ═══════════════════════════════════════════════════════════════════════════
// PULSE — Weather + Streaks + Karma
// ═══════════════════════════════════════════════════════════════════════════

class RelationshipWeather {
  final String id;
  final String familyId;
  final String weather; // sunny | partly_cloudy | cloudy | rainy | stormy
  final int daysSinceLastContact;
  final int interactionCount30d;
  final double? sentimentScore;
  final int streakDays;
  final String? previousWeather;
  final DateTime? weatherChangedAt;
  final DateTime computedAt;
  final Counterpart? counterpart;

  RelationshipWeather({
    required this.id,
    required this.familyId,
    required this.weather,
    required this.daysSinceLastContact,
    required this.interactionCount30d,
    this.sentimentScore,
    required this.streakDays,
    this.previousWeather,
    this.weatherChangedAt,
    required this.computedAt,
    this.counterpart,
  });

  factory RelationshipWeather.fromJson(Map<String, dynamic> j) => RelationshipWeather(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    weather: j['weather'] as String,
    daysSinceLastContact: j['daysSinceLastContact'] as int? ?? 0,
    interactionCount30d: j['interactionCount30d'] as int? ?? 0,
    sentimentScore: (j['sentimentScore'] as num?)?.toDouble(),
    streakDays: j['streakDays'] as int? ?? 0,
    previousWeather: j['previousWeather'] as String?,
    weatherChangedAt: j['weatherChangedAt'] != null ? DateTime.parse(j['weatherChangedAt'] as String) : null,
    computedAt: DateTime.parse(j['computedAt'] as String),
    counterpart: j['counterpart'] != null ? Counterpart.fromJson(j['counterpart'] as Map<String, dynamic>) : null,
  );

  String get weatherEmoji {
    switch (weather) {
      case 'sunny': return '☀️';
      case 'partly_cloudy': return '⛅';
      case 'cloudy': return '☁️';
      case 'rainy': return '🌧️';
      case 'stormy': return '⛈️';
      default: return '🌤️';
    }
  }
}

class ConnectionStreak {
  final String id;
  final String familyId;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastInteractionAt;
  final String streakType;
  final Counterpart? counterpart;

  ConnectionStreak({
    required this.id,
    required this.familyId,
    required this.currentStreak,
    required this.longestStreak,
    this.lastInteractionAt,
    required this.streakType,
    this.counterpart,
  });

  factory ConnectionStreak.fromJson(Map<String, dynamic> j) => ConnectionStreak(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    currentStreak: j['currentStreak'] as int? ?? 0,
    longestStreak: j['longestStreak'] as int? ?? 0,
    lastInteractionAt: j['lastInteractionAt'] != null ? DateTime.parse(j['lastInteractionAt'] as String) : null,
    streakType: j['streakType'] as String? ?? 'any',
    counterpart: j['counterpart'] != null ? Counterpart.fromJson(j['counterpart'] as Map<String, dynamic>) : null,
  );
}

class FamilyKarma {
  final String id;
  final String familyId;
  final int totalKarma;
  final int karmaThisWeek;
  final int karmaThisMonth;
  final String karmaTrend;
  final Map<String, int> karmaByRole;
  final List<dynamic> recentReasons;
  final DateTime? lastKarmaAt;

  FamilyKarma({
    required this.id,
    required this.familyId,
    required this.totalKarma,
    required this.karmaThisWeek,
    required this.karmaThisMonth,
    required this.karmaTrend,
    required this.karmaByRole,
    required this.recentReasons,
    this.lastKarmaAt,
  });

  factory FamilyKarma.fromJson(Map<String, dynamic> j) => FamilyKarma(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    totalKarma: j['totalKarma'] as int? ?? 0,
    karmaThisWeek: j['karmaThisWeek'] as int? ?? 0,
    karmaThisMonth: j['karmaThisMonth'] as int? ?? 0,
    karmaTrend: j['karmaTrend'] as String? ?? 'steady',
    karmaByRole: {
      'root': j['karmaByRole']?['root'] as int? ?? 0,
      'anchor': j['karmaByRole']?['anchor'] as int? ?? 0,
      'bridge': j['karmaByRole']?['bridge'] as int? ?? 0,
      'weaver': j['karmaByRole']?['weaver'] as int? ?? 0,
      'leaf': j['karmaByRole']?['leaf'] as int? ?? 0,
    },
    recentReasons: j['recentReasons'] as List? ?? [],
    lastKarmaAt: j['lastKarmaAt'] != null ? DateTime.parse(j['lastKarmaAt'] as String) : null,
  );
}

class Counterpart {
  final String type; // person | user
  final String id;
  final String name;
  final String? photoThumb;

  Counterpart({required this.type, required this.id, required this.name, this.photoThumb});

  factory Counterpart.fromJson(Map<String, dynamic> j) => Counterpart(
    type: j['type'] as String,
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Unknown',
    photoThumb: j['photoThumb'] as String?,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// PITRU — Ancestral Memory
// ═══════════════════════════════════════════════════════════════════════════

class AncestralMemory {
  final String id;
  final String familyId;
  final String? elderPersonId;
  final ElderInfo? elderPerson;
  final String mediaType; // audio | video
  final String mediaUrl;
  final String? thumbnailUrl;
  final int durationSec;
  final String title;
  final String? topic;
  final String language;
  final String? description;
  final String? transcript;
  final String? translation;
  final String? aiSummary;
  final List<dynamic> aiTags;
  final String status; // pending | processing | ready | failed | archived
  final bool isRevealed;
  final int viewCount;
  final int listenCount;
  final DateTime createdAt;
  final List<MemoryTagInfo> tags;

  AncestralMemory({
    required this.id,
    required this.familyId,
    this.elderPersonId,
    this.elderPerson,
    required this.mediaType,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.durationSec,
    required this.title,
    this.topic,
    required this.language,
    this.description,
    this.transcript,
    this.translation,
    this.aiSummary,
    required this.aiTags,
    required this.status,
    required this.isRevealed,
    required this.viewCount,
    required this.listenCount,
    required this.createdAt,
    required this.tags,
  });

  factory AncestralMemory.fromJson(Map<String, dynamic> j) => AncestralMemory(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    elderPersonId: j['elderPersonId'] as String?,
    elderPerson: j['elderPerson'] != null ? ElderInfo.fromJson(j['elderPerson'] as Map<String, dynamic>) : null,
    mediaType: j['mediaType'] as String? ?? 'audio',
    mediaUrl: j['mediaUrl'] as String,
    thumbnailUrl: j['thumbnailUrl'] as String?,
    durationSec: j['durationSec'] as int? ?? 0,
    title: j['title'] as String,
    topic: j['topic'] as String?,
    language: j['language'] as String? ?? 'en',
    description: j['description'] as String?,
    transcript: j['transcript'] as String?,
    translation: j['translation'] as String?,
    aiSummary: j['aiSummary'] as String?,
    aiTags: j['aiTags'] as List? ?? [],
    status: j['status'] as String? ?? 'pending',
    isRevealed: j['isRevealed'] as bool? ?? true,
    viewCount: j['viewCount'] as int? ?? 0,
    listenCount: j['listenCount'] as int? ?? 0,
    createdAt: DateTime.parse(j['createdAt'] as String),
    tags: ((j['tags'] as List?) ?? [])
        .map((e) => MemoryTagInfo.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  String get durationLabel {
    if (durationSec <= 0) return '';
    if (durationSec < 60) return '${durationSec}s';
    final m = durationSec ~/ 60;
    final s = durationSec % 60;
    return s > 0 ? '${m}m${s}s' : '${m}min';
  }
}

class ElderInfo {
  final String id;
  final String name;
  final String? photoThumb;

  ElderInfo({required this.id, required this.name, this.photoThumb});

  factory ElderInfo.fromJson(Map<String, dynamic> j) => ElderInfo(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Unknown',
    photoThumb: j['photoThumb'] as String?,
  );
}

class MemoryTagInfo {
  final String id;
  final String personId;
  final String tagType;
  final ElderInfo? person;

  MemoryTagInfo({required this.id, required this.personId, required this.tagType, this.person});

  factory MemoryTagInfo.fromJson(Map<String, dynamic> j) => MemoryTagInfo(
    id: j['id'] as String,
    personId: j['personId'] as String,
    tagType: j['tagType'] as String? ?? 'mentions',
    person: j['person'] != null ? ElderInfo.fromJson(j['person'] as Map<String, dynamic>) : null,
  );
}

class MemorialProfile {
  final String id;
  final String personId;
  final String familyId;
  final String? memorialTitle;
  final String? memorialBio;
  final String? birthDate;
  final String? deathDate;
  final String? coverPhotoUrl;
  final bool isPublic;
  final bool allowMessages;
  final bool aiPersonaEnabled;
  final ElderInfo person;
  final int memoryCount;
  final int totalListens;

  MemorialProfile({
    required this.id,
    required this.personId,
    required this.familyId,
    this.memorialTitle,
    this.memorialBio,
    this.birthDate,
    this.deathDate,
    this.coverPhotoUrl,
    required this.isPublic,
    required this.allowMessages,
    required this.aiPersonaEnabled,
    required this.person,
    required this.memoryCount,
    required this.totalListens,
  });

  factory MemorialProfile.fromJson(Map<String, dynamic> j) => MemorialProfile(
    id: j['id'] as String,
    personId: j['personId'] as String,
    familyId: j['familyId'] as String,
    memorialTitle: j['memorialTitle'] as String?,
    memorialBio: j['memorialBio'] as String?,
    birthDate: j['birthDate'] as String?,
    deathDate: j['deathDate'] as String?,
    coverPhotoUrl: j['coverPhotoUrl'] as String?,
    isPublic: j['isPublic'] as bool? ?? false,
    allowMessages: j['allowMessages'] as bool? ?? true,
    aiPersonaEnabled: j['aiPersonaEnabled'] as bool? ?? false,
    person: ElderInfo.fromJson(j['person'] as Map<String, dynamic>),
    memoryCount: j['memoryCount'] as int? ?? 0,
    totalListens: j['totalListens'] as int? ?? 0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// A-6 Festival Intelligence
// ═══════════════════════════════════════════════════════════════════════════

class Festival {
  final String id;
  final String festivalKey;
  final String dateType;
  final String festivalDate; // YYYY-MM-DD
  final String region;
  final Map<String, String> names;
  final Map<String, String> greetings;
  final String? description;
  final List<dynamic> themes;
  final List<dynamic> rituals;
  final int daysUntil;
  final bool isActive;

  Festival({
    required this.id,
    required this.festivalKey,
    required this.dateType,
    required this.festivalDate,
    required this.region,
    required this.names,
    required this.greetings,
    this.description,
    required this.themes,
    required this.rituals,
    required this.daysUntil,
    required this.isActive,
  });

  factory Festival.fromJson(Map<String, dynamic> j) => Festival(
    id: j['id'] as String,
    festivalKey: j['festivalKey'] as String,
    dateType: j['dateType'] as String? ?? 'lunar',
    festivalDate: j['festivalDate'] as String,
    region: j['region'] as String? ?? 'all',
    names: (j['names'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    greetings: (j['greetings'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    description: j['description'] as String?,
    themes: j['themes'] as List? ?? [],
    rituals: j['rituals'] as List? ?? [],
    daysUntil: j['daysUntil'] as int? ?? 0,
    isActive: j['isActive'] as bool? ?? true,
  );

  String nameForLanguage(String langCode) => names[langCode] ?? names['en'] ?? festivalKey;
  String greetingForLanguage(String langCode) => greetings[langCode] ?? greetings['en'] ?? '';
}

// ═══════════════════════════════════════════════════════════════════════════
// A-1 Blessing Chain
// ═══════════════════════════════════════════════════════════════════════════

class BlessingChain {
  final String id;
  final String familyId;
  final String? elderPersonId;
  final ElderInfo? elderPerson;
  final String? recipientUserId;
  final String mediaType; // text | audio
  final String? textContent;
  final String? mediaUrl;
  final int durationSec;
  final String triggerType; // birthday | festival | anniversary | custom
  final String triggerDate; // YYYY-MM-DD
  final String? festivalKey;
  final String language;
  final String status; // pending | delivered | viewed | cancelled
  final DateTime? deliveredAt;
  final DateTime? viewedAt;
  final bool isRecurring;
  final DateTime createdAt;

  BlessingChain({
    required this.id,
    required this.familyId,
    this.elderPersonId,
    this.elderPerson,
    this.recipientUserId,
    required this.mediaType,
    this.textContent,
    this.mediaUrl,
    required this.durationSec,
    required this.triggerType,
    required this.triggerDate,
    this.festivalKey,
    required this.language,
    required this.status,
    this.deliveredAt,
    this.viewedAt,
    required this.isRecurring,
    required this.createdAt,
  });

  factory BlessingChain.fromJson(Map<String, dynamic> j) => BlessingChain(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    elderPersonId: j['elderPersonId'] as String?,
    elderPerson: j['elderPerson'] != null ? ElderInfo.fromJson(j['elderPerson'] as Map<String, dynamic>) : null,
    recipientUserId: j['recipientUserId'] as String?,
    mediaType: j['mediaType'] as String? ?? 'text',
    textContent: j['textContent'] as String?,
    mediaUrl: j['mediaUrl'] as String?,
    durationSec: j['durationSec'] as int? ?? 0,
    triggerType: j['triggerType'] as String? ?? 'custom',
    triggerDate: j['triggerDate'] as String,
    festivalKey: j['festivalKey'] as String?,
    language: j['language'] as String? ?? 'en',
    status: j['status'] as String? ?? 'pending',
    deliveredAt: j['deliveredAt'] != null ? DateTime.parse(j['deliveredAt'] as String) : null,
    viewedAt: j['viewedAt'] != null ? DateTime.parse(j['viewedAt'] as String) : null,
    isRecurring: j['isRecurring'] as bool? ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  bool get isDelivered => status == 'delivered' || status == 'viewed';
  bool get isAudio => mediaType == 'audio';
}

// ═══════════════════════════════════════════════════════════════════════════
// A-2 Time Capsule
// ═══════════════════════════════════════════════════════════════════════════

class TimeCapsule {
  final String id;
  final String familyId;
  final String creatorId;
  final ElderInfo? creator;
  final String? recipientUserId;
  final String mediaType; // text | photo | video
  final String? textContent;
  final String? mediaUrl;
  final String title;
  final DateTime revealAt;
  final String? revealReason;
  final String status; // locked | revealed | viewed | cancelled
  final DateTime? revealedAt;
  final DateTime? viewedAt;
  final bool notifyOnReveal;
  final int countdownDays;
  final bool isLocked;
  final DateTime createdAt;

  TimeCapsule({
    required this.id,
    required this.familyId,
    required this.creatorId,
    this.creator,
    this.recipientUserId,
    required this.mediaType,
    this.textContent,
    this.mediaUrl,
    required this.title,
    required this.revealAt,
    this.revealReason,
    required this.status,
    this.revealedAt,
    this.viewedAt,
    required this.notifyOnReveal,
    required this.countdownDays,
    required this.isLocked,
    required this.createdAt,
  });

  factory TimeCapsule.fromJson(Map<String, dynamic> j) => TimeCapsule(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    creatorId: j['creatorId'] as String,
    creator: j['creator'] != null ? ElderInfo.fromJson(j['creator'] as Map<String, dynamic>) : null,
    recipientUserId: j['recipientUserId'] as String?,
    mediaType: j['mediaType'] as String? ?? 'text',
    textContent: j['textContent'] as String?,
    mediaUrl: j['mediaUrl'] as String?,
    title: j['title'] as String,
    revealAt: DateTime.parse(j['revealAt'] as String),
    revealReason: j['revealReason'] as String?,
    status: j['status'] as String? ?? 'locked',
    revealedAt: j['revealedAt'] != null ? DateTime.parse(j['revealedAt'] as String) : null,
    viewedAt: j['viewedAt'] != null ? DateTime.parse(j['viewedAt'] as String) : null,
    notifyOnReveal: j['notifyOnReveal'] as bool? ?? true,
    countdownDays: j['countdownDays'] as int? ?? 0,
    isLocked: j['isLocked'] as bool? ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  bool get isRevealed => status == 'revealed' || status == 'viewed';
}

// ═══════════════════════════════════════════════════════════════════════════
// A-3 Family Quests
// ═══════════════════════════════════════════════════════════════════════════

class FamilyQuest {
  final String id;
  final String familyId;
  final String? targetPersonId;
  final ElderInfo? targetPerson;
  final String questType; // call | message | share_photo | wish_birthday | visit | ritual
  final String title;
  final String description;
  final String actionType;
  final Map<String, dynamic> actionData;
  final String weekOf; // YYYY-MM-DD
  final DateTime deadline;
  final int karmaReward;
  final int karmaAwarded;
  final String status; // active | completed | expired | skipped
  final DateTime? completedAt;
  final String generatedBy;
  final DateTime createdAt;

  FamilyQuest({
    required this.id,
    required this.familyId,
    this.targetPersonId,
    this.targetPerson,
    required this.questType,
    required this.title,
    required this.description,
    required this.actionType,
    required this.actionData,
    required this.weekOf,
    required this.deadline,
    required this.karmaReward,
    required this.karmaAwarded,
    required this.status,
    this.completedAt,
    required this.generatedBy,
    required this.createdAt,
  });

  factory FamilyQuest.fromJson(Map<String, dynamic> j) => FamilyQuest(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    targetPersonId: j['targetPersonId'] as String?,
    targetPerson: j['targetPerson'] != null ? ElderInfo.fromJson(j['targetPerson'] as Map<String, dynamic>) : null,
    questType: j['questType'] as String,
    title: j['title'] as String,
    description: j['description'] as String,
    actionType: j['actionType'] as String,
    actionData: (j['actionData'] as Map<String, dynamic>?) ?? {},
    weekOf: j['weekOf'] as String,
    deadline: DateTime.parse(j['deadline'] as String),
    karmaReward: j['karmaReward'] as int? ?? 10,
    karmaAwarded: j['karmaAwarded'] as int? ?? 0,
    status: j['status'] as String? ?? 'active',
    completedAt: j['completedAt'] != null ? DateTime.parse(j['completedAt'] as String) : null,
    generatedBy: j['generatedBy'] as String? ?? 'graph_weak_point',
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  String get questEmoji {
    switch (questType) {
      case 'call': return '📞';
      case 'message': return '💬';
      case 'share_photo': return '📸';
      case 'wish_birthday': return '🎂';
      case 'visit': return '🏠';
      case 'ritual': return '🪔';
      default: return '✨';
    }
  }

  bool get isActive => status == 'active';
}

// ═══════════════════════════════════════════════════════════════════════════
// A-4 Silent Alarms
// ═══════════════════════════════════════════════════════════════════════════

class SilentAlarm {
  final String id;
  final String familyId;
  final String inactivePersonId;
  final ElderInfo? inactivePerson;
  final String bridgeUserId;
  final int daysInactive;
  final DateTime? lastActiveAt;
  final String severity; // gentle | moderate | urgent
  final String alarmMessage;
  final String status; // triggered | acknowledged | resolved | escalated
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final DateTime? escalatedAt;
  final List<dynamic> suggestions;
  final DateTime createdAt;

  SilentAlarm({
    required this.id,
    required this.familyId,
    required this.inactivePersonId,
    this.inactivePerson,
    required this.bridgeUserId,
    required this.daysInactive,
    this.lastActiveAt,
    required this.severity,
    required this.alarmMessage,
    required this.status,
    this.acknowledgedAt,
    this.resolvedAt,
    this.escalatedAt,
    required this.suggestions,
    required this.createdAt,
  });

  factory SilentAlarm.fromJson(Map<String, dynamic> j) => SilentAlarm(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    inactivePersonId: j['inactivePersonId'] as String,
    inactivePerson: j['inactivePerson'] != null ? ElderInfo.fromJson(j['inactivePerson'] as Map<String, dynamic>) : null,
    bridgeUserId: j['bridgeUserId'] as String,
    daysInactive: j['daysInactive'] as int? ?? 0,
    lastActiveAt: j['lastActiveAt'] != null ? DateTime.parse(j['lastActiveAt'] as String) : null,
    severity: j['severity'] as String? ?? 'gentle',
    alarmMessage: j['alarmMessage'] as String,
    status: j['status'] as String? ?? 'triggered',
    acknowledgedAt: j['acknowledgedAt'] != null ? DateTime.parse(j['acknowledgedAt'] as String) : null,
    resolvedAt: j['resolvedAt'] != null ? DateTime.parse(j['resolvedAt'] as String) : null,
    escalatedAt: j['escalatedAt'] != null ? DateTime.parse(j['escalatedAt'] as String) : null,
    suggestions: j['suggestions'] as List? ?? [],
    createdAt: DateTime.parse(j['createdAt'] as String),
  );

  String get severityEmoji {
    switch (severity) {
      case 'urgent': return '🚨';
      case 'moderate': return '⚠️';
      default: return '🔔';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// A-7 Family Chronicle
// ═══════════════════════════════════════════════════════════════════════════

class FamilyChronicle {
  final String id;
  final String familyId;
  final String title;
  final String? subtitle;
  final List<ChronicleChapter> chapters;
  final int chapterCount;
  final DateTime? lastGeneratedAt;
  final DateTime? nextGenerationAt;
  final String? aiModel;
  final DateTime createdAt;
  final DateTime updatedAt;

  FamilyChronicle({
    required this.id,
    required this.familyId,
    required this.title,
    this.subtitle,
    required this.chapters,
    required this.chapterCount,
    this.lastGeneratedAt,
    this.nextGenerationAt,
    this.aiModel,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FamilyChronicle.fromJson(Map<String, dynamic> j) => FamilyChronicle(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    title: j['title'] as String,
    subtitle: j['subtitle'] as String?,
    chapters: ((j['chapters'] as List?) ?? [])
        .map((e) => ChronicleChapter.fromJson(e as Map<String, dynamic>))
        .toList(),
    chapterCount: j['chapterCount'] as int? ?? 0,
    lastGeneratedAt: j['lastGeneratedAt'] != null ? DateTime.parse(j['lastGeneratedAt'] as String) : null,
    nextGenerationAt: j['nextGenerationAt'] != null ? DateTime.parse(j['nextGenerationAt'] as String) : null,
    aiModel: j['aiModel'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}

class ChronicleChapter {
  final int chapterNumber;
  final String title;
  final String content;
  final DateTime generatedAt;

  ChronicleChapter({
    required this.chapterNumber,
    required this.title,
    required this.content,
    required this.generatedAt,
  });

  factory ChronicleChapter.fromJson(Map<String, dynamic> j) => ChronicleChapter(
    chapterNumber: j['chapterNumber'] as int? ?? 0,
    title: j['title'] as String? ?? 'Untitled',
    content: j['content'] as String? ?? '',
    generatedAt: j['generatedAt'] != null ? DateTime.parse(j['generatedAt'] as String) : DateTime.now(),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Interaction result
// ═══════════════════════════════════════════════════════════════════════════

class InteractionResult {
  final int karmaAwarded;

  InteractionResult({required this.karmaAwarded});

  factory InteractionResult.fromJson(Map<String, dynamic> j) => InteractionResult(
    karmaAwarded: j['karmaAwarded'] as int? ?? 0,
  );
}

// Helper to safely decode JSON
Map<String, dynamic> parseJson(String body) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

List<dynamic> parseJsonList(String body) {
  try {
    return jsonDecode(body) as List<dynamic>;
  } catch (_) {
    return [];
  }
}
