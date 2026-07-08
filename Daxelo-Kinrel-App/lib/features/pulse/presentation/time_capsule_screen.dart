// lib/features/pulse/presentation/time_capsule_screen.dart
//
// A-2 Time Capsule screen — shows locked + revealed capsules.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';

class TimeCapsuleScreen extends ConsumerWidget {
  const TimeCapsuleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capsulesAsync = ref.watch(capsulesForMeProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text('Time Capsule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: KinrelColors.tealAccent),
            onPressed: () => _showCreateDialog(context, ref),
            tooltip: 'Create time capsule',
          ),
        ],
      ),
      body: capsulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.tealAccent)),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
        data: (capsules) {
          if (capsules.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⏰', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    const Text('No time capsules', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      'Lock a message for a future date —\nyour child\'s 18th birthday, a wedding,\nor after you\'re gone.',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateDialog(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create one'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KinrelColors.tealAccent,
                        foregroundColor: KinrelColors.darkBackground,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          // Sort: revealed first, then locked by reveal date
          final sorted = List<TimeCapsule>.from(capsules)
            ..sort((a, b) {
              if (a.isRevealed != b.isRevealed) return a.isRevealed ? -1 : 1;
              return a.revealAt.compareTo(b.revealAt);
            });
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            itemBuilder: (context, i) => _CapsuleCard(capsule: sorted[i]),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    // For MVP, navigate to a create route. A full form would be a separate screen.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Time capsule creation form — coming in next iteration. Use POST /api/addictiveness/time-capsules for now.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

class _CapsuleCard extends ConsumerWidget {
  final TimeCapsule capsule;

  const _CapsuleCard({required this.capsule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocked = capsule.isLocked;
    final isRevealed = capsule.status == 'revealed';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked
              ? KinrelColors.tealAccent.withOpacity(0.2)
              : (isRevealed ? KinrelColors.success.withOpacity(0.3) : Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isLocked ? '🔒' : '✉️', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  capsule.title,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (isRevealed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KinrelColors.success,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (isLocked) ...[
            // Locked: show countdown
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.tealAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock, color: KinrelColors.tealAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      capsule.countdownDays > 0
                          ? 'Unlocks in ${capsule.countdownDays} day${capsule.countdownDays == 1 ? '' : 's'}'
                          : 'Unlocks soon',
                      style: const TextStyle(color: KinrelColors.tealAccent, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            if (capsule.revealReason != null) ...[
              const SizedBox(height: 8),
              Text(
                'Purpose: ${capsule.revealReason}',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ] else ...[
            // Revealed: show content
            if (capsule.textContent != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  capsule.textContent!,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                ),
              ),
            if (capsule.mediaUrl != null && capsule.mediaType != 'text') ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: capsule.mediaType == 'photo'
                    ? Image.network(capsule.mediaUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                        Container(height: 120, color: Colors.white.withOpacity(0.05), child: const Center(child: Icon(Icons.broken_image, color: Colors.white30))))
                    : Container(
                        height: 80,
                        color: KinrelColors.darkElevated,
                        child: const Center(child: Icon(Icons.play_circle_fill, color: KinrelColors.tealAccent, size: 40)),
                      ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (capsule.creator != null)
                  Text(
                    'From ${capsule.creator!.name}',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                const Spacer(),
                if (capsule.status == 'revealed')
                  TextButton(
                    onPressed: () async {
                      await ref.read(pulseApiClientProvider).markCapsuleViewed(capsule.id);
                      ref.invalidate(capsulesForMeProvider);
                    },
                    child: const Text('Mark viewed', style: TextStyle(color: KinrelColors.tealAccent, fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
