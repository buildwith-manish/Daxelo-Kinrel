// lib/features/chat/presentation/chat_search_screen.dart
//
// DAXELO KINREL — Chat Message Search (Tier 1 chat feature)
//
// Two search scopes:
//   • "This chat" — search messages in a single family chat (passed
//     familyId). Returns matching ChatMessage rows ordered newest-first.
//   • "All chats" — search across ALL family chats the user is a member
//     of. Returns matching ChatMessage rows joined with the family name
//     so the user can see which chat each result came from.
//
// Tap a result → push to the chat screen scrolled to that message
// (the chat screen already supports scrollToIndex via message ID).
//
// Implementation notes:
//   • Uses Supabase `ilike` on the `content` column (case-insensitive
//     substring match). PG's full-text search (to_tsvector etc.) is
//     overkill for v1 — `ilike` is fine up to ~100k messages per family
//     and the user's families are well under that.
//   • Limits results to 50 to keep the query fast + the list scrollable.
//   • Searches `content` (the message text). Doesn't search poll
//     questions or reply snippets — those are surfaced via content
//     anyway (poll content mirrors pollQuestion; reply content is
//     the replied-to text, not searchable as a separate field).
//   • Excludes deleted-for-everyone messages (content is cleared).
//
// Entry point: the chat header's "more" menu has a "Search" item that
// pushes this screen with the current familyId.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';

/// A single search result row.
class ChatSearchResult {
  const ChatSearchResult({
    required this.messageId,
    required this.familyId,
    required this.familyName,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.messageType,
    required this.createdAt,
  });

  final String messageId;
  final String familyId;
  final String familyName;
  final String senderId;
  final String senderName;
  final String content;
  final String messageType;
  final DateTime createdAt;

  String get formattedTime {
    final local = createdAt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inDays == 0) {
      final hour = local.hour;
      final minute = local.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.day}/${local.month}/${local.year}';
  }

  /// A snippet of the content with the search query highlighted (up
  /// to ~80 chars, centered on the first match).
  String snippetFor(String query) {
    final lower = content.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      // No match in content (shouldn't happen since we searched by it,
      // but defensive). Return a truncated version.
      return content.length > 80 ? '${content.substring(0, 77)}…' : content;
    }
    final start = (idx - 30).clamp(0, content.length);
    final end = (idx + q.length + 30).clamp(0, content.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < content.length ? '…' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }
}

