// =============================================================================
// Track C v2.0 — AURA Insight Card Widget
// =============================================================================
// Dismissible card that renders an AIInsight. Section 8 — accept/dismiss.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trackc_providers.dart';

class InsightCard extends ConsumerStatefulWidget {
  const InsightCard({super.key, required this.insight});

  final Map<String, dynamic> insight;

  @override
  ConsumerState<InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends ConsumerState<InsightCard> {
  bool _isActing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insight = widget.insight;
    final kind = insight['kind'] as String? ?? '';
    final status = insight['status'] as String? ?? 'pending';
    final payload = (insight['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    if (status == 'dismissed' || status == 'stale') {
      return const SizedBox.shrink(); // hide dismissed/stale insights
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconForKind(kind), size: 20, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _titleForKind(kind),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (status == 'accepted')
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            _renderPayload(kind, payload, theme),
            if (status == 'presented' || status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isActing ? null : () => _dismiss('not_relevant'),
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _isActing ? null : _accept,
                    child: _isActing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Accept'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _renderPayload(String kind, Map<String, dynamic> payload, ThemeData theme) {
    switch (kind) {
      case 'decision_analysis':
        final score = (payload['qualityScore'] as num?)?.toDouble() ?? 0.5;
        final strengths = (payload['strengths'] as List? ?? []).cast<String>();
        final risks = (payload['risks'] as List? ?? []).cast<String>();
        final recommendation = payload['recommendation'] as String? ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quality score bar
            Row(
              children: [
                Text('Quality: ${(score * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: score,
                    backgroundColor: Colors.grey[300],
                    color: score > 0.7 ? Colors.green : (score > 0.4 ? Colors.orange : Colors.red),
                  ),
                ),
              ],
            ),
            if (strengths.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Strengths', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ...strengths.map((s) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.green)),
                    Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              )),
            ],
            if (risks.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Risks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ...risks.map((r) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.red)),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              )),
            ],
            if (recommendation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb, size: 16, color: Colors.blue),
                    const SizedBox(width: 6),
                    Expanded(child: Text(recommendation, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ],
          ],
        );

      case 'pros_cons':
        final pros = (payload['pros'] as List? ?? []).cast<String>();
        final cons = (payload['cons'] as List? ?? []).cast<String>();
        final assessment = payload['balancedAssessment'] as String? ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pros', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13)),
                      ...pros.map((p) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• $p', style: const TextStyle(fontSize: 13)),
                      )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cons', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
                      ...cons.map((c) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• $c', style: const TextStyle(fontSize: 13)),
                      )),
                    ],
                  ),
                ),
              ],
            ),
            if (assessment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(assessment, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
            ],
          ],
        );

      case 'summary':
        final summary = payload['summary'] as String? ?? '';
        final takeaways = (payload['keyTakeaways'] as List? ?? []).cast<String>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary, style: const TextStyle(fontSize: 14)),
            if (takeaways.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Key Takeaways', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ...takeaways.map((t) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text('• $t', style: const TextStyle(fontSize: 13)),
              )),
            ],
          ],
        );

      case 'duplicate_detection':
        final duplicates = (payload['duplicates'] as List? ?? []).cast<Map<String, dynamic>>();
        final message = payload['message'] as String? ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14)),
            if (duplicates.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Similar past decisions:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ...duplicates.map((d) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  '• ${d['reason'] ?? 'Similar decision'} (similarity: ${((d['similarity'] as num?) ?? 0 * 100).round()}%)',
                  style: const TextStyle(fontSize: 13),
                ),
              )),
            ],
          ],
        );

      default:
        return Text('Insight kind: $kind', style: const TextStyle(fontSize: 13));
    }
  }

  IconData _iconForKind(String kind) {
    return {
      'decision_analysis': Icons.analytics,
      'pros_cons': Icons.balance,
      'summary': Icons.summarize,
      'duplicate_detection': Icons.content_copy,
      'smart_reminder': Icons.notifications_active,
      'action_items': Icons.checklist,
      'draft_minutes': Icons.description,
    }[kind] ?? Icons.lightbulb;
  }

  String _titleForKind(String kind) {
    return {
      'decision_analysis': 'Decision Analysis',
      'pros_cons': 'Pros & Cons',
      'summary': 'Summary',
      'duplicate_detection': 'Duplicate Detection',
      'smart_reminder': 'Smart Reminder',
      'action_items': 'Action Items',
      'draft_minutes': 'Draft Minutes',
    }[kind] ?? kind;
  }

  Future<void> _accept() async {
    setState(() => _isActing = true);
    try {
      final familyId = ref.read(selectedFamilyIdProvider);
      if (familyId == null) return;
      final api = ref.read(trackcApiClientProvider);
      await api.acceptInsight(widget.insight['id'] as String, familyId);
      ref.invalidate(insightsProvider(widget.insight['decisionId'] as String));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _dismiss(String reason) async {
    setState(() => _isActing = true);
    try {
      final familyId = ref.read(selectedFamilyIdProvider);
      if (familyId == null) return;
      final api = ref.read(trackcApiClientProvider);
      await api.dismissInsight(widget.insight['id'] as String, familyId, reason);
      ref.invalidate(insightsProvider(widget.insight['decisionId'] as String));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to dismiss: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }
}
