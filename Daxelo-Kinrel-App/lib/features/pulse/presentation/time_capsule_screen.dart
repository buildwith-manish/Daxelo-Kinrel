// lib/features/pulse/presentation/time_capsule_screen.dart
//
// A-2 Time Capsule screen — shows locked + revealed capsules.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/networking/dio_client.dart';
import '../../trackc/presentation/providers/trackc_providers.dart';
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TimeCapsuleCreateSheet(parentContext: context, ref: ref),
    );
  }
}

class _TimeCapsuleCreateSheet extends StatefulWidget {
  final BuildContext parentContext;
  final WidgetRef ref;

  const _TimeCapsuleCreateSheet({required this.parentContext, required this.ref});

  @override
  State<_TimeCapsuleCreateSheet> createState() => _TimeCapsuleCreateSheetState();
}

class _TimeCapsuleCreateSheetState extends State<_TimeCapsuleCreateSheet> {
  final _messageController = TextEditingController();
  DateTime? _revealDate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a message.')),
      );
      return;
    }
    if (_revealDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a reveal date.')),
      );
      return;
    }
    if (_revealDate!.isBefore(DateTime.now().add(const Duration(days: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reveal date must be at least 1 day in the future.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = widget.ref.read(supabaseProvider);
      if (client == null) throw Exception('Not authenticated');

      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      // POST to the addictiveness backend
      final dio = widget.ref.read(dioProvider);
      await dio.post(
        '/api/addictiveness/time-capsules',
        data: {
          'familyId': widget.ref.read(selectedFamilyIdProvider),
          'senderId': userId,
          'recipientId': userId, // Self-addressed by default; UI could add recipient picker
          'revealAt': _revealDate!.toIso8601String(),
          'message': _messageController.text.trim(),
        },
      );

      // Invalidate the list provider so the new capsule appears
      widget.ref.invalidate(capsulesForMeProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(
            content: Text('Time capsule sealed! It will open on the chosen date.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Seal a Time Capsule',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Write a message to the future. It locks until the reveal date.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _messageController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Dear future family...',
              hintStyle: TextStyle(color: Colors.white38),
              filled: true,
              fillColor: KinrelColors.darkElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Reveal date picker
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime.now().add(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                initialDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked != null) setState(() => _revealDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: KinrelColors.tealAccent, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _revealDate == null
                        ? 'Pick a reveal date'
                        : 'Reveals on ${_revealDate!.day}/${_revealDate!.month}/${_revealDate!.year}',
                    style: TextStyle(color: _revealDate == null ? Colors.white38 : Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.tealAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Seal Capsule', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
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
