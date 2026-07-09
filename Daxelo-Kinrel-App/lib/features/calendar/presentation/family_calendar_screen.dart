// lib/features/calendar/presentation/family_calendar_screen.dart
//
// World-class Family Calendar with Month, Week, and Agenda views.
// Replaces the old occasions-only screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../models/calendar_models.dart';
import '../providers/calendar_provider.dart';
import '../../../features/occasions/providers/occasion_reminders_provider.dart';

enum CalendarView { month, week, agenda }

class FamilyCalendarScreen extends ConsumerStatefulWidget {
  const FamilyCalendarScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FamilyCalendarScreen> createState() => _FamilyCalendarScreenState();
}

class _FamilyCalendarScreenState extends ConsumerState<FamilyCalendarScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTime _focusedMonth = DateTime.now();
  DateTime _focusedWeek = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.microtask(() {
      ref.read(calendarProvider(widget.familyId).notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calState = ref.watch(calendarProvider(widget.familyId));
    final occasions = ref.watch(familyOccasionsProvider(widget.familyId));
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));

    // Merge calendar events + auto-generated occasions (birthdays/anniversaries)
    final allEvents = <CalendarEvent>[...calState.events];
    for (final occ in occasions) {
      // Only add if not already a manual event for this person+type
      final exists = allEvents.any((e) =>
          e.personId == occ.personId &&
          (e.category == EventCategory.birthday && occ.type == OccasionType.birthday ||
           e.category == EventCategory.anniversary && occ.type == OccasionType.anniversary));
      if (!exists) {
        allEvents.add(CalendarEvent(
          id: 'auto_${occ.personId}_${occ.type.name}',
          familyId: widget.familyId,
          createdBy: '',
          personId: occ.personId,
          title: '${occ.name}\'s ${occ.type == OccasionType.birthday ? "Birthday" : "Anniversary"}',
          category: occ.type == OccasionType.birthday ? EventCategory.birthday : EventCategory.anniversary,
          eventDate: occ.nextOccurrence,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Text('Family Calendar', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600)),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Today',
            onPressed: () => setState(() {
              _focusedMonth = DateTime.now();
              _focusedWeek = DateTime.now();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Event',
            onPressed: () => context.push('/family/${widget.familyId}/calendar/new'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KinrelColors.orange,
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textDim,
          labelStyle: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Month'), Tab(text: 'Week'), Tab(text: 'Agenda')],
        ),
      ),
      body: calState.isLoading && allEvents.isEmpty
          ? Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _MonthView(
                  focusedMonth: _focusedMonth,
                  events: allEvents,
                  onPageChanged: (date) => setState(() => _focusedMonth = date),
                  familyId: widget.familyId,
                ),
                _WeekView(
                  focusedWeek: _focusedWeek,
                  events: allEvents,
                  onPageChanged: (date) => setState(() => _focusedWeek = date),
                  familyId: widget.familyId,
                ),
                _AgendaView(events: allEvents, familyId: widget.familyId, detailAsync: detailAsync),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// MONTH VIEW
// ═══════════════════════════════════════════════════════════════════

class _MonthView extends StatelessWidget {
  const _MonthView({required this.focusedMonth, required this.events, required this.onPageChanged, required this.familyId});
  final DateTime focusedMonth;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onPageChanged;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final firstWeekday = firstOfMonth.weekday % 7; // 0=Sunday
    final daysInMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final today = DateTime.now();
    final isCurrentMonth = today.year == focusedMonth.year && today.month == focusedMonth.month;
    final monthLabel = '${_monthName(focusedMonth.month)} ${focusedMonth.year}';

    return Column(children: [
      // Month navigation header
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconButton(icon: Icon(Icons.chevron_left, color: KinrelColors.textSilver), onPressed: () => onPageChanged(DateTime(focusedMonth.year, focusedMonth.month - 1, 1))),
          Expanded(child: Center(child: Text(monthLabel, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
          ),
          IconButton(icon: Icon(Icons.chevron_right, color: KinrelColors.textSilver), onPressed: () => onPageChanged(DateTime(focusedMonth.year, focusedMonth.month + 1, 1))),
        ]),
      ),
      // Weekday headers
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KinrelColors.textDim))))).toList())),
      // Calendar grid
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.85),
        itemCount: firstWeekday + daysInMonth,
        itemBuilder: (context, index) {
          if (index < firstWeekday) return const SizedBox();
          final day = index - firstWeekday + 1;
          final date = DateTime(focusedMonth.year, focusedMonth.month, day);
          final isToday = isCurrentMonth && day == today.day;
          final dayEvents = events.where((e) => e.eventDate.year == date.year && e.eventDate.month == date.month && e.eventDate.day == day).toList();
          return GestureDetector(
            onTap: () {
              if (dayEvents.isNotEmpty) {
                context.push('/family/$familyId/calendar/event/${dayEvents.first.id}', extra: {'familyId': familyId, 'event': dayEvents.first.toJson()});
              } else {
                // Tap-to-add from empty day cell — lower friction for
                // quick entry, not just the top "+" icon.
                context.push('/family/$familyId/calendar/new');
              }
            },
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isToday ? KinrelColors.orange.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isToday ? Border.all(color: KinrelColors.orange, width: 1.5) : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$day', style: TextStyle(fontSize: 13, fontWeight: isToday ? FontWeight.w800 : FontWeight.w500, color: isToday ? KinrelColors.orange : KinrelColors.textWhite)),
                // Event dots — larger (7px) and more visible than the
                // previous 5px. Up to 3 dots shown, color-coded by type.
                if (dayEvents.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 3,
                      runSpacing: 2,
                      children: dayEvents.take(3).map((e) {
                        // Use a brighter version of the category color
                        // for visibility on the dark background.
                        final baseColor = Color(e.category.colorValue);
                        return Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: baseColor,
                            // Add a subtle glow for better visibility.
                            boxShadow: [
                              BoxShadow(
                                color: baseColor.withValues(alpha: 0.4),
                                blurRadius: 2,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ]),
            ),
          );
        },
      )),
    ]);
  }

  String _monthName(int month) => ['January','February','March','April','May','June','July','August','September','October','November','December'][month - 1];
}

