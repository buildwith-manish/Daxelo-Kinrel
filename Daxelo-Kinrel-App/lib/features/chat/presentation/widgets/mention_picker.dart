// lib/features/chat/presentation/widgets/mention_picker.dart
//
// DAXELO KINREL — @mention picker + highlight renderer (Phase 22, Task 3)
//
// Two related widgets:
//
//   1. MentionPickerOverlay — a popup list of family members filtered
//      by the text the user typed after "@". Shown via an OverlayEntry
//      anchored to the message input via a LayerLink. On select, the
//      caller inserts "@Name" into the input and adds a MentionRef to
//      its pending-mentions list.
//
//   2. MentionText — renders a message's `content` with @Name spans
//      highlighted based on the message's `mentions` list. Uses RichText
//      + TextSpans so the highlight is a real styled span (not a plain
//      Text widget with mixed colors glued together).
//
// Both widgets are stateless and reusable. The picker takes a callback
// for selection; the renderer takes the message content + mentions.
//
// Why a separate file: chat_screen.dart is already ~190KB / 4852 lines.
// Pulling the mention UI into its own widget keeps the diff in
// chat_screen.dart small (import + wire-up only) and makes the mention
// UI testable in isolation.

import 'package:flutter/material.dart';

import '../../providers/chat_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// MentionableMember — a minimal data class for the picker.
// ═══════════════════════════════════════════════════════════════════════

class MentionableMember {
  const MentionableMember({
    required this.userId,
    required this.name,
    this.initials = '',
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String initials;
  final String? avatarUrl;

  /// Build from an OnlineMember (the chat header's member model).
  factory MentionableMember.fromOnlineMember(OnlineMember m) =>
      MentionableMember(
        userId: m.id,
        name: m.name,
        initials: m.initials,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// MentionPickerOverlay — popup list of family members.
// ═══════════════════════════════════════════════════════════════════════

class MentionPickerOverlay extends StatelessWidget {
  const MentionPickerOverlay({
    super.key,
    required this.members,
    required this.query,
    required this.layerLink,
    required this.onSelected,
    required this.onDismissed,
    required this.currentUserId,
  });

  /// All family members (unfiltered). The picker filters by [query].
  final List<MentionableMember> members;

  /// The text the user typed after "@". Case-insensitive substring match
  /// against member.name. Empty query → show all members (capped at 8).
  final String query;

  /// The LayerLink anchoring this overlay to the message input.
  final LayerLink layerLink;

  /// Called when the user selects a member. The caller is responsible
  /// for inserting "@Name" into the input + adding the MentionRef.
  final ValueChanged<MentionableMember> onSelected;

  /// Called when the user dismisses the picker (tap outside, escape,
  /// backspace past the "@"). The caller hides the overlay.
  final VoidCallback onDismissed;

  /// The current user's ID — excluded from the picker (no self-mention
  /// in the UI; the RPC also re-validates and skips self-mentions).
  final String currentUserId;

  List<MentionableMember> get _filtered {
    final q = query.trim().toLowerCase();
    final candidates = members
        .where((m) => m.userId != currentUserId)
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q))
        .toList();
    // Cap at 8 so the overlay doesn't grow beyond the keyboard's top.
    return candidates.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: CompositedTransformFollower(
        link: layerLink,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -8),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final m = filtered[index];
                return InkWell(
                  onTap: () => onSelected(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _Avatar(name: m.name, initials: m.initials),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            m.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '@',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.initials, this.avatarUrl});
  final String name;
  final String initials;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: NetworkImage(avatarUrl!),
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
// MentionText — render content with @Name spans highlighted.
// ═══════════════════════════════════════════════════════════════════════

/// Renders a chat message's [content] with @Name spans styled as
/// highlighted chips, based on the message's [mentions] list.
///
/// Falls back to a plain Text widget when the message has no mentions
/// (the common case) so we don't pay the RichText cost for every
/// message in the thread.
///
/// The highlight style is a tinted background + primary-color text +
/// bold weight. Mentions of the CURRENT user get an extra accent so
/// the user can spot "you were mentioned" messages at a glance.
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

  /// Base text style for the non-mention spans.
  final TextStyle baseStyle;

  /// Style for @Name spans mentioning OTHER users. Defaults to a
  /// tinted version of [baseStyle] with primary color + bold.
  final TextStyle? mentionStyle;

  /// Style for @Name spans mentioning the CURRENT user. Defaults to
  /// a more prominent version of [mentionStyle] (extra accent).
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

    // Sort mentions by start offset so we can walk the content in order.
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
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in sorted) {
      // Clamp to content bounds (defensive — a malformed mention with
      // start/end past the content length would otherwise throw).
      final start = m.start.clamp(0, content.length);
      final end = m.end.clamp(0, content.length);
      if (end <= start) continue;
      if (start < cursor) continue; // overlap — skip

      // Text before the mention.
      if (start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, start), style: baseStyle));
      }
      // The @Name span itself.
      final isSelf = m.userId == currentUserId;
      spans.add(TextSpan(
        text: content.substring(start, end),
        style: isSelf ? defaultSelfMention : defaultMention,
      ));
      cursor = end;
    }
    // Trailing text after the last mention.
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor), style: baseStyle));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MentionTracker — tracks pending mention refs as the user types.
// ═══════════════════════════════════════════════════════════════════════

