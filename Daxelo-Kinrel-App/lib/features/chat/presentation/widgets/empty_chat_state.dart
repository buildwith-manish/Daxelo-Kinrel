// lib/features/chat/presentation/widgets/empty_chat_state.dart
//
// DAXELO KINREL — Feature 3: Empty Chat State
//
// Shown when a family chat has zero messages. Displays:
//   • A warm greeting ("Start the conversation in Sharmas 👋")
//   • Upcoming birthday/anniversary chips (if any) with quick-reply
//     suggestions like "Wish Mama ji happy birthday 🎂 (in 3 days)"
//   • Tappable quick-reply chips that fill the input bar with the
//     suggested message (one tap to send, no typing required)
//
// The suggestions come from the backend GET /families/:familyId/chat/nudge
// endpoint, which queries the kinship graph + the Person table for
// upcoming birthdays within the next 30 days.
//
// Design: matches the Kinrel brand language — dark background, ember
// accent, soft glow behind the greeting icon. The quick-reply chips
// use the same pill style as the relationship chip in the AppBar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/networking/dio_client.dart';
import '../../../../l10n/app_localizations.dart';

/// Snapshot of the empty-state nudge data fetched from the backend.
class EmptyStateNudge {
  const EmptyStateNudge({
    required this.familyName,
    required this.memberCount,
    required this.upcomingEvents,
    required this.suggestions,
  });

  final String familyName;
  final int memberCount;
  final List<UpcomingEvent> upcomingEvents;
  final List<String> suggestions;

