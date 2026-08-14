// Daxelo-Kinrel — Relationship Suggestion Sheet (spec §18)
// ==========================================================
// Modal bottom sheet shown when the user long-presses node A and taps
// "Relate to Another Person" → taps node B. Implements the auto-detect
// workflow per spec §10.
//
// File: lib/features/family/presentation/widgets/relationship_suggestion_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/relationship_engine.dart';

/// Provider for the offline engine instance.
final relationshipEngineProvider = Provider<RelationshipEngine>((ref) {
  return RelationshipEngine();
});

/// Provider for the offline vocabulary mapper.
final vocabularyMapperProvider = Provider<VocabularyMapper>((ref) {
  return VocabularyMapper();
});

/// Result of an auto-detect attempt (spec §10).
class DetectionResult {
  final bool detected;
  final String? localizedTerm;
  final String? englishTerm;
  final String? canonicalId;
  final KinshipSignature? signature;
  final bool requiresUserConfirmation;
  final String? missingEdgeDescription;
  final String? failureReason;

  const DetectionResult({
    required this.detected,
    this.localizedTerm,
    this.englishTerm,
    this.canonicalId,
    this.signature,
    this.requiresUserConfirmation = false,
    this.missingEdgeDescription,
    this.failureReason,
  });
}

/// Widget that displays the detection result and prompts for confirmation.
class RelationshipSuggestionSheet extends ConsumerStatefulWidget {
  final String personAName;
  final String personBName;
  final DetectionResult detection;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onPickManualEdge;

  const RelationshipSuggestionSheet({
    super.key,
    required this.personAName,
    required this.personBName,
    required this.detection,
    this.onConfirm,
    this.onCancel,
    this.onPickManualEdge,
  });

  /// Convenience: show as a modal bottom sheet.
  static Future<void> showAsModal(
    BuildContext context, {
    required String personAName,
    required String personBName,
    required DetectionResult detection,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    VoidCallback? onPickManualEdge,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RelationshipSuggestionSheet(
        personAName: personAName,
        personBName: personBName,
        detection: detection,
        onConfirm: onConfirm,
        onCancel: onCancel,
        onPickManualEdge: onPickManualEdge,
      ),
    );
  }

  @override
  ConsumerState<RelationshipSuggestionSheet> createState() => _RelationshipSuggestionSheetState();
}

class _RelationshipSuggestionSheetState extends ConsumerState<RelationshipSuggestionSheet> {
  @override
  Widget build(BuildContext context) {
    final d = widget.detection;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Text(
              'Relate ${widget.personAName} → ${widget.personBName}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Body — three branches per spec §10:
            //  (1) detection succeeded with a fundamental edge → confirm
            //  (2) detection succeeded but term is DERIVED → missing-edge prompt
            //  (3) detection failed → manual picker with 4 fundamental options
            if (!d.detected) ...[
              _FailureCard(reason: d.failureReason ?? 'Insufficient graph info.'),
              const SizedBox(height: 16),
              _ManualEdgePicker(
                onPick: (edge) {
                  Navigator.of(context).pop();
                  widget.onPickManualEdge?.call();
                },
              ),
            ] else if (d.requiresUserConfirmation) ...[
              _MissingEdgeCard(
                detectedTerm: d.englishTerm ?? '',
                missingDescription: d.missingEdgeDescription ?? '',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () { Navigator.of(context).pop(); widget.onCancel?.call(); },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () { Navigator.of(context).pop(); widget.onConfirm?.call(); },
                      child: const Text('Confirm edge'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              _DetectedCard(
                term: d.localizedTerm ?? d.englishTerm ?? '',
                englishTerm: d.englishTerm ?? '',
                signatureKey: d.signature?.signatureKey ?? '',
              ),
              const SizedBox(height: 16),
              if (d.signature != null)
                _SignatureDebugBox(signature: d.signature!),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () { Navigator.of(context).pop(); widget.onCancel?.call(); },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                      onPressed: () { Navigator.of(context).pop(); widget.onConfirm?.call(); },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetectedCard extends StatelessWidget {
  final String term;
  final String englishTerm;
  final String signatureKey;
  const _DetectedCard({required this.term, required this.englishTerm, required this.signatureKey});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detected', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(term, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (englishTerm != term) ...[
              const SizedBox(height: 4),
              Text(englishTerm, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _MissingEdgeCard extends StatelessWidget {
  final String detectedTerm;
  final String missingDescription;
  const _MissingEdgeCard({required this.detectedTerm, required this.missingDescription});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.help_outline, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Text('Action needed', style: Theme.of(context).textTheme.labelMedium),
            ]),
            const SizedBox(height: 8),
            Text(
              '"$detectedTerm" is a derived label. The engine needs one more fundamental edge to confirm.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(missingDescription, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  final String reason;
  const _FailureCard({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Text('Cannot auto-detect', style: Theme.of(context).textTheme.labelMedium),
            ]),
            const SizedBox(height: 8),
            Text(reason, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ManualEdgePicker extends StatelessWidget {
  final void Function(String edge) onPick;
  const _ManualEdgePicker({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final options = const [
      ('Parent', Icons.arrow_upward, 'PARENT'),
      ('Spouse', Icons.favorite, 'SPOUSE'),
      ('Adoptive Parent', Icons.family_restroom, 'ADOPTIVE_PARENT'),
      ('Step Parent', Icons.family_restroom, 'STEP_PARENT'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick the fundamental edge:', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((o) {
            return ActionChip(
              avatar: Icon(o.$2, size: 16),
              label: Text(o.$1),
              onPressed: () => onPick(o.$3),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SignatureDebugBox extends StatelessWidget {
  final KinshipSignature signature;
  const _SignatureDebugBox({required this.signature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Signature (debug)', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          SelectableText(
            signature.signatureKey,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
