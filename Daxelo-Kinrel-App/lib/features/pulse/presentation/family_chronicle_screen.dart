// lib/features/pulse/presentation/family_chronicle_screen.dart
//
// A-7 Family Chronicle screen — AI-written family history book.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';

class FamilyChronicleScreen extends ConsumerWidget {
  final bool embedded;
  final String familyId;

  const FamilyChronicleScreen({super.key, this.embedded = false, required this.familyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chronicleAsync = ref.watch(chronicleProvider(familyId));

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text('Family Chronicle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: KinrelColors.blue),
            onPressed: () async {
              await ref.read(pulseApiClientProvider).generateChronicle(familyId);
              ref.invalidate(chronicleProvider(familyId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chronicle updated 📖'),
                    backgroundColor: KinrelColors.blue,
                  ),
                );
              }
            },
            tooltip: 'Regenerate chronicle',
          ),
        ],
      ),
      body: chronicleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.blue)),
        error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
        data: (chronicle) {
          if (chronicle == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📖', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    const Text('No chronicle yet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      'Generate your family\'s chronicle —\na beautifully written history book\nthat updates monthly.',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await ref.read(pulseApiClientProvider).generateChronicle(familyId);
                        ref.invalidate(chronicleProvider(familyId));
                      },
                      icon: const Icon(Icons.auto_stories, size: 18),
                      label: const Text('Generate chronicle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KinrelColors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return _ChronicleContent(chronicle: chronicle);
        },
      ),
    );
  }
}

class _ChronicleContent extends StatelessWidget {
  final FamilyChronicle chronicle;

  const _ChronicleContent({required this.chronicle});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Cover ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                KinrelColors.blue.withOpacity(0.15),
                KinrelColors.extendedPurple.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: KinrelColors.blue.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              const Text('📖', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                chronicle.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              if (chronicle.subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  chronicle.subtitle!,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(label: 'Chapters', value: '${chronicle.chapterCount}'),
                  if (chronicle.lastGeneratedAt != null)
                    _Stat(
                      label: 'Updated',
                      value: '${chronicle.lastGeneratedAt!.day}/${chronicle.lastGeneratedAt!.month}',
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Chapters ───────────────────────────────────────────────────
        ...chronicle.chapters.map((ch) => _ChapterCard(chapter: ch)),

        const SizedBox(height: 32),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: KinrelColors.blue, fontSize: 18, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
      ],
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final ChronicleChapter chapter;

  const _ChapterCard({required this.chapter});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chapter number + title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KinrelColors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Ch. ${chapter.chapterNumber}',
                  style: const TextStyle(color: KinrelColors.blue, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chapter.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Content
          Text(
            chapter.content,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.7),
          ),
        ],
      ),
    );
  }
}
