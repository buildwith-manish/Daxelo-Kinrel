// lib/features/games/shared/widgets/reactions_bar.dart
//
// ReactionsBar — universal reactions widget for every multiplayer game.
//
// Renders a row of 5 universal reactions that any family member can send
// at any time during a game (lobby, gameplay, or results screen):
//
//   ❤️   👏   🔥   😂   🎉
//
// When tapped, the reaction is:
//   1. Emitted via socket 'game:reaction' to the server
//   2. Server broadcasts to everyone in the room
//   3. Each client receives the reaction + renders a floating emoji
//      animation overlay (handled by ReactionOverlay, see below)
//
// Reaction counts are tracked by the lobby chat panel (shown as system
// activity messages: "John reacted ❤️").
//
// Usage:
//   ReactionsBar(
//     gameTable: 'bingo_games',
//     gameId: state.game!.id,
//     familyId: widget.familyId,
//   )

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';

/// Universal reaction emojis supported across all games.
const kUniversalReactions = ['❤️', '👏', '🔥', '😂', '🎉'];

/// Compact row of 5 reaction buttons. Tapping one sends a socket event
/// to broadcast the reaction to everyone in the room.
class ReactionsBar extends ConsumerStatefulWidget {
  const ReactionsBar({
    super.key,
    required this.gameTable,
    required this.gameId,
    required this.familyId,
    this.size = ReactionsBarSize.md,
  });

  final String gameTable;
  final String gameId;
  final String familyId;
  final ReactionsBarSize size;

  @override
  ConsumerState<ReactionsBar> createState() => _ReactionsBarState();
}

enum ReactionsBarSize { sm, md, lg }

class _ReactionsBarState extends ConsumerState<ReactionsBar> {
  /// Per-reaction "burst" animation state — when a reaction is sent,
  /// we briefly scale up the tapped emoji to give visual feedback.
  final Map<String, bool> _bursting = {};

  Future<void> _send(String emoji) async {
    final socket = ref.read(socketServiceProvider);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id ?? '';
    final myName =
        (ref.read(supabaseProvider)?.auth.currentUser?.userMetadata?['name']
                as String?) ??
            'Family member';

    // Optimistic burst animation.
    setState(() => _bursting[emoji] = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _bursting[emoji] = false);
    });

    socket.emitGameReaction(
      gameTable: widget.gameTable,
      gameId: widget.gameId,
      familyId: widget.familyId,
      emoji: emoji,
      userId: myId,
      userName: myName,
    );
  }

  double get _emojiSize {
    switch (widget.size) {
      case ReactionsBarSize.sm:
        return 20;
      case ReactionsBarSize.md:
        return 26;
      case ReactionsBarSize.lg:
        return 34;
    }
  }

  double get _buttonPadding {
    switch (widget.size) {
      case ReactionsBarSize.sm:
        return 6;
      case ReactionsBarSize.md:
        return 10;
      case ReactionsBarSize.lg:
        return 14;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _buttonPadding / 2,
        vertical: _buttonPadding / 2,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: kUniversalReactions.map((emoji) {
          final isBursting = _bursting[emoji] ?? false;
          return GestureDetector(
            onTap: () => _send(emoji),
            child: AnimatedScale(
              scale: isBursting ? 1.5 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.elasticOut,
              child: Container(
                padding: EdgeInsets.all(_buttonPadding / 2),
                child: Text(
                  emoji,
                  style: TextStyle(fontSize: _emojiSize),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Floating-emoji overlay that renders incoming reactions as animated
/// emoji drifting upward across the screen. Wrap the game/lobby body
/// with this widget so any incoming reaction from any family member is
/// visually celebrated.
///
/// Usage:
///   ReactionOverlay(
///     gameTable: 'bingo_games',
///     gameId: state.game!.id,
///     child: GameBody(),
///   )
class ReactionOverlay extends ConsumerStatefulWidget {
  const ReactionOverlay({
    super.key,
    required this.gameTable,
    required this.gameId,
    required this.child,
  });

  final String gameTable;
  final String gameId;
  final Widget child;

  @override
  ConsumerState<ReactionOverlay> createState() => _ReactionOverlayState();
}

class _ReactionOverlayState extends ConsumerState<ReactionOverlay>
    with TickerProviderStateMixin {
  final List<_FloatingReaction> _active = [];
  VoidCallback? _unsub;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    final socket = ref.read(socketServiceProvider);
    _unsub = socket.onGameReaction((payload) {
      if (payload['gameTable'] != widget.gameTable ||
          payload['gameId'] != widget.gameId) {
        return;
      }
      if (!mounted) return;
      final emoji = (payload['emoji'] ?? '🎉') as String;
      _spawn(emoji);
    });
  }

  void _spawn(String emoji) {
    final id = _nextId++;
    final screenWidth = MediaQuery.of(context).size.width;
    final rng = DateTime.now().microsecondsSinceEpoch;
    final xOffset = (rng % 1000) / 1000.0 * (screenWidth - 80) + 40;
    final drift = ((rng ~/ 1000) % 200 - 100).toDouble();

    final controller = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );
    final reaction = _FloatingReaction(
      id: id,
      emoji: emoji,
      startX: xOffset,
      drift: drift,
      controller: controller,
    );
    setState(() => _active.add(reaction));
    controller.forward().then((_) {
      if (mounted) {
        setState(() => _active.removeWhere((r) => r.id == id));
      }
      controller.dispose();
    });
  }

  @override
  void dispose() {
    _unsub?.call();
    for (final r in _active) {
      r.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Render floating emojis on top
        ..._active.map((r) => _buildFloatingEmoji(r)),
      ],
    );
  }

  Widget _buildFloatingEmoji(_FloatingReaction r) {
    return Positioned(
      left: r.startX,
      bottom: 0,
      child: AnimatedBuilder(
        animation: r.controller,
        builder: (context, child) {
          final t = r.controller.value;
          // Drift upward + slight horizontal sway
          final dy = -t * 400; // rise 400px
          final dx = r.drift * t;
          final opacity = t < 0.8 ? 1.0 : (1.0 - (t - 0.8) / 0.2);
          return Transform.translate(
            offset: Offset(dx, dy),
            child: Opacity(
              opacity: opacity,
              child: Text(
                r.emoji,
                style: const TextStyle(fontSize: 40),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FloatingReaction {
  _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.startX,
    required this.drift,
    required this.controller,
  });
  final int id;
  final String emoji;
  final double startX;
  final double drift;
  final AnimationController controller;
}
