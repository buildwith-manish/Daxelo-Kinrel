// lib/features/pulse/presentation/addictiveness_hub_screen.dart
//
// DAXELO KINREL — Addictiveness Features Hub
//
// A single screen that links to all 7 addictiveness features:
//   🌅 Daily Brief (Pulse)
//   🎁 Blessing Chain (A-1)
//   ⏰ Time Capsule (A-2)
//   ✨ Family Quests (A-3)
//   🔔 Silent Alarms (A-4)
//   👵 Memorial (Pitru Pt-4)
//   🪔 Festival Intelligence (A-6)
//   📖 Family Chronicle (A-7)
//
// This is the entry point from the home screen — a single "Family Intelligence"
// card that opens this hub.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../providers/pulse_providers.dart';

class AddictivenessHubScreen extends ConsumerWidget {
  const AddictivenessHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text(
          'Family Intelligence',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _HubCard(
            emoji: '🌅',
            title: 'Daily Brief',
            subtitle: 'Your family intelligence, every morning',
            route: '/pulse/today',
            color: KinrelColors.orange,
          ),
          const SizedBox(height: 12),
          _HubCard(
            emoji: '✨',
            title: 'Family Quests',
            subtitle: 'Weekly missions to strengthen weak relationships',
            route: '/pulse/quests',
            color: KinrelColors.amber,
            badgeProvider: activeQuestsProvider,
          ),
          const SizedBox(height: 12),
          _HubCard(
            emoji: '🔔',
            title: 'Silent Alarms',
            subtitle: 'Private nudges when someone goes quiet',
            route: '/pulse/alarms',
            color: KinrelColors.coral,
            badgeProvider: silentAlarmsProvider,
          ),
          const SizedBox(height: 12),
          _HubCard(
            emoji: '🎁',
            title: 'Blessing Chain',
            subtitle: 'Elder blessings, delivered on birthdays & festivals',
            route: '/pulse/blessings',
            color: KinrelColors.gold,
            badgeProvider: blessingsForMeProvider,
          ),
          const SizedBox(height: 12),
          _HubCard(
            emoji: '⏰',
            title: 'Time Capsule',
            subtitle: 'Messages locked for future dates',
            route: '/pulse/time-capsules',
            color: KinrelColors.tealAccent,
            badgeProvider: capsulesForMeProvider,
          ),
          const SizedBox(height: 12),
          const _HubCard(
            emoji: '🪔',
            title: 'Festivals',
            subtitle: 'Indian festival calendar with 8-language greetings',
            route: '/pulse/festivals',
            color: KinrelColors.brightGold,
          ),
          const SizedBox(height: 12),
          const _HubCard(
            emoji: '👵',
            title: 'Memorials',
            subtitle: 'Living memorials for ancestors',
            route: '/pulse/memorials',
            color: KinrelColors.extendedPurple,
          ),
          const SizedBox(height: 12),
          const _HubCard(
            emoji: '📖',
            title: 'Family Chronicle',
            subtitle: 'The story of your family, written by AI',
            route: '/pulse/chronicle',
            color: KinrelColors.blue,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// A hub card with optional badge count (from a provider).
class _HubCard extends ConsumerWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String route;
  final Color color;
  final ProviderBase<dynamic>? badgeProvider;

  const _HubCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.color,
    this.badgeProvider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int? badgeCount;
    if (badgeProvider != null) {
      final asyncValue = ref.watch(badgeProvider!);
      asyncValue.whenData((value) {
        if (value is List) badgeCount = value.length;
      });
    }

    return Material(
      color: KinrelColors.darkCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(route),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              // Emoji icon with colored background
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 14),
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Badge count (if any)
              if (badgeCount != null && badgeCount! > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
