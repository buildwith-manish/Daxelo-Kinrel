// lib/features/pulse/presentation/daily_brief_screen.dart
//
// DAXELO KINREL — Pulse Daily Brief Screen
//
// The "WhatsApp chat" daily driver. Every morning, the user opens this screen
// to see their personalized family intelligence brief:
//
//   🌅 Good morning, {name}. Here's your family today.
//
//   💜 Needs you today
//      Dadi hasn't been active in 4 days...
//      → [Send a message]
//
//   🎂 This week
//      Priya's birthday — Thursday (3 days)
//      → [Contribute]
//
//   etc.
//
// Each item is a card with:
//   - Emoji icon (by itemType)
//   - Title (bold)
//   - Body (subtitle)
//   - Action button (localized label)
//
// Tapping an action:
//   - call → opens phone dialer
//   - message → opens chat
//   - view_post → navigates to post detail
//   - view_sparq → navigates to sparq detail
//   - contribute → opens gift pool (future)
//   - listen_memory → opens Pitru memory player
//
// The screen also shows the brief summary + karma earned today.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../data/pulse_models.dart';
import '../providers/pulse_providers.dart';

class DailyBriefScreen extends ConsumerStatefulWidget {
  const DailyBriefScreen({super.key});

  @override
  ConsumerState<DailyBriefScreen> createState() => _DailyBriefScreenState();
}

