// lib/features/events/presentation/events_screen.dart
//
// DAXELO KINREL — Events & Celebrations Screen
//
// Orange K-Graph DNA design:
//   • Header: "Events & Celebrations" with calendar icon in orange
//   • Tab filter: "Upcoming" | "This Month" | "All"
//   • Event cards: name, date/time, member avatars, location,
//     countdown timer, reminder icon, RSVP status
//   • FAB: Orange gradient to create new event
//   • Empty state: Calendar illustration with auto-birthday message
//   • Auto-reminders: 1 week, 1 day, day of
//   • "Send wishes?" quick message options
//
// Design colors:
//   Background:  #13141E (darkSurface)
//   Cards:       #191B2C (darkCard)
//   Primary:     #F5F0EE (textWhite)
//   Secondary:   #C9B4A8 (textSilver)
//   Accent:      #E8612A (orange)
//   Birthday:    orange (#E8612A)
//   Anniversary: amber (#F59240)
//   Festival:    gold (#D4AF37)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/events_provider.dart';

// ── Color shortcuts ──────────────────────────────────────────────────
const _cOrange = KinrelColors.orange;       // #E8612A
const _cAmber = KinrelColors.amber;         // #F59240
const _cGold = KinrelColors.gold;           // #D4AF37
const _cBg = KinrelColors.darkSurface;      // #13141E
const _cCard = KinrelColors.darkCard;       // #191B2C
const _cElevated = KinrelColors.darkElevated; // #202338
const _cTextPrimary = KinrelColors.textWhite;  // #F5F0EE
const _cTextSecondary = KinrelColors.textSilver; // #C9B4A8
const _cTextDim = KinrelColors.textDim;     // #8A7A72
const _cBorder = Color(0xFF3A3A4A);

// ═══════════════════════════════════════════════════════════════════════
// Events Screen
// ═══════════════════════════════════════════════════════════════════════

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Refresh countdown timers every minute
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(eventsProvider);
    final filteredEvents = eventsState.filteredEvents;

    return DKScaffold(
      backgroundColor: _cBg,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────
          _EventsHeader()
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: -0.05, end: 0),

          // ── Tab Filter ────────────────────────────────────────────
          _TabFilterBar(
            currentFilter: eventsState.filter,
            onFilterChanged: (filter) =>
                ref.read(eventsProvider.notifier).setFilter(filter),
          )
              .animate()
              .fadeIn(duration: 300.ms, delay: 50.ms),

          const SizedBox(height: 12),

          // ── Event List / Empty State ──────────────────────────────
          Expanded(
            child: filteredEvents.isEmpty
                ? _EmptyState()
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0)
                : _EventsList(events: filteredEvents),
          ),
        ],
      ),
      // ── FAB: Create New Event (Orange gradient) ──────────────────
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
      builder: (ctx) => _CreateEventSheet(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header: "Events & Celebrations" with calendar icon in orange
// ═══════════════════════════════════════════════════════════════════════

class _EventsHeader extends StatelessWidget {
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
          // Calendar icon in orange
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _cOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
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
                  'Events & Celebrations',
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
                  'Birthdays, festivals & family moments',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _cTextDim,
                  ),
                ),
              ],
            ),
          ),
          // Notification bell
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Event notifications coming soon!'),
                  backgroundColor: _cCard,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _cElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: _cTextSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tab Filter: "Upcoming" | "This Month" | "All"
// ═══════════════════════════════════════════════════════════════════════

class _TabFilterBar extends StatelessWidget {
  const _TabFilterBar({
    required this.currentFilter,
    required this.onFilterChanged,
  });

  final EventsFilter currentFilter;
  final ValueChanged<EventsFilter> onFilterChanged;