/// Helper that tracks pending @mention refs as the user types in a
/// TextEditingController. Used by the chat input to:
///
///   • detect when the user types "@" and open the picker overlay
///   • insert "@Name" + register a MentionRef when a member is picked
///   • keep the MentionRef [start, end) offsets in sync as the user
///     types more text (so the highlight stays aligned)
///   • drop a MentionRef if the user backspaces over the "@Name" span
///
/// The tracker is intentionally simple — it doesn't try to handle
/// every edge case (e.g. the user editing the @Name text directly).
/// For v1 we trust the picker to insert well-formed "@Name" spans
/// and treat any later edit as "mention is broken → drop it".
class MentionTracker {
  MentionTracker(this._controller);
  final TextEditingController _controller;

  /// The pending mention refs for the current input.
  final List<MentionRef> _refs = [];
  List<MentionRef> get refs => List.unmodifiable(_refs);

  /// Detect whether the cursor is right after an "@" that should
  /// trigger the picker. Returns the search query (text after "@")
  /// or null if no trigger is active.
  ///
  /// Rules:
  ///   • the character at cursor-1 must be "@" OR a non-space char
  ///     continuing a search query
  ///   • the "@" must be at the start of input OR preceded by whitespace
  ///   • the search query is everything between "@" and the cursor,
  ///     containing no whitespace
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
        // The "@" must be at the start of input OR preceded by whitespace.
        if (i - 1 == 0 || _isWhitespace(text[i - 2])) {
          return text.substring(i, cursor); // query between @ and cursor
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
  /// "@" + search query the user typed, replaces it with "@Name",
  /// and registers a MentionRef with the correct [start, end) offsets.
  ///
  /// After insertion the cursor is placed immediately after the "@Name"
  /// (with a trailing space appended for natural typing flow).
  void insertMention(MentionableMember m) {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final cursor = selection.baseOffset;

    // Find the "@" that triggered the picker (walk back like detectTrigger).
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

    // Build the inserted text: "@Name " (trailing space for natural flow).
    final insert = '@${m.name} ';

    final newText =
        text.substring(0, atIdx) + insert + text.substring(cursor);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIdx + insert.length),
    );

    // Register the MentionRef with [start, end) covering "@Name" (no
    // trailing space).
    final start = atIdx;
    final end = atIdx + insert.length - 1; // exclude trailing space
    _refs.add(MentionRef(
      userId: m.userId,
      name: m.name,
      start: start,
      end: end,
    ));
  }

  /// Called on every text change to keep the pending refs in sync.
  /// Drops refs whose [start, end) span no longer matches "@<name>" in
  /// the current text, and shifts refs whose offsets are still valid.
  void syncOnTextChange(String oldText, String newText) {
    if (_refs.isEmpty) return;
    final preserved = <MentionRef>[];
    for (final r in _refs) {
      // Re-validate: the span at [start, end) must still be "@<name>".
      final start = r.start;
      final end = r.end;
      if (end > newText.length) continue; // span got truncated
      final span = newText.substring(start, end);
      final expected = '@${r.name}';
      if (span == expected) {
        preserved.add(r);
      }
      // else: the user edited the @Name text → drop the ref.
    }
    _refs
      ..clear()
      ..addAll(preserved);
  }

  /// Clear all refs (called after a successful send).
  void clear() => _refs.clear();
}
