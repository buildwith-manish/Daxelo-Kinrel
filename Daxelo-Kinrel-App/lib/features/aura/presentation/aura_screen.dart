// lib/features/aura/presentation/aura_screen.dart
//
// AURA — Main Screen (Phase 15).
//
// Assembles all the AURA widgets into a single scrollable screen:
//   1. Animated symbol (large, centered)
//   2. Archetype card (name + description + confidence)
//   3. Share card (hidden behind a "Share" FAB; uses RepaintBoundary)
//   4. Timeline (scrubable history)
//   5. Recompute button (if AURA has never been computed, or stale)
//
// The screen reads from [auraProvider] keyed by familyId. It mirrors
// the structure of family_calendar_screen.dart (ConsumerStatefulWidget
// + initState → ref.read(provider.notifier).load()).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/feature_flags.dart';
import '../data/aura_model.dart';
import '../providers/aura_provider.dart';
import '../widgets/aura_archetype_card.dart';
import '../widgets/aura_share_card.dart';
import '../widgets/aura_symbol_widget.dart';
import '../widgets/aura_timeline.dart';

class AuraScreen extends ConsumerStatefulWidget {
  const AuraScreen({
    super.key,
    required this.familyId,
    this.familyName,
  });

  /// The family whose AURA to render. Required.
  final String familyId;

  /// Family name, used in the share card. Optional — falls back to
  /// "Family" if not provided.
  final String? familyName;

  @override
  ConsumerState<AuraScreen> createState() => _AuraScreenState();
}

class _AuraScreenState extends ConsumerState<AuraScreen> {
  final _shareKey = GlobalKey();
  int _selectedHistoryIndex = -1;

