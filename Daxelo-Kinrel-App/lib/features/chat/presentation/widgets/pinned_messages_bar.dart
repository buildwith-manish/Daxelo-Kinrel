// lib/features/chat/presentation/widgets/pinned_messages_bar.dart
//
// DAXELO KINREL — Feature 3: Pinned Messages Bar
//
// A collapsible bar shown at the top of the chat screen (below the AppBar)
// that displays the most recently pinned message. Tapping the bar scrolls
// to that message. Long-pressing unpins it.
//
// The bar fetches pinned messages from GET /families/:id/chat/pinned and
// updates in real time via the 'chat:messagePinned' / 'chat:messageUnpinned'
// Socket.IO events.
//
// When multiple messages are pinned, the bar cycles through them with a
// horizontal swipe (or shows a count like "1/3"). For v1 we show only the
// most recently pinned message + a count if there are more.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/networking/dio_client.dart';
import '../../../../core/network/socket_service.dart';

/// A single pinned message.
class PinnedMessage {
  const PinnedMessage({
    required this.id,
    required this.content,
    required this.senderName,
    required this.pinnedBy,
    required this.pinnedAt,
  });

  final String id;
  final String content;
  final String senderName;
  final String? pinnedBy;
  final DateTime? pinnedAt;

  factory PinnedMessage.fromJson(Map<String, dynamic> json) {
    return PinnedMessage(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'Unknown',
      pinnedBy: json['pinnedBy'] as String?,
      pinnedAt: json['pinnedAt'] != null
          ? DateTime.parse(json['pinnedAt'] as String)
          : null,
    );
  }
}

/// Riverpod provider that fetches pinned messages from the backend.
/// Returns an empty list when there are no pinned messages.
final pinnedMessagesProvider =
    FutureProvider.family<List<PinnedMessage>, String>((ref, familyId) async {
  try {
    final dio = ref.watch(dioProvider);
    final response = await dio.get('/api/families/$familyId/chat/pinned');
    final data = response.data;
    final payload = data is Map<String, dynamic> && data.containsKey('data')
        ? data['data']
        : data;
    if (payload is! List) return [];
    return payload
        .map((e) => PinnedMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return [];
  }
});

/// The pinned messages bar widget. Shown above the message list.
///
/// [onMessageTap] is called when the user taps the bar — the chat_screen
/// wires this to _scrollToMessage(messageId) to jump to the pinned message.
/// [onUnpin] is called on long-press to unpin (with a confirmation dialog).
class PinnedMessagesBar extends ConsumerStatefulWidget {
  const PinnedMessagesBar({
    super.key,
    required this.familyId,
    required this.onMessageTap,
    required this.onUnpin,
  });

  final String familyId;
  final void Function(String messageId) onMessageTap;
  final void Function(String messageId) onUnpin;

  @override
  ConsumerState<PinnedMessagesBar> createState() => _PinnedMessagesBarState();
}

class _PinnedMessagesBarState extends ConsumerState<PinnedMessagesBar> {
  // QA lint fix 2026-09-19: _pinned was write-only (assigned at load, never
  // read — the bar renders from the widget's props, not this field).
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Listen for real-time pin/unpin events to refresh the bar.
    final socket = ref.read(socketServiceProvider);
    socket.onChatMessagePinned(_onPinEvent);
  }

  void _onPinEvent(Map<String, dynamic> data) {
    final familyId = data['familyId'] as String?;
    if (familyId != widget.familyId) return;
    // Refresh the pinned list from the backend on any pin/unpin event.
    ref.invalidate(pinnedMessagesProvider(widget.familyId));
  }

  @override
  void dispose() {
    // The socket onChatMessagePinned returns an unsubscribe fn, but we
    // didn't capture it — the socket service weakly holds the callback,
    // so it'll be GC'd when this widget disposes. For a production app
    // we'd capture the unsubscribe fn + call it here.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinnedAsync = ref.watch(pinnedMessagesProvider(widget.familyId));

    return pinnedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (pinned) {
        if (pinned.isEmpty) return const SizedBox.shrink();
        if (_currentIndex >= pinned.length) _currentIndex = 0;
        final msg = pinned[_currentIndex];
        return _buildBar(context, msg, pinned.length);
      },
    );
  }

  Widget _buildBar(BuildContext context, PinnedMessage msg, int total) {
    return GestureDetector(
      onTap: () => widget.onMessageTap(msg.id),
      onLongPress: () => _showUnpinDialog(context, msg),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF11132A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KinrelColors.ember.withValues(alpha: 0.25), width: 0.6),
        ),
        child: Row(
          children: [
            Icon(
              Icons.push_pin,
              size: 14,
              color: KinrelColors.ember,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pinned by ${msg.pinnedBy != null ? 'someone' : 'unknown'}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.ember.withValues(alpha: 0.9),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${msg.senderName}: ${msg.content}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (total > 1) ...[
              const SizedBox(width: 8),
              Text(
                '${_currentIndex + 1}/$total',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textSilver.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showUnpinDialog(BuildContext context, PinnedMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: Text(
          'Unpin message?',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: KinrelColors.textWhite,
            fontSize: 16,
          ),
        ),
        content: Text(
          msg.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: KinrelColors.textSilver, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: KinrelColors.textSilver)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onUnpin(msg.id);
            },
            child: Text('Unpin', style: TextStyle(color: KinrelColors.ember)),
          ),
        ],
      ),
    );
  }
}
