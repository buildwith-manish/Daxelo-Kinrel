// lib/features/chat/presentation/direct_chat_screen.dart
//
// DAXELO KINREL — Direct (1:1) Chat Screen (Phase 21)
//
// A private conversation between two users. Backed by the DirectMessage
// table (RLS: only sender + receiver can see messages).
//
// Features:
//   - Text messages (send + receive)
//   - Special heart-themed bubble for 'thinking_of_you' messages
//   - Loads the other user's name/avatar via fn_get_user_public_profile
//   - Marks messages as read on open
//   - Refresh button to pull new messages (realtime NOT wired — uses
//     manual refresh + a 10s polling fallback to keep it simple)
//
// Entry points:
//   - /dm/:otherUserId route
//   - Tapping a thinking_of_you notification opens this screen with
//     the SENDER as the other user
//   - (Future) a DM inbox section in the ChatInboxScreen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../profile/presentation/member_profile_sheet.dart';
import '../data/chat_wallpaper_provider.dart';
import '../data/wallpaper_picker.dart';
import '../data/direct_message_provider.dart';
import 'widgets/chat_wallpaper_builder.dart';

class DirectChatScreen extends ConsumerStatefulWidget {
  const DirectChatScreen({super.key, required this.otherUserId});

  /// The OTHER user's ID (not the current user).
  final String otherUserId;

