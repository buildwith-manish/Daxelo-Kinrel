// lib/features/pulse/presentation/pulse_hub_screen.dart
//
// DAXELO KINREL — Family Intelligence Hub
//
// CONSOLIDATED from 8 tiles → 4 based on how users think about the features:
//   1. Daily Brief — the anchor/home screen (quests appear as cards inside it)
//   2. Celebrations — blessing chain + festivals (occasion-triggered content)
//   3. Time Capsule — compose-and-wait (genuinely different mode)
//   4. Family Legacy — memorials + chronicle (preserve/look back at history)
//
// What moved:
//   - Family Quests → folded into Daily Brief (content OF the brief)
//   - Silent Alarms → Settings (passive background nudge system, same
//     reasoning as Kinrel Learning — invisible infra, not a destination)
//   - Blessing Chain + Festivals → combined into "Celebrations"
//   - Memorials + Family Chronicle → combined into "Family Legacy"
//
// Note: memorials/ is Pitru's UI living inside Pulse. Not a dupe — just
// the memorial feature surfaced here alongside its natural companion
// (the AI-generated family chronicle).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../providers/pulse_providers.dart';

class PulseHubScreen extends ConsumerWidget {
  const PulseHubScreen({super.key});

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
          // ── 1. Daily Brief (anchor screen — quests appear as cards inside) ──
          const _HubCard(
            emoji: '🌅',
            title: 'Daily Brief',
            subtitle: 'Your family intelligence, every morning',
            route: '/pulse/today',
            color: KinrelColors.orange,
          ),
          const SizedBox(height: 12),

          // ── 2. Celebrations (blessing chain + festivals combined) ──
          _HubCard(
            emoji: '🎁',
            title: 'Celebrations',
            subtitle: 'Blessings, festivals & occasion greetings',
            route: '/pulse/celebrations',
            color: KinrelColors.gold,
            // Bug fix: pass a typed resolver instead of an untyped
            // ProviderBase<dynamic>. The resolver watches the provider
            // (which returns AsyncValue<List<BlessingChain>>) and maps
            // it to AsyncValue<int?> via .whenData — the AsyncValue
            // chain stays intact, no `dynamic` method dispatch.
            badgeResolver: (ref) => ref
                .watch(blessingsForMeProvider)
                .whenData((list) => list.length),
          ),
          const SizedBox(height: 12),

          // ── 3. Time Capsule (genuinely different mode — compose & wait) ──
          _HubCard(
            emoji: '⏰',
            title: 'Time Capsule',
            subtitle: 'Messages locked for future dates',
            route: '/pulse/time-capsules',
            color: KinrelColors.tealAccent,
            badgeResolver: (ref) => ref
                .watch(capsulesForMeProvider)
                .whenData((list) => list.length),
          ),
          const SizedBox(height: 12),

          // ── 4. Family Legacy (memorials + chronicle combined) ──
          const _HubCard(
            emoji: '📖',
            title: 'Family Legacy',
            subtitle: 'Living memorials & your family chronicle',
            route: '/pulse/legacy',
            color: KinrelColors.blue,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// A hub card with optional badge count (from a provider).
///
/// Bug fix (Family Intelligence crash): the previous implementation typed
/// [badgeProvider] as `ProviderBase<dynamic>?` and called `.whenData()` on
/// the result of `ref.watch(badgeProvider!)`. In debug builds this worked
/// because the provider was a `FutureProvider<List<...>>` and
/// `ref.watch` returned an `AsyncValue`. But in production/minified web
/// builds, the `dynamic` typing caused `NoSuchMethodError: whenData was
/// called on a List` when the provider had already resolved and Riverpod
/// returned the cached `List` value directly instead of wrapping it in
/// an `AsyncValue`.
///
/// Fix: replace the untyped `ProviderBase<dynamic>?` + unsafe
/// `.whenData()` pattern with a typed badge-resolver callback that
/// returns an `AsyncValue<int?>`. Each call site wraps its provider
/// watch in a properly typed `.when()` / `.maybeWhen()` call so the
/// type system — not runtime duck-typing — guarantees the value is an
/// `AsyncValue` before any method is called on it.
class _HubCard extends ConsumerWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String route;
  final Color color;

  /// Typed badge resolver. Returns `AsyncValue<int?>` so the card can
  /// safely handle loading / error / data states without ever calling
  /// a method on a non-`AsyncValue` type. Callers pass a closure like:
  ///   `(ref) => ref.watch(blessingsForMeProvider).whenData((l) => l.length)
  /// This keeps the `AsyncValue` chain intact end-to-end.
  final AsyncValue<int?> Function(WidgetRef ref)? badgeResolver;

  const _HubCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.color,
    this.badgeResolver,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int? badgeCount;
    if (badgeResolver != null) {
      // The resolver returns a properly-typed AsyncValue<int?> — no
      // `dynamic`, no runtime method dispatch on an unknown type.
      // `.valueOrNull` safely extracts the count (null while loading
      // or on error, so the badge simply doesn't show — no crash).
      badgeCount = badgeResolver!(ref).valueOrNull;
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
