// lib/graph/widgets/on_this_day_badge.dart
//
// DAXELO KINREL — "On this day" Badge (P3.7)
//
// Per Vision §2.6 #1 + §5 Layer 2 success criteria — surface memories,
// birthdays, and anniversaries that happen on this day directly in the
// graph as a small badge on the relevant node.
//
// Badge types:
//   birthday    — cake icon, ember color (#E8612A)
//   anniversary — heart icon, gold color (#FFD700)
//   memory      — photo icon, blue color (#4A90E2)
//
// Reduced motion: badges are static (no pulse).
// Semantics: "[Name] has a birthday today." etc.

import 'package:flutter/material.dart';

import '../../core/constants/brand_colors.dart';

/// The type of "on this day" event.
enum OnThisDayEventType { birthday, anniversary, memory }

/// A single "on this day" event for a person.
class OnThisDayEvent {
  const OnThisDayEvent({
    required this.personId,
    required this.type,
    this.year,
    this.title,
    this.description,
  });

  final String personId;
  final OnThisDayEventType type;
  final int? year;
  final String? title;
  final String? description;

  String get semanticsLabel {
    switch (type) {
      case OnThisDayEventType.birthday:
        return 'Birthday today';
      case OnThisDayEventType.anniversary:
        return 'Anniversary today';
      case OnThisDayEventType.memory:
        return 'Memory from this day${year != null ? ' in $year' : ''}';
    }
  }

  IconData get icon {
    switch (type) {
      case OnThisDayEventType.birthday:
        return Icons.cake_outlined;
      case OnThisDayEventType.anniversary:
        return Icons.favorite_outline;
      case OnThisDayEventType.memory:
        return Icons.photo_outlined;
    }
  }

  Color get color {
    switch (type) {
      case OnThisDayEventType.birthday:
        return const Color(0xFFE8612A); // ember
      case OnThisDayEventType.anniversary:
        return const Color(0xFFFFD700); // gold
      case OnThisDayEventType.memory:
        return const Color(0xFF4A90E2); // blue
    }
  }
}

/// A small 24x24 badge that appears at the top-right of a node.
class OnThisDayBadge extends StatelessWidget {
  const OnThisDayBadge({
    super.key,
    required this.event,
    required this.personName,
    required this.onTap,
  });

  final OnThisDayEvent event;
  final String personName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$personName ${event.semanticsLabel.toLowerCase()}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: KinrelColors.darkCard.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            border: Border.all(color: event.color, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(event.icon, size: 14, color: event.color),
        ),
      ),
    );
  }
}

/// Bottom sheet showing the details of an "on this day" event.
void showOnThisDayEventSheet(
  BuildContext context,
  OnThisDayEvent event,
  String personName,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: KinrelColors.darkCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(event.icon, color: event.color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    event.title ?? event.semanticsLabel,
                    style: const TextStyle(
                      color: KinrelColors.textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              personName,
              style: const TextStyle(color: KinrelColors.textWhite, fontSize: 16),
            ),
            if (event.year != null) ...[
              const SizedBox(height: 8),
              Text(
                'From ${event.year}',
                style: TextStyle(
                  color: KinrelColors.textWhite.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
            if (event.description != null) ...[
              const SizedBox(height: 12),
              Text(
                event.description!,
                style: TextStyle(
                  color: KinrelColors.textWhite.withValues(alpha: 0.85),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
