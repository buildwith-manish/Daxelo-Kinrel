import 'package:kinrel/core/widgets/global_error_widget.dart';
// lib/features/chat/presentation/chat_screen.dart
//
// DAXELO KINREL — Family Chat Screen
//
// Real-time family group messaging UI per KINREL Global Top 1 Prompt §22.
// Dark theme: #13141E background, #191B2C received bubbles, subtle orange
// tint (#E8612A15) sent bubbles, Ignite gradient send button.
//
// Features (v109.10 — full chat enhancement):
//   - Long-press message menu: Delete for Me, Delete for Everyone, Copy,
//     Forward, Reply, React, Edit, Star, Pin
//   - Read receipts: single tick (sent) → double tick (delivered) →
//     double blue tick (read)
//   - Message reactions (emoji reaction bar)
//   - Reply-to-message threading (quote block above message)
//   - Typing indicator + online status
//   - Message editing
//   - Starred messages
//   - Pinned messages (admin/creator)
//   - Forward to other families
//   - Date separators: "Today", "Yesterday", formatted date
//   - Scroll-to-bottom FAB when scrolled up

import 'dart:async';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/chat_enhancement_service.dart';
import '../providers/chat_provider.dart';
import 'voice_message_player.dart';
import 'sticker_panel.dart';

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

  // Phase 13: Voice recorder state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSendingVoice = false;
  Duration _recordingDuration = Duration.zero;
  String? _recordingPath;
  Timer? _recordingTimer;

  // Phase 14: Sticker panel toggle
  bool _showStickerPanel = false;

  // Quick reaction emojis
  static const _reactionEmojis = ['❤️', '😂', '👍', '😮', '😢', '🙏'];

  // The real current user id (replaces the old hard-coded 'user_me' check).
  // Read from chatCurrentUserIdProvider which is wired to Supabase auth.
  String? get _currentUserId =>
      ref.read(chatCurrentUserIdProvider);

  /// Returns true if [msg] was sent by the current user.
  bool _isMine(ChatMessage msg) =>
      msg.senderId == _currentUserId;

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
    // Phase 13: stop the recording timer + dispose the recorder
    _recordingTimer?.cancel();
    _recordingTimer = null;
    // If we're mid-recording when the screen closes, stop it
    // (best-effort; ignore errors since the recorder may already be gone).
    if (_isRecording) {
      try { _recorder.stop(); } catch (_) {}
    }
    _recorder.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show =
        _scrollController.hasClients && _scrollController.position.pixels > 300;
    if (show != _showScrollFab) {
      // CRITICAL ANR FIX: Added mounted check before setState to prevent
      // listener callbacks from triggering rebuilds after widget disposal
      if (mounted) {
        setState(() => _showScrollFab = show);
      }
    }
  }

  void _onTextChanged() {
    final composing = _textController.text.trim().isNotEmpty;
    if (composing != _isComposing) {
      // CRITICAL ANN FIX: Added mounted check before setState.
      if (mounted) {
        setState(() => _isComposing = composing);
      }
      // v109.11: Send typing status to Supabase
      final service = ref.read(chatEnhancementServiceProvider);
      service.setTypingStatus(widget.familyId, composing);
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
    // sendMessage() does an optimistic insert synchronously, then persists
    // to Supabase async. Fire-and-forget the Future — the UI already
    // updated and the realtime INSERT event will be de-duped by the
    // notifier.
    final replyToId = chatState.replyToMessage?.id;
    Future.microtask(() {
      ref
          .read(chatProvider(widget.familyId).notifier)
          .sendMessage(text, replyToId: replyToId);
    });

    _textController.clear();
    _focusNode.requestFocus();
    // Phase 14: hide sticker panel when sending a text message
    if (_showStickerPanel && mounted) {
      setState(() => _showStickerPanel = false);
    }
  }

  // ── Phase 14: Sticker send ──────────────────────────────────────────

  void _sendSticker(String emoji) {
    final chatState = ref.read(chatProvider(widget.familyId));
    final replyToId = chatState.replyToMessage?.id;
    Future.microtask(() {
      ref
          .read(chatProvider(widget.familyId).notifier)
          .sendSticker(emoji, replyToId: replyToId);
    });
    if (mounted) {
      setState(() => _showStickerPanel = false);
    }
  }

  void _toggleStickerPanel() {
    // Hide keyboard when opening sticker panel
    if (!_showStickerPanel) {
      _focusNode.unfocus();
    }
    setState(() => _showStickerPanel = !_showStickerPanel);
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

    // Loading state — show a centered spinner while the initial fetch
    // is in flight. Once _initialLoadDone is true (set by the notifier
    // after _loadMessages), isLoading flips back to false.
    Widget bodyContent;
    if (chatState.isLoading && messages.isEmpty) {
      bodyContent = const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    } else if (chatState.error != null && messages.isEmpty) {
      bodyContent = _buildErrorState(chatState.error!);
    } else {
      bodyContent = Stack(
        children: [
          _buildMessagesList(messages, chatState),
          // Scroll-to-bottom FAB
          if (_showScrollFab) _buildScrollFab(),
          // Inline error banner (non-blocking) if a send failed
          if (chatState.error != null && messages.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildInlineErrorBanner(chatState.error!),
            ),
        ],
      );
    }

    return DKScaffold(
      backgroundColor: const Color(0xFF13141E),
      appBar: _buildAppBar(chatState),
      body: Column(
        children: [
          // Messages list
          Expanded(child: bodyContent),
          // Typing indicator
          if (chatState.isTyping) _buildTypingIndicator(chatState),
          // Reply preview bar
          if (chatState.replyToMessage != null)
            _buildReplyPreview(chatState.replyToMessage!),
          // Phase 14: Sticker panel (slides up when toggled)
          if (_showStickerPanel && !_isRecording)
            StickerPanel(
              onStickerSelected: _sendSticker,
              onClose: _toggleStickerPanel,
            ),
          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  // ── Error states ─────────────────────────────────────────────────

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: KinrelColors.textDim),
            const SizedBox(height: 12),
            const Text(
              'Could not load messages',
              style: TextStyle(
                color: KinrelColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KinrelColors.textDim,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                ref.read(chatProvider(widget.familyId).notifier).reload();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineErrorBanner(String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.redAccent.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
            bottom: BorderSide(color: const Color(0xFF2A2A3D), width: 0.5),
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              size: 20,
              color: KinrelColors.textWhite,
            ),
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
                    (widget.familyName.isNotEmpty ? widget.familyName.substring(0, 1) : 'F').toUpperCase(),
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
            // Video call
            IconButton(
              icon: Icon(
                Icons.videocam_outlined,
                size: 24,
                color: KinrelColors.textSilver,
              ),
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
            // Voice call
            IconButton(
              icon: Icon(
                Icons.call_outlined,
                size: 22,
                color: KinrelColors.textSilver,
              ),
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
            // v109.11: Chat settings (wallpaper, mute)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: KinrelColors.textSilver, size: 22),
              color: KinrelColors.darkCard,
              onSelected: (value) {
                switch (value) {
                  case 'wallpaper':
                    _showWallpaperPicker();
                    break;
                  case 'mute':
                    _toggleMute();
                    break;
                  case 'starred':
                    _showStarredMessages();
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'wallpaper', child: Text('Wallpaper')),
                const PopupMenuItem(value: 'mute', child: Text('Mute notifications')),
                const PopupMenuItem(value: 'starred', child: Text('Starred messages')),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // v109.11: Wallpaper picker
  void _showWallpaperPicker() {
    final colors = [
      {'name': 'Default', 'color': '#131416'},
      {'name': 'Midnight', 'color': '#0D1117'},
      {'name': 'Deep Ocean', 'color': '#0A1929'},
      {'name': 'Forest', 'color': '#0D1F17'},
      {'name': 'Plum', 'color': '#1A0D1F'},
      {'name': 'Ember', 'color': '#1F1208'},
      {'name': 'Slate', 'color': '#1E1E2E'},
      {'name': 'Rose', 'color': '#1F0D15'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat Wallpaper',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                )),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: colors.length,
              itemBuilder: (ctx, index) {
                final c = colors[index];
                final colorValue = int.parse(c['color']!.substring(1, 7), radix: 16);
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    final service = ref.read(chatEnhancementServiceProvider);
                    await service.saveChatSettings(
                      familyId: widget.familyId,
                      wallpaperColor: c['color'],
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Wallpaper changed to ${c['name']}'),
                          backgroundColor: KinrelColors.darkCard,
                        ),
                      );
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(colorValue),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KinrelColors.border, width: 1),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _toggleMute() async {
    final service = ref.read(chatEnhancementServiceProvider);
    final settings = await service.getChatSettings(widget.familyId);
    final isMuted = settings?['isMuted'] as bool? ?? false;
    await service.saveChatSettings(familyId: widget.familyId, isMuted: !isMuted);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!isMuted ? 'Chat muted' : 'Chat unmuted'),
          backgroundColor: KinrelColors.darkCard,
        ),
      );
    }
  }

  void _showStarredMessages() {
    final chatState = ref.read(chatProvider(widget.familyId));
    final starred = chatState.messages.where((m) => m.isStarred).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, controller) => Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: KinrelColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Starred Messages',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                )),
            const SizedBox(height: 16),
            Expanded(
              child: starred.isEmpty
                  ? Center(
                      child: Text('No starred messages',
                          style: TextStyle(color: KinrelColors.textDim)))
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: starred.length,
                      itemBuilder: (ctx, index) {
                        final msg = starred[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: KinrelColors.darkCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: KinrelColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(msg.senderName,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: KinrelColors.orange)),
                              const SizedBox(height: 4),
                              Text(msg.content,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: KinrelColors.textWhite)),
                              const SizedBox(height: 4),
                              Text(msg.formattedTime,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: KinrelColors.textDim)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
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
              final isMe = _isMine(msg);
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
            border: Border.all(color: const Color(0xFF3A3A4A), width: 1),
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
                ((chatState.typingUserName != null && chatState.typingUserName!.isNotEmpty) ? chatState.typingUserName!.substring(0, 1) : '?').toUpperCase(),
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
                return KinrelAnimatedBuilder(
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
              ref.read(chatProvider(widget.familyId).notifier).clearReplyTo();
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
    // Phase 13: when recording, replace the entire input bar with the
    // recording UI (cancel + timer + send). Otherwise, show the normal
    // text field + a mic button that toggles to a send button when
    // the user types.
    if (_isRecording) {
      return _buildRecordingBar();
    }

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
              onTap: () => _pickAndSendAttachment(),
            ),
            const SizedBox(width: 6),
            // Phase 14: Sticker toggle button
            _StickerButton(
              isActive: _showStickerPanel,
              onTap: _toggleStickerPanel,
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
            // Phase 13: Mic button when empty, Send button when typing.
            // If voice sending is in-flight, show a spinner.
            if (_isSendingVoice)
              const SizedBox(
                width: 44, height: 44,
                child: Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KinrelColors.orange,
                    ),
                  ),
                ),
              )
            else if (_isComposing)
              _SendButton(isActive: true, onTap: _sendMessage)
            else
              _MicButton(onTap: _startRecording),
          ],
        ),
      ),
    );
  }

  // ── Phase 13: Voice recording bar ──────────────────────────────────

  Widget _buildRecordingBar() {
    final minutes = _recordingDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _recordingDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            // Pulsing red recording dot
            const _RecordingDot(),
            const SizedBox(width: 12),
            // Timer
            Text(
              '$minutes:$seconds',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Recording…',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
            const Spacer(),
            // Cancel button
            GestureDetector(
              onTap: _cancelRecording,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF202338),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: KinrelColors.textSilver,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            GestureDetector(
              onTap: _sendRecording,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                  boxShadow: [
                    BoxShadow(
                      color: KinrelColors.orange.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Phase 13: Voice recorder methods ────────────────────────────────

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Microphone permission denied.'),
              backgroundColor: KinrelColors.darkCard,
            ),
          );
        }
        return;
      }

      // Build a unique temp path for the recording
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = _audioFileExtension();
      final fileName = 'voice_$timestamp.$ext';
      final path = await _resolveRecordingPath(fileName);

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _recordingDuration = Duration.zero;
      });

      // Tick every second
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _recordingTimer?.cancel();
          return;
        }
        setState(() {
          _recordingDuration = _recordingDuration + const Duration(seconds: 1);
        });
        // Safety: cap recording at 5 minutes
        if (_recordingDuration.inSeconds >= 300) {
          _sendRecording();
        }
      });
    } catch (e) {
      debugPrint('⚠️ _startRecording failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start recording: $e'),
            backgroundColor: KinrelColors.darkCard,
          ),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final path = await _recorder.stop();
      // Try to delete the file on native (ignore on web)
      _tryDeleteFile(path);
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
        _recordingPath = null;
      });
    } catch (e) {
      debugPrint('⚠️ _cancelRecording failed: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingDuration = Duration.zero;
          _recordingPath = null;
        });
      }
    }
  }

  Future<void> _sendRecording() async {
    if (_isSendingVoice) return; // guard double-tap
    final durationSeconds = _recordingDuration.inSeconds;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) {
        if (mounted) {
          setState(() {
            _isRecording = false;
            _isSendingVoice = false;
            _recordingDuration = Duration.zero;
            _recordingPath = null;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isRecording = false;
          _isSendingVoice = true;
        });
      }

      // Read bytes cross-platform via XFile (works on web blob URLs and native file paths)
      final xfile = XFile(path);
      final bytes = await xfile.readAsBytes();
      final mimeType = _audioMimeType();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.${_audioFileExtension()}';

      await ref.read(chatProvider(widget.familyId).notifier).sendVoiceMessage(
        bytes: Uint8List.fromList(bytes),
        durationSeconds: durationSeconds,
        mimeType: mimeType,
        fileName: fileName,
      );

      // Clean up temp file on native (ignore on web)
      _tryDeleteFile(path);

      if (mounted) {
        setState(() {
          _isSendingVoice = false;
          _recordingDuration = Duration.zero;
          _recordingPath = null;
        });
      }
    } catch (e) {
      debugPrint('⚠️ _sendRecording failed: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isSendingVoice = false;
          _recordingDuration = Duration.zero;
          _recordingPath = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice message: $e'),
            backgroundColor: KinrelColors.darkCard,
          ),
        );
      }
    }
  }

  /// Resolve a writable temp file path for the recording.
  /// On Web, `record` ignores the path and uses a Blob URL — so any
  /// placeholder works. On native, we use the OS temp dir.
  Future<String> _resolveRecordingPath(String fileName) async {
    if (kIsWeb) return fileName; // ignored by record on web
    try {
      final tempDir = await getTemporaryDirectory();
      return '${tempDir.path}/$fileName';
    } catch (_) {
      return fileName;
    }
  }

  /// File extension to use for the recorded audio file.
  /// AAC-LC encoder produces .m4a on all platforms (iOS, Android, web).
  String _audioFileExtension() => 'm4a';

  /// MIME type matching the encoder chosen in [_startRecording].
  /// AAC-LC inside an MP4 container → audio/mp4 (widely supported).
  String _audioMimeType() => 'audio/mp4';

  /// Best-effort cleanup of the temp recording file. On Web, [path] is
  /// a Blob URL — nothing to delete. On native, we leave the temp file
  /// in place and let the OS clean it up (this is safe; temp dir is
  /// periodically cleared by the OS).
  Future<void> _tryDeleteFile(String? path) async {
    // No-op on all platforms — temp files are managed by the OS.
    // Kept as a method so future versions can hook into actual deletion.
    debugPrint('🎤 recording temp file: $path');
  }

  // ── Attachment Picker (v91) ──────────────────────────────────────

  /// Pick an image from the gallery and send it as a chat attachment.
  Future<void> _pickAndSendAttachment() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (xfile == null) return; // user cancelled

      final bytes = await xfile.readAsBytes();
      final fileName = xfile.name.isNotEmpty
          ? xfile.name
          : 'attachment_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final mimeType = xfile.mimeType ?? 'image/jpeg';

      // Show a sending indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Sending attachment...'),
              ],
            ),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
          ),
        );
      }

      await ref.read(chatProvider(widget.familyId).notifier).sendAttachment(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName,
        mimeType: mimeType,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attachment sent'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send attachment: $e'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Forward to another family (v91) ──────────────────────────────

  /// Show a bottom sheet with the user's families. Tapping one
  /// forwards the [message] to that family's chat.
  void _showForwardFamilyPicker(ChatMessage message) {
    final familiesAsync = ref.read(familyListProvider);

    familiesAsync.when(
      data: (families) {
        if (families.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You have no families to forward to.'),
              backgroundColor: KinrelColors.darkCard,
            ),
          );
          return;
        }

        showModalBottomSheet(
          context: context,
          backgroundColor: KinrelColors.darkCard,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KinrelRadius.xxl),
            ),
          ),
          builder: (ctx) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Forward to...',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ...families.map((f) {
                      // Don't show the current family — no point forwarding
                      // to the same chat.
                      final isCurrent = f.id == widget.familyId;
                      if (isCurrent) return const SizedBox.shrink();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: KinrelColors.orange.withValues(alpha: 0.15),
                          child: Text(
                            (f.name.isNotEmpty ? f.name[0] : '?').toUpperCase(),
                            style: TextStyle(color: KinrelColors.orange),
                          ),
                        ),
                        title: Text(
                          f.name,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                        subtitle: f.familyCode != null
                            ? Text(
                                f.familyCode!,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 12,
                                  color: KinrelColors.textDim,
                                ),
                              )
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          final success = await ref
                              .read(chatProvider(widget.familyId).notifier)
                              .forwardMessage(
                                targetFamilyId: f.id,
                                original: message,
                              );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? 'Forwarded to ${f.name}'
                                      : 'Failed to forward message',
                                ),
                                backgroundColor: KinrelColors.darkCard,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      );
                    }),
                    if (families.length <= 1)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Join or create another family to forward messages.',
                          style: TextStyle(color: KinrelColors.textDim),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loading families...')),
        );
      },
      error: (e, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load families: $e')),
        );
      },
    );
  }

  // ── Edit Message Dialog (v109.10) ──────────────────────────────────

  void _showEditDialog(ChatMessage message) {
    final editController = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: Text('Edit Message',
            style: TextStyle(color: KinrelColors.textWhite)),
        content: TextField(
          controller: editController,
          maxLines: null,
          autofocus: true,
          style: TextStyle(color: KinrelColors.textWhite),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: KinrelColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: KinrelColors.orange),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final newContent = editController.text.trim();
              if (newContent.isEmpty || newContent == message.content) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              final service = ref.read(chatEnhancementServiceProvider);
              final success = await service.editMessage(message.id, newContent);
              if (success) {
                ref.read(chatProvider(widget.familyId).notifier).refreshMessages();
              }
            },
            child: Text('Save', style: TextStyle(color: KinrelColors.orange)),
          ),
        ],
      ),
    );
  }

  // ── Message Actions Bottom Sheet ─────────────────────────────────

  void _showMessageActions(ChatMessage message) {
    final isMe = _isMine(message);

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
                      (r) => r.emoji == emoji && r.userId == _currentUserId,
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
                                  color: KinrelColors.orange.withValues(
                                    alpha: 0.4,
                                  ),
                                  width: 1.5,
                                )
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
                color: const Color(0xFF3A3A4A),
                height: 1,
                thickness: 0.5,
              ),
              // Reply action
              ListTile(
                leading: Icon(
                  Icons.reply,
                  color: KinrelColors.orange,
                  size: 22,
                ),
                title: Text(
                  'Reply',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(chatProvider(widget.familyId).notifier)
                      .setReplyTo(message);
                },
              ),
              // Copy action
              ListTile(
                leading: Icon(
                  Icons.copy_rounded,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: Text(
                  'Copy',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied'),
                      backgroundColor: KinrelColors.darkCard,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              // Forward action
              ListTile(
                leading: Icon(
                  Icons.forward,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: Text(
                  'Forward',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showForwardFamilyPicker(message);
                },
              ),
              // Star action
              ListTile(
                leading: Icon(
                  message.isStarred
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: message.isStarred
                      ? const Color(0xFFFFD700)
                      : KinrelColors.textSilver,
                  size: 22,
                ),
                title: Text(
                  message.isStarred ? 'Unstar' : 'Star',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final service = ref.read(chatEnhancementServiceProvider);
                  await service.starMessage(message.id, !message.isStarred);
                  ref.read(chatProvider(widget.familyId).notifier).refreshMessages();
                },
              ),
              // Edit (only for own text messages)
              if (isMe && message.messageType == MessageType.text)
                ListTile(
                  leading: Icon(
                    Icons.edit_outlined,
                    color: KinrelColors.textSilver,
                    size: 22,
                  ),
                  title: Text(
                    'Edit',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(message);
                  },
                ),
              // Delete for Me
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: Text(
                  'Delete for Me',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final service = ref.read(chatEnhancementServiceProvider);
                  final success = await service.deleteForMe(message.id);
                  if (success) {
                    ref.read(chatProvider(widget.familyId).notifier).refreshMessages();
                  }
                },
              ),
              // Delete for Everyone (only for own messages)
              if (isMe)
                ListTile(
                  leading: Icon(
                    Icons.delete_forever,
                    color: KinrelColors.error,
                    size: 22,
                  ),
                  title: Text(
                    'Delete for Everyone',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    // Confirm
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: KinrelColors.darkCard,
                        title: Text('Delete for Everyone?',
                            style: TextStyle(color: KinrelColors.textWhite)),
                        content: Text(
                            'This message will be deleted for everyone in the chat.',
                            style: TextStyle(color: KinrelColors.textSilver)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('Delete',
                                  style: TextStyle(color: KinrelColors.error))),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      final service =
                          ref.read(chatEnhancementServiceProvider);
                      final success =
                          await service.deleteForEveryone(message.id);
                      if (success) {
                        ref
                            .read(chatProvider(widget.familyId).notifier)
                            .refreshMessages();
                      }
                    }
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
        msg.timestamp.year,
        msg.timestamp.month,
        msg.timestamp.day,
      );

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
          'December',
        ];
        label =
            '${months[msg.timestamp.month]} ${msg.timestamp.day}, ${msg.timestamp.year}';
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

class _MessageBubble extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Read the current user id so we can highlight the user's own reactions.
    // _MessageBubble is a separate widget (not _ChatScreenState), so it
    // can't use the _currentUserId getter — it reads the provider directly.
    final currentUserId = ref.watch(chatCurrentUserIdProvider);

    // Phase 14: Sticker messages render WITHOUT the bubble background —
    // just the emoji + a small timestamp underneath. They are centered
    // for solo emoji impact, like WhatsApp stickers.
    final isSticker = message.messageType == MessageType.sticker;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: EdgeInsets.only(left: isMe ? 48 : 0, right: isMe ? 0 : 48),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Reply preview (if replying to a message)
              if (message.replyToId != null) _buildReplyPreview(),
              // Bubble
              Container(
                padding: isSticker
                    ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                    : const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                decoration: BoxDecoration(
                  // Stickers: transparent background (just the emoji on chat bg)
                  color: isSticker
                      ? Colors.transparent
                      : (isMe
                          ? const Color(0xFFE8612A).withValues(alpha: 0.08)
                          : const Color(0xFF191B2C)),
                  borderRadius: isSticker
                      ? BorderRadius.zero
                      : BorderRadius.only(
                          topLeft: Radius.circular(KinrelRadius.lg),
                          topRight: Radius.circular(KinrelRadius.lg),
                          bottomLeft:
                              Radius.circular(isMe ? KinrelRadius.lg : 4),
                          bottomRight:
                              Radius.circular(isMe ? 4 : KinrelRadius.lg),
                        ),
                  border: isSticker
                      ? Border.all(color: Colors.transparent)
                      : (isMe
                          ? Border.all(
                              color:
                                  KinrelColors.orange.withValues(alpha: 0.12),
                              width: 0.5,
                            )
                          : Border.all(
                              color: const Color(0xFF2A2A3D), width: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Sender name (for received messages, skip for stickers)
                    if (!isMe && !isSticker) _buildSenderName(),
                    // Message content
                    _buildMessageContent(),
                    // Time and read receipt row (skip for stickers —
                    // stickers show time inline below)
                    if (!isSticker) _buildTimeRow(),
                    if (isSticker) _buildStickerTimeRow(),
                  ],
                ),
              ),
              // Reactions row
              if (message.reactions.isNotEmpty)
                _buildReactions(currentUserId),
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
                  Icon(
                    Icons.image_outlined,
                    size: 36,
                    color: KinrelColors.textSilver.withValues(alpha: 0.5),
                  ),
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
        // Phase 13: real voice message player
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
          return VoiceMessagePlayer(
            messageId: message.id,
            mediaUrl: message.mediaUrl!,
            durationSeconds: message.durationSeconds,
            isMe: isMe,
          );
        }
        // Fallback: placeholder if no media URL (e.g. legacy message)
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                : KinrelColors.textSilver.withValues(
                                    alpha: 0.3,
                                  ),
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

      case MessageType.sticker:
        // Phase 14: render the emoji at 4x size with no bubble background.
        // The emoji IS the message — no text wrapping needed.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            message.content,
            style: const TextStyle(
              fontSize: 64,
              height: 1.0,
            ),
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
                    child: Icon(
                      Icons.celebration,
                      size: 14,
                      color: Colors.white,
                    ),
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
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: KinrelColors.orange,
                    ),
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
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
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
            _ReadReceipt(
              isRead: message.isRead,
              messageStatus: message.messageStatus,
            ),
          ],
        ],
      ),
    );
  }

  /// Phase 14: A minimal time row for stickers — right-aligned below the
  /// emoji, no read receipts (stickers don't need delivery confirmation).
  Widget _buildStickerTimeRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 0),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          message.formattedTime,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 10,
            color: KinrelColors.textDim,
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(String? currentUserId) {
    final grouped = message.groupedReactions;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: grouped.entries.map((entry) {
          final hasMyReaction = message.reactions.any(
            (r) => r.emoji == entry.key && r.userId == currentUserId,
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
// Read Receipt (WhatsApp-style ticks)
// v109.11: single tick (sent) → double tick (delivered) → blue tick (read)
// ═══════════════════════════════════════════════════════════════════════

class _ReadReceipt extends StatelessWidget {
  const _ReadReceipt({required this.isRead, this.messageStatus});

  final bool isRead;
  final String? messageStatus;

  @override
  Widget build(BuildContext context) {
    // Determine tick style based on message status
    // 'sent' → single tick (dim grey)
    // 'delivered' → double tick (dim grey)
    // 'read' or isRead=true → double tick (blue)
    final status = messageStatus ?? (isRead ? 'read' : 'sent');

    final Color color;
    final bool showDouble;

    if (status == 'read' || isRead) {
      color = const Color(0xFF4FC3F7); // WhatsApp blue
      showDouble = true;
    } else if (status == 'delivered') {
      color = KinrelColors.textDim;
      showDouble = true;
    } else {
      // 'sent' → single tick
      color = KinrelColors.textDim;
      showDouble = false;
    }

    return SizedBox(
      width: showDouble ? 16 : 10,
      height: 10,
      child: CustomPaint(painter: _DoubleTickPainter(color: color, showDouble: showDouble)),
    );
  }
}

/// Paints a WhatsApp-style tick (single or double).
class _DoubleTickPainter extends CustomPainter {
  _DoubleTickPainter({required this.color, this.showDouble = true});

  final Color color;
  final bool showDouble;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (showDouble) {
      // Double tick
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
    } else {
      // Single tick
      final path = Path();
      path.moveTo(0, size.height * 0.55);
      path.lineTo(size.width * 0.25, size.height * 0.85);
      path.lineTo(size.width * 0.95, size.height * 0.15);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DoubleTickPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.showDouble != showDouble;
}

// ═══════════════════════════════════════════════════════════════════════
// Send Button (Ignite Gradient Circle)
// ═══════════════════════════════════════════════════════════════════════

class _SendButton extends StatelessWidget {
  const _SendButton({required this.isActive, required this.onTap});

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
                  colors: [const Color(0xFF202338), const Color(0xFF202338)],
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
          color: isActive ? Colors.white : KinrelColors.textDim,
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
// Mic Button (Phase 13 — voice message trigger)
// ═══════════════════════════════════════════════════════════════════════

class _MicButton extends StatelessWidget {
  const _MicButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF202338),
        ),
        child: Icon(
          Icons.mic_rounded,
          size: 22,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sticker Button (Phase 14 — toggles the sticker panel)
// ═══════════════════════════════════════════════════════════════════════

class _StickerButton extends StatelessWidget {
  const _StickerButton({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? KinrelColors.orange.withValues(alpha: 0.15)
              : const Color(0xFF202338),
          border: isActive
              ? Border.all(color: KinrelColors.orange.withValues(alpha: 0.4), width: 1)
              : null,
        ),
        child: Icon(
          Icons.emoji_emotions_rounded,
          size: 22,
          color: isActive
              ? KinrelColors.orange
              : KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Recording Dot (pulsing red dot shown while recording)
// ═══════════════════════════════════════════════════════════════════════

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KinrelColors.error.withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.error.withValues(alpha: _animation.value * 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                          decoration: BoxDecoration(shape: BoxShape.circle),
                          child: Center(
                            child: Text(emoji, style: TextStyle(fontSize: 24)),
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