  static const _tabs = [
    (filter: EventsFilter.upcoming, label: 'Upcoming'),
    (filter: EventsFilter.thisMonth, label: 'This Month'),
    (filter: EventsFilter.all, label: 'All'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
          border: Border.all(color: _cBorder, width: 1),
        ),
        child: Row(
          children: _tabs.map((tab) {
            final isActive = currentFilter == tab.filter;
            return Expanded(
              child: GestureDetector(
                onTap: () => onFilterChanged(tab.filter),
                child: AnimatedContainer(
                  duration: KinrelMotion.fast,
                  curve: KinrelMotion.easeOut,
                  margin: EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? KinrelGradients.igniteGradient
                        : null,
                    color: isActive ? null : Colors.transparent,
                    borderRadius: BorderRadius.circular(KinrelRadius.lg),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? Colors.white : _cTextDim,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Events List
// ═══════════════════════════════════════════════════════════════════════

class _EventsList extends StatelessWidget {
  const _EventsList({required this.events});

  final List<EventModel> events;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        0,
        KinrelSpacing.base,
        100,
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _EventCard(event: events[index])
            .animate()
            .fadeIn(duration: 350.ms, delay: Duration(milliseconds: index * 60))
            .slideY(begin: 0.06, end: 0);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Event Card
// ═══════════════════════════════════════════════════════════════════════

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = event.accentColor;

    return GestureDetector(
      onTap: () => _showEventDetail(context),
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: Type badge + Reminder icon ────────────────
            Row(
              children: [
                // Type badge
                _EventTypeBadge(type: event.type, accentColor: accentColor),
                const Spacer(),
                // Auto-generated indicator
                if (event.isAutoGenerated) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(KinrelRadius.xs),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 10, color: accentColor),
                        const SizedBox(width: 3),
                        Text(
                          'Auto',
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Reminder settings icon
                GestureDetector(
                  onTap: () => _showReminderSheet(context, ref),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _cElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.sm),
                    ),
                    child: Icon(
                      event.reminderTimings.isNotEmpty
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      size: 16,
                      color: event.reminderTimings.isNotEmpty
                          ? accentColor
                          : _cTextDim,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Event Name (Heading Medium) ─────────────────────────
            Text(
              event.name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
                letterSpacing: 0.18,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 8),

            // ── Date and Time ───────────────────────────────────────
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: _cTextDim),
                const SizedBox(width: 6),
                Text(
                  '${event.formattedDate} · ${event.formattedTime}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: _cTextSecondary,
                  ),
                ),
              ],
            ),

            // ── Location (optional) ─────────────────────────────────
            if (event.location != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: _cTextDim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      event.location!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: _cTextSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // ── Description ─────────────────────────────────────────
            if (event.description != null) ...[
              const SizedBox(height: 10),
              Text(
                event.description!,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _cTextDim,
                  height: 1.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 14),

            // ── Related Members (avatar row) ────────────────────────
            if (event.members.isNotEmpty)
              _MemberAvatarRow(
                members: event.members,
                accentColor: accentColor,
              ),

            const SizedBox(height: 12),

            // ── Bottom row: Countdown + RSVP + Send Wishes ──────────
            Row(
              children: [
                // Countdown timer
                _CountdownChip(event: event),
                const Spacer(),
                // RSVP (for reunion type)
                if (event.type == EventType.reunion)
                  _RSVPChip(
                    status: event.rsvpStatus,
                    accentColor: accentColor,
                    onTap: () => _showRSVPSheet(context, ref),
                  ),
                // Send Wishes (for birthday/anniversary)
                if (event.type == EventType.birthday ||
                    event.type == EventType.anniversary)
                  _SendWishesButton(
                    event: event,
                    accentColor: accentColor,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEventDetail(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _EventDetailScreen(event: event),
        transitionsBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: KinrelMotion.easeOut,
            )),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        transitionDuration: KinrelMotion.normal,
      ),
    );
  }

  void _showReminderSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => _ReminderSettingsSheet(event: event),
    );
  }

  void _showRSVPSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => _RSVPBottomSheet(event: event),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Event Type Badge
// ═══════════════════════════════════════════════════════════════════════

class _EventTypeBadge extends StatelessWidget {
  const _EventTypeBadge({
    required this.type,
    required this.accentColor,
  });

  final EventType type;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_typeIcon, size: 12, color: accentColor),
          const SizedBox(width: 5),
          Text(
            _typeLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accentColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  String get _typeLabel {
    switch (type) {
      case EventType.birthday:
        return 'Birthday';
      case EventType.anniversary:
        return 'Anniversary';
      case EventType.reunion:
        return 'Reunion';
      case EventType.festival:
        return 'Festival';
      case EventType.custom:
        return 'Custom';
    }
  }

  IconData get _typeIcon {
    switch (type) {
      case EventType.birthday:
        return Icons.cake_rounded;
      case EventType.anniversary:
        return Icons.favorite_rounded;
      case EventType.reunion:
        return Icons.groups_rounded;
      case EventType.festival:
        return Icons.celebration_rounded;
      case EventType.custom:
        return Icons.event_rounded;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Member Avatar Row (3-4 small avatars + "+N more")
// ═══════════════════════════════════════════════════════════════════════

class _MemberAvatarRow extends StatelessWidget {
  const _MemberAvatarRow({
    required this.members,
    required this.accentColor,
  });

  final List<EventMember> members;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 28.0;
    const overlap = 10.0;
    const maxVisible = 4;
    final visibleMembers = members.take(maxVisible).toList();
    final extraCount = members.length - maxVisible;

    return SizedBox(
      height: avatarSize + 4,
      child: Row(
        children: [
          // Overlapping avatars
          Stack(
            clipBehavior: Clip.none,
            children: List.generate(visibleMembers.length, (index) {
              return Positioned(
                left: index * (avatarSize - overlap),
                child: _SmallAvatar(
                  member: visibleMembers[index],
                  size: avatarSize,
                  borderColor: accentColor,
                ),
              );
            }),
          ),

          // "+N more" text
          if (extraCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _cElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
              ),
              child: Text(
                '+$extraCount more',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _cTextSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small circular avatar for the member row.
class _SmallAvatar extends StatelessWidget {
  const _SmallAvatar({
    required this.member,
    required this.size,
    this.borderColor,
  });

  final EventMember member;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _cElevated,
        border: Border.all(
          color: borderColor ?? _cBorder,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        member.displayInitials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: borderColor ?? _cTextSecondary,
          height: 1,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Countdown Chip
// ═══════════════════════════════════════════════════════════════════════

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final days = event.daysUntil;
    final accentColor = event.accentColor;
    final isToday = days == 0;
    final isPast = days < 0;

    String label;
    IconData iconData;

    if (isToday) {
      label = 'Today! ${event.emoji}';
      iconData = Icons.today_rounded;
    } else if (days == 1) {
      label = 'Tomorrow';
      iconData = Icons.schedule_rounded;
    } else if (days <= 7) {
      label = '$days days';
      iconData = Icons.hourglass_bottom_rounded;
    } else if (days <= 30) {
      final weeks = (days / 7).floor();
      label = '$weeks w ${days % 7}d';
      iconData = Icons.event_rounded;
    } else {
      final months = (days / 30).floor();
      label = '${months}mo ${days % 30}d';
      iconData = Icons.event_rounded;
    }

    if (isPast && !isToday) {
      label = 'Past';
      iconData = Icons.history_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isToday
            ? accentColor.withValues(alpha: 0.15)
            : _cElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        border: isToday
            ? Border.all(color: accentColor.withValues(alpha: 0.3), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 13, color: isToday ? accentColor : _cTextDim),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
              color: isToday ? accentColor : _cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RSVP Chip
// ═══════════════════════════════════════════════════════════════════════

class _RSVPChip extends StatelessWidget {
  const _RSVPChip({
    required this.status,
    required this.accentColor,
    required this.onTap,
  });

  final RSVPStatus status;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      RSVPStatus.going => 'Going ✓',
      RSVPStatus.maybe => 'Maybe ~',
      RSVPStatus.notGoing => 'Can\'t ✕',
      RSVPStatus.none => 'RSVP',
    };

    final bgColor = switch (status) {
      RSVPStatus.going => KinrelColors.success.withValues(alpha: 0.12),
      RSVPStatus.maybe => _cAmber.withValues(alpha: 0.12),
      RSVPStatus.notGoing => KinrelColors.error.withValues(alpha: 0.12),
      RSVPStatus.none => _cElevated,
    };

    final fgColor = switch (status) {
      RSVPStatus.going => KinrelColors.success,
      RSVPStatus.maybe => _cAmber,
      RSVPStatus.notGoing => KinrelColors.error,
      RSVPStatus.none => _cTextSecondary,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fgColor,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Send Wishes Button
// ═══════════════════════════════════════════════════════════════════════

class _SendWishesButton extends StatelessWidget {
  const _SendWishesButton({
    required this.event,
    required this.accentColor,
  });

  final EventModel event;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showWishesSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: KinrelGradients.igniteGradient,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              'Send wishes?',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWishesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => _SendWishesSheet(event: event),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Calendar illustration
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _cOrange.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Calendar base
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 64,
                    color: _cOrange.withValues(alpha: 0.3),
                  ),
                  // Small sparkle
                  Positioned(
                    top: 20,
                    right: 22,
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: _cGold.withValues(alpha: 0.6),
                    ),
                  ),
                  // Small heart
                  Positioned(
                    bottom: 22,
                    left: 22,
                    Icon(
                      Icons.favorite_rounded,
                      size: 16,
                      color: _cAmber.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(duration: 3000.ms, color: _cOrange.withValues(alpha: 0.06)),

            const SizedBox(height: 24),

            Text(
              'No events yet',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Birthdays and anniversaries from your family will appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextSecondary,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Tap + to add a custom event or family reunion.',
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

// ═══════════════════════════════════════════════════════════════════════
// Event Detail Screen
// ═══════════════════════════════════════════════════════════════════════

class _EventDetailScreen extends ConsumerStatefulWidget {
  const _EventDetailScreen({required this.event});

  final EventModel event;

  @override
  ConsumerState<_EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<_EventDetailScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final accentColor = event.accentColor;

    return DKScaffold(
      backgroundColor: _cBg,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero Section with Festival Illustration ──────────────
            _EventHeroSection(event: event, accentColor: accentColor),

            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Large Countdown Timer ─────────────────────────
                  _LargeCountdownWidget(event: event, accentColor: accentColor),

                  const SizedBox(height: 24),

                  // ── Event Info ────────────────────────────────────
                  _InfoRow(
                    icon: Icons.event_rounded,
                    label: event.formattedDate,
                    sublabel: event.formattedTime,
                    accentColor: accentColor,
                  ),
                  if (event.location != null)
                    _InfoRow(
                      icon: Icons.location_on_rounded,
                      label: event.location!,
                      accentColor: accentColor,
                    ),
                  if (event.description != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      event.description!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _cTextSecondary,
                        height: 1.7,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── RSVP List (reunion type) ──────────────────────
                  if (event.type == EventType.reunion) ...[
                    _SectionTitle(
                      title: 'RSVP',
                      icon: Icons.how_to_reg_rounded,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 12),
                    _RSVPListSection(event: event, accentColor: accentColor),
                    const SizedBox(height: 24),
                  ],

                  // ── Related Members ───────────────────────────────
                  if (event.members.isNotEmpty) ...[
                    _SectionTitle(
                      title: 'Related Members',
                      icon: Icons.people_rounded,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 12),
                    _DetailMemberList(members: event.members, accentColor: accentColor),
                    const SizedBox(height: 24),
                  ],

                  // ── Photo Gallery (placeholder) ───────────────────
                  _SectionTitle(
                    title: 'Photos',
                    icon: Icons.photo_library_rounded,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 12),
                  _PhotoGalleryPlaceholder(accentColor: accentColor),

                  const SizedBox(height: 24),

                  // ── Comments Section ──────────────────────────────
                  _SectionTitle(
                    title: 'Comments',
                    icon: Icons.chat_bubble_outline_rounded,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 12),
                  _CommentsSection(event: event, accentColor: accentColor),

                  const SizedBox(height: 24),

                  // ── Action Buttons ────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _ShareEventButton(event: event),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReminderButton(event: event),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero Section ──────────────────────────────────────────────────────

class _EventHeroSection extends StatelessWidget {
  const _EventHeroSection({
    required this.event,
    required this.accentColor,
  });

  final EventModel event;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Hero background gradient
        Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.0,
              colors: [
                accentColor.withValues(alpha: 0.15),
                _cBg,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),

        // Festival-themed illustration
        Positioned.fill(
          child: Center(
            child: Icon(
              event.icon,
              size: 80,
              color: accentColor.withValues(alpha: 0.12),
            ),
          ),
        ),

        // Back button
        Positioned(
          top: 48,
          left: KinrelSpacing.base,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _cCard.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: _cTextPrimary,
                size: 20,
              ),
            ),
          ),
        ),

        // Event type + emoji overlay
        Positioned(
          bottom: 20,
          left: KinrelSpacing.xl,
          right: KinrelSpacing.xl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EventTypeBadge(type: event.type, accentColor: accentColor),
              const SizedBox(height: 10),
              Text(
                event.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _cTextPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Large Countdown Widget ────────────────────────────────────────────

class _LargeCountdownWidget extends StatelessWidget {
  const _LargeCountdownWidget({
    required this.event,
    required this.accentColor,
  });

  final EventModel event;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = event.date.difference(now);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    if (days < 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: _cBorder, width: 1),
        ),
        child: Column(
          children: [
            Text(
              '🎉 This event has passed!',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _cTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.08),
            _cCard,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            days == 0 ? 'HAPPENING TODAY!' : 'COUNTDOWN',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: accentColor,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CountdownUnit(value: days, label: 'Days', accentColor: accentColor),
              const SizedBox(width: 12),
              Text(':',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _cTextDim,
                  )),
              const SizedBox(width: 12),
              _CountdownUnit(value: hours, label: 'Hours', accentColor: accentColor),
              const SizedBox(width: 12),
              Text(':',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _cTextDim,
                  )),
              const SizedBox(width: 12),
              _CountdownUnit(value: minutes, label: 'Min', accentColor: accentColor),
              const SizedBox(width: 12),
              Text(':',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _cTextDim,
                  )),
              const SizedBox(width: 12),
              _CountdownUnit(value: seconds, label: 'Sec', accentColor: accentColor),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single countdown unit (Days/Hours/Min/Sec).
class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({
    required this.value,
    required this.label,
    required this.accentColor,
  });

  final int value;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString().padLeft(2, '0'),
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: _cTextPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: _cTextDim,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

// ── Info Row ──────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(KinrelRadius.sm),
            ),
            child: Icon(icon, size: 16, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _cTextPrimary,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cTextDim,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Title ─────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.accentColor,
  });

  final String title;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accentColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _cTextPrimary,
          ),
        ),
      ],
    );
  }
}

// ── RSVP List Section ─────────────────────────────────────────────────

class _RSVPListSection extends StatelessWidget {
  const _RSVPListSection({
    required this.event,
    required this.accentColor,
  });

  final EventModel event;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        color: _cElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
      ),
      child: Row(
        children: [
          // Avatar row
          ...event.members.take(4).map((m) => Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _SmallAvatar(member: m, size: 32, borderColor: accentColor),
          )),
          if (event.members.length > 4) ...[
            const SizedBox(width: 6),
            Text(
              '+${event.members.length - 4}',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _cTextSecondary,
              ),
            ),
          ],
          const Spacer(),
          // Status counts (demo)
          _RSVPSummaryChip(label: '12 Going', color: KinrelColors.success),
          const SizedBox(width: 6),
          _RSVPSummaryChip(label: '3 Maybe', color: _cAmber),
        ],
      ),
    );
  }
}

class _RSVPSummaryChip extends StatelessWidget {
  const _RSVPSummaryChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

// ── Detail Member List ────────────────────────────────────────────────

class _DetailMemberList extends StatelessWidget {
  const _DetailMemberList({
    required this.members,
    required this.accentColor,
  });

  final List<EventMember> members;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: members.map((m) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _cElevated,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: _cBorder, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmallAvatar(member: m, size: 24, borderColor: accentColor),
              const SizedBox(width: 8),
              Text(
                m.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _cTextPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Photo Gallery Placeholder ─────────────────────────────────────────

class _PhotoGalleryPlaceholder extends StatelessWidget {
  const _PhotoGalleryPlaceholder({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) {
        return Expanded(
          child: Container(
            height: 90,
            margin: EdgeInsets.only(left: index > 0 ? 8 : 0),
            decoration: BoxDecoration(
              color: _cElevated,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(color: _cBorder, width: 0.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  color: _cTextDim,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  index == 0 ? 'Add Photo' : '',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 9,
                    color: _cTextDim,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ── Comments Section ──────────────────────────────────────────────────

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({
    required this.event,
    required this.accentColor,
  });

  final EventModel event;
  final Color accentColor;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comments = widget.event.comments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No comments yet. Be the first to wish!',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _cTextDim,
              ),
            ),
          )
        else
          ...comments.map((c) => _CommentTile(comment: c, accentColor: widget.accentColor)),

        const SizedBox(height: 12),

        // Comment input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: _cTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: _cTextDim,
                  ),
                  filled: true,
                  fillColor: _cElevated,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KinrelRadius.xl),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (_commentController.text.trim().isNotEmpty) {
                  // In production, this would call the notifier
                  _commentController.clear();
                  FocusScope.of(context).unfocus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Comment posted!'),
                      backgroundColor: _cCard,
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: KinrelGradients.igniteGradient,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.accentColor,
  });

  final EventComment comment;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallAvatar(member: comment.author, size: 28, borderColor: accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.author.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _cTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comment.text,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: _cTextSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Share Event Button ────────────────────────────────────────────────

class _ShareEventButton extends StatelessWidget {
  const _ShareEventButton({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share event coming soon!'),
            backgroundColor: _cCard,
          ),
        );
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: _cBorder, width: 1),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.share_rounded, color: _cTextSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Share Event',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _cTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reminder Button ───────────────────────────────────────────────────

class _ReminderButton extends StatelessWidget {
  const _ReminderButton({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: _cCard,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KinrelRadius.bottomSheet),
            ),
          ),
          builder: (ctx) => _ReminderSettingsSheet(event: event),
        );
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: KinrelGradients.igniteGradient,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              'Set Reminder',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Reminder Settings Sheet
// ═══════════════════════════════════════════════════════════════════════

class _ReminderSettingsSheet extends ConsumerWidget {
  const _ReminderSettingsSheet({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = event.accentColor;
    final notifier = ref.read(eventsProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.xl,
        right: KinrelSpacing.xl,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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

          Text(
            'Reminder Settings',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose when to be reminded about this event',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _cTextDim,
            ),
          ),
          const SizedBox(height: 24),

          // Reminder options
          ...ReminderTiming.values.map((timing) {
            final isActive = event.reminderTimings.contains(timing);
            return _ReminderOption(
              timing: timing,
              isActive: isActive,
              accentColor: accentColor,
              onToggle: () => notifier.toggleReminder(event.id, timing),
            );
          }),
        ],
      ),
    );
  }
}

class _ReminderOption extends StatelessWidget {
  const _ReminderOption({
    required this.timing,
    required this.isActive,
    required this.accentColor,
    required this.onToggle,
  });

  final ReminderTiming timing;
  final bool isActive;
  final Color accentColor;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final (label, subtitle, icon) = switch (timing) {
      ReminderTiming.oneWeekBefore =>
        ('1 Week Before', 'Get notified 7 days ahead', Icons.event_rounded),
      ReminderTiming.oneDayBefore =>
        ('1 Day Before', 'Reminder 24 hours before', Icons.today_rounded),
      ReminderTiming.dayOf =>
        ('Day of Event', 'Morning reminder on the day', Icons.alarm_rounded),
      ReminderTiming.custom =>
        ('Custom', 'Set a custom reminder time', Icons.schedule_rounded),
    };

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? accentColor.withValues(alpha: 0.08) : _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: isActive
                ? accentColor.withValues(alpha: 0.25)
                : _cBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive
                    ? accentColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(KinrelRadius.sm),
              ),
              child: Icon(icon, size: 18, color: isActive ? accentColor : _cTextDim),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isActive ? _cTextPrimary : _cTextSecondary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cTextDim,
                    ),
                  ),
                ],
              ),
            ),
            // Toggle indicator
            AnimatedContainer(
              duration: KinrelMotion.fast,
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                color: isActive ? accentColor : _cBorder,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: KinrelMotion.fast,
                alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RSVP Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════

class _RSVPBottomSheet extends ConsumerWidget {
  const _RSVPBottomSheet({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(eventsProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.xl,
        right: KinrelSpacing.xl,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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

          Text(
            'RSVP — ${event.name}',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
            ),
          ),
          const SizedBox(height: 20),

          _RSVPOption(
            label: 'Going',
            icon: Icons.check_circle_rounded,
            color: KinrelColors.success,
            isSelected: event.rsvpStatus == RSVPStatus.going,
            onTap: () {
              notifier.updateRSVP(event.id, RSVPStatus.going);
              Navigator.pop(context);
            },
          ),
          _RSVPOption(
            label: 'Maybe',
            icon: Icons.help_outline_rounded,
            color: _cAmber,
            isSelected: event.rsvpStatus == RSVPStatus.maybe,
            onTap: () {
              notifier.updateRSVP(event.id, RSVPStatus.maybe);
              Navigator.pop(context);
            },
          ),
          _RSVPOption(
            label: 'Can\'t Go',
            icon: Icons.cancel_rounded,
            color: KinrelColors.error,
            isSelected: event.rsvpStatus == RSVPStatus.notGoing,
            onTap: () {
              notifier.updateRSVP(event.id, RSVPStatus.notGoing);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _RSVPOption extends StatelessWidget {
  const _RSVPOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.3) : _cBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: isSelected ? color : _cTextDim),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? color : _cTextSecondary,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_rounded, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Send Wishes Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════

class _SendWishesSheet extends StatelessWidget {
  const _SendWishesSheet({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    // Build quick message options
    final options = <String>[];
    switch (event.type) {
      case EventType.birthday:
        final name = event.members.firstOrNull?.name?.split(' ').firstOrNull ?? 'dear';
        options.addAll([
          'Happy Birthday, $name! 🎂 Wishing you an amazing year ahead!',
          'Wishing you a wonderful birthday filled with joy and laughter! 🎉',
          'Happy Birthday! May all your dreams come true this year! ✨',
        ]);
      case EventType.anniversary:
        options.addAll([
          'Happy Anniversary! 💍 Wishing you many more years of love and happiness!',
          'Congratulations on another year of togetherness! ❤️',
          'May your bond grow stronger with each passing year! 🥂',
        ]);
      default:
        options.add('Wishing you a wonderful ${event.name}! 🎉');
    }

    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.xl,
        right: KinrelSpacing.xl,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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

          Text(
            'Send Wishes ${event.emoji}',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _cTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a message or write your own',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _cTextDim,
            ),
          ),
          const SizedBox(height: 20),

          // Quick message options
          ...options.map((msg) => _WishOption(
            message: msg,
            accentColor: event.accentColor,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Wishes sent! 🎉'),
                  backgroundColor: _cCard,
                ),
              );
            },
          )),

          const SizedBox(height: 12),

          // Custom message input
          TextField(
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _cTextPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Write your own message...',
              hintStyle: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _cTextDim,
              ),
              filled: true,
              fillColor: _cElevated,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.send_rounded, color: _cOrange, size: 20),
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Custom wishes sent! 🎉'),
                      backgroundColor: _cCard,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WishOption extends StatelessWidget {
  const _WishOption({
    required this.message,
    required this.accentColor,
    required this.onTap,
  });

  final String message;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: _cTextSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.send_rounded, size: 16, color: accentColor),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Create Event Sheet
// ═══════════════════════════════════════════════════════════════════════

class _CreateEventSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends ConsumerState<_CreateEventSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  EventType _selectedType = EventType.custom;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  bool _isAllDay = true;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: KinrelSpacing.xl,
        right: KinrelSpacing.xl,
        top: KinrelSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + KinrelSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

            Text(
              'Create New Event',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _cTextPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // Event type selector
            Text(
              'Event Type',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: EventType.values.map((type) {
                final isSelected = _selectedType == type;
                final accentColor = _typeAccentColor(type);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedType = type),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accentColor.withValues(alpha: 0.12)
                            : _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                        border: Border.all(
                          color: isSelected
                              ? accentColor.withValues(alpha: 0.3)
                              : _cBorder,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _typeIcon(type),
                            size: 18,
                            color: isSelected ? accentColor : _cTextDim,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _typeLabel(type),
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? accentColor
                                  : _cTextDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Event name
            _InputField(
              controller: _nameController,
              hintText: 'Event name',
              icon: Icons.event_note_rounded,
            ),
            const SizedBox(height: 10),

            // Description
            _InputField(
              controller: _descController,
              hintText: 'Description (optional)',
              icon: Icons.description_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 10),

            // Location
            _InputField(
              controller: _locationController,
              hintText: 'Location (optional)',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 16),

            // Date picker row
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: ColorScheme.dark(
                              primary: _cOrange,
                              surface: _cCard,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _cElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.md),
                        border: Border.all(color: _cBorder, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 16, color: _cTextDim),
                          const SizedBox(width: 10),
                          Text(
                            '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              color: _cTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // All day toggle
                GestureDetector(
                  onTap: () => setState(() => _isAllDay = !_isAllDay),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _isAllDay
                          ? _cOrange.withValues(alpha: 0.1)
                          : _cElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: Border.all(
                        color: _isAllDay
                            ? _cOrange.withValues(alpha: 0.3)
                            : _cBorder,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: _isAllDay ? _cOrange : _cTextDim,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isAllDay ? 'All Day' : 'Set Time',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _isAllDay ? _cOrange : _cTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Create button
            GestureDetector(
              onTap: () {
                if (_nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please enter an event name'),
                      backgroundColor: _cCard,
                    ),
                  );
                  return;
                }
                final newEvent = EventModel(
                  id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                  name: _nameController.text.trim(),
                  type: _selectedType,
                  date: _selectedDate,
                  description: _descController.text.trim().isNotEmpty
                      ? _descController.text.trim()
                      : null,
                  location: _locationController.text.trim().isNotEmpty
                      ? _locationController.text.trim()
                      : null,
                  isAllDay: _isAllDay,
                  isAutoGenerated: false,
                  reminderTimings: [ReminderTiming.oneDayBefore, ReminderTiming.dayOf],
                );
                ref.read(eventsProvider.notifier).addEvent(newEvent);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Event created! 🎉'),
                    backgroundColor: _cCard,
                  ),
                );
              },
              child: Container(
                height: 52,
                width: double.infinity,
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
                  'Create Event',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeAccentColor(EventType type) => switch (type) {
    EventType.birthday => _cOrange,
    EventType.anniversary => _cAmber,
    EventType.festival => _cGold,
    EventType.reunion => _cOrange,
    EventType.custom => _cTextSecondary,
  };

  IconData _typeIcon(EventType type) => switch (type) {
    EventType.birthday => Icons.cake_rounded,
    EventType.anniversary => Icons.favorite_rounded,
    EventType.reunion => Icons.groups_rounded,
    EventType.festival => Icons.celebration_rounded,
    EventType.custom => Icons.event_rounded,
  };

  String _typeLabel(EventType type) => switch (type) {
    EventType.birthday => 'Birthday',
    EventType.anniversary => 'Anniv.',
    EventType.reunion => 'Reunion',
    EventType.festival => 'Festival',
    EventType.custom => 'Custom',
  };
}

// ═══════════════════════════════════════════════════════════════════════
// Input Field Helper
// ═══════════════════════════════════════════════════════════════════════

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 14,
        color: _cTextPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: _cTextDim,
        ),
        prefixIcon: Icon(icon, size: 18, color: _cTextDim),
        filled: true,
        fillColor: _cElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide(color: _cOrange.withValues(alpha: 0.4), width: 1),
        ),
      ),
    );
  }
}
