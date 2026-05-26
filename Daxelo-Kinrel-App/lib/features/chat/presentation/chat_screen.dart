// lib/features/chat/presentation/chat_screen.dart
//
// DAXELO KINREL — Family Chat Screen
//
// Real-time family group messaging UI per KINREL Global Top 1 Prompt §22.
// Dark theme: #13141E background, #191B2C received bubbles, subtle orange
// tint (#E8612A15) sent bubbles, Ignite gradient send button.
//
// Features:
//   - Message types: Text, photo placeholder, voice note placeholder, family event sharing
//   - Read receipts (double tick — orange for read, dim for sent)
//   - Online status indicator (green dot)
//   - Typing indicator (3 bouncing dots animation)
//   - Reply to specific messages
//   - React to messages with emoji
//   - Date separators: "Today", "Yesterday", formatted date
//   - Scroll-to-bottom FAB when scrolled up
//   - Sender name in received group messages (orange)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/chat_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Chat Screen
// ═══════════════════════════════════════════════════════════════════════

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.familyId,
    required this.familyName,
  });

  /// The family ID for this chat.
  final String familyId;

  /// Display name for the AppBar.
  final String familyName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with TickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  bool _showScrollFab = false;
  bool _isComposing = false;

  // Typing indicator animation
  late final AnimationController _typingController;
  late final List<Animation<double>> _dotAnimations;

  // Quick reaction emojis
  static const _reactionEmojis = ['❤️', '😂', '👍', '😮', '😢', '🙏'];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _textController = TextEditingController();
    _focusNode = FocusNode();

    _scrollController.addListener(_onScroll);
    _textController.addListener(_onTextChanged);

    // Typing indicator — 3 bouncing dots
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _dotAnimations = List.generate(3, (index) {
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(
          parent: _typingController,
          curve: Interval(
            index * 0.2,
            0.4 + index * 0.2,
            curve: Curves.easeOut,
          ),
        ),
      );
    });

    // Mark all as read on enter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider(widget.familyId).notifier).markAllRead();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _typingController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.hasClients &&
        _scrollController.position.pixels > 300;
    if (show != _showScrollFab) {
      setState(() => _showScrollFab = show);
    }
  }

  void _onTextChanged() {
    final composing = _textController.text.trim().isNotEmpty;
    if (composing != _isComposing) {
      setState(() => _isComposing = composing);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: KinrelMotion.normal,
        curve: KinrelMotion.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final chatState = ref.read(chatProvider(widget.familyId));
    ref.read(chatProvider(widget.familyId).notifier).sendMessage(
          text,
          replyToId: chatState.replyToMessage?.id,
        );

    _textController.clear();
    _focusNode.requestFocus();

    // Simulate someone typing back after a brief delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        ref.read(chatProvider(widget.familyId).notifier).simulateTyping();
      }
    });
  }

  void _showReactionPicker(String messageId) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _ReactionOverlay(
        onEmojiSelected: (emoji) {
          ref
              .read(chatProvider(widget.familyId).notifier)
              .toggleReaction(messageId, emoji);
          entry.remove();
        },
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.familyId));
    final messages = chatState.messages;

    return DKScaffold(
      backgroundColor: const Color(0xFF13141E),
      appBar: _buildAppBar(chatState),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: Stack(
              children: [
                _buildMessagesList(messages, chatState),
                // Scroll-to-bottom FAB
                if (_showScrollFab) _buildScrollFab(),
              ],
            ),
          ),
          // Typing indicator
          if (chatState.isTyping) _buildTypingIndicator(chatState),
          // Reply preview bar
          if (chatState.replyToMessage != null)
            _buildReplyPreview(chatState.replyToMessage!),
          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(ChatState chatState) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF13141E),
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFF2A2A3D),
              width: 0.5,
            ),
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 20,
                color: KinrelColors.textWhite),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              // Family avatar
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                ),
                child: Center(
                  child: Text(
                    widget.familyName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.familyName,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Green dot for online
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: KinrelColors.success,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${chatState.onlineCount} online',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: KinrelColors.textSilver,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            // Video call placeholder
            IconButton(
              icon: Icon(Icons.videocam_outlined,
                  size: 24, color: KinrelColors.textSilver),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Video call coming soon!'),
                    backgroundColor: KinrelColors.darkCard,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            // Voice call placeholder
            IconButton(
              icon: Icon(Icons.call_outlined,
                  size: 22, color: KinrelColors.textSilver),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Voice call coming soon!'),
                    backgroundColor: KinrelColors.darkCard,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // ── Messages List ────────────────────────────────────────────────

  Widget _buildMessagesList(List<ChatMessage> messages, ChatState chatState) {
    // Group messages by date for separators
    final grouped = _groupByDate(messages);

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final group = grouped[index];
        return Column(
          children: [
            // Date separator
            _buildDateSeparator(group.dateLabel),
            const SizedBox(height: 8),
            // Messages for this date
            ...group.messages.map((msg) {
              final isMe = msg.senderId == 'user_me';
              return Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: _MessageBubble(
                  message: msg,
                  isMe: isMe,
                  onReply: () {
                    ref
                        .read(chatProvider(widget.familyId).notifier)
                        .setReplyTo(msg);
                  },
                  onReact: () => _showReactionPicker(msg.id),
                  onLongPress: () => _showMessageActions(msg),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildDateSeparator(String label) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF202338),
          borderRadius: BorderRadius.circular(KinrelRadius.xl),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: KinrelColors.textSilver,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ── Scroll-to-bottom FAB ─────────────────────────────────────────

  Widget _buildScrollFab() {
    return Positioned(
      right: 16,
      bottom: 8,
      child: GestureDetector(
        onTap: _scrollToBottom,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.darkCard,
            border: Border.all(
              color: const Color(0xFF3A3A4A),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.keyboard_arrow_down,
            color: KinrelColors.textSilver,
            size: 24,
          ),
        ),
      ),
    );
  }

  // ── Typing Indicator ─────────────────────────────────────────────

  Widget _buildTypingIndicator(ChatState chatState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Small avatar
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.ember.withValues(alpha: 0.3),
            ),
            child: Center(
              child: Text(
                chatState.typingUserName?.substring(0, 1).toUpperCase() ?? '?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${chatState.typingUserName ?? 'Someone'} is typing',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver,
            ),
          ),
          const SizedBox(width: 6),
          // Bouncing dots
          SizedBox(
            width: 24,
            height: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _dotAnimations[i],
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _dotAnimations[i].value),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.orange,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reply Preview Bar ────────────────────────────────────────────

  Widget _buildReplyPreview(ChatMessage replyTo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF13141E),
        border: Border(
          top: BorderSide(color: const Color(0xFF2A2A3D), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Orange left bar
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: KinrelColors.orange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  replyTo.senderName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.orange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyTo.content,
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
          IconButton(
            icon: Icon(Icons.close, size: 18, color: KinrelColors.textDim),
            onPressed: () {
              ref
                  .read(chatProvider(widget.familyId).notifier)
                  .clearReplyTo();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  // ── Input Bar ────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF13141E),
        border: Border(
          top: BorderSide(color: const Color(0xFF2A2A3D), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Attachment button
            _AttachmentButton(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Attachments coming soon!'),
                    backgroundColor: KinrelColors.darkCard,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            // Text field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.textDim,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF202338),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KinrelRadius.xl),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KinrelRadius.xl),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KinrelRadius.xl),
                      borderSide: BorderSide(
                        color: KinrelColors.orange.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Send button
            _SendButton(
              isActive: _isComposing,
              onTap: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  // ── Message Actions Bottom Sheet ─────────────────────────────────

  void _showMessageActions(ChatMessage message) {
    final isMe = message.senderId == 'user_me';

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick reactions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _reactionEmojis.map((emoji) {
                    final hasReacted = message.reactions.any(
                      (r) => r.emoji == emoji && r.userId == 'user_me',
                    );
                    return GestureDetector(
                      onTap: () {
                        ref
                            .read(chatProvider(widget.familyId).notifier)
                            .toggleReaction(message.id, emoji);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasReacted
                              ? KinrelColors.orange.withValues(alpha: 0.15)
                              : Colors.transparent,
                          border: hasReacted
                              ? Border.all(
                                  color: KinrelColors.orange
                                      .withValues(alpha: 0.4),
                                  width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Text(emoji, style: TextStyle(fontSize: 22)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Divider(
                  color: const Color(0xFF3A3A4A), height: 1, thickness: 0.5),
              // Reply action
              ListTile(
                leading: Icon(Icons.reply, color: KinrelColors.orange, size: 22),
                title: Text('Reply',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        color: KinrelColors.textWhite)),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(chatProvider(widget.familyId).notifier)
                      .setReplyTo(message);
                },
              ),
              // Copy action
              ListTile(
                leading: Icon(Icons.copy_rounded,
                    color: KinrelColors.textSilver, size: 22),
                title: Text('Copy',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        color: KinrelColors.textWhite)),
                onTap: () {
                  Navigator.pop(context);
                  // Copy to clipboard placeholder
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Message copied!'),
                      backgroundColor: KinrelColors.darkCard,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              // Forward action
              ListTile(
                leading: Icon(Icons.forward,
                    color: KinrelColors.textSilver, size: 22),
                title: Text('Forward',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        color: KinrelColors.textWhite)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Forward coming soon!'),
                      backgroundColor: KinrelColors.darkCard,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              // Delete (only for own messages)
              if (isMe)
                ListTile(
                  leading:
                      Icon(Icons.delete_outline, color: KinrelColors.error, size: 22),
                  title: Text('Delete',
                      style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          color: KinrelColors.error)),
                  onTap: () {
                    Navigator.pop(context);
                    // Delete placeholder
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Date Grouping ────────────────────────────────────────────────

  List<_DateGroup> _groupByDate(List<ChatMessage> messages) {
    final groups = <_DateGroup>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final msg in messages) {
      final msgDate = DateTime(
          msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);

      String label;
      if (msgDate == today) {
        label = 'Today';
      } else if (msgDate == yesterday) {
        label = 'Yesterday';
      } else {
        final months = [
          '',
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December'
        ];
        label = '${months[msg.timestamp.month]} ${msg.timestamp.day}, ${msg.timestamp.year}';
      }

      final existing = groups.where((g) => g.dateLabel == label).firstOrNull;
      if (existing != null) {
        existing.messages.add(msg);
      } else {
        groups.add(_DateGroup(dateLabel: label, messages: [msg]));
      }
    }

    return groups;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Message Bubble Widget
// ═══════════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.onReact,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool isMe;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: EdgeInsets.only(
            left: isMe ? 48 : 0,
            right: isMe ? 0 : 48,
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Reply preview (if replying to a message)
              if (message.replyToId != null) _buildReplyPreview(),
              // Bubble
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isMe
                      ? const Color(0xFFE8612A).withValues(alpha: 0.08)
                      : const Color(0xFF191B2C),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(KinrelRadius.lg),
                    topRight: Radius.circular(KinrelRadius.lg),
                    bottomLeft: Radius.circular(isMe ? KinrelRadius.lg : 4),
                    bottomRight: Radius.circular(isMe ? 4 : KinrelRadius.lg),
                  ),
                  border: isMe
                      ? Border.all(
                          color: KinrelColors.orange.withValues(alpha: 0.12),
                          width: 0.5,
                        )
                      : Border.all(
                          color: const Color(0xFF2A2A3D),
                          width: 0.5,
                        ),
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Sender name (for received messages)
                    if (!isMe) _buildSenderName(),
                    // Message content
                    _buildMessageContent(),
                    // Time and read receipt row
                    _buildTimeRow(),
                  ],
                ),
              ),
              // Reactions row
              if (message.reactions.isNotEmpty) _buildReactions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF202338).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border(
          left: BorderSide(color: KinrelColors.orange, width: 2.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyToSenderName ?? '',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            message.replyToContent ?? '',
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
    );
  }

  Widget _buildSenderName() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Online dot
          if (message.isOnline)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.success,
              ),
            ),
          Text(
            message.senderName,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent() {
    switch (message.messageType) {
      case MessageType.text:
        return Text(
          message.content,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14.5,
            color: isMe ? KinrelColors.textWhite : KinrelColors.textWhite,
            height: 1.45,
          ),
        );

      case MessageType.photo:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo placeholder
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: const Color(0xFF202338),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined,
                      size: 36,
                      color: KinrelColors.textSilver.withValues(alpha: 0.5)),
                  const SizedBox(height: 6),
                  Text(
                    'Photo',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (message.content.isNotEmpty &&
                message.content != 'Photo placeholder') ...[
              const SizedBox(height: 6),
              Text(
                message.content,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );

      case MessageType.voiceNote:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play button
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                ),
                child: Icon(Icons.play_arrow, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 8),
              // Waveform placeholder
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Waveform bars
                    Row(
                      children: List.generate(
                        28,
                        (i) => Container(
                          width: 2.5,
                          height: 6 + (i % 5) * 4.0,
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            color: isMe
                                ? KinrelColors.orange.withValues(alpha: 0.5)
                                : KinrelColors.textSilver
                                    .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${message.durationSeconds ?? 0}s',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case MessageType.familyEvent:
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: KinrelColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(KinrelRadius.md),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Event icon and type
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient,
                    ),
                    child: Icon(Icons.celebration,
                        size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Family Event',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.orange,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Event title
              if (message.eventTitle != null)
                Text(
                  message.eventTitle!,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              const SizedBox(height: 3),
              // Event date
              if (message.eventDate != null)
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 12, color: KinrelColors.orange),
                    const SizedBox(width: 4),
                    Text(
                      message.eventDate!,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ],
                ),
              if (message.content.isNotEmpty &&
                  message.content != 'Event shared') ...[
                const SizedBox(height: 6),
                Text(
                  message.content,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }

  Widget _buildTimeRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Text(
            message.formattedTime,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
          // Read receipts (only for sent messages)
          if (isMe) ...[
            const SizedBox(width: 4),
            _ReadReceipt(isRead: message.isRead),
          ],
        ],
      ),
    );
  }

  Widget _buildReactions() {
    final grouped = message.groupedReactions;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: grouped.entries.map((entry) {
          final hasMyReaction = message.reactions.any(
            (r) => r.emoji == entry.key && r.userId == 'user_me',
          );
          return GestureDetector(
            onTap: onReact,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hasMyReaction
                    ? KinrelColors.orange.withValues(alpha: 0.12)
                    : const Color(0xFF202338),
                borderRadius: BorderRadius.circular(KinrelRadius.xl),
                border: Border.all(
                  color: hasMyReaction
                      ? KinrelColors.orange.withValues(alpha: 0.3)
                      : const Color(0xFF3A3A4A),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.key, style: TextStyle(fontSize: 13)),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 2),
                    Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: hasMyReaction
                            ? KinrelColors.orange
                            : KinrelColors.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Read Receipt (Double Tick)
// ═══════════════════════════════════════════════════════════════════════

class _ReadReceipt extends StatelessWidget {
  const _ReadReceipt({required this.isRead});

  final bool isRead;

  @override
  Widget build(BuildContext context) {
    final color = isRead ? KinrelColors.orange : KinrelColors.textDim;

    return SizedBox(
      width: 16,
      height: 10,
      child: CustomPaint(
        painter: _DoubleTickPainter(color: color),
      ),
    );
  }
}

/// Paints a WhatsApp-style double tick.
class _DoubleTickPainter extends CustomPainter {
  _DoubleTickPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.55);
    path1.lineTo(size.width * 0.2, size.height * 0.85);
    path1.lineTo(size.width * 0.42, size.height * 0.15);

    final path2 = Path();
    path2.moveTo(size.width * 0.35, size.height * 0.55);
    path2.lineTo(size.width * 0.55, size.height * 0.85);
    path2.lineTo(size.width * 0.95, size.height * 0.15);

    canvas.drawPath(path1, paint);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════
// Send Button (Ignite Gradient Circle)
// ═══════════════════════════════════════════════════════════════════════

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isActive,
    required this.onTap,
  });

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isActive ? onTap : null,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isActive
              ? KinrelGradients.igniteGradient
              : LinearGradient(
                  colors: [
                    const Color(0xFF202338),
                    const Color(0xFF202338),
                  ],
                ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: KinrelColors.orange.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.send_rounded,
          size: 20,
          color: isActive
              ? Colors.white
              : KinrelColors.textDim,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Attachment Button
// ═══════════════════════════════════════════════════════════════════════

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF202338),
        ),
        child: Icon(
          Icons.attach_file_rounded,
          size: 22,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Reaction Overlay (Popup)
// ═══════════════════════════════════════════════════════════════════════

class _ReactionOverlay extends StatelessWidget {
  const _ReactionOverlay({
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onDismiss;

  static const _emojis = ['❤️', '😂', '👍', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Dismissable background
          SizedBox.expand(),
          // Reaction bar centered
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(context).size.height * 0.55,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202338),
                    borderRadius: BorderRadius.circular(KinrelRadius.xxl),
                    border: Border.all(
                      color: const Color(0xFF3A3A4A),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _emojis.map((emoji) {
                      return GestureDetector(
                        onTap: () => onEmojiSelected(emoji),
                        child: Container(
                          width: 42,
                          height: 42,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              emoji,
                              style: TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Date Group Helper
// ═══════════════════════════════════════════════════════════════════════

class _DateGroup {
  _DateGroup({required this.dateLabel, required this.messages});

  final String dateLabel;
  final List<ChatMessage> messages;
}
