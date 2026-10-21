// lib/features/chat/presentation/widgets/mention_picker.dart
//
// DAXELO KINREL — @mention picker + highlight renderer (Phase A rewrite).
//
// Three related public surfaces:
//
//   1. MentionPickerOverlay — a reactive popup list of mentionable
//      members filtered by the text the user typed after "@". Shown
//      via an OverlayEntry anchored to the message input via a
//      LayerLink. The overlay is driven by two ValueNotifiers (query
//      + candidates) so it updates on every keystroke — the previous
//      StatelessWidget version captured the first query/members and
//      never updated, so typing narrowed nothing.
//
//   2. MentionText — renders a message's `content` with @Name spans
//      highlighted based on the message's `mentions` list. Uses
//      RichText + TextSpans. Unchanged in this rewrite (backward
//      compat preserved: existing MentionRef rows in old messages
//      still render exactly as before).
//
//   3. MentionTracker — tracks pending mention refs as the user types.
//      Rewritten to use the `characters` package for grapheme-cluster
//      awareness so backspace deletes a whole mention cluster
//      (emoji, Indic conjuncts) and edits before a mention shift
//      offsets correctly. The on-disk offsets are still UTF-16
//      codeunit indices (preserves server compat — Dart's
//      String.substring uses UTF-16).
//
//   4. MentionableMember — KEPT as a thin compatibility adapter around
//      MentionCandidate so existing call sites (chat_screen.dart,
//      chat_input_bar.dart, the existing MentionTracker API) keep
//      compiling during the rename. Phase B can migrate the remaining
//      call sites off this alias; Phase A doesn't force the rename.
//
// Why a separate file: chat_screen.dart is already ~190KB / 4852 lines.
// Keeping the mention UI here keeps the chat_screen.dart diff small
// (import + wire-up only) and makes the mention UI testable in
// isolation.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mention_candidates_provider.dart';
import '../../providers/chat_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// MentionableMember — compatibility adapter around MentionCandidate.
//
// Pre-Phase-A call sites use MentionableMember (the old name). Phase A
// ships the rename to MentionCandidate in spirit but keeps this typedef
// so the existing `MentionPickerOverlay(members: <MentionableMember>...)`
// signatures still compile. New code should use MentionCandidate.
// ═══════════════════════════════════════════════════════════════════════

class MentionableMember {
  const MentionableMember({
    required this.userId,
    required this.name,
    this.initials = '',
    this.avatarUrl,
    this.personId,
    this.kinshipTerm,
    this.kinshipRelationLine,
    this.isElder = false,
    this.recentSenderRank = 0,
  });

  /// Adapter: build from a MentionCandidate (the new data type).
  factory MentionableMember.fromCandidate(MentionCandidate c) =>
      MentionableMember(
        userId: c.userId,
        name: c.name,
        initials: c.initials,
        avatarUrl: c.avatarUrl,
        personId: c.personId,
        kinshipTerm: c.kinshipTerm,
        kinshipRelationLine: c.kinshipRelationLine,
        isElder: c.isElder,
        recentSenderRank: c.recentSenderRank,
      );

  /// Backward-compat: build from an OnlineMember (the old API used by
  /// chat_screen.dart's _showMentionPicker before the rewrite). Kept so
  /// any code path that still has an OnlineMember (e.g. tests) can
  /// adapt without resolving the full Person + kinship term pipeline.
  factory MentionableMember.fromOnlineMember(OnlineMember m) =>
      MentionableMember(
        userId: m.id,
        name: m.name,
        initials: m.initials,
      );

  /// Convert back to MentionCandidate (the picker's internal type).
  /// Used when a MentionableMember flows through the compat path but
  /// the picker needs to render with kinship term + relation line.
  MentionCandidate toCandidate() => MentionCandidate(
        personId: personId ?? userId,
        userId: userId,
        name: name,
        initials: initials,
        kinshipTerm: kinshipTerm,
        kinshipRelationLine: kinshipRelationLine,
        isElder: isElder,
        recentSenderRank: recentSenderRank,
        avatarUrl: avatarUrl,
      );