  @override
  void initState() {
    super.initState();
    // Load AURA + history on first build.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(auraProvider(widget.familyId).notifier).load(
            includeHistory: true,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Feature flag — should already be checked by the router, but
    // double-check here in case the screen is opened via deep link.
    if (!kEnableAura) {
      return const Scaffold(
        body: Center(child: Text('AURA is not available.')),
      );
    }

    final state = ref.watch(auraProvider(widget.familyId));
    final familyName = widget.familyName ?? 'Family';

    return Scaffold(
      appBar: AppBar(
        title: const Text('AURA'),
        actions: [
          if (state.aura != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share AURA',
              onPressed: () => _onShare(state.aura!, familyName),
            ),
        ],
      ),
      body: _buildBody(context, state, familyName),
      // Bug 21 fix: drop the `state.notComputed` clause — when a cached
      // AURA is shown (state.aura != null) the user should always be able
      // to recompute. The "notComputed" flag can be true simultaneously
      // with a non-null cached aura (see Bug 11), which previously hid
      // the FAB even though there was something to recompute.
      floatingActionButton:
          state.aura == null || state.isRecomputing
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _onRecompute(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recompute'),
                ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AuraState state,
    String familyName,
  ) {
    // ── Loading (no cache yet) ─────────────────────────────────────
    if (state.isLoading && state.aura == null && !state.notComputed) {
      return const Center(child: CircularProgressIndicator());
    }

    // ── Error (no cache, no fresh data) ────────────────────────────
    if (state.error != null && state.aura == null && !state.notComputed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(
                'Could not load AURA',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref
                    .read(auraProvider(widget.familyId).notifier)
                    .load(includeHistory: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // ── Not computed yet ───────────────────────────────────────────
    if (state.notComputed && state.aura == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'AURA has not been computed yet',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'AURA analyses your family graph to generate a unique '
                'symbol and archetype. This usually takes a few seconds.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (state.isRecomputing)
                const CircularProgressIndicator()
              else
                FilledButton.icon(
                  onPressed: _onRecompute,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate AURA'),
                ),
            ],
          ),
        ),
      );
    }

    // ── Have AURA data (fresh or cached) ───────────────────────────
    final aura = state.aura!;
    // Bug 5 fix: the share card is no longer a ListView child. It's
    // rendered in an offscreen `Positioned` inside a `Stack` so that:
    //   1. It is ALWAYS built + laid out at natural size (so
    //      `_shareKey.currentContext` is never null when the user
    //      taps Share before scrolling).
    //   2. It is never painted on screen (Positioned at left: -10000).
    // Previously it was a regular ListView child which meant (a) it
    // was visible to the user when they scrolled down, and (b) it
    // was lazily built so Share failed if tapped before scrolling.
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.isFromCache)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off,
                        size: 14, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Showing cached AURA — offline mode',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),

            // ── 1. Symbol ─────────────────────────────────────────────
            Center(
              child: AuraSymbolWidget(
                parameters: aura.symbol,
                archetypeKey: aura.archetype.key,
                size: 280,
              ),
            ),
            const SizedBox(height: 24),

            // ── 2. Archetype card ─────────────────────────────────────
            AuraArchetypeCard(
              archetype: aura.archetype,
              symbol: aura.symbol,
              memberCount: aura.metrics.memberCount,
            ),
            const SizedBox(height: 24),

            // ── 3. Timeline ───────────────────────────────────────────
            AuraTimeline(
              snapshots: state.history,
              selectedIndex: _selectedHistoryIndex,
              onSelect: (i) => setState(() => _selectedHistoryIndex = i),
            ),
            const SizedBox(height: 80), // FAB clearance
          ],
        ),
        // ── Offscreen share card (always built, never painted) ────
        Positioned(
          left: -10000,
          top: 0,
          child: RepaintBoundary(
            key: _shareKey,
            child: AuraShareCard(
              boundaryKey: _shareKey,
              aura: aura,
              familyName: familyName,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onShare(AuraModel aura, String familyName) async {
    final ok = await AuraShareCard.captureAndShare(
      boundaryKey: _shareKey,
      familyName: familyName,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share AURA')),
      );
    }
  }

  Future<void> _onRecompute() async {
    // Bug 6 fix: capture the previous computedAt BEFORE the recompute
    // call. We then poll until the server returns an AURA whose
    // computedAt is strictly newer than this baseline. Previously
    // the code compared against `DateTime.now()` (the client clock)
    // captured AFTER the recompute returned. If the client clock was
    // even 1 second ahead of the server clock, the poll never
    // detected the fresh AURA and ran all 5 iterations.
    final prevComputedAt =
        ref.read(auraProvider(widget.familyId)).aura?.computedAt;

    final ok = await ref
        .read(auraProvider(widget.familyId).notifier)
        .recompute();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recompute failed')),
        );
      }
      return;
    }
    // Poll with exponential backoff until the new AURA appears.
    // The backend runs graph algorithms asynchronously after returning 202.
    // For a family with 40+ members, Brandes + clustering can take longer
    // than the previous hardcoded 3-second delay on a cold Render instance.
    //
    // Strategy: poll 5 times with delays of [2, 3, 5, 8, 13] seconds
    // (Fibonacci-ish backoff). Stop early when the fetched AURA's
    // computedAt is newer than the previous baseline.
    final delays = [
      const Duration(seconds: 2),
      const Duration(seconds: 3),
      const Duration(seconds: 5),
      const Duration(seconds: 8),
      const Duration(seconds: 13),
    ];
    for (final delay in delays) {
      await Future.delayed(delay);
      if (!mounted) return;
      await ref
          .read(auraProvider(widget.familyId).notifier)
          .load(includeHistory: true);
      if (!mounted) return;
      final newAura = ref.read(auraProvider(widget.familyId)).aura;
      // Fresh AURA has landed if computedAt moved forward from the
      // previous value (or if there was no previous value).
      if (newAura != null &&
          (prevComputedAt == null ||
              newAura.computedAt.isAfter(prevComputedAt))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('AURA updated'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }
    // Polled 5 times without seeing a new computedAt. The recompute may
    // still be running server-side; the user can pull-to-refresh later.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AURA is still computing — check back in a moment'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