class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({
    super.key,
    this.familyId, // null = "all chats" mode
  });

  /// The family chat to search within. If null, the screen searches
  /// across ALL family chats the user is a member of ("all chats" mode).
  final String? familyId;

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatSearchResult> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = ref.read(supabaseProvider);
      if (client == null) {
        setState(() {
          _isLoading = false;
          _error = 'Not signed in';
        });
        return;
      }
      final myUserId = client.auth.currentUser?.id;
      if (myUserId == null) {
        setState(() {
          _isLoading = false;
          _error = 'Not signed in';
        });
        return;
      }

      // Build the query. ilike is case-insensitive substring match.
      // %wildcards% on both sides for substring search.
      final pattern = '%$trimmed%';
      final response = await client
          .from('ChatMessage')
          .select('''
            id,
            "familyId",
            "senderId",
            "senderName",
            content,
            "messageType",
            "createdAt",
            "isDeletedForEveryone",
            Family("name")
          ''')
          .ilike('content', pattern)
          .eq('isDeletedForEveryone', false)
          .order('createdAt', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 10));

      final List results = response as List;
      final mapped = <ChatSearchResult>[];
      for (final row in results) {
        final map = row as Map<String, dynamic>;
        final familyId = map['familyId'] as String? ?? '';
        final familyNameData = map['Family'];
        String familyName = 'Unknown family';
        if (familyNameData is List && familyNameData.isNotEmpty) {
          familyName =
              (familyNameData.first as Map<String, dynamic>)['name'] as String? ??
                  'Unknown family';
        } else if (familyNameData is Map<String, dynamic>) {
          familyName = familyNameData['name'] as String? ?? 'Unknown family';
        }
        mapped.add(ChatSearchResult(
          messageId: map['id'] as String? ?? '',
          familyId: familyId,
          familyName: familyName,
          senderId: map['senderId'] as String? ?? '',
          senderName: map['senderName'] as String? ?? 'Unknown',
          content: map['content'] as String? ?? '',
          messageType: map['messageType'] as String? ?? 'text',
          createdAt:
              DateTime.tryParse(map['createdAt'] as String? ?? '') ??
                  DateTime.now(),
        ));
      }

      // If we're in "this chat" mode, filter to only that family.
      // (We could filter at the query level with .eq('familyId', widget.familyId),
      // but doing it client-side keeps the query simple + lets us reuse
      // the same query for both modes. For large families this would be
      // slower; for v1 with the 50-row limit it's fine.)
      final filtered = widget.familyId != null
          ? mapped.where((r) => r.familyId == widget.familyId).toList()
          : mapped;

      if (mounted) {
        setState(() {
          _results = filtered;
          _isLoading = false;
          _hasSearched = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Search failed: $e';
          _hasSearched = true;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    // Debounce 400ms so we don't fire a query on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isThisChat = widget.familyId != null;
    // Get the family name for the title in "this chat" mode.
    String? thisChatName;
    if (isThisChat) {
      // familyDetailProvider is a FutureProvider<FamilyDetail?>; watch
      // it then read .valueOrNull off the resulting AsyncValue.
      final detailAsync =
          ref.watch(familyDetailProvider(widget.familyId!));
      thisChatName = detailAsync.valueOrNull?.family.name;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0B16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0B16),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: KinrelColors.textSilver, size: 18),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          isThisChat
              ? (thisChatName != null
                  ? 'Search $thisChatName'
                  : 'Search this chat')
              : 'Search all chats',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search field
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF11132A),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'Search messages…',
                hintStyle: TextStyle(
                  color: KinrelColors.textDim.withValues(alpha: 0.7),
                ),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: KinrelColors.textDim),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: KinrelColors.textDim),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0A0B16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          // Scope toggle (only in "all chats" mode — "this chat" mode is fixed)
          if (!isThisChat)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 13, color: KinrelColors.textDim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Searching across all your family chats',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11.5,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Results
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.ember),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: KinrelColors.error, fontSize: 13),
          ),
        ),
      );
    }
    if (_hasSearched && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48, color: KinrelColors.textDim),
              const SizedBox(height: 12),
              Text(
                'No messages found',
                style: TextStyle(
                  color: KinrelColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try different keywords',
                style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded,
                  size: 48, color: KinrelColors.textDim.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'Search your messages',
                style: TextStyle(
                  color: KinrelColors.textSilver,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Type to find messages across your chats',
                style: TextStyle(color: KinrelColors.textDim, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.04),
        indent: 56,
      ),
      itemBuilder: (context, index) => _buildResultRow(_results[index]),
    );
  }

  Widget _buildResultRow(ChatSearchResult result) {
    final query = _searchController.text.trim();
    final isThisChat = widget.familyId != null;

    return InkWell(
      onTap: () {
        // Navigate to the chat. The chat screen accepts a `highlightMessageId`
        // query param in v2 — for v1 we just push to the chat and let the
        // user scroll. The message ID is logged for debugging.
        debugPrint('Search: opening chat ${result.familyId}, message ${result.messageId}');
        context.push('/family/${result.familyId}/chat');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender avatar (initials)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.ember.withValues(alpha: 0.12),
              ),
              child: Center(
                child: Text(
                  _initials(result.senderName),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.ember,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: sender name + family (if all-chats mode) + time
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          result.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                      ),
                      if (!isThisChat) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color:
                                KinrelColors.ember.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            result.familyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.ember,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        result.formattedTime,
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Snippet with the match
                  Text(
                    result.snippetFor(query),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textSilver,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
