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
//   - Realtime INSERT/UPDATE sync (new messages + read receipts)
//
// v3.4 — Swipe-to-reply parity with the group chat (pin-to-pin reuse):
//   - enableSwipeReply=true on the shared ChatMessageList — the SAME
//     SwipeToReply wrapper (chat_meta.dart) the group uses, with the
//     same drag physics, reply-icon reveal, haptic arming, and snap-back
//     animation.
//   - The reply target lands in DirectChatState.replyToMessage via the
//     SAME setReplyTo API the group's ChatState exposes.
//   - The shared ReplyPreviewBar (reply_preview_bar.dart — moved from
//     chat_screen.dart) renders above the input: orange accent bar +
//     sender name + snippet + X to cancel, identical styling.
//   - sendText(replyToId:) persists the reply columns the group
//     ChatMessage table uses (replyToId/replyToContent/
//     replyToSenderName — migration 20261007080000_dm_reply_threading).
//   - The shared MessageBubble renders the quote block from the
//     adapter-mapped fields, and tapping it scrolls to the original
//     (the SAME _scrollToMessage estimate the group uses).
//   - Long-press sheet now offers the SAME actions the DM supports:
//     Reply, Copy (with snackbar), Preview (the shared peek-preview
//     dialog), and Share — all styled identically to the group sheet.
//   - Scroll-to-bottom FAB — the SAME shared ScrollToBottomFab the
//     group renders (moved to chat_meta.dart), same threshold (300px).
//   - HapticService.tap() on send, matching the group's send feel.
//
// Entry points:
//   - /dm/:otherUserId route
//   - Tapping a thinking_of_you notification opens this screen with
//     the SENDER as the other user
//   - a DM inbox section in the ChatInboxScreen

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/theme/kinrel_fx.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/image_cache_manager.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../profile/presentation/member_profile_sheet.dart';
// v3.5 — active status (the group's "Active now"/"Last seen" source —
// the app-wide UserPresence watcher; pure reuse, same provider the
// MemberProfileSheet renders its online dot from).
import '../../presence/last_seen_provider.dart';
import '../data/chat_wallpaper_provider.dart';
import '../data/wallpaper_picker.dart';
import '../data/direct_message_provider.dart';
import '../data/direct_message_adapter.dart';
import '../providers/chat_provider.dart';
import 'widgets/chat_background.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_list.dart';
// v3.4 — shared reply/preview/FAB widgets (the same ones the group chat
// renders; see the header comment).
import 'widgets/chat_meta.dart';
import 'widgets/message_preview_dialog.dart';
import 'widgets/reply_preview_bar.dart';
// v3.5 — shared engagement widgets (the SAME typing indicator +
// reaction pickers the group chat renders).
import 'widgets/typing_indicator.dart';
import 'widgets/reaction_picker.dart';
// v3.5 — the engagement layer's UserPresence value type (its
// lastSeenLabelLocalized renders the same "Active now" / "Last seen X
// ago" labels the group header shows — pure reuse, no re-implementation).
import '../providers/chat_socket_engagement_provider.dart'
    show UserPresence;

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

  // v3.4 — scroll-to-bottom FAB state (the same flag + threshold the
  // group chat uses: FAB appears once the user scrolls >300px up).
  bool _showScrollFab = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _textController.addListener(_onTextChanged);
    // v3.4 — same listener wiring as the group chat's initState.
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    // v3.5 — leaving mid-compose flips the typing row off (the
    // notifier's dispose also handles this; belt-and-braces for the
    // case where the text listener fires after the provider disposes).
    super.dispose();
  }

  // v3.5 — typing emission throttle (the same ≤2s cadence the group
  // screen uses): compose-flips write immediately; while actively
  // composing, the DirectTypingStatus row is refreshed at most every
  // 2s so the peer's 3-second auto-clear timer keeps resetting.
  DateTime? _lastTypingWriteAt;

  void _onTextChanged() {
    final composing = _textController.text.trim().isNotEmpty;
    if (composing != _isComposing) {
      if (mounted) setState(() => _isComposing = composing);
      // v3.5 — the same trigger the group's _onTextChanged uses
      // (setTypingStatus on compose flip), pointed at the DM's
      // DirectTypingStatus row.
      ref
          .read(directChatProvider(widget.otherUserId).notifier)
          .setTyping(composing);
      _lastTypingWriteAt = DateTime.now();
    } else if (composing) {
      // v3.5 — throttled keystroke refresh (identical to the group).
      final now = DateTime.now();
      final last = _lastTypingWriteAt;
      if (last == null || now.difference(last).inMilliseconds >= 2000) {
        ref
            .read(directChatProvider(widget.otherUserId).notifier)
            .setTyping(true);
        _lastTypingWriteAt = now;
      }
    }
  }

  // v3.4 — MOVED from chat_screen.dart's _onScroll (same logic, same
  // 300px threshold, same mounted guard).
  void _onScroll() {
    final show =
        _scrollController.hasClients && _scrollController.position.pixels > 300;
    if (show != _showScrollFab) {
      if (mounted) {
        setState(() => _showScrollFab = show);
      }
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

  /// v3.4 — MOVED from chat_screen.dart's _scrollToMessage: tapping the
  /// quoted reply preview above a bubble jumps to the original message.
  ///
  /// The ListView is reverse: true (newest at top, index 0 = newest).
  /// We find the message's index in the flat (newest-first) list, then
  /// estimate the scroll offset as index * ~72px (average bubble height
  /// including spacing). Same approximation the group chat uses.
  void _scrollToMessage(String messageId) {
    final messages = ref.read(directChatProvider(widget.otherUserId)).messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      // Message not in the current viewport (e.g. very old message not
      // loaded yet). Show a snackbar telling the user to scroll up.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)?.chatReplyToOriginalNotFound ??
                'Message is older than loaded history — scroll up to find it.'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (!_scrollController.hasClients) return;
    // Estimate: each message bubble is ~72px tall (bubble + spacing).
    // The list is reversed, so offset 0 = newest (index 0).
    const estimatedBubbleHeight = 72.0;
    final targetOffset = index * estimatedBubbleHeight;
    // Clamp to the max scroll extent so we don't overshoot.
    final maxExtent = _scrollController.position.maxScrollExtent;
    final clamped = targetOffset.clamp(0.0, maxExtent);
    _scrollController.animateTo(
      clamped,
      duration: KinrelMotion.normal,
      curve: KinrelMotion.easeOut,
    );
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // v3.4 — Haptic: tap confirms the send fired before the optimistic
    // insert completes (the SAME WhatsApp/iMessage-pattern feel the
    // group chat has).
    HapticService.tap();

    // v3.4 — capture the reply target the same way the group's
    // _sendMessage does (provider state, not screen state).
    final replyToId = ref
        .read(directChatProvider(widget.otherUserId))
        .replyToMessage
        ?.id;
    Future.microtask(() {
      ref
          .read(directChatProvider(widget.otherUserId).notifier)
          .sendText(text, replyToId: replyToId);
    });
    _textController.clear();
    _focusNode.requestFocus();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  String? get _currentUserId =>
      ref.read(supabaseProvider)?.auth.currentUser?.id;

  /// v3.5 — the peer's live active-status line for the DM header.
  ///
  /// Pure reuse of the group's active-status sources: lastSeenProvider
  /// (the app-wide UserPresence watcher kept live by realtime + the
  /// presence heartbeat) supplies the peer's row, and the engagement
  /// layer's UserPresence.lastSeenLabelLocalized renders the SAME
  /// labels the group header shows ("Active now" when online, the
  /// localized "Last seen 5m ago" otherwise). The dot styling matches
  /// the group header / MemberProfileSheet presence dot (green glow
  /// when online, dim grey otherwise).
  Widget _buildPeerStatus() {
    final l10n = S.of(context);
    final presenceMap = ref.watch(lastSeenProvider);
    final seen = presenceMap[widget.otherUserId];
    final isOnline = seen?.isOnline ?? false;

    final presence = UserPresence(
      userId: widget.otherUserId,
      isOnline: isOnline,
      lastSeenAt: seen?.lastSeenAt,
    );
    final label = presence.lastSeenLabelLocalized(l10n);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOnline
                ? KinrelColors.success
                : KinrelColors.textDim.withValues(alpha: 0.6),
            boxShadow: isOnline
                ? [
                    BoxShadow(
                      color: KinrelColors.success.withValues(alpha: 0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 0),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: isOnline ? FontWeight.w600 : FontWeight.w400,
              color: isOnline
                  ? KinrelColors.success
                  : KinrelColors.textDim,
            ),
          ),
        ),
      ],
    );
  }

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

  /// v3.4: Long-press on a DM message shows the actions the DM backend
  /// supports — styled EXACTLY like the group chat's sheet (same icons,
  /// colors, ListTile typography, same KinrelRadius.xxl corners +
  /// vertical-12 padding).
  ///
  /// v3.5: the sheet now ALSO leads with the SAME quick-reactions row
  /// the group sheet shows (the shared MessageActionQuickReactions — 6
  /// quick emojis + "+" for the full picker), wired to the DM's
  /// toggleReaction. The group's remaining actions (Forward, Star,
  /// Pin, Edit, Delete) are still backed by ChatMessage-table features
  /// the DirectMessage table doesn't have.
  void _showDmMessageActions(ChatMessage msg) {
    final currentUserId = _currentUserId;
    showModalBottomSheet<void>(
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
                // v3.5 — Quick reactions row: the SAME shared widget the
                // group sheet leads with (same 6 emojis, same 44x44
                // circles, same has-reacted highlight, same "+").
                MessageActionQuickReactions(
                  reactions: msg.reactions,
                  currentUserId: currentUserId,
                  onToggle: (emoji) {
                    ref
                        .read(directChatProvider(widget.otherUserId).notifier)
                        .toggleReaction(msg.id, emoji);
                    Navigator.pop(ctx);
                  },
                  onMoreTap: () {
                    // Pop the actions sheet first, then open the full
                    // emoji sheet (same flow as the group).
                    Navigator.pop(ctx);
                    showFullEmojiSheet(
                      context,
                      onEmojiSelected: (emoji) {
                        ref
                            .read(directChatProvider(widget.otherUserId)
                                .notifier)
                            .toggleReaction(msg.id, emoji);
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
                const Divider(
                  color: Color(0xFF3A3A4A),
                  height: 1,
                  thickness: 0.5,
                ),
                // Reply action — the same ListTile the group sheet has.
                ListTile(
                  leading: const Icon(
                    Icons.reply,
                    color: KinrelColors.orange,
                    size: 22,
                  ),
                  title: const Text(
                    'Reply',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref
                        .read(directChatProvider(widget.otherUserId).notifier)
                        .setReplyTo(msg);
                  },
                ),
                // Copy action — the same ListTile + snackbar the group
                // sheet shows.
                if (msg.content.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded,
                        color: KinrelColors.textSilver, size: 22),
                    title: const Text(
                      'Copy',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: msg.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied'),
                          backgroundColor: KinrelColors.darkCard,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                // Preview action — the SAME shared peek-preview dialog
                // the group opens (message_preview_dialog.dart).
                ListTile(
                  leading: const Icon(
                    Icons.zoom_out_map_rounded,
                    color: KinrelColors.ember,
                    size: 22,
                  ),
                  title: const Text(
                    'Preview',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    showMessagePeekPreview(context, msg);
                  },
                ),
                // Share action — the same ListTile + Share.share call
                // the group sheet makes (DMs are text-only, so the text
                // branch always applies here).
                if (msg.content.isNotEmpty)
                  ListTile(
                    leading: const Icon(
                      Icons.share_outlined,
                      color: KinrelColors.textSilver,
                      size: 22,
                    ),
                    title: const Text(
                      'Share',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 15,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Share.share(
                        msg.content,
                        subject: 'Message from ${msg.senderName}',
                      );
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// v3.5 — shows the SAME shared reaction overlay the group chat
  /// opens (ReactionOverlay + full-emoji sheet), wired to the DM's
  /// toggleReaction. Mirrors the group's _showReactionPicker exactly.
  void _showReactionPicker(String messageId) {
    showReactionOverlay(
      context,
      onEmojiSelected: (emoji) {
        ref
            .read(directChatProvider(widget.otherUserId).notifier)
            .toggleReaction(messageId, emoji);
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
      // v3.4: enableSwipeReply=true → the SAME SwipeToReply wrapper the
      // group uses (the DirectMessage table now persists reply fields).
      // v3.5: showReactions=true → the DM reactions table exists
      // (migration 20261007100000) and toggleReaction implements the
      // group's exact optimistic + realtime flow — onReact opens the
      // SAME shared reaction overlay. onRetryFailed/onDeleteFailed →
      // the DM provider's retryMessage/deleteFailedMessage so the
      // shared failed-message sheet works in DMs too.
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
              // v3.4 — the SAME wiring the group chat uses: swipe/Reply
              // sets the provider's replyToMessage, which renders the
              // shared ReplyPreviewBar above the input.
              onReply: (msg) {
                ref
                    .read(directChatProvider(widget.otherUserId).notifier)
                    .setReplyTo(msg);
              },
              // v3.5 — the SAME reaction wiring the group uses: tapping
              // the bubble opens the shared quick-reaction overlay.
              onReact: (msg) => _showReactionPicker(msg.id),
              onLongPress: (msg) => _showDmMessageActions(msg),
              // v3.4 — tapping the quote block scrolls to the original
              // message, exactly like the group chat.
              onReplyPreviewTap: (msg) {
                if (msg.replyToId != null) _scrollToMessage(msg.replyToId!);
              },
              enableSwipeReply: true,
              // v3.5 — reactions ON (the DM reactions table + toggle
              // flow now mirror the group's, pin-to-pin).
              showReactions: true,
              // v3.5 — failed-send seam: the DM provider's retry/delete
              // methods (the group leaves these null and falls back to
              // its built-in chatProvider calls).
              onRetryFailed: (messageId) {
                ref
                    .read(directChatProvider(widget.otherUserId).notifier)
                    .retryMessage(messageId);
              },
              onDeleteFailed: (messageId) {
                ref
                    .read(directChatProvider(widget.otherUserId).notifier)
                    .deleteFailedMessage(messageId);
              },
            );
    }

    return DKScaffold(
      backgroundColor: const Color(0xFF13141E),
      appBar: AppBar(
        // v3.3: same header gradient as the group chat — vertical
        // gradient (warm dark navy → base dark) + hairline bottom
        // border. Uses flexibleSpace so the gradient fills the entire
        // AppBar area including the status bar slot.
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          // PERF (Flat): solid color in flat mode; gradient in rich mode.
          decoration: BoxDecoration(
            color: KinrelFx.rich ? null : const Color(0xFF0A0B16),
            gradient: KinrelFx.gradient(
              const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF11132A), // top — warm dark navy (matches group)
                  Color(0xFF0A0B16), // bottom — base dark (matches group)
                ],
              ),
            ),
            border: const Border(
              bottom: BorderSide(
                  color: Color(0x0FFFFFFF), width: 0.5),
            ),
          ),
        ),
        // v3.3: same back button icon as the group chat.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: KinrelColors.textSilver),
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
                  // v3.3: avatar bumped to 40px (closer to the group's
                  // 48px) with the same orange-tint circle. Kept at 40
                  // rather than 48 so the DM header (which has no
                  // member-count chip) doesn't feel oversized.
                  Container(
                    width: 40,
                    height: 40,
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
                                  (40 * MediaQuery.devicePixelRatioOf(context))
                                      .toInt(),
                              memCacheHeight:
                                  (40 * MediaQuery.devicePixelRatioOf(context))
                                      .toInt(),
                              errorWidget: (_, __, ___) => Center(
                                child: Text(
                                  peer.initials,
                                  style: const TextStyle(
                                    fontSize: 15,
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
                                fontSize: 15,
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
                        // v3.5 — Active status: replaces the static
                        // "Private chat" subtitle with the peer's LIVE
                        // status, reusing the app-wide UserPresence
                        // watcher (lastSeenProvider — the SAME provider
                        // the group header's presence fallback + the
                        // MemberProfileSheet online dot render from).
                        // Online → green glowing dot + "Active now"
                        // (the group header's exact label); offline →
                        // the localized "Last seen X ago" via the
                        // engagement layer's UserPresence label logic.
                        _buildPeerStatus(),
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
          // v3.3: Wrap messages with ChatBackground — the SAME multi-layer
          // ambient gradient + custom wallpaper the group chat uses. The
          // wallpaperPathProvider is keyed by chatId string; we pass
          // 'dm_<otherUserId>' so DM wallpapers are independent of group
          // wallpapers (no new provider needed — the existing family-keyed
          // path is a different chatId string, so there's no collision).
          //
          // v3.4: a Stack above the background now hosts the SAME shared
          // ScrollToBottomFab the group chat renders (chat_meta.dart) —
          // appears once the user scrolls >300px up, taps back to bottom.
          Expanded(
            child: ChatBackground(
              chatId: 'dm_${widget.otherUserId}',
              child: Stack(
                children: [
                  bodyContent,
                  // Scroll-to-bottom FAB — the shared group widget.
                  if (_showScrollFab)
                    ScrollToBottomFab(onTap: _scrollToBottom),
                ],
              ),
            ),
          ),
          // v3.5 — Typing indicator: the SAME shared TypingIndicator the
          // group renders (same position in the Column — between the
          // message area and the reply bar; same avatar + label +
          // bouncing dots). DirectTypingStatus realtime events drive
          // chatState.isTyping / typingUserName.
          if (chatState.isTyping)
            TypingIndicator(
              name: chatState.typingUserName ?? peer?.name ?? 'Them',
              label: S.of(context)?.chatTypingSingle(
                      chatState.typingUserName ?? peer?.name ?? 'Them') ??
                  '${chatState.typingUserName ?? peer?.name ?? 'Them'} is typing',
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
          // v3.4 — Reply preview bar: the SAME shared ReplyPreviewBar the
          // group chat renders above its input (moved from
          // chat_screen.dart). Shows while composing a reply; X clears it.
          if (chatState.replyToMessage != null)
            ReplyPreviewBar(
              replyTo: chatState.replyToMessage!,
              onClose: () {
                ref
                    .read(directChatProvider(widget.otherUserId).notifier)
                    .clearReplyTo();
              },
            ),
          // v3.3: shared ChatInputBar — same gradient surface, same
          // elevated capsule, same send button as the group. DM passes
          // only text + send (showAttach/showEmoji/showStickers/showPoll/
          // showVoice all false — the DM backend supports text only).
          ChatInputBar(
            textController: _textController,
            focusNode: _focusNode,
            isComposing: _isComposing,
            onSend: _sendMessage,
            showAttach: false,
            showEmoji: false,
            showStickers: false,
            showPoll: false,
            showVoice: false,
          ),
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

  // v3.3: the old DM-only _buildInputBar was replaced by the shared
  // ChatInputBar widget (see the body Column above). The DM passes
  // showAttach/showEmoji/showStickers/showPoll/showVoice all false —
  // the DM backend supports text only.
}