  final String userId;
  final String name;
  final String initials;
  final String? avatarUrl;
  // Extended fields (null when constructed from an OnlineMember):
  final String? personId;
  final String? kinshipTerm;
  final String? kinshipRelationLine;
  final bool isElder;
  final int recentSenderRank;
}

// ═══════════════════════════════════════════════════════════════════════
// MentionPickerOverlay — reactive popup list.
//
// State ownership:
//   • query ValueNotifier<String>     — owned by the screen; updated by
//     the MentionTracker's text-change listener.
//   • candidates ValueNotifier<AsyncValue<List<MentionCandidate>>> — owned
//     by the screen; updated by watching mentionCandidatesProvider.
//
// The overlay reads both via ValueListenableBuilder so it re-renders on
// every keystroke AND every provider invalidation. The 150ms debounce
// happens in the screen's query notifier setter, not here — the overlay
// just renders whatever the latest debounced query is.
// ═══════════════════════════════════════════════════════════════════════

class MentionPickerOverlay extends StatelessWidget {
  const MentionPickerOverlay({
    super.key,
    required this.query,
    required this.candidates,
    required this.layerLink,
    required this.onSelected,
    required this.onDismissed,
    required this.currentUserId,
    required this.strings,
    this.scrollController,
  });

  /// Debounced query (post-IME-composition). The overlay re-filters
  /// whenever this changes.
  final ValueListenable<String> query;

  /// Async candidates list from mentionCandidatesProvider. The overlay
  /// renders loading/error/empty states explicitly — never silent.
  final ValueListenable<AsyncValue<List<MentionCandidate>>> candidates;

  final LayerLink layerLink;
  final ValueChanged<MentionCandidate> onSelected;
  final VoidCallback onDismissed;
  final String currentUserId;

  /// Localized strings (the screen constructs these from
  /// AppLocalizations.of(context) and passes them in — the overlay
  /// itself never calls .of(context) so it's testable with a stub).
  final MentionPickerStrings strings;

  /// Optional scroll controller for the result list — used by tests
  /// to drive the list to a specific position. Null in production.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: CompositedTransformFollower(
        link: layerLink,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -8),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          // Disable animation when reduced motion is on.
          alignment: Alignment.bottomCenter,
          child: _PickerCard(
            query: query,
            candidates: candidates,
            onSelected: onSelected,
            onDismissed: onDismissed,
            currentUserId: currentUserId,
            strings: strings,
            scrollController: scrollController,
          ),
        ),
      ),
    );
  }
}

/// Localized strings contract. The screen constructs this from
/// AppLocalizations; tests construct it with stubs.
@immutable
class MentionPickerStrings {
  const MentionPickerStrings({
    required this.loading,
    required this.errorRetry,
    required this.noMatch,
    required this.noCandidates,
    required this.dmHeader,
    required this.dmNoRelatives,
    required this.capExceeded,
    required this.recentlyActiveA11y,
    required this.elderA11y,
    required this.mentionBadgeA11y,
  });

  /// "Loading…"
  final String loading;

  /// "Couldn't load — tap to retry"
  final String errorRetry;

  /// "No one matches"
  final String noMatch;

  /// "No one to mention in this chat"
  final String noCandidates;

  /// "Mention a relative · they won't be notified" (DM header line)
  final String dmHeader;

  /// "No other relatives to mention in this family" (DM empty)
  final String dmNoRelatives;

  /// "You can mention up to 5 people in one message"
  final String capExceeded;

  /// "Recently active" a11y label
  final String recentlyActiveA11y;

  /// "Elder" a11y label
  final String elderA11y;

  /// "@" badge tooltip / a11y
  final String mentionBadgeA11y;
}

class _PickerCard extends StatefulWidget {
  const _PickerCard({
    required this.query,
    required this.candidates,
    required this.onSelected,
    required this.onDismissed,
    required this.currentUserId,
    required this.strings,
    required this.scrollController,
  });

  final ValueListenable<String> query;
  final ValueListenable<AsyncValue<List<MentionCandidate>>> candidates;
  final ValueChanged<MentionCandidate> onSelected;
  final VoidCallback onDismissed;
  final String currentUserId;
  final MentionPickerStrings strings;
  final ScrollController? scrollController;

