// lib/features/smart_calendar/presentation/smart_calendar_screen.dart
//
// DAXELO KINREL — Smart Calendar & Auto-Reminders Screen
//
// Orange K-Graph DNA design:
//   • Header: "Smart Calendar" with panchang icon in orange
//   • View toggle: Month | Week | Day
//   • Panchang toggle: Show/hide panchang overlay
//   • Custom calendar grid with panchang day names
//   • Date cells with color-coded event dots
//   • Week view: 7-column timeline
//   • Day view: Full day timeline
//   • Panchang panel: slides up with full panchang info
//   • Events list below calendar for selected date
//   • Festival notification banner
//   • Reminders section
//   • Auspicious date finder
//   • FAB: Create new event/reminder
//
// Design colors:
//   Background:  #131416 (darkBackground)
//   Cards:       #191B2C (darkCard)
//   Primary:     #F5F0EE (textWhite)
//   Secondary:   #C9B4A8 (textSilver)
//   Accent:      #E8612A (orange)
//   Panchang:    orange/amber accents
//   Festival:    gold (#D4AF37)
//   Auspicious:  green (#4CAF7A)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/smart_calendar_provider.dart';
import '../../../core/utils/device_tier.dart';

// ── Color shortcuts ──────────────────────────────────────────────────
const _cOrange = KinrelColors.orange;
const _cAmber = KinrelColors.amber;
const _cGold = KinrelColors.gold;
const _cBg = KinrelColors.darkBackground;
const _cCard = KinrelColors.darkCard;
const _cElevated = KinrelColors.darkElevated;
const _cTextPrimary = KinrelColors.textWhite;
const _cTextSecondary = KinrelColors.textSilver;
const _cTextDim = KinrelColors.textDim;
const _cBorder = Color(0xFF3A3A4A);

// ═══════════════════════════════════════════════════════════════════════
// Smart Calendar Screen
// ═══════════════════════════════════════════════════════════════════════

class SmartCalendarScreen extends ConsumerStatefulWidget {
  const SmartCalendarScreen({super.key});

  @override
  ConsumerState<SmartCalendarScreen> createState() =>
      _SmartCalendarScreenState();
}

