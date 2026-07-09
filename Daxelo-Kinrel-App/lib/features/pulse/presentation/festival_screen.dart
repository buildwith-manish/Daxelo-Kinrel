// lib/features/pulse/presentation/festival_screen.dart
//
// A-6 Festival Intelligence screen — upcoming + today's festivals.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';

class FestivalScreen extends ConsumerWidget {
  const FestivalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final festivalsAsync = ref.watch(upcomingFestivalsProvider);
    final todayAsync = ref.watch(festivalsTodayProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text('Festivals', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Today's festivals
          todayAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (today) {
              if (today.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🎉 Today',
                    style: TextStyle(color: KinrelColors.brightGold, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  ...today.map((f) => _TodayFestivalCard(festival: f)),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
          // Upcoming festivals
          const Text(
            '📅 Upcoming',
            style: TextStyle(color: KinrelColors.amber, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          festivalsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.brightGold)),
            error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
            data: (festivals) {
              if (festivals.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No upcoming festivals in the next 90 days.',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return Column(
                children: festivals.map((f) => _FestivalCard(festival: f)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TodayFestivalCard extends StatelessWidget {
  final Festival festival;
  const _TodayFestivalCard({required this.festival});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.brightGold.withOpacity(0.15),
            KinrelColors.orange.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinrelColors.brightGold.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🪔', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  festival.nameForLanguage('en'),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            festival.greetingForLanguage('en'),
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontStyle: FontStyle.italic),
          ),
          if (festival.description != null) ...[
            const SizedBox(height: 8),
            Text(
              festival.description!,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _FestivalCard extends StatelessWidget {
  final Festival festival;
  const _FestivalCard({required this.festival});

  @override
  Widget build(BuildContext context) {
    final daysWord = festival.daysUntil == 0
        ? 'Today'
        : festival.daysUntil == 1
            ? 'Tomorrow'
            : '${festival.daysUntil} days';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KinrelColors.amber.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          // Days until badge
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: KinrelColors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${festival.daysUntil}',
                  style: const TextStyle(color: KinrelColors.amber, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  'days',
                  style: TextStyle(color: KinrelColors.amber.withOpacity(0.7), fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  festival.nameForLanguage('en'),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      festival.festivalDate,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    if (festival.region != 'all')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          festival.region,
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Text(daysWord, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
        ],
      ),
    );
  }
}