// ═══════════════════════════════════════════════════════════════════
// WEEK VIEW
// ═══════════════════════════════════════════════════════════════════

class _WeekView extends StatelessWidget {
  const _WeekView({required this.focusedWeek, required this.events, required this.onPageChanged, required this.familyId});
  final DateTime focusedWeek;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onPageChanged;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    final monday = focusedWeek.subtract(Duration(days: focusedWeek.weekday - 1));
    final today = DateTime.now();
    final weekLabel = '${_monthName(monday.month)} ${monday.day} - ${monday.day + 6}';

    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Row(children: [
        IconButton(icon: Icon(Icons.chevron_left, color: KinrelColors.textSilver), onPressed: () => onPageChanged(focusedWeek.subtract(const Duration(days: 7)))),
        Expanded(child: Center(child: Text(weekLabel, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)))),
        IconButton(icon: Icon(Icons.chevron_right, color: KinrelColors.textSilver), onPressed: () => onPageChanged(focusedWeek.add(const Duration(days: 7)))),
      ])),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        itemBuilder: (context, index) {
          final date = monday.add(Duration(days: index));
          final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
          final dayEvents = events.where((e) => e.eventDate.year == date.year && e.eventDate.month == date.month && e.eventDate.day == date.day).toList();
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 40, child: Column(children: [
              Text(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][index], style: TextStyle(fontSize: 10, color: KinrelColors.textDim, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('${date.day}', style: TextStyle(fontSize: 18, fontWeight: isToday ? FontWeight.w800 : FontWeight.w600, color: isToday ? KinrelColors.orange : KinrelColors.textWhite)),
            ])),
            const SizedBox(width: 12),
            Expanded(child: dayEvents.isEmpty
              ? GestureDetector(
                  onTap: () => context.push('/family/$familyId/calendar/new'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 16,
                            color: KinrelColors.textDim
                                .withValues(alpha: 0.4)),
                        const SizedBox(width: 6),
                        Text('Add event',
                            style: TextStyle(
                              fontSize: 12,
                              color: KinrelColors.textDim
                                  .withValues(alpha: 0.4),
                            )),
                      ],
                    ),
                  ),
                )
              : Column(children: dayEvents.map((e) => _EventMiniCard(event: e, familyId: familyId)).toList())),
          ]));
        },
      )),
    ]);
  }

  String _monthName(int month) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][month - 1];
}

