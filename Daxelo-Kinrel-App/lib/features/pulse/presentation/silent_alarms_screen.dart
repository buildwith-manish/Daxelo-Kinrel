// lib/features/pulse/presentation/silent_alarms_screen.dart
//
// A-4 Silent Alarms screen — private nudges for the family bridge role.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';

class SilentAlarmsScreen extends ConsumerWidget {
  const SilentAlarmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(silentAlarmsProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text('Silent Alarms', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
        ),
      ),
      body: alarmsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.coral)),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
        data: (alarms) {
          if (alarms.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🔔', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    const Text('All clear', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      'No one in your family has gone quiet.\nAs the family bridge, you\'ll be notified\nhere if someone needs a check-in.',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alarms.length,
            itemBuilder: (context, i) => _AlarmCard(alarm: alarms[i]),
          );
        },
      ),
    );
  }
}

class _AlarmCard extends ConsumerWidget {
  final SilentAlarm alarm;

  const _AlarmCard({required this.alarm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severityColor = alarm.severity == 'urgent'
        ? KinrelColors.coral
        : alarm.severity == 'moderate'
            ? KinrelColors.amber
            : KinrelColors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: severityColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(alarm.severityEmoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alarm.inactivePerson?.name ?? 'A family member',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Quiet for ${alarm.daysInactive} day${alarm.daysInactive == 1 ? '' : 's'}',
                      style: TextStyle(color: severityColor, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              // Severity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: severityColor.withOpacity(0.4)),
                ),
                child: Text(
                  alarm.severity.toUpperCase(),
                  style: TextStyle(color: severityColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Alarm message
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: severityColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              alarm.alarmMessage,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
          ),
          // Suggestions
          if (alarm.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Suggestions:',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (alarm.suggestions as List).map((s) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.toString(),
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ],
          // Action row
          const SizedBox(height: 12),
          Row(
            children: [
              if (alarm.status == 'triggered' || alarm.status == 'escalated')
                ElevatedButton(
                  onPressed: () async {
                    await ref.read(pulseApiClientProvider).acknowledgeAlarm(alarm.id);
                    ref.invalidate(silentAlarmsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Alarm acknowledged. Thank you for reaching out 💜'),
                          backgroundColor: KinrelColors.success,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: severityColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('I\'ll reach out', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              if (alarm.status == 'acknowledged') ...[
                Icon(Icons.check_circle, color: KinrelColors.success, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Acknowledged',
                  style: TextStyle(color: KinrelColors.success, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
              if (alarm.status == 'resolved') ...[
                Icon(Icons.check_circle, color: KinrelColors.success, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Resolved — they\'re back!',
                  style: TextStyle(color: KinrelColors.success, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
