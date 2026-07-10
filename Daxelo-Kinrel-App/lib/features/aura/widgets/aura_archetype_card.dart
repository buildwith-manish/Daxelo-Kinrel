// lib/features/aura/widgets/aura_archetype_card.dart
//
// AURA — Archetype Card (Phase 11).
//
// Displays the family's archetype name + poetic 2-line description +
// confidence meter, with a small AURA symbol preview on the left.
//
// Designed to be dropped into the AURA screen, the family detail screen,
// or anywhere else that wants to surface "what kind of family is this?".
// The card itself is stateless — it just renders from AuraArchetype +
// AuraSymbolParameters.

import 'package:flutter/material.dart';

import '../data/archetype_strings.dart';
import '../data/aura_model.dart';
import 'aura_symbol_widget.dart';

class AuraArchetypeCard extends StatelessWidget {
  const AuraArchetypeCard({
    super.key,
    required this.archetype,
    required this.symbol,
    this.memberCount,
    this.compact = false,
  });

  /// The archetype classification to display.
  final AuraArchetype archetype;

  /// Symbol parameters — used for the small preview on the left.
  final AuraSymbolParameters symbol;

  /// Optional member count, shown as a small caption.
  final int? memberCount;

  /// Compact mode: smaller preview, no description, just name + confidence.
  /// Used in drawer / list rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Bug 8 fix: pass the backend's localized definition + the current
    // locale so the card renders the user's language when available.
    final locale = Localizations.localeOf(context).languageCode;
    final strings = archetypeStrings(
      archetype.key,
      definition: archetype.definition,
      locale: locale,
    );
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _parseColor(symbol.primaryColorHex).withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          // ── Symbol preview ─────────────────────────────────────────
          StaticAuraSymbol(
            parameters: symbol,
            archetypeKey: archetype.key,
            size: compact ? 48 : 80,
          ),
          const SizedBox(width: 16),
          // ── Text content ───────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.name,
                  style: (compact
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    // Bug 9 fix: removed the no-op `.replaceAll('\\n', '\n')`.
                    // The archetype_strings.dart and backend ARCHETYPES already
                    // contain real newline characters (Dart single-quoted
                    // strings interpret `\n` as a single newline char). The
                    // replaceAll was searching for the literal 2-char sequence
                    // backslash-n which never matched, producing no change.
                    strings.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                // Confidence meter
                _ConfidenceMeter(
                  confidence: archetype.confidence,
                  color: _parseColor(symbol.primaryColorHex),
                ),
                if (memberCount != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '$memberCount members',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin horizontal bar showing the archetype confidence (0.0–1.0).
class _ConfidenceMeter extends StatelessWidget {
  const _ConfidenceMeter({required this.confidence, required this.color});

  final double confidence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (confidence.clamp(0.0, 1.0) * 100).round();
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: confidence.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          // Bug 16 fix: label is "$pct% confidence" instead of "$pct% match".
          // The backend's confidence formula `0.5 + (winner - runnerUp) / 6`
          // caps at ~0.833 for current archetypes (MAX_POSSIBLE_SCORE = 3 but
          // the highest actual checksTotal is 2). "Match" implies the
          // archetype fits the family X%, which is misleading when the cap
          // is 83%. "Confidence" is honest — it's the classifier's confidence
          // in its own pick, with built-in headroom for future archetypes.
          '$pct% confidence',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

Color _parseColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final value = int.tryParse('FF$h', radix: 16);
    if (value != null) return Color(value);
  }
  return const Color(0xFFC8853A);
}
