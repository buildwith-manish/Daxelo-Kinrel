// lib/features/pulse/presentation/family_quests_screen.dart
//
// A-3 Family Suggestions screen — shows active weekly suggestions + history.
// P1.2: Renamed from "Quests" to "Suggestions". Removed countdown timer,
// "expired" badge, and guilt language. Karma is fixed at 10 per suggestion.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';

class FamilyQuestsScreen extends ConsumerStatefulWidget {
  const FamilyQuestsScreen({super.key});

  @override
  ConsumerState<FamilyQuestsScreen> createState() => _FamilyQuestsScreenState();
}

class _FamilyQuestsScreenState extends ConsumerState<FamilyQuestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text('Family Suggestions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KinrelColors.orange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.4),
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ActiveQuestsTab(),
          _QuestHistoryTab(),
        ],
      ),
    );
  }
}

class _ActiveQuestsTab extends ConsumerWidget {
  const _ActiveQuestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questsAsync = ref.watch(activeQuestsProvider);
    return questsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.orange)),
      error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
      data: (quests) {
        if (quests.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  const Text('No active suggestions', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'New suggestions appear every Monday.\nReach out to family when you are ready.',
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
          itemCount: quests.length,
          itemBuilder: (context, i) => _QuestCard(quest: quests[i]),
        );
      },
    );
  }
}

class _QuestHistoryTab extends ConsumerWidget {
  const _QuestHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(questHistoryProvider);
    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: KinrelColors.orange)),
      error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white54))),
      data: (quests) {
        if (quests.isEmpty) {
          return Center(
            child: Text('No quest history yet', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: quests.length,
          itemBuilder: (context, i) => _QuestCard(quest: quests[i], isHistory: true),
        );
      },
    );
  }
}

class _QuestCard extends ConsumerWidget {
  final FamilyQuest quest;
  final bool isHistory;

  const _QuestCard({required this.quest, this.isHistory = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: quest.status == 'completed'
              ? KinrelColors.success.withOpacity(0.3)
              : KinrelColors.amber.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(quest.questEmoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  quest.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: quest.status == 'completed' ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              // Karma reward badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: KinrelColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: KinrelColors.gold.withOpacity(0.3)),
                ),
                child: Text(
                  '+${quest.karmaReward}',
                  style: const TextStyle(color: KinrelColors.gold, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              quest.description,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.4),
            ),
          ),
          if (quest.isActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // P1.2: No countdown timer — suggestions don't expire.
                // Skip button
                TextButton(
                  onPressed: () async {
                    await ref.read(pulseApiClientProvider).skipQuest(quest.id);
                    ref.invalidate(activeQuestsProvider);
                  },
                  child: Text('Not now', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
                ),
                const Spacer(),
                // Complete button
                ElevatedButton(
                  onPressed: () async {
                    final result = await ref.read(pulseApiClientProvider).completeQuest(quest.id);
                    ref.invalidate(activeQuestsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Suggestion complete! +${result.karmaAwarded} karma'),
                          backgroundColor: KinrelColors.success,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KinrelColors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('Reach out', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
          if (quest.status == 'completed') ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: KinrelColors.success, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Completed +${quest.karmaAwarded} karma',
                    style: TextStyle(color: KinrelColors.success, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
