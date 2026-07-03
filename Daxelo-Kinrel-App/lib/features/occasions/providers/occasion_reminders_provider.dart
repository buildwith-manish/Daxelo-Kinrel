// lib/features/occasions/providers/occasion_reminders_provider.dart
//
// DAXELO KINREL — Occasion Reminders Provider
//
// Manages birthday and anniversary reminders for all family members.
// Reads Person objects from familyMembersProvider, computes next
// calendar occurrence, calculates daysUntil, and persists disabled
// reminder IDs via SharedPreferences.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/family/family_provider.dart';
import '../../../core/services/local_notification_scheduler.dart';

// ── Occasion Type ────────────────────────────────────────────────────

/// The type of occasion being tracked.
enum OccasionType {
  birthday,
  anniversary,
}

// ── Occasion Item ────────────────────────────────────────────────────

/// A single occasion reminder for a family member.
class OccasionItem {
  const OccasionItem({
    required this.personId,
    required this.name,
    this.photoUrl,
    required this.type,
    required this.nextOccurrence,
    required this.daysUntil,
    required this.isReminderEnabled,
  });

  /// The Person ID this occasion belongs to.
  final String personId;

  /// Display name of the person.
  final String name;

  /// Optional photo URL for the person's avatar.
  final String? photoUrl;

  /// The type of occasion (birthday or anniversary).
  final OccasionType type;

  /// The next calendar occurrence of this occasion.
  final DateTime nextOccurrence;

  /// Number of days until the next occurrence.
  final int daysUntil;

  /// Whether the reminder is currently enabled for this occasion.
  final bool isReminderEnabled;

  /// Unique key combining personId and type for SharedPreferences storage.
  String get reminderKey => '${personId}_${type.name}';

  OccasionItem copyWith({
    String? personId,
    String? name,
    String? photoUrl,
    OccasionType? type,
    DateTime? nextOccurrence,
    int? daysUntil,
    bool? isReminderEnabled,
  }) {
    return OccasionItem(
      personId: personId ?? this.personId,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      type: type ?? this.type,
      nextOccurrence: nextOccurrence ?? this.nextOccurrence,
      daysUntil: daysUntil ?? this.daysUntil,
      isReminderEnabled: isReminderEnabled ?? this.isReminderEnabled,
    );
  }
}

// ── Occasion Reminders State ─────────────────────────────────────────

/// State for the occasion reminders feature.
class OccasionRemindersState {
  const OccasionRemindersState({
    this.occasions = const [],
    this.isLoading = false,
    this.error,
  });

  /// All occasions across all families, sorted by daysUntil ascending.
  final List<OccasionItem> occasions;

  /// Whether data is currently being loaded.
  final bool isLoading;

  /// Error message if loading failed, null otherwise.
  final String? error;

  /// Occasions sorted by daysUntil ascending (same as occasions).
  List<OccasionItem> get upcoming => occasions;

  /// Filtered list showing only birthdays.
  List<OccasionItem> get birthdays =>
      occasions.where((o) => o.type == OccasionType.birthday).toList();

  /// Filtered list showing only anniversaries.
  List<OccasionItem> get anniversaries =>
      occasions.where((o) => o.type == OccasionType.anniversary).toList();

  /// Occasions occurring within the next 7 days.
  List<OccasionItem> get withinSevenDays =>
      occasions.where((o) => o.daysUntil <= 7).toList();