  @override
  ConsumerState<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen> {
  late final ScrollController _scrollController;
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final composing = _textController.text.trim().isNotEmpty;
    if (composing != _isComposing) {
      if (mounted) setState(() => _isComposing = composing);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    Future.microtask(() {
      ref
          .read(directChatProvider(widget.otherUserId).notifier)
          .sendText(text);
    });
    _textController.clear();
    _focusNode.requestFocus();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  String? get _currentUserId =>
      ref.read(supabaseProvider)?.auth.currentUser?.id;

  bool _isMine(DirectMessage msg) => msg.senderId == _currentUserId;

  /// v114: Shows the image-based wallpaper picker bottom sheet with
  /// three options: Choose from Gallery, Remove Wallpaper (only if one
  /// is set), and Set as Default Wallpaper.
  void _showImageWallpaperPicker(BuildContext context, String chatId) {
    final currentPath = ref.read(wallpaperPathProvider(chatId));

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Chat Wallpaper',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_rounded,
                color: KinrelColors.orange,
              ),
              title: Text(
                'Choose from Gallery',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final path = await WallpaperPicker.pickFromGallery(context);
                if (path != null) {
                  await ref
                      .read(chatWallpaperProvider.notifier)
                      .setWallpaper(chatId, path);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Wallpaper set!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            if (currentPath != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  'Remove Wallpaper',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(chatWallpaperProvider.notifier)
                      .clearWallpaper(chatId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Wallpaper removed'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: KinrelColors.textSilver,
              ),
              title: Text(
                'Set as Default Wallpaper',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final path = await WallpaperPicker.pickFromGallery(context);
                if (path != null) {
                  await ref
                      .read(chatWallpaperProvider.notifier)
                      .setWallpaper('default', path);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Default wallpaper set!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(directChatProvider(widget.otherUserId));
    final peer = chatState.peer;
    final messages = chatState.messages;

    Widget bodyContent;
    if (chatState.isLoading) {
      bodyContent = const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    } else if (chatState.error != null && messages.isEmpty) {
      bodyContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            chatState.error!,
            style: TextStyle(color: KinrelColors.textDim, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      bodyContent = messages.isEmpty
          ? _buildEmptyState(peer?.name ?? 'them')
          : ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isMe = _isMine(msg);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _DirectMessageBubble(message: msg, isMe: isMe),
                );
              },
            );
    }

    return DKScaffold(
      backgroundColor: const Color(0xFF13141E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13141E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KinrelColors.textWhite),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/home'); } },
        ),
        title: Row(
          children: [
            // Phase 22 / Header Nav Fix: The entire profile area
            // (avatar + name + "Private chat" status) is wrapped in a
            // single GestureDetector that opens the peer's profile via
            // MemberProfileSheet. This matches the user's requirement
            // that tapping anywhere in the chat header's profile
            // information area should open the user's profile, not
            // navigate elsewhere. The wallpaper PopupMenuButton below
            // is a separate action and is not affected.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => MemberProfileSheet.show(context, widget.otherUserId),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.orange.withValues(alpha: 0.15),
                    ),
                    child: peer?.avatarUrl != null &&
                            peer!.avatarUrl!.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              peer.avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  peer.initials,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: KinrelColors.orange,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              peer?.initials ?? '?',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.orange,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  // Expanded so a long peer name ellipsizes instead of
                  // overflowing the AppBar's title slot.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peer?.name ?? 'Loading…',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Private chat',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // v114: Wallpaper menu for DM — uses chatId 'dm_<otherUserId>'.
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: KinrelColors.textSilver, size: 22),
            color: KinrelColors.darkCard,
            onSelected: (value) {
              if (value == 'wallpaper') {
                _showImageWallpaperPicker(
                    context, 'dm_${widget.otherUserId}');
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 'wallpaper', child: Text('Chat Wallpaper')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // v114: Wrap messages with ChatWallpaperBuilder so the custom
          // wallpaper (if set) renders only behind the messages.
          Expanded(
            child: ChatWallpaperBuilder(
              chatId: 'dm_${widget.otherUserId}',
              child: bodyContent,
            ),
          ),
          if (chatState.error != null && messages.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: KinrelColors.error.withValues(alpha: 0.1),
              child: Text(
                chatState.error!,
                style: TextStyle(color: KinrelColors.error, fontSize: 12),
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String peerName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 40,
              color: KinrelColors.textDim,
            ),
            const SizedBox(height: 12),
            Text(
              'This is a private chat with $peerName',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Only you and $peerName can see this conversation.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF13141E),
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A3D), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
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
                    hintText: 'Message…',
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
            GestureDetector(
              onTap: _isComposing ? _sendMessage : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _isComposing
                      ? KinrelGradients.igniteGradient
                      : const LinearGradient(
                          colors: [Color(0xFF202338), Color(0xFF202338)],
                        ),
                  boxShadow: _isComposing
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
                  color: _isComposing ? Colors.white : KinrelColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Message Bubble
// ═══════════════════════════════════════════════════════════════════════

class _DirectMessageBubble extends StatelessWidget {
  const _DirectMessageBubble({required this.message, required this.isMe});

  final DirectMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    // Special heart-themed card for Thinking of You messages
    if (message.isThinkingOfYou) {
      return _buildThinkingOfYouBubble(context);
    }
    return _buildTextBubble(context);
  }

  Widget _buildTextBubble(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(left: isMe ? 48 : 0, right: isMe ? 0 : 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              : Border.all(color: const Color(0xFF2A2A3D), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14.5,
                color: KinrelColors.textWhite,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.formattedTime,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isRead
                        ? Icons.done_all_rounded
                        : Icons.check_rounded,
                    size: 12,
                    color: message.isRead
                        ? KinrelColors.orange
                        : KinrelColors.textDim,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingOfYouBubble(BuildContext context) {
    // Pink-coral themed card with a heart icon. Renders the message as
    // "<sender> <message>" (e.g. "Manish is thinking of you.").
    const accent = Color(0xFFE91E63); // pink
    const accentDim = Color(0x1FE91E63); // 12% alpha
    const accentBorder = Color(0x33E91E63); // 20% alpha

    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accentDim,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: accentBorder,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
                border: Border.all(
                  color: accent.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.favorite,
                size: 18,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thinking of You',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: accent,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Phase 22 fix: the RPC now stores the FULL grammatical
                    // sentence in content (e.g. "Manish is thinking of you."),
                    // so we render it as-is for both sender and receiver.
                    // The previous code prepended "You " for the sender's own
                    // messages — which produced broken output
                    // ("You is thinking of you.") because the templates are
                    // third-person verb phrases. See migration
                    // 20260906150000_fix_thinking_of_you_grammar_and_per_receiver_cooldown.sql.
                    message.content,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textWhite,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.formattedTime,
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
      ),
    );
  }
}