// ═══════════════════════════════════════════════════════════════════
// AGENDA VIEW
// ═══════════════════════════════════════════════════════════════════

class _AgendaView extends StatelessWidget {
  const _AgendaView({required this.events, required this.familyId, required this.detailAsync});
  final List<CalendarEvent> events;
  final String familyId;
  final AsyncValue<FamilyDetail?> detailAsync;

  @override
  Widget build(BuildContext context) {
    final sorted = List<CalendarEvent>.from(events)..sort((a, b) => a.eventDate.compareTo(b.eventDate));
    final upcoming = sorted.where((e) => e.isUpcoming).toList();
    final past = sorted.where((e) => e.isPast).toList().reversed.toList();

    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      if (upcoming.isEmpty && past.isEmpty) ...[
        const SizedBox(height: 80),
        Center(child: Column(children: [
          Icon(Icons.calendar_month_outlined, size: 56, color: KinrelColors.textDim.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No Events Yet', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(height: 8),
          Text('Add birthdays, anniversaries, and family events\nto see them here.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => context.push('/family/$familyId/calendar/new'), icon: Icon(Icons.add), label: Text('Add Event'), style: FilledButton.styleFrom(backgroundColor: KinrelColors.orange, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
        ])),
      ] else ...[
        if (upcoming.isNotEmpty) ...[
          Text('Upcoming', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
          const SizedBox(height: 12),
          ...upcoming.map((e) => _EventFullCard(event: e, familyId: familyId)),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Past Events', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textDim)),
          const SizedBox(height: 12),
          ...past.take(10).map((e) => _EventFullCard(event: e, familyId: familyId, isPast: true)),
        ],
      ],
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════
// EVENT CARDS
// ═══════════════════════════════════════════════════════════════════

class _EventMiniCard extends StatelessWidget {
  const _EventMiniCard({required this.event, required this.familyId});
  final CalendarEvent event;
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/family/$familyId/calendar/event/${event.id}', extra: {'familyId': familyId, 'event': event.toJson()}),
      child: Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Color(event.category.colorValue).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Text(event.category.icon, style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(child: Text(event.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: KinrelColors.textWhite), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])),
    );
  }
}

class _EventFullCard extends StatelessWidget {
  const _EventFullCard({required this.event, required this.familyId, this.isPast = false});
  final CalendarEvent event;
  final String familyId;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final color = Color(event.category.colorValue);
    return GestureDetector(
      onTap: () => context.push('/family/$familyId/calendar/event/${event.id}', extra: {'familyId': familyId, 'event': event.toJson()}),
      child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: isPast ? KinrelColors.darkCard.withValues(alpha: 0.5) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isPast ? Colors.transparent : color.withValues(alpha: 0.25))),
        child: Row(children: [
          // Date block
          Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
            child: Center(child: Text(event.category.icon, style: TextStyle(fontSize: 22)))),
          const SizedBox(width: 14),
          // Title + countdown
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 15, fontWeight: FontWeight.w600, color: isPast ? KinrelColors.textDim : KinrelColors.textWhite)),
            const SizedBox(height: 2),
            Text('${event.eventDate.month}/${event.eventDate.day}/${event.eventDate.year}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
          ])),
          // Countdown badge
          if (!isPast)
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: event.isToday ? color : color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Text(event.countdownLabel, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w700, color: event.isToday ? Colors.white : color))),
        ]),
      ),
    );
  }
}