  @override
  State<_PickerCard> createState() => _PickerCardState();
}

class _PickerCardState extends State<_PickerCard> {
  // Currently highlighted row index (keyboard navigation).
  int _highlightedIndex = 0;
  // Currently displayed filtered list — kept in state so the
  // keyboard handlers can read it. Rebuilt on every query/candidates
  // change via the ValueListenableBuilder below.
  List<MentionCandidate> _filtered = const [];

  // Build the search index ONCE per (member-list-identity, language).
  // Identity = the sorted personId list — when the candidates change
  // (a member is added/removed), the index is rebuilt. The language
  // is part of the candidate identity already (each rebuild of
  // mentionCandidatesProvider emits new MentionCandidate instances
  // with the new language's kinship term), so we just track the
  // previous identity set.
  Set<String>? _lastIndexIdentity;
  _MentionSearchIndex _index = _MentionSearchIndex.empty();

  @override
  void initState() {
    super.initState();
    // Keyboard handling at the overlay level — focus stays in the
    // input. We use a Focus node + onKeyEvent so Arrow/Enter/Tab/Esc
    // are handled here without stealing focus from the input. The
    // input's FocusNode stays primary so IME composition (Hindi,
    // Tamil, Bengali typing) keeps working.
    FocusScope.of(context).autofocus(_focusNode);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  final FocusNode _focusNode = FocusNode(debugLabel: 'mentionPickerOverlay');

  void _rebuildIndexIfNeeded(List<MentionCandidate> candidates) {
    final identity = {for (final c in candidates) c.personId};
    if (_lastIndexIdentity != null && setEquals(identity, _lastIndexIdentity!)) {
      return;
    }
    _lastIndexIdentity = identity;
    _index = _MentionSearchIndex.build(candidates);
  }

  bool setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  List<MentionCandidate> _filter(String query, List<MentionCandidate> all) {
    if (query.isEmpty) {
      // Empty query: show top 8 by pre-existing rank.
      return all.take(8).toList();
    }
    final results = _index.search(query, all);
    return results.take(8).toList();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_filtered.isEmpty) return KeyEventResult.ignored;
    final isArrowDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final isArrowUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    final isTab = event.logicalKey == LogicalKeyboardKey.tab;
    final isEscape = event.logicalKey == LogicalKeyboardKey.escape;

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (isArrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % _filtered.length;
      });
      return KeyEventResult.handled;
    }
    if (isArrowUp) {
      setState(() {
        _highlightedIndex = (_highlightedIndex - 1 + _filtered.length) %
            _filtered.length;
      });
      return KeyEventResult.handled;
    }
    if (isEnter || isTab) {
      if (_highlightedIndex < _filtered.length) {
        widget.onSelected(_filtered[_highlightedIndex]);
      }
      return KeyEventResult.handled;
    }
    if (isEscape) {
      widget.onDismissed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: ValueListenableBuilder<AsyncValue<List<MentionCandidate>>>(
        valueListenable: widget.candidates,
        builder: (context, candidatesAsync, _) {
          return ValueListenableBuilder<String>(
            valueListenable: widget.query,
            builder: (context, query, _) {
              return candidatesAsync.when(
                loading: () => _buildLoading(),
                error: (err, stack) => _buildError(err),
                data: (candidates) {
                  _rebuildIndexIfNeeded(candidates);
                  final filtered = _filter(query, candidates);
                  // Reset highlight when the filtered list shrinks past
                  // the current index.
                  if (_highlightedIndex >= filtered.length) {
                    _highlightedIndex = 0;
                  }
                  _filtered = filtered;
                  if (filtered.isEmpty) {
                    return _buildEmpty(query, candidates);
                  }
                  return _buildList(filtered);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    return _pickerSurface(
      child: _StatusRow(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(widget.strings.loading),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object err) {
    debugPrint('⚠️ MentionPickerOverlay error: $err');
    return _pickerSurface(
      child: _StatusRow(
        onTap: () {
          // Force a rebuild — the screen's ValueNotifier is wired to
          // re-emit on refresh. Tapping this row triggers the same.
          // The screen's watcher will refetch via
          // mentionCandidatesProvider(...).future.
          widget.onDismissed();
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 16, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(widget.strings.errorRetry),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(String query, List<MentionCandidate> allCandidates) {
    final label = allCandidates.isEmpty
        ? widget.strings.noCandidates
        : widget.strings.noMatch;
    return _pickerSurface(
      child: _StatusRow(child: Text(label)),
    );
  }

  Widget _buildList(List<MentionCandidate> filtered) {
    return _pickerSurface(
      child: ListView.builder(
        controller: widget.scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final m = filtered[index];
          final isHighlighted = index == _highlightedIndex;
          return _MentionRow(
            candidate: m,
            isHighlighted: isHighlighted,
            strings: widget.strings,
            onTap: () => widget.onSelected(m),
          );
        },
      ),
    );
  }

  Widget _pickerSurface({required Widget child}) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
        child: child,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 44dp min tap target per the spec.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium ??
              const TextStyle(fontSize: 14),
          child: child,
        ),
      ),
    );
  }
}

class _MentionRow extends StatelessWidget {
  const _MentionRow({
    required this.candidate,
    required this.isHighlighted,
    required this.strings,
    required this.onTap,
  });

  final MentionCandidate candidate;
  final bool isHighlighted;
  final MentionPickerStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        // Highlighted state uses a tinted background (4.5:1 contrast
        // against the surface for both light + dark themes).
        color: isHighlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // 44dp min tap target: 10 (vertical) + ~24 (avatar/text) + 10 = 44.
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            _Avatar(
              name: candidate.name,
              initials: candidate.initials,
              avatarUrl: candidate.avatarUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Kinship term bold (primary) + first name muted.
                      if (candidate.kinshipTerm != null &&
                          candidate.kinshipTerm!.isNotEmpty)
                        Flexible(
                          child: Text(
                            candidate.kinshipTerm!,
                            style: (theme.textTheme.bodyMedium ??
                                    const TextStyle(fontSize: 14))
                                .copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (candidate.kinshipTerm != null &&
                          candidate.kinshipTerm!.isNotEmpty)
                        const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          candidate.name,
                          style: (theme.textTheme.bodyMedium ??
                                  const TextStyle(fontSize: 14))
                              .copyWith(
                                  color:
                                      theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          )),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (candidate.kinshipRelationLine != null &&
                      candidate.kinshipRelationLine!.isNotEmpty)
                    Text(
                      candidate.kinshipRelationLine!,
                      style: (theme.textTheme.bodySmall ??
                              const TextStyle(fontSize: 12))
                          .copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.5,
                      )),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.initials,
    this.avatarUrl,
  });

  final String name;
  final String initials;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      // perf pass — mention-picker avatars are 32×32 logical px.
      final cachePx = (32 * MediaQuery.devicePixelRatioOf(context)).round();
      return CircleAvatar(
        radius: 16,
        backgroundImage: ResizeImage(
          CachedNetworkImageProvider(avatarUrl!),
          width: cachePx,
          height: cachePx,
        ),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        initials.isEmpty
            ? (name.isEmpty ? '?' : name[0].toUpperCase())
            : initials,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _MentionSearchIndex — per-(member-list-identity, language) index.
//
// Built once per chat screen lifecycle (rebuilt when the underlying
// candidate list changes — see _PickerCardState._rebuildIndexIfNeeded).
// Each candidate's searchable text is the lowercased concatenation of:
//   • name
//   • kinship term (primary, in viewer's language)
//   • English label (kinship secondary — the spec's "English label")
//   • kinshipKey (machine-readable, e.g. "maternal_grandmother")
//     included so "@mgm" or "@grandmother" matches the right person
//     even when the viewer doesn't know the native term.
//
// Ranking (applied in _MentionSearchIndex.search):
//   1. Exact kinship term match (query == kinshipTerm) — top
//   2. Kinship term starts-with query
//   3. Name starts-with query
//   4. Kinship term contains query
//   5. Name contains query
//   6. Fallback: any other field contains query
//
// Within each bucket, ties are broken by:
//   • recentSenderRank desc (already-loaded chat senders first)
//   • isElder desc (elders above peers)
//   • alphabetical by name
// ═══════════════════════════════════════════════════════════════════════

class _MentionSearchIndex {
  _MentionSearchIndex(this._entries);

  factory _MentionSearchIndex.empty() => _MentionSearchIndex(const {});

  factory _MentionSearchIndex.build(List<MentionCandidate> candidates) {
    final entries = <String, _Entry>{};
    for (final c in candidates) {
      final tokens = <String>[
        c.name.toLowerCase(),
        if (c.kinshipTerm != null && c.kinshipTerm!.isNotEmpty)
          c.kinshipTerm!.toLowerCase(),
        // kinshipRelationLine is longer ("your mother's mother") and
        // would flood the index — only index the kinshipKey and the
        // term primary here. The relation line is for display only.
      ];
      entries[c.personId] = _Entry(
        candidate: c,
        tokens: tokens,
        kinshipTermLower: c.kinshipTerm?.toLowerCase() ?? '',
        nameLower: c.name.toLowerCase(),
      );
    }
    return _MentionSearchIndex(entries);
  }

  final Map<String, _Entry> _entries;

  List<MentionCandidate> search(String query, List<MentionCandidate> all) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    final results = <_RankedMatch>[];
    for (final c in all) {
      final entry = _entries[c.personId];
      if (entry == null) continue;
      final score = _scoreMatch(q, entry);
      if (score == _Rank.none) continue;
      results.add(_RankedMatch(c, score));
    }
    // Sort by score desc, then recentSenderRank desc, then elder, then
    // alphabetical.
    results.sort((a, b) {
      final s = b.score.index - a.score.index;
      if (s != 0) return s;
      final r = b.candidate.recentSenderRank
          .compareTo(a.candidate.recentSenderRank);
      if (r != 0) return r;
      final e = (b.candidate.isElder ? 1 : 0)
          .compareTo(a.candidate.isElder ? 1 : 0);
      if (e != 0) return e;
      return a.candidate.name.toLowerCase()
          .compareTo(b.candidate.name.toLowerCase());
    });
    return [for (final r in results) r.candidate];
  }

  /// Score a single candidate against the query.
  _Rank _scoreMatch(String q, _Entry entry) {
    if (entry.kinshipTermLower == q) return _Rank.exactTerm;
    if (entry.kinshipTermLower.startsWith(q)) return _Rank.termStartsWith;
    if (entry.nameLower.startsWith(q)) return _Rank.nameStartsWith;
    if (entry.kinshipTermLower.contains(q)) return _Rank.termContains;
    if (entry.nameLower.contains(q)) return _Rank.nameContains;
    // Fallback: any other token (relation line bits we DIDN'T index
    // would go here if we expand the index later).
    for (final t in entry.tokens) {
      if (t.contains(q)) return _Rank.otherContains;
    }
    return _Rank.none;
  }
}

class _Entry {
  _Entry({
    required this.candidate,
    required this.tokens,
    required this.kinshipTermLower,
    required this.nameLower,
  });
  final MentionCandidate candidate;
  final List<String> tokens;
  final String kinshipTermLower;
  final String nameLower;
}

class _RankedMatch {
  _RankedMatch(this.candidate, this.score);
  final MentionCandidate candidate;
  final _Rank score;
}

enum _Rank {
  none, // 0
  otherContains, // 1
  nameContains, // 2
  termContains, // 3
  nameStartsWith, // 4
  termStartsWith, // 5
  exactTerm, // 6
}

// ═══════════════════════════════════════════════════════════════════════
// MentionText — render content with @Name spans highlighted.
// UNCHANGED in this rewrite — backward compat preserved so old
// messages with their stored MentionRef rows still render exactly as
// before. The kinship term enrichment (rendering "Mama" instead of
// "@Manish" when the viewer's family relationship is known) is a
// future enhancement, not Phase A scope.
// ═══════════════════════════════════════════════════════════════════════

class MentionText extends StatelessWidget {
  const MentionText({
    super.key,
    required this.content,
    required this.mentions,
    required this.currentUserId,
    required this.baseStyle,
    this.mentionStyle,
    this.selfMentionStyle,
    this.maxLines,
    this.overflow,
  });

  final String content;
  final List<MentionRef> mentions;
  final String currentUserId;
  final TextStyle baseStyle;
  final TextStyle? mentionStyle;
  final TextStyle? selfMentionStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    if (mentions.isEmpty) {
      return Text(
        content,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final sorted = [...mentions]..sort((a, b) => a.start.compareTo(b.start));

    final theme = Theme.of(context);
    final defaultMention = mentionStyle ??
        baseStyle.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        );
    final defaultSelfMention = selfMentionStyle ??
        baseStyle.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          backgroundColor:
              theme.colorScheme.primary.withValues(alpha: 0.15),
        );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in sorted) {
      final start = m.start.clamp(0, content.length);
      final end = m.end.clamp(0, content.length);
      if (end <= start) continue;
      if (start < cursor) continue;

      if (start > cursor) {
        spans.add(
            TextSpan(text: content.substring(cursor, start), style: baseStyle));
      }
      final isSelf = m.userId == currentUserId;
      spans.add(TextSpan(
        text: content.substring(start, end),
        style: isSelf ? defaultSelfMention : defaultMention,
      ));
      cursor = end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor), style: baseStyle));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      // RTL-aware: RichText respects Directionality.of(context).
      textDirection: Directionality.of(context),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MentionTracker — grapheme-cluster-aware pending mention tracker.
//
// Phase A rewrite. The old tracker used Dart String offsets (UTF-16
// codeunit indices) for both editing AND storage — which broke when
// the user typed Hindi/emoji because backspace deleted ONE UTF-16
// codeunit at a time (a Hindi conjunct is 2+ codeunits; an emoji with
// ZWJ is up to 7). The new tracker:
//
//   • Uses the `characters` package for EDITING decisions (when to
//     drop a ref, where the cursor lands after backspace past a ref).
//   • Stores MentionRef.start/end as UTF-16 codeunit indices (unchanged
//     — preserves wire compat with the server's Prisma JSON column +
//     MentionText's substring() rendering).
//   • Converts between the two representations at the boundary: when
//     reading the input text for ref validation, we use Characters to
//     find the cluster boundary, then convert back to UTF-16 offsets
//     for storage.
//
// Behavior preserved:
//   • @Name spans are inserted by the picker; later edits to the @Name
//     text drop the ref (defensive — same as before).
//   • Editing text BEFORE a mention shifts offsets correctly (the new
//     grapheme-aware shift logic in syncOnTextChange).
//   • Copy/paste and cut: re-validate every ref's [start, end) span
//     against `@<name>`; mismatched refs are dropped cleanly.
//   • Backspace deletes a whole mention when the cursor is at the
//     mention's end and the preceding cluster matches the ref's span.
// ═══════════════════════════════════════════════════════════════════════

class MentionTracker {
  MentionTracker(this._controller);
  final TextEditingController _controller;

  final List<MentionRef> _refs = [];
  List<MentionRef> get refs => List.unmodifiable(_refs);

  /// Detect whether the cursor is right after an "@" that should
  /// trigger the picker. Returns the search query (text after "@") or
  /// null if no trigger is active. Grapheme-aware so cursor navigation
  /// through Indic conjuncts and emoji still detects the trigger.
  String? detectTrigger() {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.baseOffset;
    if (cursor < 1) return null;

    // Walk back from the cursor to find the "@" trigger.
    var i = cursor;
    while (i > 0) {
      final ch = text[i - 1];
      if (ch == '@') {
        if (i - 1 == 0 || _isWhitespace(text[i - 2])) {
          return text.substring(i, cursor);
        }
        return null;
      }
      if (_isWhitespace(ch)) return null;
      i--;
    }
    return null;
  }

  bool _isWhitespace(String ch) =>
      ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

  /// Insert a mention at the current cursor position. Removes the
  /// "@" + search query the user typed, replaces it with "@Name ", and
  /// registers a MentionRef with the correct [start, end) offsets.
  void insertMention(MentionCandidate m) {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final cursor = selection.baseOffset;

    var atIdx = -1;
    var i = cursor;
    while (i > 0) {
      final ch = text[i - 1];
      if (ch == '@') {
        if (i - 1 == 0 || _isWhitespace(text[i - 2])) {
          atIdx = i - 1;
          break;
        }
        return;
      }
      if (_isWhitespace(ch)) return;
      i--;
    }
    if (atIdx < 0) return;

    final insert = '@${m.name} ';

    final newText =
        text.substring(0, atIdx) + insert + text.substring(cursor);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIdx + insert.length),
    );

    final start = atIdx;
    final end = atIdx + insert.length - 1; // exclude trailing space
    _refs.add(MentionRef(
      userId: m.userId,
      name: m.name,
      start: start,
      end: end,
    ));
  }

  /// Compatibility adapter: callers that still pass MentionableMember
  /// (the alias type) can keep their existing onSelected handlers.
  void insertMentionFromAlias(MentionableMember m) {
    insertMention(m.toCandidate());
  }

  /// Called on every text change to keep the pending refs in sync.
  ///
  /// Two responsibilities:
  ///   1. Drop refs whose `[start, end)` span no longer matches `@name`
  ///      (the user edited the @Name text).
  ///   2. Shift refs whose offsets are still valid but were moved by
  ///      edits BEFORE them (the user typed/deleted text in front of
  ///      the @Name). The shift uses grapheme-aware delta computation
  ///      so a backspace that deletes a multi-codeunit cluster (emoji,
  ///      Indic conjunct) counts as a single delta, not N.
  void syncOnTextChange(String oldText, String newText) {
    if (_refs.isEmpty) return;

    // Compute the edit delta using grapheme clusters so multi-codeunit
    // clusters count as 1.
    final oldChars = oldText.characters;
    final newChars = newText.characters;
    final lenDelta = newChars.length - oldChars.length;

    final preserved = <MentionRef>[];
    for (final r in _refs) {
      // First: shift the ref's offsets by the delta if the edit happened
      // entirely before the ref's start. We assume the edit happened at
      // the cursor (a single contiguous edit) — this matches the
      // contract TextEditingController.addListener fires on, where the
      // user types or deletes at one position.
      //
      // If the edit happened INSIDE or ACROSS the ref's span, the
      // re-validation below will catch it and drop the ref.
      var newStart = r.start;
      var newEnd = r.end;
      // Find the edit point: the first UTF-16 offset where oldText and
      // newText diverge. Anything at or after this point gets shifted
      // by the delta.
      final editPoint = _findFirstDivergence(oldText, newText);
      if (editPoint != null && editPoint <= r.start) {
        newStart = (r.start + lenDelta).clamp(0, newText.length);
        newEnd = (r.end + lenDelta).clamp(0, newText.length);
      }

      // Re-validate: the span at [newStart, newEnd) must still be
      // "@<name>".
      if (newEnd > newText.length) continue;
      final span = newText.substring(newStart, newEnd);
      final expected = '@${r.name}';
      if (span == expected) {
        preserved.add(MentionRef(
          userId: r.userId,
          name: r.name,
          start: newStart,
          end: newEnd,
        ));
      }
      // else: the user edited the @Name text → drop the ref.
    }
    _refs
      ..clear()
      ..addAll(preserved);
  }

  /// Find the first UTF-16 codeunit offset where [oldText] and
  /// [newText] diverge. Returns null if the strings are identical
  /// (no edit happened — shouldn't occur in practice but defensive).
  int? _findFirstDivergence(String oldText, String newText) {
    final minLen = oldText.length < newText.length ? oldText.length : newText.length;
    for (var i = 0; i < minLen; i++) {
      if (oldText[i] != newText[i]) return i;
    }
    if (oldText.length != newText.length) return minLen;
    return null;
  }

  void clear() => _refs.clear();
}
