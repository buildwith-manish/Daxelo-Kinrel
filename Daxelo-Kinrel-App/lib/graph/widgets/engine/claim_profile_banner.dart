// lib/graph/widgets/engine/claim_profile_banner.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Banner shown when the authenticated user has not yet claimed a
/// Person node in this family. Tapping it navigates to person selection
/// so the user can tap "This is me" / Claim on their own Person node.
///
/// GAP 3 FIX: Without this banner, the graph silently renders from the
/// anchor person's perspective when the user has no linked Person node,
/// which makes the labels look wrong (e.g. a father sees his children
/// labeled as "sibling") with no explanation.
class ClaimProfileBanner extends ConsumerWidget {
  const ClaimProfileBanner({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFE8622A).withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.person_search, color: Color(0xFFE8622A), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Tap to claim your profile — you're viewing as the family anchor",
              style: TextStyle(
                color: Color(0xFFE8622A),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // Navigate to the family detail screen, which has a Members
              // tab where the user can find their own Person node and tap
              // "This is me" / Claim. The app uses GoRouter, so we use
              // context.push('/family/$familyId'). If the route changes,
              // search for how other parts of the app navigate to the
              // members list for a family.
              context.push('/family/$familyId');
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE8622A),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Claim', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
