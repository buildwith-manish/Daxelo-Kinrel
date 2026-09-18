// lib/features/games/retention/live_presence_strip.dart
//
// LivePresenceStrip — replaces the static online-status banner with a
// horizontal strip of small avatar circles for currently-online family
// members. If nobody's online, shows an inviting CTA instead.
//
// Tapping an online member's circle jumps to the Play With flow for
// that person (reuses existing Play With suggestion logic).

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import 'retention_providers.dart';

class LivePresenceStrip extends ConsumerWidget {
  const LivePresenceStrip({super.key, required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presenceAsync = ref.watch(livePresenceProvider(familyId));

    return presenceAsync.when(
      loading: () => const SizedBox(height: 44),
      error: (_, __) => const SizedBox.shrink(),
      data: (members) {
        final online = members.where((m) => m.isOnline).toList();
        final offline = members.where((m) => !m.isOnline).take(4).toList();

        if (online.isEmpty && offline.isEmpty) {
          return _EmptyPresence(familyId: familyId);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // Online avatars
              ...online.take(6).map((m) => _PresenceAvatar(
                    userName: m.userName,
                    isOnline: true,
                    onTap: () => _navigateToGame(context, familyId),
                  )),
              // Offline (dimmed) avatars
              ...offline.where((m) => !online.any((o) => o.userId == m.userId)).map((m) => _PresenceAvatar(
                    userName: m.userName,
                    isOnline: false,
                    onTap: null,
                  )),
              const SizedBox(width: 8),
              if (online.isNotEmpty)
                Expanded(
                  child: Text(
                    '${online.length} ${online.length == 1 ? "person" : "people"} here now',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.tealAccent,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToGame(BuildContext context, String familyId) {
    // Jump to the Games tab where the Play With row is
    context.push('/family/$familyId');
  }
}

class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({
    required this.userName,
    required this.isOnline,
    this.onTap,
  });

  final String userName;
  final bool isOnline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = userName.isNotEmpty
        ? userName.substring(0, 1).toUpperCase()
        : '?';

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Stack(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isOnline
                      ? [
                          KinrelColors.orange.withValues(alpha: 0.5),
                          KinrelColors.amber.withValues(alpha: 0.3),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.04),
                        ],
                ),
                border: Border.all(
                  color: isOnline
                      ? KinrelColors.tealAccent.withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isOnline
                        ? KinrelColors.textWhite
                        : KinrelColors.textDim,
                  ),
                ),
              ),
            ),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: KinrelColors.tealAccent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: KinrelColors.darkSurface, width: 2),
                    boxShadow: const [
                      BoxShadow(color: KinrelColors.tealAccent, blurRadius: 4),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms);
  }
}

class _EmptyPresence extends StatelessWidget {
  const _EmptyPresence({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(Icons.nightlight_outlined,
              size: 16, color: KinrelColors.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Be the first one here — invite someone to play',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/family/$familyId'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: KinrelColors.orange.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Invite',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
