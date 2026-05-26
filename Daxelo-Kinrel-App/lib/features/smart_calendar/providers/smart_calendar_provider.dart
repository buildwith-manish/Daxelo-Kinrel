// lib/features/smart_calendar/providers/smart_calendar_provider.dart
//
// DAXELO KINREL — Smart Calendar & Auto-Reminders with Hindu Panchang
//
// Orange K-Graph DNA design:
//   • PanchangModel: Full Hindu Panchang data model
//   • SmartCalendarEvent: Calendar events with Panchang integration
//   • HinduPanchangService: Simplified Panchang calculation engine
//   • SmartCalendarNotifier: State management for calendar views
//   • Providers: Riverpod providers for calendar state & Panchang data
//
// Design colors:
//   Birthday:     orange (#E8612A)
//   Anniversary:  amber (#F59240)
//   Festival:     gold (#D4AF37)
//   Panchang:     warm saffron (#E8612A)
//   Auspicious:   success green (#4CAF7A)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// Calendar Event Type
// ═══════════════════════════════════════════════════════════════════════

/// Types of calendar events.
enum CalendarEventType {
  birthday,
  anniversary,
  festival,
  panchangFestival,
  panchangAuspicious,
  custom,
  reminder,
}

// ═══════════════════════════════════════════════════════════════════════
// Reminder Timing
// ═══════════════════════════════════════════════════════════════════════

/// When a reminder should fire relative to the event.
enum ReminderTiming {
  oneWeekBefore,
  threeDaysBefore,
  oneDayBefore,
  morningOf,
  custom,
}

// ═══════════════════════════════════════════════════════════════════════
// Calendar View Mode
// ═══════════════════════════════════════════════════════════════════════

/// Calendar view mode options.
enum CalendarView {
  month,
  week,
  day,
}

// ═══════════════════════════════════════════════════════════════════════
// Panchang Model
// ═══════════════════════════════════════════════════════════════════════

/// Full Hindu Panchang data for a given date.
class PanchangModel {
  const PanchangModel({
    required this.date,
    required this.tithi,
    required this.nakshatra,
    required this.yoga,
    required this.karana,
    required this.vaar,
    required this.paksha,
    required this.rashi,
    required this.samvatsara,
    required this.masa,
    required this.ayana,
    required this.ritu,
    this.festivals = const [],
    this.isAuspicious = false,
    this.auspiciousTimeStart,
    this.auspiciousTimeEnd,
    this.rahukaalStart,
    this.rahukaalEnd,
    this.gulikaStart,
    this.gulikaEnd,
    this.yamaghantaStart,
    this.yamaghantaEnd,
  });

  final DateTime date;

  /// Lunar day (1-30)
  final String tithi;

  /// Lunar mansion (27 nakshatras)
  final String nakshatra;

  /// Sun-moon combination (27 yogas)
  final String yoga;

  /// Half-tithi
  final String karana;

  /// Day of week in Sanskrit/Hindi
  final String vaar;

  /// 'Shukla' (waxing) or 'Krishna' (waning)
  final String paksha;

  /// Zodiac sign
  final String rashi;

  /// Year name in 60-year cycle
  final String samvatsara;

  /// Lunar month name
  final String masa;

  /// 'Uttarayana' or 'Dakshinayana'
  final String ayana;

  /// Season
  final String ritu;

  /// Festivals on this day
  final List<String> festivals;

  /// Whether this day is auspicious
  final bool isAuspicious;

  /// Shubh muhurat start time
  final String? auspiciousTimeStart;

  /// Shubh muhurat end time
  final String? auspiciousTimeEnd;

  /// Inauspicious period start
  final String? rahukaalStart;

  /// Inauspicious period end
  final String? rahukaalEnd;

  /// Gulika period start
  final String? gulikaStart;

  /// Gulika period end
  final String? gulikaEnd;

  /// Yamaghanta period start
  final String? yamaghantaStart;

  /// Yamaghanta period end
  final String? yamaghantaEnd;

  /// Tithi symbol for compact display
  String get tithiSymbol {
    if (tithi.contains('Ekadashi')) return '✦';
    if (tithi.contains('Purnima')) return '●';
    if (tithi.contains('Amavasya')) return '○';
    if (paksha == 'Shukla') return '☽';
    return '☾';
  }

  /// Short display for tithi
  String get tithiShort {
    final parts = tithi.split(' ');
    if (parts.isEmpty) return tithi;
    // Return just the number part like "1", "2", etc.
    final numPart = parts.first;
    return numPart;
  }