  factory EmptyStateNudge.fromJson(Map<String, dynamic> json) {
    return EmptyStateNudge(
      familyName: json['familyName'] as String? ?? 'your family',
      memberCount: json['memberCount'] as int? ?? 0,
      upcomingEvents: ((json['upcomingEvents'] as List?) ?? [])
          .map((e) => UpcomingEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      suggestions: ((json['suggestions'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class UpcomingEvent {
  const UpcomingEvent({
    required this.personId,
    required this.name,
    required this.eventType,
    required this.daysUntil,
  });

  final String personId;
  final String name;
  final String eventType; // 'birthday' | 'anniversary'
  final int daysUntil;

  factory UpcomingEvent.fromJson(Map<String, dynamic> json) {
    return UpcomingEvent(
      personId: json['personId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      eventType: json['eventType'] as String? ?? 'birthday',
      daysUntil: json['daysUntil'] as int? ?? 0,
    );
  }

  /// Human-readable label for the chip: "Mama ji's birthday in 3 days"
  /// or "Mama ji's birthday is today!" when daysUntil == 0.
  ///
  /// Feature 7: use [labelLocalized] in widgets for locale-aware labels.
  /// This legacy getter returns the English-only version.
  String get label => labelLocalized(null);

  /// Feature 7: locale-aware label. Falls back to English if [l10n] is null.
  String labelLocalized(S? l10n) {
    if (daysUntil == 0) {
      return l10n?.chatBirthdayToday(name) ?? "$name's birthday is today! 🎂";
    }
    if (daysUntil == 1) {
      return l10n?.chatBirthdayTomorrow(name) ?? "$name's birthday tomorrow 🎂";
    }
    return l10n?.chatBirthdayInDays(name, daysUntil) ??
        "$name's birthday in $daysUntil days 🎂";
  }
}

/// Riverpod future provider that fetches the nudge data from the backend.
/// Returns null if the fetch fails (the empty state still shows generic
/// suggestions in that case).
final emptyStateNudgeProvider =
    FutureProvider.family<EmptyStateNudge?, String>((ref, familyId) async {
  try {
    final dio = ref.watch(dioProvider);
    final response = await dio.get('/api/families/$familyId/chat/nudge');
    final data = response.data;
    // The ResponseEnvelopeInterceptor wraps responses in {success, data, ...}.
    // Handle both wrapped + unwrapped responses.
    final payload = data is Map<String, dynamic> && data.containsKey('data')
        ? data['data'] as Map<String, dynamic>?
        : data is Map<String, dynamic>
            ? data
            : null;
    if (payload == null) return null;
    return EmptyStateNudge.fromJson(payload);
  } catch (e) {
    // Silent — the empty state shows generic suggestions on failure.
    return null;
  }
});

/// The empty-state widget. Shown when the chat has zero messages.
///
/// [onSuggestionTap] is called when the user taps a quick-reply chip.
/// The chat_screen's sendMessage handler is invoked with the suggestion
/// text, so one tap sends the message immediately.
class EmptyChatState extends ConsumerWidget {
  const EmptyChatState({
    super.key,
    required this.familyId,
    required this.onSuggestionTap,
  });

  final String familyId;
  final void Function(String suggestion) onSuggestionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nudgeAsync = ref.watch(emptyStateNudgeProvider(familyId));

    return nudgeAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: KinrelColors.ember,
          strokeWidth: 1.5,
        ),
      ),
      error: (_, __) => _buildContent(context, null),
      data: (nudge) => _buildContent(context, nudge),
    );
  }

  Widget _buildContent(BuildContext context, EmptyStateNudge? nudge) {
    final familyName = nudge?.familyName ?? 'your family';
    final memberCount = nudge?.memberCount ?? 0;
    // Feature 7: use localized suggestions as fallback when the backend
    // nudge fetch fails or returns no suggestions.
    final l10n = S.of(context);
    final suggestions = nudge?.suggestions ??
        [
          l10n?.chatSuggestionNamaste ?? 'Namaste everyone 🙏',
          l10n?.chatSuggestionHowIsEveryone ?? 'How is everyone doing?',
        ];
    final upcomingEvents = nudge?.upcomingEvents ?? <UpcomingEvent>[];

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Greeting icon with ember glow ──────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.ember.withValues(alpha: 0.10),
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.ember.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '👋',
                  style: TextStyle(
                    fontSize: 36,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Greeting headline ───────────────────────────────────────
            Text(
              l10n?.chatEmptyStateTitle ?? 'Start the conversation',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                letterSpacing: 0.1,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              // Feature 7: localized subtitle with family name + member count
              memberCount > 0
                  ? (l10n?.chatEmptyStateSubtitle(familyName, memberCount) ??
                      'in the $familyName family ($memberCount members)')
                  : (l10n?.chatEmptyStateSubtitleNoCount(familyName) ??
                      'in the $familyName family'),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13.5,
                color: KinrelColors.textSilver.withValues(alpha: 0.8),
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // ── Upcoming event chips (birthday/anniversary) ────────────
            if (upcomingEvents.isNotEmpty) ...[
              for (final event in upcomingEvents.take(2)) ...[
                _EventChip(event: event),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
            ],

            // ── Quick-reply suggestion chips ────────────────────────────
            // Tapping a chip fills the input bar with the suggestion text.
            // The user can then send it as-is or edit it.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions
                  .map((s) => _SuggestionChip(
                        text: s,
                        onTap: () => onSuggestionTap(s),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pill-shaped chip showing an upcoming birthday/anniversary.
/// Non-interactive (informational only) — the quick-reply suggestions
/// below are the actionable elements.
class _EventChip extends StatelessWidget {
  const _EventChip({required this.event});
  final UpcomingEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KinrelColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: KinrelColors.gold.withValues(alpha: 0.30),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '🎂',
            style: TextStyle(fontSize: 12, decoration: TextDecoration.none),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              // Feature 7: locale-aware event label
              event.labelLocalized(S.of(context)),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: KinrelColors.gold,
                decoration: TextDecoration.none,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable quick-reply suggestion chip. Tapping it fills the input
/// bar with the suggestion text (or sends immediately, depending on the
/// chat_screen's onSuggestionTap handler).
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: KinrelColors.ember.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: KinrelColors.ember.withValues(alpha: 0.25),
              width: 0.6,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: KinrelColors.textSilver,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