class _DailyBriefScreenState extends ConsumerState<DailyBriefScreen> {
  @override
  Widget build(BuildContext context) {
    final briefAsync = ref.watch(todayBriefProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        title: const Text(
          'Daily Brief',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: KinrelColors.amber),
            onPressed: () => context.push('/pulse/history'),
            tooltip: 'Brief history',
          ),
        ],
      ),
      body: briefAsync.when(
        loading: () => const _LoadingState(),
        error: (err, _) => _ErrorState(message: err.toString()),
        data: (brief) {
          if (brief == null) {
            return _EmptyState(
              onRetry: () => ref.invalidate(todayBriefProvider),
            );
          }
          return _BriefContent(brief: brief);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Brief content
// ═══════════════════════════════════════════════════════════════════════════

class _BriefContent extends ConsumerWidget {
  final DailyBrief brief;

  const _BriefContent({required this.brief});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: KinrelColors.orange,
      onRefresh: () async {
        ref.invalidate(todayBriefProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Greeting header ────────────────────────────────────────────
          _GreetingHeader(brief: brief),

          const SizedBox(height: 24),

          // ── Summary + karma strip ──────────────────────────────────────
          if (brief.summary != null || brief.karmaEarned > 0)
            _SummaryStrip(brief: brief),

          const SizedBox(height: 16),

          // ── Brief items ────────────────────────────────────────────────
          if (brief.items.isEmpty)
            _NoItemsState()
          else
            ...brief.items.map((item) => _BriefItemCard(item: item)),

          const SizedBox(height: 32),

          // ── Footer: engagement stats ───────────────────────────────────
          _EngagementFooter(brief: brief),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Greeting header
// ═══════════════════════════════════════════════════════════════════════════

class _GreetingHeader extends StatelessWidget {
  final DailyBrief brief;

  const _GreetingHeader({required this.brief});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greetingEmoji = hour < 12 ? '🌅' : hour < 17 ? '☀️' : hour < 20 ? '🌇' : '🌙';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.orange.withOpacity(0.15),
            KinrelColors.amber.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinrelColors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(greetingEmoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  brief.greeting,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Archetype badge
          if (brief.familyArchetype != 'unknown')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: KinrelColors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: KinrelColors.amber.withOpacity(0.4)),
              ),
              child: Text(
                '${_archetypeEmoji(brief.familyArchetype)} ${brief.familyArchetype} family',
                style: TextStyle(
                  color: KinrelColors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _archetypeEmoji(String archetype) {
    // Global-launch fix: the `lotus` emoji 🪷 was a religious symbol
    // (sacred lotus of Hinduism/Buddhism). Replaced with 🔆 (sun —
    // abstract radiance, matches the renamed "The Radiant" archetype
    // and its new abstract radiating-segments visual pattern). The
    // `banyan` emoji 🌳 is a generic tree (not the sacred fig
    // specifically) and still pairs well with the renamed "The Deep
    // Root" archetype, so it is kept.
    switch (archetype) {
      case 'banyan': return '🌳';
      case 'river_delta': return '🌊';
      case 'confluence': return '🔀';
      case 'spine': return '🦴';
      case 'lotus': return '🔆';
      case 'forest': return '🌲';
      default: return '✨';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Summary strip + karma
// ═══════════════════════════════════════════════════════════════════════════

class _SummaryStrip extends StatelessWidget {
  final DailyBrief brief;

  const _SummaryStrip({required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          if (brief.summary != null)
            Expanded(
              child: Text(
                brief.summary!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          if (brief.karmaEarned > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: KinrelColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KinrelColors.gold.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    '+${brief.karmaEarned}',
                    style: const TextStyle(
                      color: KinrelColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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

// ═══════════════════════════════════════════════════════════════════════════
// Brief item card
// ═══════════════════════════════════════════════════════════════════════════

class _BriefItemCard extends ConsumerWidget {
  final BriefItem item;

  const _BriefItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInteracted = item.interactedAt != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isInteracted
            ? KinrelColors.darkCard.withOpacity(0.5)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isInteracted
              ? Colors.white.withOpacity(0.04)
              : _itemTypeColor().withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: emoji + title + interacted check ─────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.itemType.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    decoration: isInteracted ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
              if (isInteracted)
                Icon(Icons.check_circle, color: KinrelColors.success, size: 18),
            ],
          ),

          // ── Body ───────────────────────────────────────────────────────
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Text(
                item.body,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],

          // ── Action button ──────────────────────────────────────────────
          if (!isInteracted && item.actionType != 'none') ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _ActionButton(item: item),
            ),
          ],
        ],
      ),
    );
  }

  Color _itemTypeColor() {
    switch (item.itemType) {
      case BriefItemType.needYou: return KinrelColors.coral;
      case BriefItemType.birthday: return KinrelColors.amber;
      case BriefItemType.feedHighlight: return KinrelColors.blue;
      case BriefItemType.weather: return const Color(0xFF60A5FA);
      case BriefItemType.memoryOrbit: return KinrelColors.gold;
      case BriefItemType.onThisDay: return KinrelColors.tealAccent;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Action button — handles the tap + records interaction
// ═══════════════════════════════════════════════════════════════════════════

class _ActionButton extends ConsumerWidget {
  final BriefItem item;

  const _ActionButton({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: _actionColor(),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _handleTap(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_actionIcon(), color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                item.actionLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _actionColor() {
    switch (item.actionType) {
      case 'call': return KinrelColors.success;
      case 'message': return KinrelColors.blue;
      case 'view_post': return KinrelColors.amber;
      case 'view_sparq': return KinrelColors.tealAccent;
      case 'contribute': return KinrelColors.gold;
      case 'listen_memory': return KinrelColors.gold;
      case 'view_memory': return KinrelColors.gold;
      default: return KinrelColors.orange;
    }
  }

  IconData _actionIcon() {
    switch (item.actionType) {
      case 'call': return Icons.phone;
      case 'message': return Icons.chat_bubble_outline;
      case 'view_post': return Icons.photo_outlined;
      case 'view_sparq': return Icons.play_arrow;
      case 'contribute': return Icons.card_giftcard;
      case 'listen_memory': return Icons.headphones;
      case 'view_memory': return Icons.memory;
      default: return Icons.arrow_forward;
    }
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    // Record the interaction (awards karma)
    try {
      final client = ref.read(pulseApiClientProvider);
      await client.recordInteraction(item.id, item.actionType);

      // Invalidate the brief so it refreshes (item shows as interacted)
      ref.invalidate(todayBriefProvider);

      // Handle navigation / deep-link based on actionType
      if (!context.mounted) return;
      switch (item.actionType) {
        case 'call':
          // The actionData may contain a phone number
          // For now, just show a snackbar — the actual dialer launch would
          // use url_launcher with 'tel:${phone}'
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Calling... (interaction recorded, +karma earned)'),
              backgroundColor: KinrelColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
          break;
        case 'message':
          if (item.targetUserId != null) {
            context.push('/chat?userId=${item.targetUserId}');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Opening chat...'),
                duration: Duration(seconds: 1),
              ),
            );
          }
          break;
        case 'view_post':
          if (item.actionData['postId'] != null) {
            // Navigate to post detail — would use a post detail route
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Opening post ${item.actionData['postId']}...')),
            );
          }
          break;
        case 'view_sparq':
          final sparqId = item.actionData['sparqId'] ?? item.actionData['targetSparqId'];
          if (sparqId != null) {
            context.push('/sparq/$sparqId');
          }
          break;
        case 'listen_memory':
          if (item.actionData['memoryId'] != null) {
            context.push('/pitru/memory/${item.actionData['memoryId']}');
          }
          break;
        case 'contribute':
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Opening gift pool... (coming soon)')),
          );
          break;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record interaction: $e')),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Engagement footer
// ═══════════════════════════════════════════════════════════════════════════

class _EngagementFooter extends StatelessWidget {
  final DailyBrief brief;

  const _EngagementFooter({required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s engagement',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatChip(icon: '📞', label: 'Calls', value: brief.callsInitiated),
              const SizedBox(width: 12),
              _StatChip(icon: '💬', label: 'Messages', value: brief.messagesSent),
              const SizedBox(width: 12),
              _StatChip(icon: '👵', label: 'Memories', value: brief.memoriesViewed),
              const SizedBox(width: 12),
              _StatChip(icon: '✨', label: 'Karma', value: brief.karmaEarned),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String icon;
  final String label;
  final int value;

  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Loading / error / empty states
// ═══════════════════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              color: KinrelColors.orange,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Generating your family brief...',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'Could not load your brief',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌅', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'No brief yet',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Your daily brief generates at 7am IST. Tap below to generate it now.',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Generate now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoItemsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          const Text('🌿', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            'Nothing urgent today.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your family is doing well. Enjoy the day.',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
