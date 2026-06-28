// lib/core/widgets/relationship_badge.dart
//
// DAXELO KINREL — Relationship Badge Widget
//
// Shows a relationship label in feed posts and profiles.
// Example: "आपके चाचा" or "Your Chacha"

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/kinship_resolver.dart';
import '../../providers/kinship_providers.dart';

class RelationshipBadge extends ConsumerWidget {
  final String fromKey; // viewer's relationship key
  final String viaKey; // target's relationship key
  final String language; // 'hindi', 'english', etc.
  final String viewerGender; // 'male' or 'female'
  final double fontSize;
  final bool showIcon;

  const RelationshipBadge({
    super.key,
    required this.fromKey,
    required this.viaKey,
    this.language = 'hindi',
    this.viewerGender = 'male',
    this.fontSize = 12,
    this.showIcon = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolver = ref.read(kinshipResolverProvider);
    final result = resolver.resolve(
      fromKey,
      viaKey,
      viewerGender: viewerGender,
    );
    final displayName = resolver.getDisplayName(
      result.resultKey,
      language,
    );

    // Pick color based on resolution source
    Color badgeColor;
    switch (result.source) {
      case ResolutionSource.chainRule:
        badgeColor = const Color(0xFFE8622A); // Orange — full accuracy
        break;
      case ResolutionSource.math:
        badgeColor = const Color(0xFF607D8B); // Blue-grey — math fallback
        break;
      case ResolutionSource.fallback:
        badgeColor = const Color(0xFF9E9E9E); // Grey — generic fallback
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              Icons.family_restroom,
              size: fontSize - 2,
              color: badgeColor,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            displayName,
            style: TextStyle(
              color: badgeColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
