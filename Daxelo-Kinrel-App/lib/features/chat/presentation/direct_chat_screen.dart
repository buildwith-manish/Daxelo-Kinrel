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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../profile/presentation/member_profile_sheet.dart';
import '../data/chat_wallpaper_provider.dart';
import '../data/wallpaper_picker.dart';
import '../data/direct_message_provider.dart';
import '../data/direct_message_adapter.dart';
import '../providers/chat_provider.dart';
import 'widgets/chat_wallpaper_builder.dart';
import 'widgets/chat_message_list.dart';

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

  /// v3.3: Resolves the host's familyId from the FIRST game-invite DM
  /// in the thread (the payload stores `familyId` as the family the
  /// game lives in). Passed to ChatMessageList as `inviteFamilyId` so
  /// the shared game-invite card's Join button can deep-link into the
  /// host's family space (/family/<id>/<gameType>/lobby?join=<gameId>).
  /// Returns null if there are no game-invite DMs — the Join button is
  /// disabled in that case (the card still renders).
  String? _resolveInviteFamilyId(List<DirectMessage> messages) {
    for (final msg in messages) {
      if (msg.isGameInvite) {
        final payload = msg.gameInvitePayload;
        final famId = payload?['familyId'] as String?;
        if (famId != null && famId.isNotEmpty) return famId;
      }
    }
    return null;
  }

  /// v3.3: Long-press on a DM message shows only the actions the DM
  /// backend supports — currently just Copy. The group chat's full
  /// action sheet (Delete, Forward, Reply, React, Edit, Star, Pin) is
  /// NOT shown because the DM backend doesn't support those operations.
  void _showDmMessageActions(ChatMessage msg) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KinrelColors.textDim.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (msg.content.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded,
                      color: KinrelColors.textSilver, size: 22),
                  title: const Text('Copy',
                      style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Clipboard.setData(ClipboardData(text: msg.content));
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

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
            const Padding(
              padding: EdgeInsets.all(16),
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
              leading: const Icon(
                Icons.photo_library_rounded,
                color: KinrelColors.orange,
              ),
              title: const Text(
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
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
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
              leading: const Icon(
                Icons.photo_library_outlined,
                color: KinrelColors.textSilver,
              ),
              title: const Text(
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
            style: const TextStyle(color: KinrelColors.textDim, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      // v3.3: the DM screen now renders the SAME shared ChatMessageList
      // as the group chat — same date separators, same MessageBubble,
      // same game-invite card, same RepaintBoundary/cacheExtent. The
      // DM messages are converted to ChatMessage via the memoized
      // directChatMessagesProvider (see direct_message_adapter.dart).
      //
      // isDirectChat=true → hides avatar + sender name (a DM only has
      // two parties so both are unambiguous from bubble alignment).
      // enableSwipeReply=false → DM backend doesn't support replies.
      // showReactions=false → DM backend doesn't support reactions.
      // familyId=null → skips the relationship label + group chatProvider
      // actions inside MessageBubble.
      // inviteFamilyId → resolved from the DM invite payload so the
      // game-invite Join button deep-links into the host's family space.
      final chatMessages = ref.watch(directChatMessagesProvider(widget.otherUserId));
      bodyContent = messages.isEmpty
          ? _buildEmptyState(peer?.name ?? 'them')
          : ChatMessageList(
              messages: chatMessages,
              currentUserId: _currentUserId,
              familyId: null,
              isDirectChat: true,
              inviteFamilyId: _resolveInviteFamilyId(messages),
              scrollController: _scrollController,
              onReply: (_) {}, // DMs don't support replies — no-op
              onReact: (_) {}, // DMs don't support reactions — no-op (showReactions=false hides the entry point)
              onLongPress: (msg) => _showDmMessageActions(msg),
              enableSwipeReply: false,
              showReactions: false,
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
                            child: CachedNetworkImage(
                              imageUrl: peer.avatarUrl!,
                              cacheManager: KinrelImageCacheManager.instance,
                              fit: BoxFit.cover,
                              memCacheWidth:
                                  (36 * MediaQuery.devicePixelRatioOf(context))
                                      .toInt(),
                              memCacheHeight:
                                  (36 * MediaQuery.devicePixelRatioOf(context))
                                      .toInt(),
                              errorWidget: (_, __, ___) => Center(
                                child: Text(
                                  peer.initials,
                                  style: const TextStyle(
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
                              style: const TextStyle(
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
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
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
            icon: const Icon(Icons.more_vert,
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
                style: const TextStyle(color: KinrelColors.error, fontSize: 12),
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
            const Icon(
              Icons.lock_outline,
              size: 40,
              color: KinrelColors.textDim,
            ),
            const SizedBox(height: 12),
            Text(
              'This is a private chat with $peerName',
              style: const TextStyle(
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
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    hintStyle: const TextStyle(
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
