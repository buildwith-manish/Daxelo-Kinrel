// lib/features/games/ghost_painter/ghost_painter_join_screen.dart
//
// Ghost Painter — invite/deep-link landing screen.
//
// Ghost Painter is family-scoped: there is one active round per family
// (no room codes, no waiting-room lobby). But the shared invite system
// navigates every accepted invite to
// `/family/:id/<routeSegment>/lobby?join=<gameId>`. Before the QA
// 2026-09-20 fix there was no `/ghost-painter/lobby` route at all, so
// an accepted Ghost Painter invite (and any `?join=` deep link) landed
// on a 404. This screen resolves where the joiner actually belongs:
//
//   • active round + they are the drawer  → draw screen (canvas re-seeds)
//   • active round + they are a guesser   → guess screen
//   • no active round                     → draw screen (start screen)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/supabase_service.dart';
import 'ghost_painter_provider.dart';

class GhostPainterJoinScreen extends ConsumerStatefulWidget {
  const GhostPainterJoinScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<GhostPainterJoinScreen> createState() =>
      _GhostPainterJoinScreenState();
}

class _GhostPainterJoinScreenState
    extends ConsumerState<GhostPainterJoinScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Load fresh round state so the destination decision is based on the
    // CURRENT round, not whatever the provider cached from an earlier
    // visit to another family screen.
    Future.microtask(() {
      if (mounted) {
        ref.read(ghostPainterProvider(widget.familyId).notifier).load();
      }
    });
  }

  void _navigate() {
    if (!mounted) return;
    final state = ref.read(ghostPainterProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final round = state.activeRound;
    final iAmTheDrawer =
        myId != null && round != null && round.drawerPersonId == myId;

    // Guessers (and anyone whose role we can't determine while a round is
    // live) belong on the guess screen; the drawer belongs back on the
    // canvas; with no live round everyone lands on the draw/start screen.
    final String target;
    if (round != null && round.isActive && !iAmTheDrawer) {
      target = '/family/${widget.familyId}/ghost-painter/guess';
    } else {
      target = '/family/${widget.familyId}/ghost-painter/draw';
    }
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ghostPainterProvider(widget.familyId));

    if (!state.isLoading && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                border: Border.all(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.brush_rounded,
                color: Color(0xFFEC4899),
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Joining Ghost Painter…',
              style: TextStyle(
                color: Color(0xFFFDF4FF),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEC4899)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