  OccasionRemindersState copyWith({
    List<OccasionItem>? occasions,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return OccasionRemindersState(
      occasions: occasions ?? this.occasions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Occasion Reminders Notifier ──────────────────────────────────────

/// AsyncNotifier that manages occasion reminders state.
///
/// Loads all family members across families, computes next occurrences
/// for birthdays and anniversaries, and persists disabled reminder IDs
/// via SharedPreferences.
class OccasionRemindersNotifier extends AsyncNotifier<OccasionRemindersState> {
  static const String _disabledRemindersKey = 'disabled_reminder_ids';

  @override
  OccasionRemindersState build() {
    // Start loading immediately when the provider is first accessed.
    Future.microtask(() => loadOccasions());
    return const OccasionRemindersState(isLoading: true);
  }

  /// Loads all occasions from family members across all families.
  ///
  /// For each Person with a dateOfBirth or anniversaryDate:
  /// 1. Computes the next calendar occurrence
  /// 2. Calculates daysUntil from today
  /// 3. Checks SharedPreferences for disabled reminders
  /// 4. Sorts all occasions by daysUntil ascending
  Future<void> loadOccasions() async {
    state = AsyncData(state.valueOrNull?.copyWith(isLoading: true) ??
        const OccasionRemindersState(isLoading: true));

    try {
      // Get all families
      final familiesAsync = ref.read(familyListProvider);
      final families = familiesAsync.valueOrNull ?? [];

      if (families.isEmpty) {
        state = AsyncData(const OccasionRemindersState());
        return;
      }

      // Load disabled reminder IDs from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final disabledIds = prefs.getStringList(_disabledRemindersKey)?.toSet() ?? <String>{};

      // Collect all occasions from all families
      final List<OccasionItem> allOccasions = [];

      for (final family in families) {
        final membersAsync = ref.read(familyMembersProvider(family.id));
        final members = membersAsync.valueOrNull ?? [];

        for (final person in members) {
          // Birthday occasion
          if (person.dateOfBirth != null && person.dateOfBirth!.isNotEmpty) {
            final dob = DateTime.tryParse(person.dateOfBirth!);
            if (dob != null) {
              final nextOccurrence = _nextOccurrence(dob);
              final daysUntil = _calculateDaysUntil(nextOccurrence);
              final reminderKey = '${person.id}_${OccasionType.birthday.name}';

              allOccasions.add(OccasionItem(
                personId: person.id,
                name: person.name,
                photoUrl: person.photoUrl,
                type: OccasionType.birthday,
                nextOccurrence: nextOccurrence,
                daysUntil: daysUntil,
                isReminderEnabled: !disabledIds.contains(reminderKey),
              ));
            }
          }

          // Anniversary occasion
          final anniversaryDate = _getAnniversaryDate(person);
          if (anniversaryDate != null && anniversaryDate.isNotEmpty) {
            final annDate = DateTime.tryParse(anniversaryDate);
            if (annDate != null) {
              final nextOccurrence = _nextOccurrence(annDate);
              final daysUntil = _calculateDaysUntil(nextOccurrence);
              final reminderKey =
                  '${person.id}_${OccasionType.anniversary.name}';

              allOccasions.add(OccasionItem(
                personId: person.id,
                name: person.name,
                photoUrl: person.photoUrl,
                type: OccasionType.anniversary,
                nextOccurrence: nextOccurrence,
                daysUntil: daysUntil,
                isReminderEnabled: !disabledIds.contains(reminderKey),
              ));
            }
          }
        }
      }

      // Sort by daysUntil ascending (soonest first)
      allOccasions.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));

      state = AsyncData(OccasionRemindersState(
        occasions: allOccasions,
        isLoading: false,
      ));
    } catch (e) {
      debugPrint('⚠️ OccasionRemindersNotifier.loadOccasions error: $e');
      state = AsyncData(OccasionRemindersState(
        isLoading: false,
        error: 'Failed to load occasions. Please try again.',
      ));
    }
  }

  /// Toggle a reminder on/off for a specific person and occasion type.
  ///
  /// When disabling: adds the reminder key to SharedPreferences disabled list
  /// and cancels the local notification.
  ///
  /// When enabling: removes from the disabled list and re-schedules the
  /// local notification.
  Future<void> toggleReminder(String personId, OccasionType type) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    final reminderKey = '${personId}_${type.name}';

    try {
      final prefs = await SharedPreferences.getInstance();
      final disabledIds = prefs.getStringList(_disabledRemindersKey)?.toSet() ?? <String>{};

      // Find the occasion item
      final occasionIndex = currentState.occasions.indexWhere(
        (o) => o.personId == personId && o.type == type,
      );
      if (occasionIndex == -1) return;

      final occasion = currentState.occasions[occasionIndex];
      final wasEnabled = occasion.isReminderEnabled;

      if (wasEnabled) {
        // Disabling: add to disabled list
        disabledIds.add(reminderKey);
        await prefs.setStringList(_disabledRemindersKey, disabledIds.toList());

        // Cancel the local notification
        await _cancelNotification(occasionIndex, type);
      } else {
        // Enabling: remove from disabled list
        disabledIds.remove(reminderKey);
        await prefs.setStringList(_disabledRemindersKey, disabledIds.toList());

        // Re-schedule the local notification
        await _scheduleNotification(occasion);
      }

      // Update state with the toggled reminder
      final updatedOccasions = List<OccasionItem>.from(currentState.occasions);
      updatedOccasions[occasionIndex] = occasion.copyWith(
        isReminderEnabled: !wasEnabled,
      );

      state = AsyncData(currentState.copyWith(
        occasions: updatedOccasions,
      ));
    } catch (e) {
      debugPrint('⚠️ OccasionRemindersNotifier.toggleReminder error: $e');
    }
  }

  // ── Private Helpers ──────────────────────────────────────────────

  /// Computes the next calendar occurrence of a date (month/day).
  ///
  /// If the date has already passed this year, returns next year's date.
  DateTime _nextOccurrence(DateTime date) {
    final now = DateTime.now();
    var next = DateTime(now.year, date.month, date.day);
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year + 1, date.month, date.day);
    }
    return next;
  }

  /// Calculates the number of days from today until the given date.
  int _calculateDaysUntil(DateTime nextOccurrence) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(
      nextOccurrence.year,
      nextOccurrence.month,
      nextOccurrence.day,
    );
    return target.difference(today).inDays;
  }

  /// Extracts the anniversaryDate from a Person object.
  String? _getAnniversaryDate(Person person) {
    return person.anniversaryDate;
  }

  /// Cancels a scheduled notification for an occasion.
  Future<void> _cancelNotification(int index, OccasionType type) async {
    try {
      final int baseId;
      switch (type) {
        case OccasionType.birthday:
          baseId = 6000;
        case OccasionType.anniversary:
          baseId = 6500;
      }
      // Use a stable ID based on the person index
      // The LocalNotificationScheduler uses _idBirthdayBase + index
      final notificationId = baseId + (index % 500);
      await LocalNotificationScheduler.cancelNotification(notificationId);
    } catch (e) {
      debugPrint('⚠️ Failed to cancel notification: $e');
    }
  }

  /// Schedules a local notification for an occasion.
  Future<void> _scheduleNotification(OccasionItem occasion) async {
    try {
      final members = <Map<String, dynamic>>[
        {
          'id': occasion.personId,
          'name': occasion.name,
          'dateOfBirth': occasion.nextOccurrence.toIso8601String(),
        },
      ];

      switch (occasion.type) {
        case OccasionType.birthday:
          await LocalNotificationScheduler.scheduleBirthdayReminders(members);
        case OccasionType.anniversary:
          await LocalNotificationScheduler.scheduleAnniversaryReminders(
            <Map<String, dynamic>>[
              {
                'names': occasion.name,
                'date': occasion.nextOccurrence.toIso8601String(),
                'familyName': '',
              },
            ],
          );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to schedule notification: $e');
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────

/// Provider that manages occasion reminders state.
///
/// ```dart
/// final state = ref.watch(occasionRemindersProvider);
/// state.when(
///   data: (data) => /* show occasions */,
///   loading: () => /* show shimmer */,
///   error: (e, st) => /* show error */,
/// );
/// ```
final occasionRemindersProvider =
    AsyncNotifierProvider<OccasionRemindersNotifier, OccasionRemindersState>(
  OccasionRemindersNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════
// FAMILY-SCOPED OCCASIONS PROVIDER
// ═══════════════════════════════════════════════════════════════════════
//
// Computes occasions for a single family (not global). Reuses the same
// per-person birthday/anniversary calculation logic from the global
// notifier. Used by the Family Calendar card + screen in Family Space.

/// Computes occasions for a single family, keyed by familyId.
/// Returns a sorted list of OccasionItem (birthdays + anniversaries).
final familyOccasionsProvider =
    Provider.autoDispose.family<List<OccasionItem>, String>(
  (ref, familyId) {
    final membersAsync = ref.watch(familyMembersProvider(familyId));
    final members = membersAsync.valueOrNull ?? [];

    // Load disabled reminder IDs synchronously from the global state
    // (the global notifier already tracks this in SharedPreferences)
    final globalState = ref.watch(occasionRemindersProvider).valueOrNull;
    final disabledIds = <String>{};
    // We can't await SharedPreferences in a sync provider, so we
    // rely on the global notifier having loaded them. If the global
    // state hasn't loaded yet, reminders default to enabled — the
    // toggle still works via the global notifier.
    if (globalState != null) {
      for (final occasion in globalState.occasions) {
        if (!occasion.isReminderEnabled) {
          disabledIds.add(occasion.reminderKey);
        }
      }
    }

    final occasions = <OccasionItem>[];

    for (final person in members) {
      // Birthday
      if (person.dateOfBirth != null && person.dateOfBirth!.isNotEmpty) {
        final dob = DateTime.tryParse(person.dateOfBirth!);
        if (dob != null) {
          final next = _computeNextOccurrence(dob);
          final days = _computeDaysUntil(next);
          final key = '${person.id}_${OccasionType.birthday.name}';
          occasions.add(OccasionItem(
            personId: person.id,
            name: person.name,
            photoUrl: person.photoUrl,
            type: OccasionType.birthday,
            nextOccurrence: next,
            daysUntil: days,
            isReminderEnabled: !disabledIds.contains(key),
          ));
        }
      }

      // Anniversary
      final anniv = person.anniversaryDate;
      if (anniv != null && anniv.isNotEmpty) {
        final annivDate = DateTime.tryParse(anniv);
        if (annivDate != null) {
          final next = _computeNextOccurrence(annivDate);
          final days = _computeDaysUntil(next);
          final key = '${person.id}_${OccasionType.anniversary.name}';
          occasions.add(OccasionItem(
            personId: person.id,
            name: person.name,
            photoUrl: person.photoUrl,
            type: OccasionType.anniversary,
            nextOccurrence: next,
            daysUntil: days,
            isReminderEnabled: !disabledIds.contains(key),
          ));
        }
      }
    }

    occasions.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
    return occasions;
  },
);

// ── Shared helper functions (extracted from the notifier's private
//    methods so both the global notifier and familyOccasionsProvider
//    can use the same calculation logic) ──────────────────────────

DateTime _computeNextOccurrence(DateTime date) {
  final now = DateTime.now();
  var next = DateTime(now.year, date.month, date.day);
  if (next.isBefore(DateTime(now.year, now.month, now.day))) {
    next = DateTime(now.year + 1, date.month, date.day);
  }
  return next;
}

int _computeDaysUntil(DateTime nextOccurrence) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(
    nextOccurrence.year,
    nextOccurrence.month,
    nextOccurrence.day,
  );
  return target.difference(today).inDays;
}