class _SmartCalendarScreenState extends ConsumerState<SmartCalendarScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = DateTime.now();
      ref
          .read(smartCalendarProvider.notifier)
          .loadFestivalsForMonth(now.year, now.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final calendarState = ref.watch(smartCalendarProvider);

    return DKScaffold(
      backgroundColor: _cBg,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────
          _CalendarHeader()
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: -0.05, end: 0),

          // ── View Toggle + Panchang Toggle ─────────────────────────
          _ViewAndPanchangToggle().animate().fadeIn(
            duration: 300.ms,
            delay: 50.ms,
          ),

          const SizedBox(height: 8),

          // ── Festival Notification Banner ──────────────────────────
          if (calendarState.upcomingFestivalEvents.isNotEmpty)
            _FestivalBanner(
              festivals: calendarState.upcomingFestivalEvents,
            ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.04, end: 0),

          // ── Reminders Bar ────────────────────────────────────────
          if (calendarState.activeReminders.isNotEmpty)
            _RemindersBar(
              reminders: calendarState.activeReminders.take(3).toList(),
            ).animate().fadeIn(duration: 350.ms),

          // ── Content based on view mode ───────────────────────────
          Expanded(child: _buildCalendarContent(calendarState)),
        ],
      ),
      // ── FAB: Create New Event/Reminder ──────────────────────────
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: KinrelGradients.igniteGradient,
          boxShadow: [
            BoxShadow(
              color: _cOrange.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showCreateEventSheet(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          label: Text(
            'New Event',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarContent(SmartCalendarState calendarState) {
    switch (calendarState.viewMode) {
      case CalendarView.month:
        return _MonthViewContent(calendarState: calendarState);
      case CalendarView.week:
        return _WeekView(calendarState: calendarState);
      case CalendarView.day:
        return _DayView(calendarState: calendarState);
    }
  }

  void _showCreateEventSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => const _CreateEventSheet(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Month View Content (existing grid + panchang + events)
// ═══════════════════════════════════════════════════════════════════════

class _MonthViewContent extends StatelessWidget {
  const _MonthViewContent({required this.calendarState});
  final SmartCalendarState calendarState;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Month Navigation ──────────────────────────────────────
        _MonthNavigation(),
        const SizedBox(height: 4),

        // ── Calendar Grid ─────────────────────────────────────────
        _CalendarGrid(),
        const SizedBox(height: 8),

        // ── Panchang Panel (animated) ─────────────────────────────
        AnimatedSize(
          duration: KinrelMotion.normal,
          curve: KinrelMotion.easeOut,
          alignment: Alignment.topCenter,
          child:
              calendarState.showPanchang &&
                  calendarState.panchangForSelectedDate != null
              ? _PanchangPanel(
                  panchang: calendarState.panchangForSelectedDate!,
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08, end: 0)
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 8),

        // ── Events List ───────────────────────────────────────────
        Expanded(
          child: _EventsForDateList(
            events: calendarState.eventsForSelectedDate,
            selectedDate: calendarState.effectiveSelectedDate,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Week View
// ═══════════════════════════════════════════════════════════════════════

class _WeekView extends StatelessWidget {
  const _WeekView({required this.calendarState});
  final SmartCalendarState calendarState;

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final selected = calendarState.effectiveSelectedDate;
    final today = DateTime.now();
    // Find the Sunday of the week containing the selected date
    final startOfWeek = selected.subtract(Duration(days: selected.weekday % 7));

    return Column(
      children: [
        // ── Week navigation ─────────────────────────────────────
        Consumer(
          builder: (context, ref, _) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      final prev = startOfWeek.subtract(
                        const Duration(days: 7),
                      );
                      ref
                          .read(smartCalendarProvider.notifier)
                          .selectDate(prev.add(const Duration(days: 3)));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.sm),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: _cTextSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                  Text(
                    '${_monthNames[startOfWeek.month]} ${startOfWeek.day} – ${_monthNames[startOfWeek.add(const Duration(days: 6)).month]} ${startOfWeek.add(const Duration(days: 6)).day}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _cTextPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      final next = startOfWeek.add(const Duration(days: 7));
                      ref
                          .read(smartCalendarProvider.notifier)
                          .selectDate(next.add(const Duration(days: 3)));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.sm),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: _cTextSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 4),

        // ── Day headers row ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
          child: Row(
            children: List.generate(7, (i) {
              final date = startOfWeek.add(Duration(days: i));
              final isToday =
                  date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              final isSelected =
                  date.year == selected.year &&
                  date.month == selected.month &&
                  date.day == selected.day;
              final panchang = HinduPanchangService.getPanchang(date);

              return Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    return GestureDetector(
                      onTap: () => ref
                          .read(smartCalendarProvider.notifier)
                          .selectDate(date),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _cOrange.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                          border: isSelected
                              ? Border.all(
                                  color: _cOrange.withValues(alpha: 0.3),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(
                              _dayLabels[i],
                              style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: _cTextDim,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isSelected
                                    ? KinrelGradients.igniteGradient
                                    : null,
                                color: isToday && !isSelected
                                    ? _cOrange.withValues(alpha: 0.15)
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 12,
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? Colors.white
                                      : isToday
                                      ? _cOrange
                                      : _cTextPrimary,
                                ),
                              ),
                            ),
                            if (calendarState.showPanchang)
                              Text(
                                panchang.tithiSymbol,
                                style: TextStyle(
                                  fontSize: 7,
                                  color: _cAmber.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 6),

        // ── Time grid ──────────────────────────────────────────────
        Expanded(
          child: _WeekTimeGrid(
            startOfWeek: startOfWeek,
            events: calendarState.events,
            showPanchang: calendarState.showPanchang,
          ),
        ),
      ],
    );
  }
}

// ── Week Time Grid ────────────────────────────────────────────────────

class _WeekTimeGrid extends StatelessWidget {
  const _WeekTimeGrid({
    required this.startOfWeek,
    required this.events,
    required this.showPanchang,
  });

  final DateTime startOfWeek;
  final List<SmartCalendarEvent> events;
  final bool showPanchang;

  static const int _startHour = 6;
  static const int _endHour = 22;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentHour = now.hour;

    return SingleChildScrollView(
      child: Column(
        children: List.generate(_endHour - _startHour, (hourIndex) {
          final hour = _startHour + hourIndex;
          final isCurrentHour =
              now.year == startOfWeek.year &&
              now.month == startOfWeek.month &&
              now.day == startOfWeek.day &&
              hour == currentHour;

          return IntrinsicHeight(
            child: Row(
              children: [
                // Time label
                SizedBox(
                  width: 44,
                  child: Text(
                    hour == 0
                        ? '12 AM'
                        : hour < 12
                        ? '$hour AM'
                        : hour == 12
                        ? '12 PM'
                        : '${hour - 12} PM',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: _cTextDim,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 4),

                // Day columns
                Expanded(
                  child: Row(
                    children: List.generate(7, (dayIndex) {
                      final date = startOfWeek.add(Duration(days: dayIndex));
                      final dayEvents = events
                          .where((e) => e.isOnDate(date))
                          .where(
                            (e) =>
                                e.startTime != null &&
                                e.startTime! <= hour &&
                                (e.endTime ?? (e.startTime! + 1)) > hour,
                          )
                          .toList();

                      return Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _cBorder.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                              right: BorderSide(
                                color: _cBorder.withValues(alpha: 0.15),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              // Current time indicator
                              if (isCurrentHour)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: (now.minute / 60 * 48).clamp(0, 44),
                                  child: Container(height: 2, color: _cOrange),
                                ),
                              // Events
                              ...dayEvents.map(
                                (event) => Positioned(
                                  left: 1,
                                  right: 1,
                                  top: 2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: event.color.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(
                                        color: event.color.withValues(
                                          alpha: 0.3,
                                        ),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      event.title,
                                      style: TextStyle(
                                        fontFamily: KinrelTypography.bodyFont,
                                        fontSize: 7,
                                        fontWeight: FontWeight.w500,
                                        color: event.color,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Day View
// ═══════════════════════════════════════════════════════════════════════

class _DayView extends StatelessWidget {
  const _DayView({required this.calendarState});
  final SmartCalendarState calendarState;

  static const _monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final selected = calendarState.effectiveSelectedDate;
    final dayEvents = calendarState.eventsForSelectedDate;
    final panchang = calendarState.panchangForSelectedDate;

    return Column(
      children: [
        // ── Day navigation ───────────────────────────────────────
        Consumer(
          builder: (context, ref, _) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base,
                vertical: 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => ref
                        .read(smartCalendarProvider.notifier)
                        .selectDate(selected.subtract(const Duration(days: 1))),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.sm),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: _cTextSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        _dayNames[selected.weekday - 1],
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _cTextPrimary,
                        ),
                      ),
                      Text(
                        '${_monthNames[selected.month]} ${selected.day}, ${selected.year}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _cTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => ref
                        .read(smartCalendarProvider.notifier)
                        .selectDate(selected.add(const Duration(days: 1))),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.sm),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: _cTextSecondary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // ── Compact Panchang Panel ────────────────────────────────
        if (calendarState.showPanchang && panchang != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.base,
              vertical: 4,
            ),
            child: _DayPanchangBar(panchang: panchang),
          ),

        // ── Day Timeline ─────────────────────────────────────────
        Expanded(
          child: _DayTimeline(selectedDate: selected, events: dayEvents),
        ),
      ],
    );
  }
}

// ── Compact Panchang Bar for Day View ─────────────────────────────────

class _DayPanchangBar extends StatelessWidget {
  const _DayPanchangBar({required this.panchang});
  final PanchangModel panchang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: _cOrange.withValues(alpha: 0.12), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: _cOrange),
          const SizedBox(width: 6),
          Text(
            '${panchang.tithi} · ${panchang.nakshatra} · ${panchang.yoga}',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: _cTextSecondary,
            ),
          ),
          const Spacer(),
          _AuspiciousBadge(isAuspicious: panchang.isAuspicious),
        ],
      ),
    );
  }
}

// ── Day Timeline ─────────────────────────────────────────────────────

class _DayTimeline extends StatelessWidget {
  const _DayTimeline({required this.selectedDate, required this.events});

  final DateTime selectedDate;
  final List<SmartCalendarEvent> events;

  static const int _startHour = 6;
  static const int _endHour = 22;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80),
      child: Column(
        children: List.generate(_endHour - _startHour, (hourIndex) {
          final hour = _startHour + hourIndex;
          final isCurrentHour = isToday && hour == now.hour;

          // Events at this hour
          final hourEvents = events
              .where(
                (e) =>
                    e.startTime != null &&
                    e.startTime! <= hour &&
                    (e.endTime ?? (e.startTime! + 1)) > hour,
              )
              .toList();

          // Events without specific time (all-day)
          final allDayEvents = events
              .where((e) => e.startTime == null)
              .toList();

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time label
                SizedBox(
                  width: 52,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      hour == 0
                          ? '12 AM'
                          : hour < 12
                          ? '$hour AM'
                          : hour == 12
                          ? '12 PM'
                          : '${hour - 12} PM',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: isCurrentHour ? _cOrange : _cTextDim,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Timeline line + events
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Current time indicator
                      if (isCurrentHour)
                        Padding(
                          padding: EdgeInsets.only(
                            top: (now.minute / 60 * 48).clamp(0, 44),
                          ),
                          child: Row(
                            children: [
                              Container(width: 8, height: 2, color: _cOrange),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _cOrange,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Hour events
                      if (hourEvents.isNotEmpty)
                        ...hourEvents.map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _DayEventCard(event: event),
                          ),
                        ),

                      // All-day events at 6 AM
                      if (hour == _startHour && allDayEvents.isNotEmpty)
                        ...allDayEvents.map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _DayEventCard(event: event),
                          ),
                        ),

                      // Hour separator
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _cBorder.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ── Day Event Card ────────────────────────────────────────────────────

class _DayEventCard extends StatelessWidget {
  const _DayEventCard({required this.event});
  final SmartCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: event.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: event.color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: event.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _cTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.startTime != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.formattedTime,
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      color: _cTextDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(event.icon, size: 16, color: event.color),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Festival Notification Banner
// ═══════════════════════════════════════════════════════════════════════

class _FestivalBanner extends StatelessWidget {
  const _FestivalBanner({required this.festivals});
  final List<SmartCalendarEvent> festivals;

  static const _monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final festival = festivals.first;
    final daysUntil = festival.date.difference(DateTime.now()).inDays;
    final daysText = daysUntil <= 0
        ? 'Today!'
        : daysUntil == 1
        ? 'Tomorrow'
        : 'In $daysUntil days';

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: KinrelGradients.shareCardGradient,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        boxShadow: [
          BoxShadow(
            color: _cGold.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration_rounded, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  festival.title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$daysText · ${festival.date.day} ${_monthNames[festival.date.month]}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          // Send greetings button
          GestureDetector(
            onTap: () {
              // TODO: Link to festival cards feature
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(KinrelRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.send_rounded, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'Greet',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Reminders Bar
// ═══════════════════════════════════════════════════════════════════════

class _RemindersBar extends StatelessWidget {
  const _RemindersBar({required this.reminders});
  final List<PendingReminder> reminders;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KinrelColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: KinrelColors.info.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_rounded,
            size: 14,
            color: KinrelColors.info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reminders.map((r) => r.eventTitle).take(2).join(' · '),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: KinrelColors.info,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: KinrelColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KinrelRadius.full),
            ),
            child: Text(
              '${reminders.length}',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: KinrelColors.info,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header: "Smart Calendar" with panchang icon
// ═══════════════════════════════════════════════════════════════════════

class _CalendarHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        16,
        KinrelSpacing.base,
        8,
      ),
      decoration: BoxDecoration(
        color: _cBg,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Panchang icon in orange
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _cOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
            child: const Icon(
              Icons.temple_buddhist_rounded,
              color: _cOrange,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Calendar',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Panchang & Family Events',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _cTextDim,
                  ),
                ),
              ],
            ),
          ),
          // Auspicious Finder button
          Consumer(
            builder: (context, ref, _) {
              return GestureDetector(
                onTap: () => _showAuspiciousFinder(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(
                      color: _cGold.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_rounded, size: 14, color: _cGold),
                      const SizedBox(width: 4),
                      Text(
                        'Shubh',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _cGold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          // Today button
          Consumer(
            builder: (context, ref, _) {
              return GestureDetector(
                onTap: () =>
                    ref.read(smartCalendarProvider.notifier).goToToday(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(color: _cBorder, width: 1),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _cOrange,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAuspiciousFinder(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => const _AuspiciousDateFinderSheet(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// View Toggle + Panchang Toggle
// ═══════════════════════════════════════════════════════════════════════

class _ViewAndPanchangToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        children: [
          // View toggle
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
                final viewMode = ref.watch(smartCalendarProvider).viewMode;
                return Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: _cCard,
                    borderRadius: BorderRadius.circular(KinrelRadius.lg),
                    border: Border.all(color: _cBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      _viewTab('Month', CalendarView.month, viewMode, ref),
                      _viewTab('Week', CalendarView.week, viewMode, ref),
                      _viewTab('Day', CalendarView.day, viewMode, ref),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          // Panchang toggle
          Consumer(
            builder: (context, ref, _) {
              final showPanchang = ref
                  .watch(smartCalendarProvider)
                  .showPanchang;
              return GestureDetector(
                onTap: () =>
                    ref.read(smartCalendarProvider.notifier).togglePanchang(),
                child: AnimatedContainer(
                  duration: KinrelMotion.fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: showPanchang
                        ? KinrelGradients.igniteGradient
                        : null,
                    color: showPanchang ? null : _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: showPanchang
                        ? null
                        : Border.all(color: _cBorder, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: showPanchang ? Colors.white : _cAmber,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Panchang',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: showPanchang ? Colors.white : _cTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _viewTab(
    String label,
    CalendarView view,
    CalendarView currentView,
    WidgetRef ref,
  ) {
    final isActive = currentView == view;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(smartCalendarProvider.notifier).toggleView(view),
        child: AnimatedContainer(
          duration: KinrelMotion.fast,
          curve: KinrelMotion.easeOut,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: isActive ? KinrelGradients.igniteGradient : null,
            color: isActive ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(KinrelRadius.md),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? Colors.white : _cTextDim,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Month Navigation
// ═══════════════════════════════════════════════════════════════════════

class _MonthNavigation extends StatelessWidget {
  static const _monthNames = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final selectedDate = ref
            .watch(smartCalendarProvider)
            .effectiveSelectedDate;
        final notifier = ref.read(smartCalendarProvider.notifier);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => notifier.previousMonth(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    color: _cTextSecondary,
                    size: 20,
                  ),
                ),
              ),
              Text(
                '${_monthNames[selectedDate.month]} ${selectedDate.year}',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              GestureDetector(
                onTap: () => notifier.nextMonth(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: _cTextSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Calendar Grid
// ═══════════════════════════════════════════════════════════════════════

class _CalendarGrid extends StatelessWidget {
  static const _dayHeaders = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _panchangDayNames = [
    'Ravi',
    'Soma',
    'Mangal',
    'Budh',
    'Guru',
    'Shukra',
    'Shani',
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(smartCalendarProvider);
        final selectedDate = state.effectiveSelectedDate;
        final events = state.events;
        final showPanchang = state.showPanchang;
        final today = DateTime.now();

        final firstOfMonth = DateTime(selectedDate.year, selectedDate.month, 1);
        final daysInMonth = DateTime(
          selectedDate.year,
          selectedDate.month + 1,
          0,
        ).day;
        final startWeekday = firstOfMonth.weekday % 7; // Sunday = 0

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: List.generate(7, (i) {
                  return Expanded(
                    child: Column(
                      children: [
                        Text(
                          _dayHeaders[i],
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: i == 0
                                ? _cOrange.withValues(alpha: 0.8)
                                : _cTextDim,
                          ),
                        ),
                        if (showPanchang)
                          Text(
                            _panchangDayNames[i],
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 8,
                              fontWeight: FontWeight.w400,
                              color: _cOrange.withValues(alpha: 0.5),
                              letterSpacing: 0.5,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 6),

              Wrap(
                children: List.generate(startWeekday + daysInMonth, (index) {
                  if (index < startWeekday) {
                    return const _EmptyDateCell();
                  }
                  final day = index - startWeekday + 1;
                  final date = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    day,
                  );
                  final isToday =
                      date.year == today.year &&
                      date.month == today.month &&
                      date.day == today.day;
                  final isSelected =
                      date.year == selectedDate.year &&
                      date.month == selectedDate.month &&
                      date.day == selectedDate.day;
                  final dayEvents = events
                      .where(
                        (e) =>
                            e.date.year == date.year &&
                            e.date.month == date.month &&
                            e.date.day == date.day,
                      )
                      .toList();

                  return _DateCell(
                    date: date,
                    day: day,
                    isToday: isToday,
                    isSelected: isSelected,
                    events: dayEvents,
                    showPanchang: showPanchang,
                    onTap: () => ref
                        .read(smartCalendarProvider.notifier)
                        .selectDate(date),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Empty Date Cell ───────────────────────────────────────────────────

class _EmptyDateCell extends StatelessWidget {
  const _EmptyDateCell();

  static const double _cellSize = 48.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - KinrelSpacing.sm * 2) / 7,
      height: _cellSize,
    );
  }
}

// ── Date Cell ─────────────────────────────────────────────────────────

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.events,
    required this.showPanchang,
    required this.onTap,
  });

  final DateTime date;
  final int day;
  final bool isToday;
  final bool isSelected;
  final List<SmartCalendarEvent> events;
  final bool showPanchang;
  final VoidCallback onTap;

  static const double _cellSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final cellWidth =
        (MediaQuery.of(context).size.width - KinrelSpacing.sm * 2) / 7;

    String? tithiSymbol;
    if (showPanchang) {
      final panchang = HinduPanchangService.getPanchang(date);
      tithiSymbol = panchang.tithiSymbol;
    }

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: cellWidth,
        height: _cellSize,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected ? KinrelGradients.igniteGradient : null,
                color: isToday && !isSelected
                    ? _cOrange.withValues(alpha: 0.15)
                    : null,
                border: isToday && !isSelected
                    ? Border.all(color: _cOrange, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: isSelected
                      ? Colors.white
                      : isToday
                      ? _cOrange
                      : _cTextPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            if (events.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: events.take(3).map((e) {
                  return Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.color,
                    ),
                  );
                }).toList(),
              )
            else if (showPanchang && tithiSymbol != null)
              Text(
                tithiSymbol,
                style: TextStyle(
                  fontSize: 8,
                  color: _cAmber.withValues(alpha: 0.6),
                ),
              )
            else
              const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Panchang Panel
// ═══════════════════════════════════════════════════════════════════════

class _PanchangPanel extends StatelessWidget {
  const _PanchangPanel({required this.panchang});

  final PanchangModel panchang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: _cOrange.withValues(alpha: 0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: _cOrange.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _cOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: _cOrange,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Panchang — ${panchang.vaar}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _cTextPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                _AuspiciousBadge(isAuspicious: panchang.isAuspicious),
              ],
            ),

            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: [
                _PanchangInfoChip(
                  label: 'Tithi',
                  value: panchang.tithi,
                  icon: Icons.nights_stay_rounded,
                  color: _cAmber,
                ),
                _PanchangInfoChip(
                  label: 'Nakshatra',
                  value: panchang.nakshatra,
                  icon: Icons.star_rounded,
                  color: _cGold,
                ),
                _PanchangInfoChip(
                  label: 'Yoga',
                  value: panchang.yoga,
                  icon: Icons.self_improvement_rounded,
                  color: _cOrange,
                ),
                _PanchangInfoChip(
                  label: 'Karana',
                  value: panchang.karana,
                  icon: Icons.hourglass_top_rounded,
                  color: _cAmber,
                ),
                _PanchangInfoChip(
                  label: 'Paksha',
                  value: panchang.paksha,
                  icon: Icons.brightness_2_rounded,
                  color: panchang.paksha == 'Shukla'
                      ? KinrelColors.info
                      : _cOrange,
                ),
                _PanchangInfoChip(
                  label: 'Rashi',
                  value: panchang.rashi,
                  icon: Icons.auto_awesome_rounded,
                  color: _cGold,
                ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                _MiniInfo(label: 'Masa', value: panchang.masa),
                const SizedBox(width: 16),
                _MiniInfo(label: 'Ayana', value: panchang.ayana),
                const SizedBox(width: 16),
                _MiniInfo(label: 'Ritu', value: panchang.ritu),
              ],
            ),

            const SizedBox(height: 14),

            // Inauspicious Times
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.block_rounded,
                        size: 14,
                        color: KinrelColors.error.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Inauspicious Periods',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.error.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _TimeRow(
                    label: 'Rahu Kaal',
                    start: panchang.rahukaalStart,
                    end: panchang.rahukaalEnd,
                    color: KinrelColors.error,
                  ),
                  const SizedBox(height: 4),
                  _TimeRow(
                    label: 'Gulika',
                    start: panchang.gulikaStart,
                    end: panchang.gulikaEnd,
                    color: _cAmber,
                  ),
                  const SizedBox(height: 4),
                  _TimeRow(
                    label: 'Yamaghanta',
                    start: panchang.yamaghantaStart,
                    end: panchang.yamaghantaEnd,
                    color: _cOrange,
                  ),
                ],
              ),
            ),

            // Auspicious Time
            if (panchang.auspiciousTimeStart != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KinrelColors.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(
                    color: KinrelColors.success.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: KinrelColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Shubh Muhurat: ${panchang.auspiciousTimeStart} — ${panchang.auspiciousTimeEnd}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Festivals
            if (panchang.festivals.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...panchang.festivals.map(
                (festival) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.shareCardGradient,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.celebration_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          festival,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Auspicious Badge ──────────────────────────────────────────────────

class _AuspiciousBadge extends StatelessWidget {
  const _AuspiciousBadge({required this.isAuspicious});

  final bool isAuspicious;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAuspicious
            ? KinrelColors.success.withValues(alpha: 0.12)
            : KinrelColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAuspicious ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 11,
            color: isAuspicious
                ? KinrelColors.success
                : KinrelColors.error.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 4),
          Text(
            isAuspicious ? 'Shubh' : 'Ashubh',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isAuspicious
                  ? KinrelColors.success
                  : KinrelColors.error.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Panchang Info Chip ────────────────────────────────────────────────

class _PanchangInfoChip extends StatelessWidget {
  const _PanchangInfoChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.12), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: 0.7),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 140),
            child: Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _cTextPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini Info ─────────────────────────────────────────────────────────

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: _cTextDim,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _cTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Time Row ──────────────────────────────────────────────────────────

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.start,
    required this.end,
    required this.color,
  });

  final String label;
  final String? start;
  final String? end;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (start == null || end == null) return const SizedBox.shrink();

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ),
        Text(
          '$start — $end',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _cTextSecondary,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Events List for Selected Date
// ═══════════════════════════════════════════════════════════════════════

class _EventsForDateList extends StatelessWidget {
  const _EventsForDateList({required this.events, required this.selectedDate});

  final List<SmartCalendarEvent> events;
  final DateTime selectedDate;

  static const _monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            children: [
              Text(
                '${selectedDate.day} ${_monthNames[selectedDate.month]}',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${events.length} event${events.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: _cTextDim,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: events.isEmpty
              ? _EmptyEventsState(selectedDate: selectedDate)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    KinrelSpacing.base,
                    0,
                    KinrelSpacing.base,
                    100,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _EventCard(event: events[index])
                        .animate()
                        .fadeIn(
                          duration: 350.ms,
                          delay: Duration(milliseconds: index * 60),
                        )
                        .slideY(begin: 0.06, end: 0);
                  },
                ),
        ),
      ],
    );
  }
}

// ── Empty Events State ────────────────────────────────────────────────

class _EmptyEventsState extends StatelessWidget {
  const _EmptyEventsState({required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _cOrange.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_available_rounded,
                size: 40,
                color: _cOrange.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No events',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap + to add an event or reminder for this day.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _cTextDim,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Event Card ────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final SmartCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final accentColor = event.color;
    final isPanchangFestival = event.type == CalendarEventType.panchangFestival;
    return GestureDetector(
      onTap: () => _showEventDetail(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: isPanchangFestival
                ? _cGold.withValues(alpha: 0.2)
                : accentColor.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: isPanchangFestival
              ? [
                  BoxShadow(
                    color: _cGold.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: isPanchangFestival
                    ? KinrelGradients.shareCardGradient
                    : null,
                color: isPanchangFestival
                    ? null
                    : accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              alignment: Alignment.center,
              child: Icon(
                event.icon,
                size: 20,
                color: isPanchangFestival ? Colors.white : accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _cTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (event.startTime != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          event.formattedTime,
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: accentColor,
                          ),
                        ),
                      ],
                      if (event.isAutoGenerated) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              KinrelRadius.xs,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 9,
                                color: accentColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Auto',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.monoFont,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w500,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (event.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.description!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: _cTextDim,
                        height: 1.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (event.reminderTimings.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.notifications_active_rounded,
                size: 16,
                color: accentColor.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showEventDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => _EventDetailSheet(event: event),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Event Detail Sheet
// ═══════════════════════════════════════════════════════════════════════

class _EventDetailSheet extends StatelessWidget {
  const _EventDetailSheet({required this.event});

  final SmartCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final accentColor = event.color;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _cBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: event.type == CalendarEventType.panchangFestival
                          ? KinrelGradients.shareCardGradient
                          : null,
                      color: event.type == CalendarEventType.panchangFestival
                          ? null
                          : accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(KinrelRadius.lg),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      event.icon,
                      size: 24,
                      color: event.type == CalendarEventType.panchangFestival
                          ? Colors.white
                          : accentColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      event.title,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _cTextPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: _cTextDim),
                  const SizedBox(width: 8),
                  Text(
                    '${event.formattedDate}${event.startTime != null ? " · ${event.formattedTime}" : ""}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: _cTextSecondary,
                    ),
                  ),
                ],
              ),

              if (event.location != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 16, color: _cTextDim),
                    const SizedBox(width: 8),
                    Text(
                      event.location!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _cTextSecondary,
                      ),
                    ),
                  ],
                ),
              ],

              if (event.description != null) ...[
                const SizedBox(height: 12),
                Text(
                  event.description!,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: _cTextSecondary,
                    height: 1.6,
                  ),
                ),
              ],

              if (event.panchangInfo != null) ...[const SizedBox(height: 16)],
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Enhanced Create Event Sheet
// ═══════════════════════════════════════════════════════════════════════

class _CreateEventSheet extends ConsumerStatefulWidget {
  const _CreateEventSheet();

  @override
  ConsumerState<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends ConsumerState<_CreateEventSheet> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  CalendarEventType _selectedType = CalendarEventType.custom;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  final Set<ReminderTiming> _selectedReminders = {
    ReminderTiming.oneDayBefore,
    ReminderTiming.morningOf,
  };
  bool _isPanchangChecked = false;
  bool? _isDateAuspicious;

  @override
  void initState() {
    super.initState();
    _checkAuspicious();
  }

  void _checkAuspicious() {
    final panchang = HinduPanchangService.getPanchang(_selectedDate);
    setState(() {
      _isDateAuspicious = panchang.isAuspicious;
      _isPanchangChecked = true;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(KinrelSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _cBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  'Create Event',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                  ),
                ),
                const SizedBox(height: 20),

                // Event Title Input
                _buildInputField(
                  controller: _titleController,
                  hint: 'Event title',
                  icon: Icons.edit_rounded,
                ),
                const SizedBox(height: 12),

                // Event Type Selector
                Text(
                  'Event Type',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _cTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: CalendarEventType.values
                      .where(
                        (t) =>
                            t != CalendarEventType.panchangFestival &&
                            t != CalendarEventType.panchangAuspicious,
                      )
                      .map((type) {
                        final isSelected = _selectedType == type;
                        final color = _getTypeColor(type);
                        return GestureDetector(
                          onTap: () => setState(() => _selectedType = type),
                          child: AnimatedContainer(
                            duration: KinrelMotion.fast,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color.withValues(alpha: 0.15)
                                  : _cElevated,
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.md,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? color.withValues(alpha: 0.4)
                                    : _cBorder,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getTypeIcon(type),
                                  size: 14,
                                  color: isSelected ? color : _cTextDim,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _getTypeLabel(type),
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected ? color : _cTextDim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
                const SizedBox(height: 16),

                // Date Picker
                _buildDateRow(),
                const SizedBox(height: 12),

                // Time Picker
                _buildTimeRow(),
                const SizedBox(height: 12),

                // Location Input
                _buildInputField(
                  controller: _locationController,
                  hint: 'Location (optional)',
                  icon: Icons.location_on_rounded,
                ),
                const SizedBox(height: 16),

                // Reminder Timing Multi-select
                Text(
                  'Reminders',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _cTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _reminderChip('1 Week', ReminderTiming.oneWeekBefore),
                    _reminderChip('3 Days', ReminderTiming.threeDaysBefore),
                    _reminderChip('1 Day', ReminderTiming.oneDayBefore),
                    _reminderChip('Morning', ReminderTiming.morningOf),
                  ],
                ),
                const SizedBox(height: 16),

                // Panchang-aware auspicious indicator
                if (_isPanchangChecked && _isDateAuspicious != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isDateAuspicious!
                          ? KinrelColors.success.withValues(alpha: 0.06)
                          : KinrelColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: Border.all(
                        color: _isDateAuspicious!
                            ? KinrelColors.success.withValues(alpha: 0.15)
                            : KinrelColors.error.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isDateAuspicious!
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: _isDateAuspicious!
                              ? KinrelColors.success
                              : KinrelColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isDateAuspicious!
                                ? 'This date is Shubh (auspicious) according to Panchang'
                                : 'This date is not marked as auspicious. Consider checking for better dates.',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: _isDateAuspicious!
                                  ? KinrelColors.success
                                  : KinrelColors.error.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // Save Button
                GestureDetector(
                  onTap: _saveEvent,
                  child: Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: KinrelGradients.igniteGradient,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      boxShadow: [
                        BoxShadow(
                          color: _cOrange.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Save Event',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: _cBorder, width: 1),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: _cTextPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: _cTextDim,
          ),
          prefixIcon: Icon(icon, size: 18, color: _cTextDim),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    const monthNames = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
          builder: (ctx, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: _cOrange,
                  surface: _cCard,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() {
            _selectedDate = picked;
            _isPanchangChecked = false;
          });
          _checkAuspicious();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: _cBorder, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 18, color: _cOrange),
            const SizedBox(width: 10),
            Text(
              '${_selectedDate.day} ${monthNames[_selectedDate.month]} ${_selectedDate.year}',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextPrimary,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 18, color: _cTextDim),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRow() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _startTime,
                builder: (ctx, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: _cOrange,
                        surface: _cCard,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _startTime = picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _cElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(color: _cBorder, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 16, color: _cOrange),
                  const SizedBox(width: 8),
                  Text(
                    _startTime.format(context),
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _cTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'to',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: _cTextDim,
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _endTime,
                builder: (ctx, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: _cOrange,
                        surface: _cCard,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _endTime = picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _cElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(color: _cBorder, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 16, color: _cAmber),
                  const SizedBox(width: 8),
                  Text(
                    _endTime.format(context),
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _cTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reminderChip(String label, ReminderTiming timing) {
    final isSelected = _selectedReminders.contains(timing);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedReminders.remove(timing);
          } else {
            _selectedReminders.add(timing);
          }
        });
      },
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _cOrange.withValues(alpha: 0.15) : _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: isSelected ? _cOrange.withValues(alpha: 0.4) : _cBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 14,
              color: isSelected ? _cOrange : _cTextDim,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? _cOrange : _cTextDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.birthday:
        return KinrelColors.orange;
      case CalendarEventType.anniversary:
        return KinrelColors.amber;
      case CalendarEventType.festival:
        return KinrelColors.gold;
      case CalendarEventType.custom:
        return KinrelColors.textSilver;
      case CalendarEventType.reminder:
        return KinrelColors.info;
      default:
        return KinrelColors.textSilver;
    }
  }

  IconData _getTypeIcon(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.birthday:
        return Icons.cake_rounded;
      case CalendarEventType.anniversary:
        return Icons.favorite_rounded;
      case CalendarEventType.festival:
        return Icons.celebration_rounded;
      case CalendarEventType.custom:
        return Icons.event_rounded;
      case CalendarEventType.reminder:
        return Icons.alarm_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  String _getTypeLabel(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.birthday:
        return 'Birthday';
      case CalendarEventType.anniversary:
        return 'Anniversary';
      case CalendarEventType.festival:
        return 'Festival';
      case CalendarEventType.custom:
        return 'Custom';
      case CalendarEventType.reminder:
        return 'Reminder';
      default:
        return 'Event';
    }
  }

  void _saveEvent() {
    if (_titleController.text.trim().isEmpty) return;

    final event = SmartCalendarEvent(
      id: 'event-${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim(),
      date: _selectedDate,
      type: _selectedType,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : null,
      startTime: _startTime.hour,
      endTime: _endTime.hour,
      reminderTimings: _selectedReminders.toList(),
      panchangInfo: HinduPanchangService.getPanchang(_selectedDate),
    );

    ref.read(smartCalendarProvider.notifier).addEvent(event);
    Navigator.of(context).pop();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Auspicious Date Finder Sheet
// ═══════════════════════════════════════════════════════════════════════

class _AuspiciousDateFinderSheet extends StatefulWidget {
  const _AuspiciousDateFinderSheet();

  @override
  State<_AuspiciousDateFinderSheet> createState() =>
      _AuspiciousDateFinderSheetState();
}

class _AuspiciousDateFinderSheetState
    extends State<_AuspiciousDateFinderSheet> {
  AuspiciousEventType _selectedType = AuspiciousEventType.wedding;
  List<AuspiciousDateResult> _results = [];
  bool _isLoading = false;

  static const _typeInfo = {
    AuspiciousEventType.wedding: (
      label: 'Wedding',
      icon: Icons.favorite_rounded,
    ),
    AuspiciousEventType.grihaPravesh: (
      label: 'Griha Pravesh',
      icon: Icons.home_rounded,
    ),
    AuspiciousEventType.namingCeremony: (
      label: 'Naming Ceremony',
      icon: Icons.child_care_rounded,
    ),
    AuspiciousEventType.mundan: (
      label: 'Mundan',
      icon: Icons.content_cut_rounded,
    ),
    AuspiciousEventType.engagement: (
      label: 'Engagement',
      icon: Icons.diamond_rounded,
    ),
    AuspiciousEventType.upanayana: (
      label: 'Upanayana',
      icon: Icons.auto_stories_rounded,
    ),
    AuspiciousEventType.startingBusiness: (
      label: 'New Business',
      icon: Icons.store_rounded,
    ),
    AuspiciousEventType.travel: (
      label: 'Travel',
      icon: Icons.flight_takeoff_rounded,
    ),
  };

  void _search() {
    setState(() => _isLoading = true);
    // Simulate async
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final results = HinduPanchangService.findAuspiciousDates(
        _selectedType,
        DateTime.now(),
      );
      setState(() {
        _results = results;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(KinrelSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _cBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _cGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: _cGold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Find Auspicious Date',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _cTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Based on Panchang Tithi, Nakshatra & Yoga',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: _cTextDim,
                ),
              ),
              const SizedBox(height: 20),

              // Event Type Selector
              Text(
                'Select Event Type',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: AuspiciousEventType.values.map((type) {
                  final info = _typeInfo[type]!;
                  final isSelected = _selectedType == type;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = type),
                    child: AnimatedContainer(
                      duration: KinrelMotion.fast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _cGold.withValues(alpha: 0.15)
                            : _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                        border: Border.all(
                          color: isSelected
                              ? _cGold.withValues(alpha: 0.4)
                              : _cBorder,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            info.icon,
                            size: 13,
                            color: isSelected ? _cGold : _cTextDim,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            info.label,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected ? _cGold : _cTextDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Search Button
              GestureDetector(
                onTap: _isLoading ? null : _search,
                child: Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.shareCardGradient,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(
                          'Find Shubh Dates',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // Results
              if (_results.isNotEmpty) ...[
                Text(
                  'Top ${_results.length} Auspicious Dates',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ..._results.asMap().entries.map((entry) {
                  final index = entry.key;
                  final result = entry.value;
                  return _AuspiciousDateCard(result: result, rank: index + 1);
                }),
              ] else if (!_isLoading) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 40,
                          color: _cGold.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Select an event type and search',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: _cTextDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

// ── Auspicious Date Card ──────────────────────────────────────────────

class _AuspiciousDateCard extends StatelessWidget {
  const _AuspiciousDateCard({required this.result, required this.rank});

  final AuspiciousDateResult result;
  final int rank;

  static const _monthNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final p = result.panchang;
    final scorePercent = result.score;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: _cGold.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Rank badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: rank == 1
                      ? KinrelGradients.shareCardGradient
                      : null,
                  color: rank == 1 ? null : _cGold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: rank == 1 ? Colors.white : _cGold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_dayNames[result.date.weekday - 1]}, ${result.date.day} ${_monthNames[result.date.month]} ${result.date.year}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _cTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.tithi} · ${p.paksha} Paksha',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        color: _cTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Score
              Column(
                children: [
                  Text(
                    '$scorePercent%',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scorePercent >= 80 ? KinrelColors.success : _cGold,
                    ),
                  ),
                  Text(
                    'Shubh',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 8,
                      color: _cTextDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Nakshatra, Yoga, Karana details
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _detailChip('Nakshatra', p.nakshatra, _cGold),
              _detailChip('Yoga', p.yoga, _cOrange),
              _detailChip('Karana', p.karana, _cAmber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.12), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: _cTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