  PanchangModel copyWith({
    DateTime? date,
    String? tithi,
    String? nakshatra,
    String? yoga,
    String? karana,
    String? vaar,
    String? paksha,
    String? rashi,
    String? samvatsara,
    String? masa,
    String? ayana,
    String? ritu,
    List<String>? festivals,
    bool? isAuspicious,
    String? auspiciousTimeStart,
    String? auspiciousTimeEnd,
    String? rahukaalStart,
    String? rahukaalEnd,
    String? gulikaStart,
    String? gulikaEnd,
    String? yamaghantaStart,
    String? yamaghantaEnd,
  }) {
    return PanchangModel(
      date: date ?? this.date,
      tithi: tithi ?? this.tithi,
      nakshatra: nakshatra ?? this.nakshatra,
      yoga: yoga ?? this.yoga,
      karana: karana ?? this.karana,
      vaar: vaar ?? this.vaar,
      paksha: paksha ?? this.paksha,
      rashi: rashi ?? this.rashi,
      samvatsara: samvatsara ?? this.samvatsara,
      masa: masa ?? this.masa,
      ayana: ayana ?? this.ayana,
      ritu: ritu ?? this.ritu,
      festivals: festivals ?? this.festivals,
      isAuspicious: isAuspicious ?? this.isAuspicious,
      auspiciousTimeStart: auspiciousTimeStart ?? this.auspiciousTimeStart,
      auspiciousTimeEnd: auspiciousTimeEnd ?? this.auspiciousTimeEnd,
      rahukaalStart: rahukaalStart ?? this.rahukaalStart,
      rahukaalEnd: rahukaalEnd ?? this.rahukaalEnd,
      gulikaStart: gulikaStart ?? this.gulikaStart,
      gulikaEnd: gulikaEnd ?? this.gulikaEnd,
      yamaghantaStart: yamaghantaStart ?? this.yamaghantaStart,
      yamaghantaEnd: yamaghantaEnd ?? this.yamaghantaEnd,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Smart Calendar Event
// ═══════════════════════════════════════════════════════════════════════

/// A calendar event with optional Panchang integration.
class SmartCalendarEvent {
  const SmartCalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    this.description,
    this.location,
    this.memberIds = const [],
    this.reminderTimings = const [],
    this.isAutoGenerated = false,
    this.panchangInfo,
  });

  final String id;
  final String title;
  final DateTime date;
  final CalendarEventType type;
  final String? description;
  final String? location;
  final List<String> memberIds;
  final List<ReminderTiming> reminderTimings;
  final bool isAutoGenerated;
  final PanchangModel? panchangInfo;

  /// Computed color from event type
  Color get color {
    switch (type) {
      case CalendarEventType.birthday:
        return KinrelColors.orange;           // #E8612A
      case CalendarEventType.anniversary:
        return KinrelColors.amber;            // #F59240
      case CalendarEventType.festival:
        return KinrelColors.gold;             // #D4AF37
      case CalendarEventType.panchangFestival:
        return KinrelColors.gold;             // #D4AF37
      case CalendarEventType.panchangAuspicious:
        return KinrelColors.success;          // #4CAF7A
      case CalendarEventType.custom:
        return KinrelColors.textSilver;       // #C9B4A8
      case CalendarEventType.reminder:
        return KinrelColors.info;             // #60A5FA
    }
  }

  /// Icon for the event type
  IconData get icon {
    switch (type) {
      case CalendarEventType.birthday:
        return Icons.cake_rounded;
      case CalendarEventType.anniversary:
        return Icons.favorite_rounded;
      case CalendarEventType.festival:
        return Icons.celebration_rounded;
      case CalendarEventType.panchangFestival:
        return Icons.temple_buddhist_rounded;
      case CalendarEventType.panchangAuspicious:
        return Icons.auto_awesome_rounded;
      case CalendarEventType.custom:
        return Icons.event_rounded;
      case CalendarEventType.reminder:
        return Icons.alarm_rounded;
    }
  }

  /// Emoji for the event type
  String get emoji {
    switch (type) {
      case CalendarEventType.birthday:
        return '🎂';
      case CalendarEventType.anniversary:
        return '💍';
      case CalendarEventType.festival:
        return '🎉';
      case CalendarEventType.panchangFestival:
        return '🪔';
      case CalendarEventType.panchangAuspicious:
        return '✨';
      case CalendarEventType.custom:
        return '📌';
      case CalendarEventType.reminder:
        return '⏰';
    }
  }

  /// Whether the event is on a specific date
  bool isOnDate(DateTime checkDate) {
    return date.year == checkDate.year &&
        date.month == checkDate.month &&
        date.day == checkDate.day;
  }

  /// Formatted date
  String get formattedDate {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month]}, ${date.year}';
  }

  SmartCalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    CalendarEventType? type,
    String? description,
    String? location,
    List<String>? memberIds,
    List<ReminderTiming>? reminderTimings,
    bool? isAutoGenerated,
    PanchangModel? panchangInfo,
  }) {
    return SmartCalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      type: type ?? this.type,
      description: description ?? this.description,
      location: location ?? this.location,
      memberIds: memberIds ?? this.memberIds,
      reminderTimings: reminderTimings ?? this.reminderTimings,
      isAutoGenerated: isAutoGenerated ?? this.isAutoGenerated,
      panchangInfo: panchangInfo ?? this.panchangInfo,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Hindu Panchang Service
// ═══════════════════════════════════════════════════════════════════════

/// Simplified Hindu Panchang calculation service.
///
/// Provides approximate Panchang data based on simplified astronomical
/// calculations and hardcoded festival dates for 2024-2027.
class HinduPanchangService {
  HinduPanchangService._();

  // ── Sanskrit Day Names ────────────────────────────────────────────
  static const List<String> vaarNames = [
    'Ravivaar',       // Sunday
    'Somavaar',       // Monday
    'Mangalvaar',     // Tuesday
    'Budhvaar',       // Wednesday
    'Guruvaar',       // Thursday
    'Shukravaar',     // Friday
    'Shanivaar',      // Saturday
  ];

  // ── Tithi Names ───────────────────────────────────────────────────
  static const List<String> shuklaTithiNames = [
    '1 Pratipada', '2 Dwitiya', '3 Tritiya', '4 Chaturthi',
    '5 Panchami', '6 Shashthi', '7 Saptami', '8 Ashtami',
    '9 Navami', '10 Dashami', '11 Ekadashi', '12 Dwadashi',
    '13 Trayodashi', '14 Chaturdashi', 'Purnima',
  ];

  static const List<String> krishnaTithiNames = [
    '1 Pratipada', '2 Dwitiya', '3 Tritiya', '4 Chaturthi',
    '5 Panchami', '6 Shashthi', '7 Saptami', '8 Ashtami',
    '9 Navami', '10 Dashami', '11 Ekadashi', '12 Dwadashi',
    '13 Trayodashi', '14 Chaturdashi', 'Amavasya',
  ];

  // ── Nakshatra Names ───────────────────────────────────────────────
  static const List<String> nakshatraNames = [
    'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira',
    'Ardra', 'Punarvasu', 'Pushya', 'Ashlesha', 'Magha',
    'Purva Phalguni', 'Uttara Phalguni', 'Hasta', 'Chitra',
    'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha', 'Mula',
    'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishtha',
    'Shatabhisha', 'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati',
  ];

  // ── Yoga Names ────────────────────────────────────────────────────
  static const List<String> yogaNames = [
    'Vishkumbha', 'Priti', 'Ayushman', 'Saubhagya', 'Shobhana',
    'Atiganda', 'Sukarma', 'Dhriti', 'Shula', 'Ganda',
    'Vriddhi', 'Dhruva', 'Vyaghata', 'Harshana', 'Vajra',
    'Siddhi', 'Vyatipata', 'Variyana', 'Parigha', 'Shiva',
    'Siddha', 'Sadhya', 'Shubha', 'Shukla', 'Brahma',
    'Indra', 'Vaidhriti',
  ];

  // ── Karana Names ──────────────────────────────────────────────────
  static const List<String> karanaNames = [
    'Bava', 'Balava', 'Kaulava', 'Taitila', 'Gara',
    'Vanija', 'Vishti', 'Shakuni', 'Chatushpada', 'Naga',
    'Kimstughna',
  ];

  // ── Rashi Names ───────────────────────────────────────────────────
  static const List<String> rashiNames = [
    'Mesha (Aries)', 'Vrishabha (Taurus)', 'Mithuna (Gemini)',
    'Karka (Cancer)', 'Simha (Leo)', 'Kanya (Virgo)',
    'Tula (Libra)', 'Vrischika (Scorpio)', 'Dhanu (Sagittarius)',
    'Makara (Capricorn)', 'Kumbha (Aquarius)', 'Meena (Pisces)',
  ];

  // ── Samvatsara Names (60-year cycle) ──────────────────────────────
  static const List<String> samvatsaraNames = [
    'Prabhava', 'Vibhava', 'Shukla', 'Pramoda', 'Prajapati',
    'Angirasa', 'Shrimukha', 'Bhava', 'Yuvan', 'Dhatri',
    'Ishvara', 'Bahudhanya', 'Pramathin', 'Vikrama', 'Vrisha',
    'Chitrabhanu', 'Swabhanu', 'Tarana', 'Parthiva', 'Vyaya',
    'Sarvajit', 'Sarvadhari', 'Virodhi', 'Vikrita', 'Khara',
    'Nandana', 'Vijaya', 'Jaya', 'Manmatha', 'Durmukha',
    'Hemalamba', 'Vilamba', 'Vikari', 'Sharvari', 'Plava',
    'Shubhakrita', 'Shobhakrita', 'Krodhin', 'Vishvavasu', 'Parabhava',
    'Plavanga', 'Keelaka', 'Saumya', 'Sadharana', 'Virodhikrita',
    'Paridhavi', 'Pramadicha', 'Ananda', 'Rakshasa', 'Nala',
    'Pingala', 'Kalayukti', 'Sadharana', 'Vrodhi', 'Vikarta',
    'Khara', 'Nandana', 'Vijaya', 'Jaya', 'Manmatha',
  ];

  // ── Masa Names ────────────────────────────────────────────────────
  static const List<String> masaNames = [
    'Chaitra', 'Vaishakha', 'Jyeshtha', 'Ashadha',
    'Shravana', 'Bhadrapada', 'Ashwina', 'Kartika',
    'Margashirsha', 'Pausha', 'Magha', 'Phalguna',
  ];

  // ── Ritu Names ────────────────────────────────────────────────────
  static const List<String> rituNames = [
    'Vasanta (Spring)', 'Grishma (Summer)', 'Varsha (Monsoon)',
    'Sharad (Autumn)', 'Hemanta (Pre-Winter)', 'Shishira (Winter)',
  ];

  // ── Rahu Kaal Times (approximate, by weekday) ─────────────────────
  // Index: 0=Mon, 1=Tue, 2=Wed, 3=Thu, 4=Fri, 5=Sat, 6=Sun
  static const List<({String start, String end})> rahukaalTimes = [
    (start: '7:30 AM', end: '9:00 AM'),     // Monday
    (start: '3:00 PM', end: '4:30 PM'),      // Tuesday
    (start: '12:00 PM', end: '1:30 PM'),     // Wednesday
    (start: '1:30 PM', end: '3:00 PM'),      // Thursday
    (start: '10:30 AM', end: '12:00 PM'),    // Friday
    (start: '9:00 AM', end: '10:30 AM'),     // Saturday
    (start: '4:30 PM', end: '6:00 PM'),      // Sunday
  ];

  // ── Gulika Times (approximate, by weekday) ────────────────────────
  static const List<({String start, String end})> gulikaTimes = [
    (start: '1:30 PM', end: '3:00 PM'),      // Monday
    (start: '12:00 PM', end: '1:30 PM'),     // Tuesday
    (start: '10:30 AM', end: '12:00 PM'),    // Wednesday
    (start: '9:00 AM', end: '10:30 AM'),     // Thursday
    (start: '7:30 AM', end: '9:00 AM'),      // Friday
    (start: '3:00 PM', end: '4:30 PM'),      // Saturday
    (start: '3:00 PM', end: '4:30 PM'),      // Sunday
  ];

  // ── Yamaghanta Times (approximate, by weekday) ────────────────────
  static const List<({String start, String end})> yamaghantaTimes = [
    (start: '10:30 AM', end: '12:00 PM'),    // Monday
    (start: '9:00 AM', end: '10:30 AM'),     // Tuesday
    (start: '7:30 AM', end: '9:00 AM'),      // Wednesday
    (start: '4:30 PM', end: '6:00 PM'),      // Thursday
    (start: '3:00 PM', end: '4:30 PM'),      // Friday
    (start: '12:00 PM', end: '1:30 PM'),     // Saturday
    (start: '1:30 PM', end: '3:00 PM'),      // Sunday
  ];

  // ── Festival Database (hardcoded for 2024-2027) ───────────────────
  static const List<({int year, int month, int day, String name})> _festivals = [
    // 2024
    (year: 2024, month: 1,  day: 14, name: 'Makar Sankranti'),
    (year: 2024, month: 1,  day: 22, name: 'Ram Mandir Inauguration'),
    (year: 2024, month: 3,  day: 8,  name: 'Maha Shivaratri'),
    (year: 2024, month: 3,  day: 25, name: 'Holi'),
    (year: 2024, month: 4,  day: 9,  name: 'Ugadi / Gudi Padwa'),
    (year: 2024, month: 4,  day: 11, name: 'Chaitra Navratri Begins'),
    (year: 2024, month: 4,  day: 17, name: 'Ram Navami'),
    (year: 2024, month: 4,  day: 23, name: 'Hanuman Jayanti'),
    (year: 2024, month: 6,  day: 17, name: 'Vat Purnima'),
    (year: 2024, month: 7,  day: 7,  name: 'Guru Purnima'),
    (year: 2024, month: 8,  day: 5,  name: 'Nag Panchami'),
    (year: 2024, month: 8,  day: 12, name: 'Varalakshmi Vrat'),
    (year: 2024, month: 8,  day: 19, name: 'Raksha Bandhan'),
    (year: 2024, month: 8,  day: 26, name: 'Krishna Janmashtami'),
    (year: 2024, month: 9,  day: 7,  name: 'Ganesh Chaturthi'),
    (year: 2024, month: 9,  day: 17, name: 'Pitru Paksha Begins'),
    (year: 2024, month: 10, day: 3,  name: 'Shardiya Navratri Begins'),
    (year: 2024, month: 10, day: 11, name: 'Maha Ashtami'),
    (year: 2024, month: 10, day: 12, name: 'Maha Navami'),
    (year: 2024, month: 10, day: 13, name: 'Dussehra / Vijayadashami'),
    (year: 2024, month: 10, day: 20, name: 'Sharad Purnima'),
    (year: 2024, month: 11, day: 1,  name: 'Karwa Chauth'),
    (year: 2024, month: 11, day: 2,  name: 'Ahoi Ashtami'),
    (year: 2024, month: 11, day: 7,  name: 'Dhanteras'),
    (year: 2024, month: 11, day: 8,  name: 'Naraka Chaturdashi / Kali Chaudas'),
    (year: 2024, month: 11, day: 9,  name: 'Diwali (Lakshmi Puja)'),
    (year: 2024, month: 11, day: 10, name: 'Govardhan Puja'),
    (year: 2024, month: 11, day: 11, name: 'Bhai Dooj'),
    (year: 2024, month: 11, day: 15, name: 'Chhath Puja'),
    (year: 2024, month: 11, day: 20, name: 'Tulsi Vivah'),
    (year: 2024, month: 12, day: 14, name: 'Geeta Jayanti'),
    (year: 2024, month: 12, day: 25, name: 'Christmas'),

    // 2025
    (year: 2025, month: 1,  day: 14, name: 'Makar Sankranti'),
    (year: 2025, month: 2,  day: 26, name: 'Maha Shivaratri'),
    (year: 2025, month: 3,  day: 14, name: 'Holi'),
    (year: 2025, month: 3,  day: 30, name: 'Ugadi / Gudi Padwa'),
    (year: 2025, month: 4,  day: 6,  name: 'Chaitra Navratri Begins'),
    (year: 2025, month: 4,  day: 6,  name: 'Ram Navami'),
    (year: 2025, month: 4,  day: 12, name: 'Hanuman Jayanti'),
    (year: 2025, month: 7,  day: 10, name: 'Guru Purnima'),
    (year: 2025, month: 8,  day: 9,  name: 'Raksha Bandhan'),
    (year: 2025, month: 8,  day: 16, name: 'Krishna Janmashtami'),
    (year: 2025, month: 8,  day: 27, name: 'Ganesh Chaturthi'),
    (year: 2025, month: 9,  day: 7,  name: 'Pitru Paksha Begins'),
    (year: 2025, month: 9,  day: 22, name: 'Shardiya Navratri Begins'),
    (year: 2025, month: 9,  day: 30, name: 'Maha Ashtami'),
    (year: 2025, month: 10, day: 1,  name: 'Maha Navami'),
    (year: 2025, month: 10, day: 2,  name: 'Dussehra / Vijayadashami'),
    (year: 2025, month: 10, day: 9,  name: 'Sharad Purnima'),
    (year: 2025, month: 10, day: 20, name: 'Karwa Chauth'),
    (year: 2025, month: 10, day: 28, name: 'Dhanteras'),
    (year: 2025, month: 10, day: 29, name: 'Naraka Chaturdashi'),
    (year: 2025, month: 10, day: 30, name: 'Diwali (Lakshmi Puja)'),
    (year: 2025, month: 10, day: 31, name: 'Govardhan Puja'),
    (year: 2025, month: 11, day: 1,  name: 'Bhai Dooj'),
    (year: 2025, month: 11, day: 5,  name: 'Chhath Puja'),
    (year: 2025, month: 11, day: 14, name: 'Dev Deepawali'),
    (year: 2025, month: 12, day: 25, name: 'Christmas'),

    // 2026
    (year: 2026, month: 1,  day: 14, name: 'Makar Sankranti'),
    (year: 2026, month: 2,  day: 15, name: 'Maha Shivaratri'),
    (year: 2026, month: 3,  day: 4,  name: 'Holi'),
    (year: 2026, month: 3,  day: 20, name: 'Ugadi / Gudi Padwa'),
    (year: 2026, month: 3,  day: 26, name: 'Chaitra Navratri Begins'),
    (year: 2026, month: 4,  day: 2,  name: 'Ram Navami'),
    (year: 2026, month: 4,  day: 3,  name: 'Hanuman Jayanti'),
    (year: 2026, month: 7,  day: 29, name: 'Guru Purnima'),
    (year: 2026, month: 8,  day: 18, name: 'Raksha Bandhan'),
    (year: 2026, month: 8,  day: 5,  name: 'Krishna Janmashtami'),
    (year: 2026, month: 9,  day: 15, name: 'Ganesh Chaturthi'),
    (year: 2026, month: 9,  day: 27, name: 'Pitru Paksha Begins'),
    (year: 2026, month: 10, day: 11, name: 'Shardiya Navratri Begins'),
    (year: 2026, month: 10, day: 19, name: 'Maha Ashtami'),
    (year: 2026, month: 10, day: 20, name: 'Maha Navami'),
    (year: 2026, month: 10, day: 21, name: 'Dussehra / Vijayadashami'),
    (year: 2026, month: 11, day: 8,  name: 'Karwa Chauth'),
    (year: 2026, month: 11, day: 17, name: 'Dhanteras'),
    (year: 2026, month: 11, day: 18, name: 'Diwali (Lakshmi Puja)'),
    (year: 2026, month: 11, day: 19, name: 'Govardhan Puja'),
    (year: 2026, month: 11, day: 20, name: 'Bhai Dooj'),
    (year: 2026, month: 11, day: 23, name: 'Chhath Puja'),
    (year: 2026, month: 12, day: 25, name: 'Christmas'),

    // 2027
    (year: 2027, month: 1,  day: 14, name: 'Makar Sankranti'),
    (year: 2027, month: 2,  day: 4,  name: 'Maha Shivaratri'),
    (year: 2027, month: 3,  day: 22, name: 'Holi'),
    (year: 2027, month: 4,  day: 9,  name: 'Ugadi / Gudi Padwa'),
    (year: 2027, month: 4,  day: 15, name: 'Ram Navami'),
    (year: 2027, month: 4,  day: 22, name: 'Hanuman Jayanti'),
    (year: 2027, month: 7,  day: 18, name: 'Guru Purnima'),
    (year: 2027, month: 8,  day: 7,  name: 'Raksha Bandhan'),
    (year: 2027, month: 8,  day: 15, name: 'Krishna Janmashtami'),
    (year: 2027, month: 9,  day: 4,  name: 'Ganesh Chaturthi'),
    (year: 2027, month: 10, day: 1,  name: 'Shardiya Navratri Begins'),
    (year: 2027, month: 10, day: 9,  name: 'Maha Ashtami'),
    (year: 2027, month: 10, day: 10, name: 'Dussehra / Vijayadashami'),
    (year: 2027, month: 10, day: 28, name: 'Karwa Chauth'),
    (year: 2027, month: 11, day: 5,  name: 'Dhanteras'),
    (year: 2027, month: 11, day: 7,  name: 'Diwali (Lakshmi Puja)'),
    (year: 2027, month: 11, day: 8,  name: 'Govardhan Puja'),
    (year: 2027, month: 11, day: 9,  name: 'Bhai Dooj'),
    (year: 2027, month: 11, day: 12, name: 'Chhath Puja'),
    (year: 2027, month: 12, day: 25, name: 'Christmas'),
  ];

  // ── Auspicious Day Patterns ───────────────────────────────────────
  /// Days generally considered auspicious in Hindu tradition
  static const List<int> _auspiciousTithiIndices = [
    0,  // Pratipada
    4,  // Panchami
    6,  // Saptami
    9,  // Dashami
    10, // Ekadashi
    14, // Purnima (shukla)
  ];

  // ── Public Methods ────────────────────────────────────────────────

  /// Calculate Panchang for a given date.
  static PanchangModel getPanchang(DateTime date) {
    // Simplified calculation using approximate lunar cycle
    final dayOfYear = _dayOfYear(date);
    final lunarCycle = (dayOfYear + _lunarOffset(date.year)) % 30;
    final tithiIndex = lunarCycle;
    final isShukla = tithiIndex < 15;
    final paksha = isShukla ? 'Shukla' : 'Krishna';

    final tithiName = isShukla
        ? shuklaTithiNames[tithiIndex.clamp(0, 14)]
        : krishnaTithiNames[(tithiIndex - 15).clamp(0, 14)];

    // Nakshatra: ~13.3 days per nakshatra, use day offset
    final nakshatraIndex =
        ((dayOfYear + _nakshatraOffset(date.year)) % 27).clamp(0, 26);

    // Yoga: similar cycle
    final yogaIndex =
        ((dayOfYear + _yogaOffset(date.year)) % 27).clamp(0, 26);

    // Karana
    final karanaIndex =
        ((dayOfYear * 2 + _karanaOffset(date.year)) % 11).clamp(0, 10);

    // Rashi: month-based
    final rashiIndex = (date.month - 1 + 3) % 12; // Approximate

    // Samvatsara: 60-year cycle from a base year
    final samvatsaraIndex = ((date.year - 1987) % 60).clamp(0, 59);

    // Masa: approximate lunar month
    final masaIndex = ((date.month - 2) % 12).clamp(0, 11);

    // Ayana
    final ayana = (date.month >= 1 && date.month <= 6)
        ? 'Uttarayana'
        : 'Dakshinayana';

    // Ritu
    final rituIndex = ((date.month - 1) ~/ 2) % 6;

    // Weekday index for Rahu Kaal (0=Mon...6=Sun)
    final weekdayIndex = (date.weekday - 1) % 7;

    // Festivals for this date
    final festivals = _festivals
        .where((f) =>
            f.year == date.year &&
            f.month == date.month &&
            f.day == date.day)
        .map((f) => f.name)
        .toList();

    // Is auspicious
    final isAuspicious = _auspiciousTithiIndices.contains(tithiIndex % 15) ||
        festivals.isNotEmpty;

    // Auspicious time (shubh muhurat)
    String? auspiciousStart;
    String? auspiciousEnd;
    if (isAuspicious) {
      // Approximate: 6:00 AM to 10:30 AM is generally considered shubh
      auspiciousStart = '6:00 AM';
      auspiciousEnd = '10:30 AM';
    }

    return PanchangModel(
      date: date,
      tithi: tithiName,
      nakshatra: nakshatraNames[nakshatraIndex],
      yoga: yogaNames[yogaIndex],
      karana: karanaNames[karanaIndex],
      vaar: vaarNames[date.weekday % 7],
      paksha: paksha,
      rashi: rashiNames[rashiIndex],
      samvatsara: samvatsaraNames[samvatsaraIndex],
      masa: masaNames[masaIndex],
      ayana: ayana,
      ritu: rituNames[rituIndex],
      festivals: festivals,
      isAuspicious: isAuspicious,
      auspiciousTimeStart: auspiciousStart,
      auspiciousTimeEnd: auspiciousEnd,
      rahukaalStart: rahukaalTimes[weekdayIndex].start,
      rahukaalEnd: rahukaalTimes[weekdayIndex].end,
      gulikaStart: gulikaTimes[weekdayIndex].start,
      gulikaEnd: gulikaTimes[weekdayIndex].end,
      yamaghantaStart: yamaghantaTimes[weekdayIndex].start,
      yamaghantaEnd: yamaghantaTimes[weekdayIndex].end,
    );
  }

  /// Get Hindu festivals for a specific month.
  static List<SmartCalendarEvent> getFestivalsForMonth(int year, int month) {
    final festivalDates = _festivals
        .where((f) => f.year == year && f.month == month)
        .toList();

    return festivalDates.map((f) {
      final panchang = getPanchang(DateTime(f.year, f.month, f.day));
      return SmartCalendarEvent(
        id: 'panchang-${f.year}-${f.month}-${f.day}-${f.name.hashCode}',
        title: f.name,
        date: DateTime(f.year, f.month, f.day),
        type: CalendarEventType.panchangFestival,
        description: '${f.name} — Hindu Festival',
        isAutoGenerated: true,
        panchangInfo: panchang,
        reminderTimings: [
          ReminderTiming.oneDayBefore,
          ReminderTiming.morningOf,
        ],
      );
    }).toList();
  }

  /// Check if a given date is auspicious.
  static bool isAuspiciousDay(DateTime date) {
    final panchang = getPanchang(date);
    return panchang.isAuspicious;
  }

  /// Get auspicious days in a given month.
  static List<SmartCalendarEvent> getAuspiciousDays(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final auspiciousDays = <SmartCalendarEvent>[];

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final panchang = getPanchang(date);
      if (panchang.isAuspicious && panchang.festivals.isEmpty) {
        auspiciousDays.add(SmartCalendarEvent(
          id: 'auspicious-$year-$month-$day',
          title: 'Shubh Din — ${panchang.tithi}',
          date: date,
          type: CalendarEventType.panchangAuspicious,
          description:
              '${panchang.tithi} · ${panchang.nakshatra} · ${panchang.yoga}',
          isAutoGenerated: true,
          panchangInfo: panchang,
        ));
      }
    }

    return auspiciousDays;
  }

  // ── Private Helpers ───────────────────────────────────────────────

  /// Day of year (1-based)
  static int _dayOfYear(DateTime date) {
    return date.difference(DateTime(date.year, 1, 0)).inDays;
  }

  /// Approximate lunar offset for a given year.
  /// This creates a pseudo-random but consistent offset per year
  /// to simulate the lunar calendar drift.
  static int _lunarOffset(int year) {
    return ((year - 2000) * 11 + 7) % 30;
  }

  /// Nakshatra offset per year
  static int _nakshatraOffset(int year) {
    return ((year - 2000) * 7 + 3) % 27;
  }

  /// Yoga offset per year
  static int _yogaOffset(int year) {
    return ((year - 2000) * 13 + 5) % 27;
  }

  /// Karana offset per year
  static int _karanaOffset(int year) {
    return ((year - 2000) * 9 + 11) % 11;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Smart Calendar State
// ═══════════════════════════════════════════════════════════════════════

/// State for the Smart Calendar feature.
class SmartCalendarState {
  const SmartCalendarState({
    this.selectedDate,
    this.viewMode = CalendarView.month,
    this.events = const [],
    this.showPanchang = false,
    this.panchangForSelectedDate,
  });

  /// Currently selected date. Defaults to today.
  final DateTime? selectedDate;

  /// Current calendar view mode.
  final CalendarView viewMode;

  /// All calendar events.
  final List<SmartCalendarEvent> events;

  /// Whether to show Panchang overlay.
  final bool showPanchang;

  /// Panchang data for the selected date.
  final PanchangModel? panchangForSelectedDate;

  /// Get the effective selected date (defaults to today).
  DateTime get effectiveSelectedDate => selectedDate ?? DateTime.now();

  /// Get events for the selected date.
  List<SmartCalendarEvent> get eventsForSelectedDate {
    final sel = effectiveSelectedDate;
    return events
        .where((e) =>
            e.date.year == sel.year &&
            e.date.month == sel.month &&
            e.date.day == sel.day)
        .toList();
  }

  /// Get events for a specific date.
  List<SmartCalendarEvent> eventsForDate(DateTime date) {
    return events
        .where((e) =>
            e.date.year == date.year &&
            e.date.month == date.month &&
            e.date.day == date.day)
        .toList();
  }

  SmartCalendarState copyWith({
    DateTime? selectedDate,
    bool clearSelectedDate = false,
    CalendarView? viewMode,
    List<SmartCalendarEvent>? events,
    bool? showPanchang,
    bool clearPanchang = false,
    PanchangModel? panchangForSelectedDate,
  }) {
    return SmartCalendarState(
      selectedDate:
          clearSelectedDate ? null : (selectedDate ?? this.selectedDate),
      viewMode: viewMode ?? this.viewMode,
      events: events ?? this.events,
      showPanchang: showPanchang ?? this.showPanchang,
      panchangForSelectedDate:
          clearPanchang ? null : (panchangForSelectedDate ?? this.panchangForSelectedDate),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Smart Calendar Notifier
// ═══════════════════════════════════════════════════════════════════════

/// State notifier managing the smart calendar.
class SmartCalendarNotifier extends StateNotifier<SmartCalendarState> {
  SmartCalendarNotifier() : super(const SmartCalendarState()) {
    _initializeEvents();
  }

  void _initializeEvents() {
    final now = DateTime.now();
    final panchang = HinduPanchangService.getPanchang(now);

    // Seed with demo events including auto-generated birthdays
    final demoEvents = <SmartCalendarEvent>[
      // Birthdays
      SmartCalendarEvent(
        id: 'bday-arjun',
        title: 'Arjun Sharma — Birthday',
        date: DateTime(now.year, now.month, now.day + 5),
        type: CalendarEventType.birthday,
        description: 'Arjun turns 32 today! 🎂',
        isAutoGenerated: true,
        reminderTimings: [
          ReminderTiming.oneWeekBefore,
          ReminderTiming.oneDayBefore,
          ReminderTiming.morningOf,
        ],
      ),
      SmartCalendarEvent(
        id: 'bday-meera',
        title: 'Meera Patel — Birthday',
        date: DateTime(now.year, now.month, now.day + 18),
        type: CalendarEventType.birthday,
        description: 'Meera\'s special day! 🎂',
        isAutoGenerated: true,
        reminderTimings: [
          ReminderTiming.oneDayBefore,
          ReminderTiming.morningOf,
        ],
      ),
      SmartCalendarEvent(
        id: 'bday-dadi',
        title: 'Dadi (Kamla) — Birthday',
        date: DateTime(now.year, now.month + 1, 10),
        type: CalendarEventType.birthday,
        description: 'Dadi\'s 75th birthday celebration! 🎂🎉',
        isAutoGenerated: true,
        reminderTimings: [
          ReminderTiming.oneWeekBefore,
          ReminderTiming.oneDayBefore,
          ReminderTiming.morningOf,
        ],
      ),

      // Anniversaries
      SmartCalendarEvent(
        id: 'anni-sharma',
        title: 'Sharma Family — Anniversary',
        date: DateTime(now.year, now.month, now.day + 12),
        type: CalendarEventType.anniversary,
        description: '35 years of togetherness! 💍',
        isAutoGenerated: true,
        reminderTimings: [
          ReminderTiming.oneWeekBefore,
          ReminderTiming.oneDayBefore,
          ReminderTiming.morningOf,
        ],
      ),

      // Custom events
      SmartCalendarEvent(
        id: 'custom-griha-pravesh',
        title: 'Griha Pravesh — New Home',
        date: DateTime(now.year, now.month + 2, 5),
        type: CalendarEventType.custom,
        description: 'Housewarming ceremony 🏠🙏',
        reminderTimings: [
          ReminderTiming.oneWeekBefore,
          ReminderTiming.oneDayBefore,
        ],
      ),
    ];

    // Add Panchang festivals for current month
    final festivals = HinduPanchangService.getFestivalsForMonth(
        now.year, now.month);
    demoEvents.addAll(festivals);

    // Add Panchang festivals for next month
    final nextMonth = now.month == 12
        ? DateTime(now.year + 1, 1)
        : DateTime(now.year, now.month + 1);
    final nextFestivals = HinduPanchangService.getFestivalsForMonth(
        nextMonth.year, nextMonth.month);
    demoEvents.addAll(nextFestivals);

    // Set initial Panchang
    state = state.copyWith(
      events: demoEvents,
      panchangForSelectedDate: panchang,
    );
  }

  /// Select a date and update Panchang.
  void selectDate(DateTime date) {
    final panchang = HinduPanchangService.getPanchang(date);
    state = state.copyWith(
      selectedDate: date,
      panchangForSelectedDate: panchang,
    );
  }

  /// Toggle calendar view mode.
  void toggleView(CalendarView mode) {
    state = state.copyWith(viewMode: mode);
  }

  /// Toggle Panchang overlay visibility.
  void togglePanchang() {
    state = state.copyWith(showPanchang: !state.showPanchang);
  }

  /// Add a new event.
  void addEvent(SmartCalendarEvent event) {
    state = state.copyWith(events: [...state.events, event]);
  }

  /// Add a reminder to an existing event.
  void addReminder(String eventId, ReminderTiming timing) {
    final updatedEvents = state.events.map((e) {
      if (e.id == eventId) {
        final timings = List<ReminderTiming>.from(e.reminderTimings);
        if (!timings.contains(timing)) {
          timings.add(timing);
        }
        return e.copyWith(reminderTimings: timings);
      }
      return e;
    }).toList();
    state = state.copyWith(events: updatedEvents);
  }

  /// Navigate to previous month.
  void previousMonth() {
    final current = state.effectiveSelectedDate;
    final prev = DateTime(current.year, current.month - 1, 1);
    selectDate(prev);
  }

  /// Navigate to next month.
  void nextMonth() {
    final current = state.effectiveSelectedDate;
    final next = DateTime(current.year, current.month + 1, 1);
    selectDate(next);
  }

  /// Go to today.
  void goToToday() {
    selectDate(DateTime.now());
  }

  /// Load festivals for a specific month and merge into events.
  void loadFestivalsForMonth(int year, int month) {
    final festivals =
        HinduPanchangService.getFestivalsForMonth(year, month);
    final existingIds = state.events.map((e) => e.id).toSet();
    final newFestivals =
        festivals.where((f) => !existingIds.contains(f.id)).toList();
    if (newFestivals.isNotEmpty) {
      state = state.copyWith(events: [...state.events, ...newFestivals]);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════

/// Main smart calendar provider.
final smartCalendarProvider =
    StateNotifierProvider<SmartCalendarNotifier, SmartCalendarState>(
  (ref) => SmartCalendarNotifier(),
);

/// Panchang for a specific date provider.
final panchangForDateProvider =
    FutureProvider.family<PanchangModel, DateTime>((ref, date) async {
  // Simulate a small delay for async feel
  await Future.delayed(const Duration(milliseconds: 100));
  return HinduPanchangService.getPanchang(date);
});

/// Festivals for a specific month provider.
final festivalsForMonthProvider = FutureProvider.family<
    List<SmartCalendarEvent>, ({int year, int month})>((ref, params) async {
  await Future.delayed(const Duration(milliseconds: 150));
  return HinduPanchangService.getFestivalsForMonth(params.year, params.month);
});
