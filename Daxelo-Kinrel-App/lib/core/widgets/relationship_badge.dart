// lib/core/widgets/relationship_badge.dart
//
// Shows a kinship label chip in feed posts and profile cards.
// Example: "आपके चाचा" or "Your Chacha"

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/kinship_providers.dart';

class RelationshipBadge extends ConsumerWidget {
  final String fromKey;
  final String viaKey;
  final String language;
  final String viewerGender;

  const RelationshipBadge({
    required this.fromKey,
    required this.viaKey,
    this.language = 'hindi',
    this.viewerGender = 'male',
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolver = ref.read(kinshipResolverProvider);
    final result = resolver.resolve(fromKey, viaKey, viewerGender: viewerGender);
    final displayName = resolver.getDisplayName(result.resultKey, language);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE8622A).withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        displayName,
        style: const TextStyle(
          color: Color(0xFFE8622A),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
