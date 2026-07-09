// lib/features/pulse/presentation/memorials_screen.dart
//
// Pitru Pt-4 Memorials screen — list of deceased family members with living memorials.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';

class MemorialsScreen extends ConsumerWidget {
  final String familyId;

  const MemorialsScreen({super.key, required this.familyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memorialsAsync = ref.watch(memorialsProvider(familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text('In Memoriam', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: memorialsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.extendedPurple)),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
        data: (memorials) {
          if (memorials.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🪔', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    const Text('No memorials yet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      'When a family member passes, their memorial\nappears here with all their voice memories.\nTheir stories live on.',
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
            itemCount: memorials.length,
            itemBuilder: (context, i) => _MemorialCard(memorial: memorials[i]),
          );
        },
      ),
    );
  }
}

class _MemorialCard extends StatelessWidget {
  final MemorialProfile memorial;

  const _MemorialCard({required this.memorial});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.extendedPurple.withOpacity(0.12),
            KinrelColors.darkCard,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinrelColors.extendedPurple.withOpacity(0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/pulse/memorial/${memorial.personId}'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Photo + name
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: KinrelColors.extendedPurple.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: KinrelColors.extendedPurple.withOpacity(0.4), width: 2),
                      ),
                      child: memorial.person.photoThumb != null
                          ? ClipOval(child: Image.network(memorial.person.photoThumb!, fit: BoxFit.cover))
                          : const Center(child: Text('🪔', style: TextStyle(fontSize: 28))),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memorial.person.name,
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          if (memorial.birthDate != null || memorial.deathDate != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${memorial.birthDate ?? '?'} — ${memorial.deathDate ?? '?'}',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
                  ],
                ),
                const SizedBox(height: 16),
                // Memorial title
                if (memorial.memorialTitle != null)
                  Text(
                    memorial.memorialTitle!,
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Stat(icon: '🎤', label: 'Memories', value: memorial.memoryCount),
                    _Stat(icon: '🎧', label: 'Listens', value: memorial.totalListens),
                    if (memorial.aiPersonaEnabled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: KinrelColors.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: KinrelColors.gold.withOpacity(0.3)),
                        ),
                        child: const Text('AI Persona', style: TextStyle(color: KinrelColors.gold, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String icon;
  final String label;
  final int value;
  const _Stat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text('$value', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
      ],
    );
  }
}
