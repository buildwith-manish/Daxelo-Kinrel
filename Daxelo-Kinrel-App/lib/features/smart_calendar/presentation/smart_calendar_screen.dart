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
//   • Panchang panel: slides up with full panchang info
//   • Events list below calendar for selected date
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
    // Load festivals when screen initializes
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
          _ViewAndPanchangToggle()
              .animate()
              .fadeIn(duration: 300.ms, delay: 50.ms),

          const SizedBox(height: 8),

          // ── Month Navigation ──────────────────────────────────────
          _MonthNavigation()
              .animate()
              .fadeIn(duration: 300.ms, delay: 80.ms),

          const SizedBox(height: 4),

          // ── Calendar Grid ─────────────────────────────────────────
          _CalendarGrid()
              .animate()
              .fadeIn(duration: 300.ms, delay: 100.ms),

          const SizedBox(height: 8),

          // ── Panchang Panel (animated) ─────────────────────────────
          AnimatedSize(
            duration: KinrelMotion.normal,
            curve: KinrelMotion.easeOut,
            alignment: Alignment.topCenter,
            child: calendarState.showPanchang &&
                    calendarState.panchangForSelectedDate != null
                ? _PanchangPanel(
                    panchang: calendarState.panchangForSelectedDate!)
                    .animate()
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.08, end: 0)
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
          // Today button
          Consumer(builder: (context, ref, _) {
            return GestureDetector(
              onTap: () =>
                  ref.read(smartCalendarProvider.notifier).goToToday(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          }),
        ],
      ),
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
            child: Consumer(builder: (context, ref, _) {
              final viewMode =
                  ref.watch(smartCalendarProvider).viewMode;
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
            }),
          ),
          const SizedBox(width: 10),
          // Panchang toggle
          Consumer(builder: (context, ref, _) {
            final showPanchang =
                ref.watch(smartCalendarProvider).showPanchang;
            return GestureDetector(
              onTap: () => ref
                  .read(smartCalendarProvider.notifier)
                  .togglePanchang(),
              child: AnimatedContainer(
                duration: KinrelMotion.fast,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          }),
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
        onTap: () =>
            ref.read(smartCalendarProvider.notifier).toggleView(view),
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
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final selectedDate =
          ref.watch(smartCalendarProvider).effectiveSelectedDate;
      final notifier = ref.read(smartCalendarProvider.notifier);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Previous month
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
            // Month & Year
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
            // Next month
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
    });
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
    return Consumer(builder: (context, ref, _) {
      final state = ref.watch(smartCalendarProvider);
      final selectedDate = state.effectiveSelectedDate;
      final events = state.events;
      final showPanchang = state.showPanchang;
      final today = DateTime.now();

      final firstOfMonth =
          DateTime(selectedDate.year, selectedDate.month, 1);
      final daysInMonth =
          DateTime(selectedDate.year, selectedDate.month + 1, 0).day;
      final startWeekday =
          firstOfMonth.weekday % 7; // Sunday = 0

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Day Headers with Panchang names ──────────────────────
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

            // ── Date Cells ──────────────────────────────────────────
            Wrap(
              children: List.generate(
                startWeekday + daysInMonth,
                (index) {
                  if (index < startWeekday) {
                    return const _EmptyDateCell();
                  }
                  final day = index - startWeekday + 1;
                  final date = DateTime(
                      selectedDate.year, selectedDate.month, day);
                  final isToday = date.year == today.year &&
                      date.month == today.month &&
                      date.day == today.day;
                  final isSelected =
                      date.year == selectedDate.year &&
                          date.month == selectedDate.month &&
                          date.day == selectedDate.day;
                  final dayEvents = events
                      .where((e) =>
                          e.date.year == date.year &&
                          e.date.month == date.month &&
                          e.date.day == date.day)
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
                },
              ),
            ),
          ],
        ),
      );
    });
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

    // Get Panchang tithi for compact display
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
            // ── Date number with ring ──────────────────────────────
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected
                    ? KinrelGradients.igniteGradient
                    : null,
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

            // ── Event dots ─────────────────────────────────────────
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
          border: Border.all(
            color: _cOrange.withValues(alpha: 0.12),
            width: 1,
          ),
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
            // ── Panchang Header ──────────────────────────────────────
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
                // Auspicious indicator
                _AuspiciousBadge(isAuspicious: panchang.isAuspicious),
              ],
            ),

            const SizedBox(height: 16),

            // ── Main Panchang Info Grid ──────────────────────────────
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

            // ── Additional Info Row ──────────────────────────────────
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

            // ── Inauspicious Times ───────────────────────────────────
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
                      Icon(Icons.block_rounded,
                          size: 14,
                          color: KinrelColors.error.withValues(alpha: 0.7)),
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

            // ── Auspicious Time ──────────────────────────────────────
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
                    Icon(Icons.check_circle_rounded,
                        size: 14, color: KinrelColors.success),
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

            // ── Festivals ────────────────────────────────────────────
            if (panchang.festivals.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...panchang.festivals.map((festival) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: KinrelGradients.shareCardGradient,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.celebration_rounded,
                            size: 16, color: Colors.white),
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
                  )),
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
            isAuspicious
                ? Icons.check_circle_rounded
                : Icons.cancel_outlined,
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
  const _EventsForDateList({
    required this.events,
    required this.selectedDate,
  });

  final List<SmartCalendarEvent> events;
  final DateTime selectedDate;

  static const _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ─────────────────────────────────────────
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

        // ── Events List ────────────────────────────────────────────
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
                            delay: Duration(milliseconds: index * 60))
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
    final isPanchangFestival =
        event.type == CalendarEventType.panchangFestival;
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
            // ── Icon ───────────────────────────────────────────────
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

            // ── Title & Description ────────────────────────────────
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
                      if (event.isAutoGenerated) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(KinrelRadius.xs),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded,
                                  size: 9, color: accentColor),
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

            // ── Reminder icon ──────────────────────────────────────
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
              const SizedBox(height: 20),

              // Title
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: event.type ==
                              CalendarEventType.panchangFestival
                          ? KinrelGradients.shareCardGradient
                          : null,
                      color: event.type ==
                              CalendarEventType.panchangFestival
                          ? null
                          : accentColor.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(KinrelRadius.lg),
                    ),
                    alignment: Alignment.center,
                    child: Icon(event.icon,
                        size: 24,
                        color: event.type ==
                                CalendarEventType.panchangFestival
                            ? Colors.white
                            : accentColor),
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

              // Date
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: _cTextDim),
                  const SizedBox(width: 8),
                  Text(
                    event.formattedDate,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: _cTextSecondary,
                    ),
                  ),
                ],
              ),

              // Description
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

              // Panchang info
              if (event.panchangInfo != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(
                      color: _cOrange.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 14, color: _cOrange),
                          const SizedBox(width: 6),
                          Text(
                            'Panchang',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _cOrange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tithi: ${event.panchangInfo!.tithi}  •  Nakshatra: ${event.panchangInfo!.nakshatra}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _cTextSecondary,
                          height: 1.5,
                        ),
                      ),
                      Text(
                        'Yoga: ${event.panchangInfo!.yoga}  •  Karana: ${event.panchangInfo!.karana}',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _cTextSecondary,
                          height: 1.5,
                        ),
                      ),
                      if (event.panchangInfo!.rahukaalStart != null)
                        Text(
                          'Rahu Kaal: ${event.panchangInfo!.rahukaalStart} — ${event.panchangInfo!.rahukaalEnd}',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color:
                                KinrelColors.error.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              // Reminders
              if (event.reminderTimings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Reminders',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: event.reminderTimings.map((t) {
                    final label = switch (t) {
                      ReminderTiming.oneWeekBefore => '1 week before',
                      ReminderTiming.threeDaysBefore => '3 days before',
                      ReminderTiming.oneDayBefore => '1 day before',
                      ReminderTiming.morningOf => 'Morning of',
                      ReminderTiming.custom => 'Custom',
                    };
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _cOrange.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.sm),
                        border: Border.all(
                          color: _cOrange.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.alarm_rounded,
                              size: 11, color: _cOrange),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _cOrange,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Create Event Sheet
// ═══════════════════════════════════════════════════════════════════════

class _CreateEventSheet extends ConsumerStatefulWidget {
  const _CreateEventSheet();

  @override
  ConsumerState<_CreateEventSheet> createState() =>
      _CreateEventSheetState();
}

class _CreateEventSheetState extends ConsumerState<_CreateEventSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  CalendarEventType _selectedType = CalendarEventType.custom;
  DateTime _selectedDate = DateTime.now();
  final List<ReminderTiming> _selectedReminders = [
    ReminderTiming.oneDayBefore,
    ReminderTiming.morningOf,
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
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
              const SizedBox(height: 20),

              // Title
              Text(
                'Create Event',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 20),

              // Event title input
              _InputField(
                controller: _titleController,
                hint: 'Event title',
                icon: Icons.event_rounded,
              ),
              const SizedBox(height: 12),

              // Description input
              _InputField(
                controller: _descController,
                hint: 'Description (optional)',
                icon: Icons.notes_rounded,
              ),
              const SizedBox(height: 16),

              // Event type selector
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
                spacing: 6,
                runSpacing: 6,
                children: [
                  _TypeChip(
                    label: '🎂 Birthday',
                    type: CalendarEventType.birthday,
                    selected: _selectedType == CalendarEventType.birthday,
                    color: KinrelColors.orange,
                    onTap: () =>
                        setState(() => _selectedType = CalendarEventType.birthday),
                  ),
                  _TypeChip(
                    label: '💍 Anniversary',
                    type: CalendarEventType.anniversary,
                    selected:
                        _selectedType == CalendarEventType.anniversary,
                    color: KinrelColors.amber,
                    onTap: () => setState(
                        () => _selectedType = CalendarEventType.anniversary),
                  ),
                  _TypeChip(
                    label: '🎉 Festival',
                    type: CalendarEventType.festival,
                    selected: _selectedType == CalendarEventType.festival,
                    color: KinrelColors.gold,
                    onTap: () => setState(
                        () => _selectedType = CalendarEventType.festival),
                  ),
                  _TypeChip(
                    label: '📌 Custom',
                    type: CalendarEventType.custom,
                    selected: _selectedType == CalendarEventType.custom,
                    color: KinrelColors.textSilver,
                    onTap: () => setState(
                        () => _selectedType = CalendarEventType.custom),
                  ),
                  _TypeChip(
                    label: '⏰ Reminder',
                    type: CalendarEventType.reminder,
                    selected: _selectedType == CalendarEventType.reminder,
                    color: KinrelColors.info,
                    onTap: () => setState(
                        () => _selectedType = CalendarEventType.reminder),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Date selector
              Text(
                'Date',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.dark(
                            primary: _cOrange,
                            surface: _cCard,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _cElevated,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(color: _cBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 18, color: _cOrange),
                      const SizedBox(width: 10),
                      Text(
                        SmartCalendarEvent(
                          id: '',
                          title: '',
                          date: _selectedDate,
                          type: CalendarEventType.custom,
                        ).formattedDate,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _cTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Reminder toggles
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
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ReminderChip(
                    label: '1 week before',
                    timing: ReminderTiming.oneWeekBefore,
                    selected: _selectedReminders
                        .contains(ReminderTiming.oneWeekBefore),
                    onTap: () => _toggleReminder(ReminderTiming.oneWeekBefore),
                  ),
                  _ReminderChip(
                    label: '3 days before',
                    timing: ReminderTiming.threeDaysBefore,
                    selected: _selectedReminders
                        .contains(ReminderTiming.threeDaysBefore),
                    onTap: () =>
                        _toggleReminder(ReminderTiming.threeDaysBefore),
                  ),
                  _ReminderChip(
                    label: '1 day before',
                    timing: ReminderTiming.oneDayBefore,
                    selected: _selectedReminders
                        .contains(ReminderTiming.oneDayBefore),
                    onTap: () =>
                        _toggleReminder(ReminderTiming.oneDayBefore),
                  ),
                  _ReminderChip(
                    label: 'Morning of',
                    timing: ReminderTiming.morningOf,
                    selected:
                        _selectedReminders.contains(ReminderTiming.morningOf),
                    onTap: () => _toggleReminder(ReminderTiming.morningOf),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Create button
              SizedBox(
                width: double.infinity,
                child: DKButton(
                  label: 'Create Event',
                  variant: DKButtonVariant.gradient,
                  icon: Icons.add_rounded,
                  size: DKButtonSize.lg,
                  fullWidth: true,
                  onPressed: _createEvent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleReminder(ReminderTiming timing) {
    setState(() {
      if (_selectedReminders.contains(timing)) {
        _selectedReminders.remove(timing);
      } else {
        _selectedReminders.add(timing);
      }
    });
  }

  void _createEvent() {
    if (_titleController.text.trim().isEmpty) return;

    final event = SmartCalendarEvent(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim(),
      date: _selectedDate,
      type: _selectedType,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      reminderTimings: List.from(_selectedReminders),
      panchangInfo:
          HinduPanchangService.getPanchang(_selectedDate),
    );

    ref.read(smartCalendarProvider.notifier).addEvent(event);
    Navigator.of(context).pop();
  }
}

// ── Input Field ───────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
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
              horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

// ── Type Chip ─────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.type,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final CalendarEventType type;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: selected ? color : _cBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? color : _cTextDim,
          ),
        ),
      ),
    );
  }
}

// ── Reminder Chip ─────────────────────────────────────────────────────

class _ReminderChip extends StatelessWidget {
  const _ReminderChip({
    required this.label,
    required this.timing,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ReminderTiming timing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? _cOrange.withValues(alpha: 0.12)
              : _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: selected ? _cOrange : _cBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected
                  ? Icons.alarm_rounded
                  : Icons.alarm_add_rounded,
              size: 13,
              color: selected ? _cOrange : _cTextDim,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? _cOrange : _cTextDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
