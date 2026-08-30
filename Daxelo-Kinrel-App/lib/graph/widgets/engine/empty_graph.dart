// lib/graph/widgets/engine/empty_graph.dart
// P0.4: Extracted from family_graph_engine_view.dart.
// v5.135: Added distinct AccessIssueGraph state for RLS/access-denied cases.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// v5.135: The genuinely-empty state — the family has 0 real members.
/// Shows the "add someone to start" prompt.
class EmptyGraph extends StatelessWidget {
  const EmptyGraph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No family members yet.\nAdd someone to start the graph.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// v5.135: The access-issue state — the stats/count query shows a non-zero
/// member count but the direct graph query returned empty (or the layout
/// produced no positions). This is the "RLS blocked access" or "stale
/// session" case, NOT the "genuinely empty family" case.
///
/// Shows a distinct message directing the user to log out and back in,
/// instead of the misleading "add someone to start" prompt.
class AccessIssueGraph extends StatelessWidget {
  const AccessIssueGraph({
    super.key,
    this.reportedMemberCount,
    this.onRetry,
  });

  /// The member count reported by the stats/count query (non-zero).
  /// Displayed to the user so they understand data exists but can't be
  /// accessed by the current session.
  final int? reportedMemberCount;

  /// Optional retry callback — re-invalidates the graph provider.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 48,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to load graph',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reportedMemberCount != null && reportedMemberCount! > 0
                  ? 'This family has $reportedMemberCount members, but your '
                      'current session may not have access.\n\n'
                      'Please try logging out and back in, or contact '
                      'support if this persists.'
                  : 'Your session may have expired or the access was '
                      'revoked.\n\nPlease try logging out and back in, or '
                      'contact support if this persists.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          const Text('Could not load the family graph.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
