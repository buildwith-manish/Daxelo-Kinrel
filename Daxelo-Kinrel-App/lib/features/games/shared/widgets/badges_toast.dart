// lib/features/games/shared/widgets/badges_toast.dart
//
// Transient celebratory toast shown after a game ends if the current user
// earned new game-related badges. Polls the check-game-badges Edge Function
// when triggered and shows an animated overlay with the newly-earned badge
// icons + names.
//
// Usage from a board/results screen on game completion:
//   BadgesToast.maybeShowAfterGame(
//     context: context,
//     familyId: widget.familyId,
//   )

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/supabase_service.dart';

class BadgesToast {
  BadgesToast._();

  /// Call after a game ends. Polls the Edge Function, and if new badges
  /// were earned, shows an animated overlay for 4 seconds.
  static Future<void> maybeShowAfterGame({
    required BuildContext context,
    required String familyId,
    WidgetRef? ref,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final client = container.read(supabaseProvider);
    if (client == null) return;
    final myId = client.auth.currentUser?.id;
    if (myId == null) return;

    try {
      final resp = await client.functions.invoke(
        'check-game-badges',
        body: {'userId': myId, 'familyId': familyId},
      ).timeout(const Duration(seconds: 10));
      final data = resp.data;
      if (data is! Map) return;
      final newlyEarned = data['newlyEarned'];
      if (newlyEarned is! List || newlyEarned.isEmpty) return;

      if (!context.mounted) return;
      final badges = <Map<String, String>>[];
      for (final b in newlyEarned) {
        if (b is Map) {
          final slug = b['slug'];
          final name = b['name'];
          badges.add({
            'slug': slug is String ? slug : '',
            'name': name is String ? name : 'Badge',
          });
        }
      }
      if (badges.isEmpty) return;
      _showOverlay(context, badges);
    } catch (_) {
      // silent — badge toasts are best-effort, not critical
    }
  }

  static void _showOverlay(
      BuildContext context, List<Map<String, String>> badges) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _BadgesOverlay(
        badges: badges,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }
}

class _BadgesOverlay extends StatefulWidget {
  const _BadgesOverlay({required this.badges, required this.onDismiss});
  final List<Map<String, String>> badges;
  final VoidCallback onDismiss;

  @override
  State<_BadgesOverlay> createState() => _BadgesOverlayState();
}

class _BadgesOverlayState extends State<_BadgesOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: KinrelSpacing.lg,
      right: KinrelSpacing.lg,
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.6),
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.badges.length == 1
                            ? 'New badge earned!'
                            : '${widget.badges.length} new badges!',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.orange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.badges.map((b) => b['name']).join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: KinrelColors.textDim, size: 16),
                  onPressed: widget.onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
