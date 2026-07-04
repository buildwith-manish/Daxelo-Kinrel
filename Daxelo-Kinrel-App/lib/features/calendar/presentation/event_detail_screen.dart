// lib/features/calendar/presentation/event_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../models/calendar_models.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.familyId, required this.event});
  final String familyId;
  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(event.category.colorValue);
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: CustomScrollView(slivers: [
        // Hero header
        SliverAppBar(expandedHeight: 200, pinned: true,
          backgroundColor: color.withValues(alpha: 0.3),
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
          actions: [IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.white), onPressed: () => context.push('/family/$familyId/calendar/new', extra: event))],
          flexibleSpace: FlexibleSpaceBar(
            title: Text(event.title, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w700, color: Colors.white, fontSize: 16)),
            background: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withValues(alpha: 0.4), KinrelColors.darkCard]))),
          ),
        ),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(KinrelSpacing.base), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Category + countdown
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [Text(event.category.icon, style: TextStyle(fontSize: 14)), const SizedBox(width: 6), Text(event.category.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))])),
            const Spacer(),
            if (event.isUpcoming)
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: event.isToday ? color : color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Text(event.countdownLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: event.isToday ? Colors.white : color))),
          ]),
          const SizedBox(height: 20),
          // Date
          _DetailRow(icon: Icons.calendar_today_outlined, label: 'Date', value: '${event.eventDate.month}/${event.eventDate.day}/${event.eventDate.year}'),
          if (event.location != null && event.location!.isNotEmpty) ...[const SizedBox(height: 12), _DetailRow(icon: Icons.location_on_outlined, label: 'Location', value: event.location!)],
          if (event.isRecurring) ...[const SizedBox(height: 12), _DetailRow(icon: Icons.repeat_rounded, label: 'Repeats', value: event.recurrenceRule ?? 'Custom')],
          if (event.description != null && event.description!.isNotEmpty) ...[const SizedBox(height: 20),
            Text('Notes', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
              child: Text(event.description!, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textSilver, height: 1.5))),
          ],
          const SizedBox(height: 20),
          // RSVP
          Text('RSVP', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
          const SizedBox(height: 8),
          Row(children: [
            _RSVPButton(label: 'Going', color: KinrelColors.success, onTap: () => ref.read(calendarProvider(familyId).notifier).submitRSVP(event.id, RSVPStatus.going)),
            const SizedBox(width: 8),
            _RSVPButton(label: 'Maybe', color: KinrelColors.amber, onTap: () => ref.read(calendarProvider(familyId).notifier).submitRSVP(event.id, RSVPStatus.maybe)),
            const SizedBox(width: 8),
            _RSVPButton(label: 'Can\'t', color: KinrelColors.error, onTap: () => ref.read(calendarProvider(familyId).notifier).submitRSVP(event.id, RSVPStatus.notGoing)),
          ]),
        ]))),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});
  final IconData icon; final String label; final String value;
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: KinrelColors.orange),
    const SizedBox(width: 10),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: KinrelColors.textDim, fontWeight: FontWeight.w500)),
      Text(value, style: TextStyle(fontSize: 14, color: KinrelColors.textWhite, fontWeight: FontWeight.w500)),
    ]),
  ]);
}

class _RSVPButton extends StatelessWidget {
  const _RSVPButton({required this.label, required this.color, required this.onTap});
  final String label; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Center(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))))));
}
