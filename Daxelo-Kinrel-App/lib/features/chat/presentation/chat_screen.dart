// v3.5: the global_error_widget import (KinrelAnimatedBuilder) moved
// with the typing indicator into the shared typing_indicator.dart.
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
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
// v3.5: the emoji_picker_flutter import moved with the full-emoji sheet
// into the shared reaction_picker.dart (this screen now delegates).
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/theme/kinrel_fx.dart';
import '../../../core/family/family_provider.dart';
import '../../../l10n/app_localizations.dart';
// v3.3: AppTime import removed — date grouping moved to ChatMessageList.
import '../../../core/utils/web_keyboard_height.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/celebration_service.dart';
// Phase 4 — consolidated image cache manager (used for the header avatar
// + MessageInfoSheet photo/gif previews so they share the singleton cache
// and decode at display-size × DPR instead of native resolution).
import '../../../core/services/image_cache_manager.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../family/data/relationship_label_provider.dart';
import '../../profile/presentation/member_profile_sheet.dart';
import '../data/chat_enhancement_service.dart';
import '../data/chat_lock_service.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_onboarding_provider.dart';
import '../providers/chat_socket_engagement_provider.dart';
import 'chat_onboarding_coach_marks.dart';
// QA fix 2026-09-19: socketServiceProvider (emitUnpinMessage at the unpin call
// site) requires this import — it was missing from the chat-engagement merge.
import '../../../core/network/socket_service.dart';
import 'sticker_panel.dart';
// Phase 22 / Task 3 — @mention picker overlay + highlight renderer.
import 'widgets/mention_picker.dart';
// Phase 22 / Task 5 — poll card bubble (reuses the gameInvite card pattern).
// Phase 22 / Task 5 — poll composer bottom sheet.
import 'widgets/poll_composer_sheet.dart';
import 'widgets/forward_picker_sheet.dart';
import 'widgets/disappearing_messages_sheet.dart';
import 'widgets/message_info_sheet.dart';
import 'widgets/gif_search_sheet.dart';
import 'widgets/sticker_pack_sheet.dart';
import 'widgets/chat_meta.dart';
import 'widgets/empty_chat_state.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/pinned_messages_bar.dart';
// v3.4 — shared reply bar / peek-preview / scroll FAB (moved here from
// this file so the DM screen renders the SAME widgets).
import 'widgets/reply_preview_bar.dart';
import 'widgets/message_preview_dialog.dart';
// v3.5 — shared engagement widgets (moved from this screen so the DM
// renders the SAME indicator + reaction pickers).
import 'widgets/typing_indicator.dart';
import 'widgets/reaction_picker.dart';
import '../../family/presentation/family_space_floating_nav.dart';
import '../data/chat_wallpaper_provider.dart';
import '../data/wallpaper_picker.dart';
import 'widgets/chat_background.dart';
import 'widgets/chat_theme_picker_sheet.dart';
import 'widgets/selection_mode_toolbar.dart';

// ═══════════════════════════════════════════════════════════════════════
// Chat Screen
// ═══════════════════════════════════════════════════════════════════════

// PERF (Tier C3): Hoisted const shadow list — avoids per-build allocation
// of the chat avatar's ember glow. The chat-thread screen rebuilds on
// every new realtime message + every typing-indicator tick, so even a
// single BoxShadow allocation per rebuild was visible as ~5ms of GC
// pressure per minute of active chat use.
//
// `KinrelColors.ember` is Color(0xFFC44A18). Multiplied by alpha 0.18
// → Color(0x2EC44A18). RGB matches exactly; alpha is pre-multiplied.
//
// PERF (Flat): KinrelFx.shadows returns the empty list in flat mode
// (no avatar glow). The const list is preserved for rich mode.
final List<BoxShadow> _kChatAvatarGlow = KinrelFx.shadows(const [
  BoxShadow(
    color: Color(0x2EC44A18), // KinrelColors.ember (#C44A18) × alpha 0.18
    blurRadius: 14,
    offset: Offset(0, 0),
  ),
]);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.familyId,
    required this.familyName,
    this.showFamilyNav = true,
    this.groupId,
    this.groupName,
    this.hideAppBar = false,
    this.isDirectChat = false,
    this.directOtherUserId,
  });

  /// The family ID for this chat.
  final String familyId;

  /// Display name for the AppBar.
  final String familyName;

  /// v115: Whether to show the FamilySpaceFloatingNav at the bottom.
  ///
  /// When `true` (default, backward-compatible), the chat screen shows
  /// the Family Space bottom nav — this is the old behaviour where the
  /// Chat tab opened the group chat directly.
  ///
  /// When `false`, the chat screen is full-screen (no bottom nav) —
  /// used when the chat is opened from the Family Chat List screen as
  /// a pushed conversation, matching WhatsApp/Telegram UX.
  final bool showFamilyNav;

  /// v139: Group ID for sub-group chats. When set, the screen filters
  /// messages to this group only and uses [groupName] in the header.
  /// When null, shows the family-wide chat (existing behavior).
  final String? groupId;

  /// v139: Display name for the group (used in the AppBar when
  /// [groupId] is set). Falls back to [familyName] if null.
  final String? groupName;

  /// v140 Family-Centric Chat Navigation: when true, the ChatScreen's
  /// own AppBar is suppressed. Used when the ChatScreen is embedded
  /// inside a parent Scaffold (e.g. the redesigned FamilyChatListScreen
  /// which provides its own header with [Family] [Direct] tab switcher).
  /// The parent screen is responsible for rendering the family name +
  /// member count header in this case.
  final bool hideAppBar;

  /// Kin Thread / C2: true when this chat is a PRIVATE 2-person direct
  /// group (groupType='direct'). The screen is the SAME group chat
  /// screen; direct capabilities hide the group-only UI (Family chip,
  /// group info header tap, mentions picker, read-by info, sender
  /// identity, relationship pills + rails) and swap the header for the
  /// other person's identity. Everything else (reply, swipe, reactions,
  /// selection-mode actions, attachments, invites, wallpapers, the
  /// unread divider, the floating date chip) is identical.
  final bool isDirectChat;

  /// Kin Thread / C2: the other person's user id (set when
  /// [isDirectChat] is true). Used for the header identity + subtitle,
  /// and to keep the dm_-keyed wallpaper/lock keys stable.
  final String? directOtherUserId;

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

  // Tier 2 / Chat Lock — when true, the chat screen shows a biometric
  // lock overlay instead of the message thread. Set in initState by
  // reading the per-chat lock flag from shared_preferences.
  bool _isChatLocked = false;
  bool _isCheckingLock = true; // true while initState is reading the lock

  // Phase 22 / Task 3 — @mention picker state.
  // The picker is rendered as an OverlayEntry anchored to the message
  // input via a LayerLink. MentionTracker keeps the pending MentionRef
  // list in sync with the text as the user types.
  late final MentionTracker _mentionTracker;
  final LayerLink _inputLayerLink = LayerLink();
  OverlayEntry? _mentionOverlay;
  String? _currentUserIdCache;

  // v3.5: the typing indicator's animation MOVED to the shared
  // TypingIndicator widget (typing_indicator.dart) — it owns its own
  // controller and only animates while mounted (the screen gates the
  // widget on someone-typing, so the PERF (Part C3) behavior is
  // preserved). The screen-side controller/dot animations are gone.

  // Phase 13: Voice recorder state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSendingVoice = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  // Phase 14: Sticker panel toggle
  bool _showStickerPanel = false;

  // ── Selection Mode (multi-select) ───────────────────────────────────
  // When active, the AppBar is replaced with SelectionModeToolbar,
  // bubbles get a selection checkbox + ring, and tapping a bubble
  // toggles selection instead of opening the action sheet.
  // Long-press on a bubble ENTERS selection mode + selects that bubble.
  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};

  // v112: Chat wallpaper color — loaded from ChatSettings in initState
  // and applied as the messages-list background. Updated immediately
  // in _showWallpaperPicker's onTap so the change is visible without
  // needing to leave and re-enter the chat.
  Color? _wallpaperColor;

  // v128: Web keyboard height — on Flutter Web, resizeToAvoidBottomInset
  // doesn't work because the browser doesn't resize the layout viewport
  // when the keyboard opens. We use the visualViewport API instead to
  // detect the actual keyboard height and add explicit bottom padding.
  double _webKeyboardHeight = 0;

  // v3.5: the quick-reaction emoji list MOVED to the shared
  // reaction_picker.dart (kQuickReactionEmojis) with the quick-reactions
  // row — both chat types render the identical 6 defaults.

  // The real current user id (replaces the old hard-coded 'user_me' check).
  // Read from chatCurrentUserIdProvider which is wired to Supabase auth.
  String? get _currentUserId =>
      ref.read(chatCurrentUserIdProvider);

  /// Returns true if [msg] was sent by the current user.
  bool _isMine(ChatMessage msg) =>
      msg.senderId == _currentUserId;

  /// Kin Thread / C2 — the wallpaper (and lock) key: direct chats keep
  /// the OLD dm_-prefixed keys so users' saved wallpapers/locks carry
  /// over from the DirectMessage era; family + group chats keep using
  /// familyId (existing behavior).
  String get _chatSettingsKey =>
      widget.isDirectChat && widget.directOtherUserId != null
          ? 'dm_${widget.directOtherUserId}'
          : widget.familyId;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _mentionTracker = MentionTracker(_textController);

    // Tier 2 / Chat Lock — check if this chat is locked + prompt
    // biometrics if so. Fires async in initState; the lock overlay
    // shows until the user authenticates.
    _checkChatLock();

    _scrollController.addListener(_onScroll);
    _textController.addListener(_onTextChanged);

    // v126: When the text field gains focus (keyboard opens), scroll
    // to the latest message so it's not hidden behind the keyboard.
    // v133: Also trigger setState on focus change so the unified
    // capsule's focus border + ember glow update smoothly.
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
      if (mounted) setState(() {});
    });

    // v128: Start web keyboard height detection. On native, this is
    // a no-op (Scaffold's resizeToAvoidBottomInset handles it).
    WebKeyboardHeight.instance.start();
    WebKeyboardHeight.instance.addListener(_onWebKeyboardHeight);

    // v3.5: typing indicator setup was REMOVED — the shared
    // TypingIndicator widget (typing_indicator.dart) owns its animation
    // and only animates while mounted. The ref.listen calls that
    // started/stopped the screen-side controller are gone with it.

    // Mark all as read on enter (this chat's scope only).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(chatProvider(widget.familyId).notifier)
          .markAllRead(groupId: widget.groupId);
      // v112: Load saved wallpaper color so it's applied on first render.
      _loadWallpaperColor();
    });
  }

  /// Kin Thread / PR2 Task 3 — the provider no longer auto-marks
  /// messages read after its initial load (that cleared the family
  /// badge whenever a group/direct chat was opened). This screen now
  /// marks its OWN scope read, once, as soon as its messages arrive.
  /// The unread-divider snapshot is captured inside markAllRead BEFORE
  /// the isRead flags flip, so the divider survives marking.
  bool _markedReadOnOpen = false;
  void _maybeMarkReadOnOpen(ChatState chatState) {
    if (_markedReadOnOpen) return;
    if (chatState.isLoading || chatState.messages.isEmpty) return;
    _markedReadOnOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(chatProvider(widget.familyId).notifier)
          .markAllRead(groupId: widget.groupId);
    });
  }

  /// v128: Called when the web keyboard height changes (visualViewport API).
  void _onWebKeyboardHeight() {
    if (mounted) {
      setState(() {
        _webKeyboardHeight = WebKeyboardHeight.instance.currentHeight;
      });
    }
  }

  /// v112: Fetch the saved wallpaperColor from ChatSettings and store
  /// it in _wallpaperColor so the body background picks it up. Called
  /// once from initState (via addPostFrameCallback so ref is ready).
  void _loadWallpaperColor() async {
    final service = ref.read(chatEnhancementServiceProvider);
    final settings = await service.getChatSettings(widget.familyId);
    if (mounted && settings != null) {
      final hex = settings['wallpaperColor'] as String?;
      if (hex != null && hex.isNotEmpty) {
        try {
          final colorValue =
              int.parse(hex.substring(1, 7), radix: 16) + 0xFF000000;
          setState(() => _wallpaperColor = Color(colorValue));
        } catch (_) {
          // Ignore malformed hex — keep null (default background).
        }
      }
    }
  }

  @override
  void dispose() {
    // v128: Clean up web keyboard height listener.
    WebKeyboardHeight.instance.removeListener(_onWebKeyboardHeight);
    // Phase 22 / Task 3 — clean up the mention picker overlay so it
    // doesn't leak if the screen closes while it's open.
    _hideMentionPicker();
    // Tier 3 / Live Location — cancel the location update timer so it
    // doesn't keep sending updates after the screen closes.
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
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

  // v3.5 — typing emission throttle: while the user is composing, the
  // typing row is refreshed at most once every 2s so receivers' 3-second
  // auto-clear timers keep getting reset (a live typer never looks
  // idle). Compose-flips (empty→text / text→empty) always write
  // immediately — the same start/stop semantics as before.
  DateTime? _lastTypingWriteAt;

  void _onTextChanged() {
    final composing = _textController.text.trim().isNotEmpty;
    if (composing != _isComposing) {
      // CRITICAL ANN FIX: Added mounted check before setState.
      if (mounted) {
        setState(() => _isComposing = composing);
      }
      // v109.11: Send typing status to Supabase.
      // Kin Thread / C2: skipped in direct chats — ChatTypingStatus is
      // family-scoped (UNIQUE(familyId, userId), no groupId), so a
      // private typing signal would leak into the family chat's
      // indicator. Documented in docs/DM_REBUILD_PLAN.md.
      if (!widget.isDirectChat) {
        final service = ref.read(chatEnhancementServiceProvider);
        service.setTypingStatus(widget.familyId, composing);
        _lastTypingWriteAt = DateTime.now();
      }
    } else if (composing) {
      // v3.5 — throttled keystroke refresh: the receiver-side indicator
      // auto-clears 3s after the last event, so an actively-typing user
      // must keep the ChatTypingStatus row fresh (≤2s cadence).
      final now = DateTime.now();
      final last = _lastTypingWriteAt;
      if (!widget.isDirectChat &&
          (last == null ||
              now.difference(last).inMilliseconds >= 2000)) {
        final service = ref.read(chatEnhancementServiceProvider);
        service.setTypingStatus(widget.familyId, true);
        _lastTypingWriteAt = now;
      }
    }

    // Phase 22 / Task 3 — @mention picker detection. MentionTracker
    // walks back from the cursor to find an "@" trigger that's at the
    // start of input or preceded by whitespace. If found, the text
    // between "@" and the cursor becomes the search query and the
    // picker overlay is shown (or updated with the new query).
    // Kin Thread / C2: no mentions picker in direct chats (2 people
    // only — a group-only feature).
    if (widget.isDirectChat) {
      if (_mentionOverlay != null) _hideMentionPicker();
      return;
    }
    final trigger = _mentionTracker.detectTrigger();
    if (trigger != null) {
      _showMentionPicker(trigger);
    } else if (_mentionOverlay != null) {
      _hideMentionPicker();
    }
  }

  // ── Phase 22 / Task 3: @mention picker show/hide ──────────────────

  void _showMentionPicker(String query) {
    if (!mounted) return;

    // Cache the current user ID once (used to exclude self from the list).
    _currentUserIdCache ??= _currentUserId;
    final currentUserId = _currentUserIdCache ?? '';

    // Resolve family members from chat state.
    final chatState = ref.read(chatProvider(widget.familyId));
    final members = chatState.members
        .map(MentionableMember.fromOnlineMember)
        .toList();

    if (_mentionOverlay == null) {
      _mentionOverlay = OverlayEntry(
        builder: (context) => MentionPickerOverlay(
          members: members,
          query: query,
          layerLink: _inputLayerLink,
          currentUserId: currentUserId,
          onSelected: _onMentionSelected,
          onDismissed: _hideMentionPicker,
        ),
      );
      Overlay.of(context).insert(_mentionOverlay!);
    } else {
      // Update the query + members in the existing overlay.
      _mentionOverlay!.markNeedsBuild();
    }
  }

  void _hideMentionPicker() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
  }

  void _onMentionSelected(MentionableMember m) {
    _mentionTracker.insertMention(m);
    _hideMentionPicker();
    _focusNode.requestFocus();
    if (mounted) setState(() {}); // refresh to update send button state
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

  /// Feature 6: scroll to a specific message by ID. Used when the user
  /// taps the quoted reply preview above a bubble — jumps to the original
  /// message being replied to.
  ///
  /// The ListView is reverse: true (newest at top, index 0 = newest).
  /// We find the message's index in the flat (newest-first) list, then
  /// estimate the scroll offset as index * ~72px (average bubble height
  /// including spacing). This is approximate — for very long chats the
  /// estimate may be off by a few bubbles, but the user can fine-tune
  /// with a manual scroll. A future improvement would use
  /// Scrollable.ensureVisible with a GlobalKey per message.
  void _scrollToMessage(String messageId) {
    final messages = ref.read(chatProvider(widget.familyId)).messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      // Message not in the current viewport (e.g. very old message not
      // loaded yet). Show a snackbar telling the user to scroll up.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // Feature 7: localized snackbar
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

    // ── Haptic: tap confirms the send fired before the optimistic insert
    // completes. This is the WhatsApp/iMessage pattern — the message
    // appears instantly with a tiny tactile confirmation.
    HapticService.tap();

    final chatState = ref.read(chatProvider(widget.familyId));
    // ── Celebration: fire the firstMessage milestone on the user's very
    // first chat send. Idempotent — only fires once per user, ever.
    // This is the "social activation" moment: the user went from passive
    // (browsing trees) to active (talking to family).
    unawaited(
      CelebrationService.instance
          .checkAndCelebrate(
            context: context,
            milestone: Milestone.firstMessage,
          )
          .catchError((_) => false),
    );
    // sendMessage() does an optimistic insert synchronously, then persists
    // to Supabase async. Fire-and-forget the Future — the UI already
    // updated and the realtime INSERT event will be de-duped by the
    // notifier.
    final replyToId = chatState.replyToMessage?.id;

    // Phase 22 / Task 3 — if the user has any pending @mention refs,
    // route through sendMessageWithMentions so the RPC fires the
    // distinct 'chat_mention' notifications to each mentioned user.
    // The MentionTracker has already kept the refs in sync with the
    // text on every change, so its .refs list is the source of truth.
    final pendingMentions = _mentionTracker.refs.toList();
    Future.microtask(() {
      if (pendingMentions.isEmpty) {
        ref
            .read(chatProvider(widget.familyId).notifier)
            .sendMessage(text, replyToId: replyToId, groupId: widget.groupId);
      } else {
        ref.read(chatProvider(widget.familyId).notifier).sendMessageWithMentions(
              text,
              mentions: pendingMentions,
              replyToId: replyToId,
              groupId: widget.groupId,
            );
      }
    });

    _textController.clear();
    _mentionTracker.clear();
    _hideMentionPicker();
    _focusNode.requestFocus();
    // v126: Scroll to bottom after sending so the new message is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
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

  // Phase 22 / Task 5 — open the poll composer sheet. Closes the
  // sticker panel first so we don't stack two input surfaces.
  /// Tier 3 / Sticker Packs — opens the StickerPackSheet (Giphy
  /// transparent-background stickers). Closes the emoji panel first.
  Future<void> _openStickerPacks() async {
    if (_showStickerPanel && mounted) {
      setState(() => _showStickerPanel = false);
    }
    _focusNode.unfocus();
    await StickerPackSheet.show(
      context,
      onStickerSelected: (stickerUrl, title) {
        ref.read(chatProvider(widget.familyId).notifier).sendGif(
              gifUrl: stickerUrl,
              title: title,
            );
      },
    );
  }

  Future<void> _openPollComposer() async {
    if (_showStickerPanel && mounted) {
      setState(() => _showStickerPanel = false);
    }
    _focusNode.unfocus();
    final replyToId = ref.read(chatProvider(widget.familyId)).replyToMessage?.id;
    await PollComposerSheet.show(
      context,
      familyId: widget.familyId,
      replyToId: replyToId,
    );
  }

  void _showReactionPicker(String messageId) {
    // v3.5: the overlay + full-emoji sheet were MOVED to the shared
    // reaction_picker.dart (showReactionOverlay / showFullEmojiSheet)
    // so the DM opens the SAME UI. The group passes its provider's
    // toggleReaction as the emoji handler — identical behavior to the
    // previous inline version.
    showReactionOverlay(
      context,
      onEmojiSelected: (emoji) {
        ref
            .read(chatProvider(widget.familyId).notifier)
            .toggleReaction(messageId, emoji);
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.familyId));
    // Kin Thread / PR2 T3: mark THIS chat's scope read once its
    // messages have loaded (the provider no longer auto-marks the
    // whole family — see markAllRead({groupId})).
    _maybeMarkReadOnOpen(chatState);
    // Pack 13: Socket.IO engagement state (typing / streak / presence /
    // read receipts / reactions). Additive to the Supabase Realtime state
    // in chatState — gives sub-second updates for the engagement signals.
    final engagement = ref.watch(chatEngagementProvider(widget.familyId));
    final rawMessages = chatState.messages;

    // v112: Filter out messages that were deleted-for-me or
    // deleted-for-everyone. The ChatMessage model already has an
    // isHiddenFor(userId) helper, but it was never called — so even
    // after the fn_delete_message_for_me / fn_delete_for_everyone RPCs
    // succeeded (they set deletedForMe / isDeletedForEveryone columns),
    // refreshMessages() re-fetched ALL rows including the hidden ones
    // and they stayed visible. This filter fixes that.
    final uid = _currentUserId;
    // v139: If groupId is set, filter to only messages belonging to
    // this sub-group. Otherwise (family-wide chat), show messages
    // where groupId is null (excludes group-scoped messages).
    List<ChatMessage> messages = uid != null
        ? rawMessages.where((m) => !m.isHiddenFor(uid)).toList()
        : rawMessages;
    if (widget.groupId != null) {
      messages = messages.where((m) => m.groupId == widget.groupId).toList();
    } else {
      messages = messages.where((m) => m.groupId == null).toList();
    }

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
    } else if (messages.isEmpty) {
      // Feature 3: Empty state with kinship-aware greeting suggestions.
      // Shown when the chat has zero messages (not loading, no error).
      // The widget fetches upcoming birthdays + relationship-aware
      // suggestions from GET /families/:id/chat/nudge.
      bodyContent = EmptyChatState(
        familyId: widget.familyId,
        onSuggestionTap: (suggestion) {
          // One-tap send: call the chatProvider's sendMessage directly
          // with the suggestion text. This gives the user a one-tap
          // "send greeting" flow without typing.
          ref
              .read(chatProvider(widget.familyId).notifier)
              .sendMessage(suggestion, groupId: widget.groupId);
        },
      );
    } else {
      bodyContent = Column(
        children: [
          // Feature 3: Pinned messages bar (shown above the message list).
          // Hidden when there are no pinned messages. Tapping scrolls to
          // the pinned message; long-press unpins (with confirmation).
          PinnedMessagesBar(
            familyId: widget.familyId,
            onMessageTap: (messageId) => _scrollToMessage(messageId),
            onUnpin: (messageId) {
              ref.read(socketServiceProvider).emitUnpinMessage(
                familyId: widget.familyId,
                messageId: messageId,
              );
            },
          ),
          Expanded(
            child: Stack(
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
            ),
          ),
        ],
      );
    }

    // Feature 7: check if the onboarding coach marks should be shown.
    // Triggered after the user sends their first message ever (based on
    // the first_message_in_chat analytics event) AND hasn't seen the
    // coach marks yet (hasSeenChatOnboarding flag in SharedPreferences).
    final showOnboarding = ref.watch(shouldShowChatOnboardingProvider(widget.familyId));

    return PopScope(
      // v6.0 — When selection mode is active, the back button exits
      // selection mode instead of popping the screen (Image 3 reference).
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) {
          _exitSelectionMode();
        }
      },
      child: Stack(
      children: [
        DKScaffold(
      // v132: The background is now rendered by ChatBackground (a
      // multi-layer ambient gradient + optional blurred wallpaper).
      // The Scaffold background is a flat dark color that only shows
      // behind the AppBar/input bar — the messages area is fully
      // covered by ChatBackground.
      backgroundColor: const Color(0xFF0A0B16),
      // v126: Explicitly enable keyboard resizing so the input bar
      // moves above the keyboard (WhatsApp-style).
      resizeToAvoidBottomInset: true,
      // v140 Family-Centric Chat Navigation: hideAppBar lets the parent
      // (e.g. FamilyChatListScreen with [Family]/[Direct] tabs) provide
      // its own header without a double-AppBar.
      // Selection mode: swap the normal AppBar for the selection toolbar
      // when active, so the user sees count + bulk actions at the top.
      appBar: widget.hideAppBar
          ? null
          : (_selectionMode
              ? SelectionModeToolbar(
                  selectedCount: _selectedMessageIds.length,
                  onClose: _exitSelectionMode,
                  onReply: _bulkReply,
                  onForward: _bulkForward,
                  onStar: _bulkStar,
                  onDelete: _bulkDelete,
                  onMore: _bulkMore,
                )
              : _buildAppBar(chatState)),
      // v115: Only show the Family Space bottom nav when this screen
      // is the tab destination (showFamilyNav=true). When opened as a
      // pushed conversation from the chat list, the bottom nav is
      // hidden so the chat is full-screen (WhatsApp/Telegram style).
      bottomNavigationBar: widget.showFamilyNav
          ? FamilySpaceFloatingNav(familyId: widget.familyId)
          : null,
      body: _isCheckingLock
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.ember),
            )
          : _isChatLocked
              ? _buildLockScreen()
              : Column(
                  children: [
                    // v132: Messages list wrapped with ChatBackground — a
                    // multi-layer ambient gradient (base + accent glow +
                    // vignette) plus optional blurred custom wallpaper.
                    // Gives the chat space depth without competing with bubbles.
                    Expanded(
                      child: ChatBackground(
                        // Kin Thread / C2: direct chats keep the dm_-keyed
                        // wallpaper slot so saved choices carry over.
                        chatId: _chatSettingsKey,
                        child: bodyContent,
                      ),
                    ),
                    // Selection mode hides the typing indicator, reply
                    // preview, sticker panel, and input bar — the user
                    // is picking messages, not composing.
                    if (!_selectionMode) ...[
                      // Typing indicator — shows if EITHER the Supabase
                      // Realtime typing status OR the Socket.IO engagement
                      // layer reports someone typing. The engagement layer
                      // is preferred when both fire (it has the more recent
                      // event + a richer multi-user label).
                      if (chatState.isTyping || engagement.isSomeoneTyping)
                        _buildTypingIndicator(chatState, engagement),
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
                      // v128: On Flutter Web, resizeToAvoidBottomInset doesn't detect
                      // the mobile keyboard. We add explicit bottom padding equal to
                      // the visualViewport-measured keyboard height so the input bar
                      // is always visible above the keyboard.
                      if (kIsWeb && _webKeyboardHeight > 0)
                        SizedBox(height: _webKeyboardHeight),
                    ],
                  ],
                ),
        ),
        // Feature 7: onboarding coach-mark overlay (shown once after
        // the user's first message ever).
        if (showOnboarding)
          ChatOnboardingCoachMarks(
            onComplete: () {
              // Invalidate the onboarding status provider so it refetches
              // (the hasSeenChatOnboarding flag is now true, so
              // shouldShowChatOnboardingProvider returns false).
              ref.invalidate(chatOnboardingStatusProvider(widget.familyId));
            },
          ),
      ],
      ),
    );
  }

  // ── Tier 2 / Chat Lock — Lock Screen ─────────────────────────────

  /// Full-screen lock overlay shown when the chat is locked. Renders
  /// a lock icon + "This chat is locked" + an "Authenticate" button.
  /// The user taps the button to trigger biometrics via _promptUnlock.
  Widget _buildLockScreen() {
    return Container(
      color: const Color(0xFF0A0B16),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.ember.withValues(alpha: 0.12),
                    border: Border.all(
                      color: KinrelColors.ember.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 36,
                    color: KinrelColors.ember,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'This chat is locked',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Authenticate with Face ID, Touch ID, or your device PIN to view messages.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _promptUnlock,
                  icon: const Icon(Icons.fingerprint_rounded, size: 20),
                  label: const Text('Authenticate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KinrelColors.ember,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                  child: const Text(
                    'Go back',
                    style: TextStyle(color: KinrelColors.textDim),
                  ),
                ),
              ],
            ),
          ),
        ),
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

  /// v124: Builds the default letter avatar (fallback when no image).
  Widget _buildLetterAvatar() {
    return Text(
      (widget.familyName.isNotEmpty
              ? widget.familyName.substring(0, 1)
              : 'F')
          .toUpperCase(),
      style: const TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }


  /// Kin Thread / C2: the header action buttons (search, video,
  /// call, and the â® menu) — ONE implementation shared by the
  /// family header AND the direct-chat header. The differences
  /// between group and direct chat come from capabilities and per
  /// screen wiring — never from copy-pasted UI.
  Widget _buildHeaderActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Action buttons (visually balanced, secondary) ────
        // v134: Actions use a softer icon style (outline, 20px,
        // silver) so they never compete with the identity column.
        // The members button is dropped — redundant with tapping
        // the avatar/header which navigates to family detail.
        // Feature 5: search icon added before video/voice for
        // discoverability (also accessible via the more menu).
        HeaderActionButton(
          icon: Icons.search,
          size: 20,
          onPressed: () {
            context.push('/family/${widget.familyId}/chat/search');
          },
        ),
        HeaderActionButton(
          icon: Icons.videocam_outlined,
          size: 20,
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video call coming soon!'),
                backgroundColor: KinrelColors.darkCard,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        HeaderActionButton(
          icon: Icons.call_outlined,
          size: 18,
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Voice call coming soon!'),
                backgroundColor: KinrelColors.darkCard,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        // More menu — settings, wallpaper, mute, etc.
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              color: KinrelColors.textSilver, size: 20),
          color: KinrelColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onSelected: (value) {
            switch (value) {
              case 'search':
                context.push('/family/${widget.familyId}/chat/search');
                break;
              case 'search_all':
                context.push('/chats/search');
                break;
              case 'disappearing':
                DisappearingMessagesSheet.show(
                  context,
                  familyId: widget.familyId,
                );
                break;
              case 'lock':
                _toggleChatLock();
                break;
              case 'export':
                _exportChat();
                break;
              case 'live_location':
                _shareLiveLocation();
                break;
              case 'theme':
                _showThemePicker();
                break;
              case 'constellation':
                // Kin Thread / PR2 T4: one-tap access to the
                // Constellation preset (also in Chat Atmosphere).
                ref.read(chatWallpaperProvider.notifier).setWallpaper(
                      _chatSettingsKey,
                      'theme:constellation',
                    );
                break;
              case 'wallpaper':
                _showImageWallpaperPicker(context, _chatSettingsKey);
                break;
              case 'wallpaper_color':
                _showWallpaperColorPicker();
                break;
              case 'mute':
                _toggleMute();
                break;
              case 'starred':
                _showStarredMessages();
                break;
              case 'pinned':
                _showPinnedMessages();
                break;
            }
          },
          itemBuilder: (ctx) => [
            // Tier 1 / Message Search — put search at the top of
            // the menu since it's the most-used action. Two
            // scopes: this chat + all chats.
            const PopupMenuItem(
                value: 'search',
                child: Row(children: [
                  Icon(Icons.search_rounded, size: 18,
                      color: KinrelColors.ember),
                  SizedBox(width: 12),
                  Text('Search this chat'),
                ])),
            const PopupMenuItem(
                value: 'search_all',
                child: Row(children: [
                  Icon(Icons.manage_search_rounded, size: 18,
                      color: KinrelColors.ember),
                  SizedBox(width: 12),
                  Text('Search all chats'),
                ])),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'constellation',
                child: Text('Constellation (default wallpaper)')),
            const PopupMenuItem(
                value: 'theme', child: Text('Chat Atmosphere')),
            const PopupMenuItem(
                value: 'wallpaper', child: Text('Custom Wallpaper')),
            const PopupMenuItem(
                value: 'wallpaper_color', child: Text('Solid Color')),
            const PopupMenuItem(
                value: 'mute', child: Text('Mute notifications')),
            // Tier 2 / Disappearing Messages — opens the
            // DisappearingMessagesSheet to enable/disable per-chat
            // auto-deletion (24h / 7d / 90d / off).
            const PopupMenuItem(
                value: 'disappearing',
                child: Row(children: [
                  Icon(Icons.timer_outlined, size: 18,
                      color: KinrelColors.ember),
                  SizedBox(width: 12),
                  Text('Disappearing messages'),
                ])),
            // Tier 2 / Chat Lock — toggle per-chat biometric lock.
            const PopupMenuItem(
                value: 'lock',
                child: Row(children: [
                  Icon(Icons.lock_outline, size: 18,
                      color: KinrelColors.ember),
                  SizedBox(width: 12),
                  Text('Chat lock'),
                ])),
            // Tier 3 / Export chat — exports conversation as text
            const PopupMenuItem(
                value: 'export',
                child: Row(children: [
                  Icon(Icons.file_download_outlined, size: 18,
                      color: KinrelColors.ember),
                  SizedBox(width: 12),
                  Text('Export chat'),
                ])),
            // Tier 3 / Live location — share live location with
            // duration options (15min / 1h / 8h)
            const PopupMenuItem(
                value: 'live_location',
                child: Row(children: [
                  Icon(Icons.my_location_rounded, size: 18,
                      color: KinrelColors.ember),
                  SizedBox(width: 12),
                  Text('Share live location'),
                ])),
            const PopupMenuItem(
                value: 'starred', child: Text('Starred messages')),
            const PopupMenuItem(
                value: 'pinned', child: Text('Pinned messages')),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }


  /// Kin Thread / C2 — the DIRECT chat header: the other person's
  /// identity (avatar + name) with the RELATIONSHIP to the viewer as
  /// the subtitle when it resolves (e.g. "Father"), otherwise their
  /// online status. No Family chip, no member count, no family-profile
  /// tap targets; tapping the identity opens the person's profile
  /// sheet. Shares _buildHeaderActions() with the family header.
  PreferredSizeWidget _buildDirectAppBar(ChatState chatState) {
    final otherUserId = widget.directOtherUserId;
    final displayName = widget.groupName ?? widget.familyName;
    String? relationship;
    if (widget.familyId.isNotEmpty && otherUserId != null) {
      relationship = ref.watch(relationshipLabelProvider(
        (familyId: widget.familyId, senderUserId: otherUserId),
      ));
    }
    final otherMember = otherUserId == null
        ? null
        : chatState.members.where((m) => m.id == otherUserId).firstOrNull;
    final isOnline = otherMember?.isOnline ?? false;
    final subtitle = relationship ?? (isOnline ? 'Active now' : 'Offline');

    return PreferredSize(
      preferredSize: const Size.fromHeight(72),
      child: Container(
        decoration: BoxDecoration(
          // Same flat surface as the family header (one visual language).
          color: KinrelFx.rich ? null : const Color(0xFF0A0B16),
          gradient: KinrelFx.gradient(
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF11132A),
                Color(0xFF0A0B16),
              ],
            ),
          ),
          border: Border(
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.06), width: 0.5),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                // ── Back ──────────────────────────────────────────────
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: KinrelColors.textSilver,
                  ),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else if (widget.directOtherUserId != null) {
                      context.go(
                          '/family/${widget.familyId}/direct/${widget.directOtherUserId}');
                    } else {
                      context.go('/family/${widget.familyId}');
                    }
                  },
                ),
                // ── The other person's avatar (tap → profile) ─────────
                GestureDetector(
                  onTap: otherUserId != null
                      ? () => MemberProfileSheet.show(context, otherUserId)
                      : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    // PERF note: NOT const — _kChatAvatarGlow is a
                    // runtime-final list (same reason as the family
                    // header's avatar decoration).
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: _kChatAvatarGlow,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: KinrelColors.ember.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: ClipOval(
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: KinrelGradients.igniteGradient,
                          ),
                          child: Center(
                            child: Text(
                              displayName.isNotEmpty
                                  ? displayName.substring(0, 1).toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // ── Identity + subtitle (tap → profile) ───────────────
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: otherUserId != null
                        ? () => MemberProfileSheet.show(context, otherUserId)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                            letterSpacing: 0.1,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline
                                    ? KinrelColors.success
                                    : KinrelColors.textDim,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: KinrelColors.textSilver
                                    .withValues(alpha: 0.8),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Shared actions (search / video / call / ⋮ menu) ────
                _buildHeaderActions(),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ChatState chatState) {
    // Kin Thread / C2 — direct chats render a PERSON header (the other
    // person's name + avatar, relationship/online subtitle) instead of
    // the FAMILY header. No Family chip, no family-profile tap targets,
    // no member count. Tapping the identity opens the other person's
    // profile sheet (not the family profile).
    if (widget.isDirectChat) {
      return _buildDirectAppBar(chatState);
    }
    // v134 KINREL SIGNATURE HEADER
    // Design language: relationship-centered rather than utility-bar.
    // The header celebrates the human connection rather than treating
    // the recipient as a contact row. Visual hierarchy is:
    //   1. Person (avatar with premium framing)
    //   2. Relationship (Kinrel signature chip — "Family" / "Group")
    //   3. Status (refined presence indicator)
    //   4. Actions (visually balanced, never competing with identity)
    //
    // Unique Kinrel element: a small relationship chip below the name
    // with a soft ember accent — this is what makes the header
    // recognizable as Kinrel rather than another messaging app.
    //
    // Header atmosphere: the surface uses the same vertical gradient
    // as the v132 ChatBackground + v133 composer so the whole screen
    // feels cohesive. A subtle ember ambient glow behind the avatar
    // adds warmth.
    final avatarUrl = ref.watch(familyAvatarProvider(widget.familyId));
    // v5.211 (member-count de-conflation): the chat header used to show
    // `familyDetail.family.memberCount` — a BLENDED count of every
    // Person row (Linked Kinrel accounts + Manual placeholder
    // relatives). That was misleading: a placeholder relative can
    // never send or receive a chat message, so "Family · 5" in a chat
    // context implies 5 real people who could chat — not 5 tree nodes.
    //
    // Now we read [linkedMemberCountProvider] which counts only real,
    // active Kinrel accounts (Linked status). Falls back to the chat
    // state's `members.length` while the family detail provider is
    // still loading — chat-state members are themselves Linked-only
    // (sourced from the membership table), so the fallback is also a
    // real-people count.
    final linkedCount = ref.watch(linkedMemberCountProvider(widget.familyId));
    final memberCount = linkedCount > 0
        ? linkedCount
        : chatState.members.length;

    return PreferredSize(
      preferredSize: const Size.fromHeight(72),
      child: Container(
        decoration: BoxDecoration(
          // PERF (Flat): solid color in flat mode; gradient in rich mode.
          // v134: Vertical gradient matches ChatBackground + composer
          // for full-screen cohesion. Top is slightly lighter (lit
          // from above), bottom darker.
          color: KinrelFx.rich ? null : const Color(0xFF0A0B16),
          gradient: KinrelFx.gradient(
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF11132A), // top — warm dark navy
                Color(0xFF0A0B16), // bottom — base dark
              ],
            ),
          ),
          border: Border(
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.06), width: 0.5),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                // ── Back button ────────────────────────────────────────
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: KinrelColors.textSilver,
                  ),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/family/${widget.familyId}');
                    }
                  },
                ),

                // ── Premium avatar with ambient glow ──────────────────
                // v134: Avatar gets a soft ember ambient glow behind it
                // so it feels like the visual anchor of the header.
                // Double-ring framing: outer hairline ember ring + inner
                // image. This is the Kinrel signature avatar treatment.
                //
                // Phase 22 / Header Nav Fix (revised): Tapping the avatar
                // opens the FAMILY Profile screen (/family/<id>/profile),
                // NOT an individual member's profile. The family chat
                // header represents the FAMILY (family name, family
                // avatar, family member count), so a header tap is a
                // family-level action. Individual member profiles are
                // opened from member-specific UI (message bubble avatars)
                // via MemberProfileSheet, not from the header.
                //
                // ── Phase 6 / RepaintBoundary ─────────────────────────
                // Wrap the avatar in a RepaintBoundary so the CachedNetwork
                // image decode + circle clip doesn't repaint on every
                // chatState change (which fires on every new message,
                // read-receipt flip, etc.). The avatar only changes when
                // the family's avatarUrl changes — a separate concern.
                RepaintBoundary(
                  child: GestureDetector(
                    onTap: () =>
                        context.push('/family/${widget.familyId}/profile'),
                    child: Container(
                      width: 48,
                      height: 48,
                      // PERF (Flat): BoxDecoration is no longer `const`
                      // because _kChatAvatarGlow is now a runtime-final
                      // list (KinrelFx.shadows() resolves at app start,
                      // but the list identity isn't a compile-time const).
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // v134: Soft ember ambient glow — felt behind the
                        // avatar, suggests warmth + human connection.
                        //
                        // PERF (Tier C3): hoisted to a top-level _kAvatarGlow
                        // const below this file so the BoxShadow list is
                        // allocated ONCE at app start (not per chat rebuild).
                        // The chat avatar mounts on every chat-thread frame
                        // so even one shadow allocation per build is wasteful.
                        boxShadow: _kChatAvatarGlow,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // v134: Hairline ember ring frames the avatar.
                          border: Border.all(
                            color: KinrelColors.ember.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                        ),
                        child: ClipOval(
                          child: avatarUrl != null && avatarUrl.isNotEmpty
                              ? (avatarUrl.startsWith('data:')
                                  ? Image.memory(
                                      base64Decode(avatarUrl.substring(
                                          avatarUrl.indexOf(',') + 1)),
                                      fit: BoxFit.cover,
                                      width: 46,
                                      height: 46,
                                      // Phase 4 — cap decode at the
                                      // 46×46 display size × DPR so a 4K
                                      // family-avatar URL doesn't
                                      // allocate a 4K bitmap in memory.
                                      cacheWidth:
                                          (46 * MediaQuery.devicePixelRatioOf(
                                                  context))
                                              .round(),
                                      cacheHeight:
                                          (46 * MediaQuery.devicePixelRatioOf(
                                                  context))
                                              .round(),
                                      errorBuilder: (_, __, ___) =>
                                          _buildLetterAvatar(),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: avatarUrl,
                                      cacheManager:
                                          KinrelImageCacheManager.instance,
                                      fit: BoxFit.cover,
                                      width: 46,
                                      height: 46,
                                      // Phase 4 — consolidated cache
                                      // manager + cap decode at the on-
                                      // screen 46×46 size × DPR. Without
                                      // these the family avatar would
                                      // decode at full source resolution
                                      // (often 512×512) and pollute the
                                      // shared ImageCache, evicting
                                      // message thumbnails.
                                      memCacheWidth:
                                          (46 * MediaQuery.devicePixelRatioOf(
                                                  context))
                                              .round(),
                                      memCacheHeight:
                                          (46 * MediaQuery.devicePixelRatioOf(
                                                  context))
                                              .round(),
                                      placeholder: (_, __) =>
                                          _buildLetterAvatar(),
                                      errorWidget: (_, __, ___) =>
                                          _buildLetterAvatar(),
                                    ))
                              : Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: KinrelGradients.igniteGradient,
                                  ),
                                  child: Center(child: _buildLetterAvatar()),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // ── Identity + relationship + status column ───────────
                // Visual hierarchy: name (primary) → relationship chip
                // (Kinrel signature) → presence status (supporting).
                //
                // Phase 22 / Header Nav Fix (revised): The outer
                // GestureDetector wraps the name + presence status
                // ("1 active") and routes to the FAMILY Profile screen
                // (/family/<id>/profile). The family chat header
                // represents the FAMILY, so a tap here is a family-level
                // action — NOT an individual member profile. Individual
                // member profiles are opened from message bubble avatars.
                //
                // The relationship chip ("Family · N") has its own
                // GestureDetector inside that ALSO routes to the Family
                // Profile (it's part of the header's family-info area).
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        context.push('/family/${widget.familyId}/profile'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Name ──────────────────────────────────────
                        // v139: Show group name if this is a group chat,
                        // otherwise the family name.
                        Text(
                          widget.groupName ?? widget.familyName,
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                            letterSpacing: 0.1,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // ── Relationship chip + presence row ──────────
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // v134: KINREL SIGNATURE RELATIONSHIP CHIP
                            // A small pill with a soft ember tint +
                            // hairline border. Communicates the type of
                            // connection. This is the unique Kinrel
                            // element that distinguishes the header
                            // from standard messaging apps.
                            //
                            // Phase 22 / Header Nav Fix: This chip is a
                            // SEPARATE tap target from the surrounding
                            // name+status column, but it ALSO routes to
                            // the Family Profile (it's part of the
                            // header's family-info area). The inner
                            // GestureDetector with HitTestBehavior.opaque
                            // captures the tap before the outer
                            // GestureDetector can fire. Tapping anywhere
                            // in the header's profile area — avatar,
                            // name, status, OR badge — all consistently
                            // open the Family Profile.
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => context.push(
                                  '/family/${widget.familyId}/profile'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: KinrelColors.ember
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: KinrelColors.ember
                                        .withValues(alpha: 0.30),
                                    width: 0.6,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Small family icon — heart for
                                    // family connection (warmth, care)
                                    const Icon(
                                      Icons.favorite_rounded,
                                      size: 9,
                                      color:
                                          KinrelColors.ember,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      memberCount > 2
                                          ? 'Family · $memberCount'
                                          : 'Family',
                                      style: TextStyle(
                                        fontFamily: KinrelTypography.bodyFont,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: KinrelColors.ember
                                            .withValues(alpha: 0.95),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // ── Feature 3: Chat streak flame badge ─────
                            // Shows a flame icon + current streak count
                            // when streak >= 2 (1-day streaks aren't worth
                            // showing — every chat has at least 1).
                            // Sourced from the Socket.IO engagement
                            // provider, which is updated instantly on
                            // chat:streakUpdated events.
                            Builder(builder: (context) {
                              final streak = ref
                                  .watch(chatEngagementProvider(widget.familyId))
                                  .streak;
                              if (streak < 2) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: KinrelColors.orange
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: KinrelColors.orange
                                          .withValues(alpha: 0.35),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        '🔥',
                                        style: TextStyle(
                                          fontSize: 9,
                                          height: 1.0,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$streak',
                                        style: const TextStyle(
                                          fontFamily: KinrelTypography.bodyFont,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: KinrelColors.orange,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            // ── Presence indicator ────────────────────
                            // v134: Refined status — small glowing dot
                            // (with subtle ambient glow, not flat) +
                            // letter-spaced count text. Feels integrated
                            // rather than a generic green dot.
                            //
                            // Feature 4: presence is now driven by the
                            // Socket.IO engagement provider (instant updates
                            // via 'presenceUpdate' events) in addition to
                            // the Supabase-Realtime-based chatState.onlineCount.
                            // The engagement provider updates within
                            // milliseconds of a user connecting/disconnecting;
                            // the Supabase Realtime update arrives 100-500ms
                            // later. We show "Active now" when 1+ member is
                            // online (matches WhatsApp/Telegram UX), or fall
                            // back to "Last seen" via the engagement provider's
                            // presence map when no one is online.
                            Builder(builder: (context) {
                              final eng = ref.watch(
                                  chatEngagementProvider(widget.familyId));
                              final onlineCount = eng.presence.values
                                  .where((p) => p.isOnline)
                                  .length;
                              final showOnline = onlineCount > 0 ||
                                  chatState.onlineCount > 0;
                              // For the "Last seen X ago" fallback, find the
                              // most recently seen offline user.
                              final lastSeenPresence = eng.presence.values
                                  .where((p) => !p.isOnline && p.lastSeenAt != null)
                                  .toList()
                                ..sort((a, b) => b.lastSeenAt!
                                    .compareTo(a.lastSeenAt!));
                              // Feature 7: locale-aware presence labels.
                              final l10n = S.of(context);
                              if (!showOnline &&
                                  lastSeenPresence.isNotEmpty &&
                                  lastSeenPresence.first.lastSeenAt!.year > 1970) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(width: 8),
                                    Text(
                                      lastSeenPresence.first.lastSeenLabelLocalized(l10n),
                                      style: TextStyle(
                                        fontFamily: KinrelTypography.bodyFont,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w500,
                                        color: KinrelColors.textSilver
                                            .withValues(alpha: 0.7),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                );
                              }
                              if (!showOnline) return const SizedBox.shrink();
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: KinrelColors.success,
                                      boxShadow: [
                                        BoxShadow(
                                          color: KinrelColors.success
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          offset: const Offset(0, 0),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    // Feature 7: localized "Active now" / "N active"
                                    (onlineCount == 1 || chatState.onlineCount == 1)
                                        ? (l10n?.chatActiveNow ?? 'Active now')
                                        : (l10n?.chatNActive(onlineCount > 0 ? onlineCount : chatState.onlineCount) ??
                                            '${onlineCount > 0 ? onlineCount : chatState.onlineCount} active'),
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: KinrelColors.textSilver
                                          .withValues(alpha: 0.85),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Action buttons — ONE shared implementation,
                // used by the family header AND the direct header.
                _buildHeaderActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// v113: Opens a bottom sheet listing all family members (from the
  /// chat presence/online members list). Tapping a member opens their
  /// MemberProfileSheet.
  ///
  /// This is reached from member-specific UI (e.g. a long-press on a
  /// message sender, or the message bubble avatar), NOT from the chat
  /// header. The chat header opens the Family Profile screen instead.

  /// Tier 2 / Chat Lock — check if this chat is locked on screen open
  /// + prompt biometrics if so. Called from initState.
  Future<void> _checkChatLock() async {
    final lockService = ref.read(chatLockServiceProvider);
    // Kin Thread / C2: direct chats lock under their own dm_-key (the
    // same key the old DM screen used) so locking a private chat never
    // locks the family chat.
    final isLocked = await lockService.isLocked(_chatSettingsKey);
    if (!mounted) return;

    if (isLocked) {
      setState(() {
        _isChatLocked = true;
        _isCheckingLock = false;
      });
      // Prompt biometrics automatically on screen open.
      _promptUnlock();
    } else {
      setState(() {
        _isChatLocked = false;
        _isCheckingLock = false;
      });
    }
  }

  /// Tier 2 / Chat Lock — prompt biometrics to unlock the chat.
  Future<void> _promptUnlock() async {
    final lockService = ref.read(chatLockServiceProvider);
    final success = await lockService.authenticate(
      'Authenticate to open this locked chat',
    );
    if (!mounted) return;
    if (success) {
      setState(() => _isChatLocked = false);
    }
    // If failed, the lock overlay stays. The user can tap "Try again"
    // on the overlay to re-prompt.
  }

  /// Tier 2 / Chat Lock — toggle the per-chat biometric lock.
  /// If biometrics aren't available (web, no fingerprint), shows a
  /// snackbar instead of silently failing. Otherwise:
  ///   - If the chat is currently unlocked, lock it (no auth needed
  ///     — locking doesn't require authentication, only unlocking does).
  /// Tier 3 / Export Chat — exports the conversation as a text file
  /// (timestamp + sender name + content per message) and shares it via
  /// the native share sheet. v1 is text-only (no media zip) — a
  /// future v2 could export media via a server-side job.
  Future<void> _exportChat() async {
    final chatState = ref.read(chatProvider(widget.familyId));
    final messages = chatState.messages;
    if (messages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No messages to export'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Build the export text. Sort oldest-first (reverse of state which
    // is newest-first). Format: [YYYY-MM-DD HH:MM] SenderName: content
    final sorted = messages.reversed.toList();
    final lines = <String>[];
    lines.add('Daxelo Kinrel — Chat Export');
    lines.add('Family: ${widget.familyName}');
    lines.add('Exported: ${DateTime.now().toLocal()}');
    lines.add('Messages: ${sorted.length}');
    lines.add('');
    lines.add('─' * 60);
    lines.add('');

    for (final msg in sorted) {
      if (msg.isDeletedForEveryone) continue;
      final dt = msg.timestamp.toLocal();
      final timeStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      String contentLabel;
      switch (msg.messageType) {
        case MessageType.photo:
          contentLabel = '[Photo]';
          break;
        case MessageType.voiceNote:
          contentLabel = '[Voice note ${msg.durationSeconds ?? 0}s]';
          break;
        case MessageType.sticker:
          contentLabel = '[Sticker]';
          break;
        case MessageType.familyEvent:
          contentLabel = '[${msg.eventTitle ?? 'Family event'}]';
          break;
        case MessageType.gameInvite:
          contentLabel = '[Game invite]';
          break;
        case MessageType.poll:
          contentLabel = '[Poll: ${msg.pollQuestion ?? msg.content}]';
          break;
        case MessageType.gif:
          contentLabel = '[GIF: ${msg.content}]';
          break;
        case MessageType.document:
          contentLabel = '[Document: ${msg.content}]';
          break;
        case MessageType.location:
          contentLabel = '[Location shared]';
          break;
        case MessageType.system:
          contentLabel = msg.content;
          break;
        case MessageType.text:
          contentLabel = msg.content;
      }
      lines.add('[$timeStr] ${msg.senderName}: $contentLabel');
      if (msg.forwardedFrom != null && msg.forwardedFrom!.isNotEmpty) {
        lines.add('  ↳ Forwarded from ${msg.forwardedFrom}');
      }
    }

    lines.add('');
    lines.add('─' * 60);
    lines.add('Export complete');

    final exportText = lines.join('\n');

    try {
      // Write to a temp file + share via share_plus
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'chat_export_${widget.familyId}_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(exportText);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Chat export: ${widget.familyName}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Tier 3 / Live Location — share your location with duration
  /// options (15min / 1h / 8h). Sends an initial location message,
  /// then updates it periodically until the duration expires.
  Timer? _liveLocationTimer;

  Future<void> _shareLiveLocation() async {
    // Show a bottom sheet with duration options
    final duration = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Share live location',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.access_time_rounded,
                  color: KinrelColors.ember),
              title: const Text('15 minutes',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () => Navigator.pop(ctx, 15),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded,
                  color: KinrelColors.ember),
              title: const Text('1 hour',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () => Navigator.pop(ctx, 60),
            ),
            ListTile(
              leading: const Icon(Icons.update_rounded,
                  color: KinrelColors.ember),
              title: const Text('8 hours',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () => Navigator.pop(ctx, 480),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (duration == null) return;

    try {
      // Get initial position + send the first location message
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      await ref.read(chatProvider(widget.familyId).notifier).sendLocation(
            lat: position.latitude,
            lng: position.longitude,
            label: 'Live location (sharing for ${_durationLabel(duration)})',
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Live location shared for ${_durationLabel(duration)}'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Start a timer that updates the location every 30s.
      // v1: we don't UPDATE the existing message — we send a new
      // location message every 30s (updating an existing message
      // would require a fn_update_location RPC). The 30s interval
      // is a balance between freshness + battery.
      _liveLocationTimer?.cancel();
      var remaining = duration;
      _liveLocationTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
        remaining -= 1;
        if (remaining <= 0) {
          t.cancel();
          _liveLocationTimer = null;
          return;
        }
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
            ),
          );
          if (mounted) {
            ref.read(chatProvider(widget.familyId).notifier).sendLocation(
                  lat: pos.latitude,
                  lng: pos.longitude,
                  label:
                      'Live location update (${remaining * 30}s remaining)',
                );
          }
        } catch (e) {
          debugPrint('⚠️ Live location update failed: $e');
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get location: $e'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _durationLabel(int minutes) {
    if (minutes < 60) return '${minutes}min';
    if (minutes < 480) return '${minutes ~/ 60}h';
    return '${minutes ~/ 480}h';
  }

  /// Tier 2 / Chat Lock — toggle the per-chat biometric lock.
  /// If biometrics aren't available (web, no fingerprint), shows a
  /// snackbar instead of silently failing. Otherwise:
  ///   - If the chat is currently unlocked, lock it (no auth needed
  ///     — locking doesn't require authentication, only unlocking does).
  ///   - If the chat is currently locked, prompt biometrics first
  ///     (to verify the user is the owner), then unlock.
  Future<void> _toggleChatLock() async {
    final lockService = ref.read(chatLockServiceProvider);
    final isAvailable = await lockService.isBiometricsAvailable;
    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication is not available on this device.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final isLocked = await lockService.isLocked(_chatSettingsKey);
    if (isLocked) {
      // Unlocking requires biometric auth.
      final success = await lockService.authenticate(
        'Authenticate to unlock this chat',
      );
      if (success) {
        await lockService.setLocked(_chatSettingsKey, false);
        if (mounted) {
          setState(() => _isChatLocked = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Chat unlocked'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication failed — chat stays locked'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      // Locking doesn't require auth.
      await lockService.setLocked(_chatSettingsKey, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat locked. You\'ll need biometrics to open it next time.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // v132: Opens the curated theme picker sheet. Each theme is a
  // multi-layer ambient gradient (base + accent glow + vignette)
  // that gives the chat space a curated atmosphere. Stored as
  // "theme:<id>" in chatWallpaperProvider.
  void _showThemePicker() {
    showChatThemePickerSheet(
      context,
      // Kin Thread / C2: direct chats pick their own atmosphere (the
      // dm_-keyed wallpaper slot).
      chatId: _chatSettingsKey,
      onPickCustomWallpaper: () =>
          _showImageWallpaperPicker(context, _chatSettingsKey),
      ref: ref,
    );
  }

  // v109.11: Wallpaper picker
  // v113: Widened the palette so swatches are clearly distinguishable
  // at a glance. The previous 8 options were all near-black with
  // <10% hue variance — impossible to tell apart on a phone screen.
  // The new palette keeps the default dark base but adds noticeably
  // different hues AND brightness levels (deep teal, warm cocoa,
  // indigo, burgundy, slate, forest, plum) so each swatch reads as a
  // distinct color. All remain dark-mode appropriate (none are bright
  // enough to hurt message-bubble contrast).
  void _showWallpaperColorPicker() {
    final colors = [
      {'name': 'Default', 'color': '#13141E'},
      {'name': 'Deep Teal', 'color': '#0B3D3D'},
      {'name': 'Cocoa', 'color': '#3D2B1F'},
      {'name': 'Indigo', 'color': '#1E1B4B'},
      {'name': 'Burgundy', 'color': '#3B0A1A'},
      {'name': 'Slate Blue', 'color': '#1E2A4A'},
      {'name': 'Forest', 'color': '#1B3320'},
      {'name': 'Plum', 'color': '#2D1B3D'},
      {'name': 'Charcoal', 'color': '#2A2A2A'},
      {'name': 'Midnight', 'color': '#0A0A1A'},
      {'name': 'Rosewood', 'color': '#4A1A2E'},
      {'name': 'Steel', 'color': '#1A2332'},
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
            const Text('Chat Wallpaper',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                )),
            const SizedBox(height: 4),
            const Text(
              'Pick a color — changes instantly',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
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
                // v113: Checkmark overlay on the active swatch so users
                // get visual confirmation of which wallpaper is applied.
                final isActive = _wallpaperColor != null &&
                    _wallpaperColor!.toARGB32() == 0xFF000000 + colorValue;
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    final service = ref.read(chatEnhancementServiceProvider);
                    await service.saveChatSettings(
                      familyId: widget.familyId,
                      wallpaperColor: c['color'],
                    );
                    if (mounted) {
                      // v112: Apply the new wallpaper immediately so the
                      // change is visible without leaving and re-entering
                      // the chat.
                      setState(() => _wallpaperColor = Color(colorValue));
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
                      border: Border.all(
                        color: isActive
                            ? KinrelColors.orange
                            : KinrelColors.border,
                        width: isActive ? 2.5 : 1,
                      ),
                    ),
                    child: isActive
                        ? const Center(
                            child: Icon(
                              Icons.check_rounded,
                              color: KinrelColors.orange,
                              size: 26,
                            ),
                          )
                        : null,
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
            // Option A: Choose from Gallery
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
            // Option B: Remove Wallpaper (only if one is set)
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
            // Option C: Set as Default Wallpaper
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
            const Text('Starred Messages',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                )),
            const SizedBox(height: 16),
            Expanded(
              child: starred.isEmpty
                  ? const Center(
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
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: KinrelColors.orange)),
                              const SizedBox(height: 4),
                              Text(msg.content,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: KinrelColors.textWhite)),
                              const SizedBox(height: 4),
                              Text(msg.formattedTime,
                                  style: const TextStyle(
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

  /// v122: Shows all pinned messages in a bottom sheet.
  /// Modelled on _showStarredMessages, filtering by isPinned.
  void _showPinnedMessages() {
    final chatState = ref.read(chatProvider(widget.familyId));
    final pinned = chatState.messages.where((m) => m.isPinned).toList();

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
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.push_pin, size: 18, color: KinrelColors.orange),
                SizedBox(width: 6),
                Text('Pinned Messages',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    )),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: pinned.isEmpty
                  ? const Center(
                      child: Text('No pinned messages',
                          style: TextStyle(color: KinrelColors.textDim)))
                  : ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: pinned.length,
                      itemBuilder: (ctx, index) {
                        final msg = pinned[index];
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
                              Row(
                                children: [
                                  const Icon(Icons.push_pin,
                                      size: 14, color: KinrelColors.orange),
                                  const SizedBox(width: 4),
                                  Text(msg.senderName,
                                      style: const TextStyle(
                                        fontFamily: KinrelTypography.bodyFont,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: KinrelColors.orange,
                                      )),
                                  const Spacer(),
                                  Text(msg.formattedTime,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: KinrelColors.textDim,
                                      )),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg.content.isNotEmpty
                                    ? msg.content
                                    : '[${msg.messageType.name}]',
                                style: const TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                  color: KinrelColors.textWhite,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
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
    // v3.3: the message list logic (date grouping, first/last-in-group,
    // SwipeToReply wrapping, RepaintBoundary per bubble, reversed
    // ListView with cacheExtent=1500) was MOVED to the shared
    // ChatMessageList widget so the DM screen can render the same list.
    // The group chat passes enableSwipeReply=true, showReactions=true,
    // and all callbacks wired — so the group chat behaves EXACTLY as
    // before.
    //
    // The typing indicator, scroll-to-bottom FAB, and unread logic are
    // NOT in ChatMessageList — they live ABOVE the list in this screen's
    // Column (they're tightly coupled to the engagement provider + this
    // screen's scroll controller state and would risk regressions if
    // moved).
    return ChatMessageList(
      messages: messages,
      currentUserId: _currentUserId,
      familyId: widget.familyId,
      // Kin Thread / C2: direct chats hide sender identity, avatars,
      // relationship pills and rails (the shared list/bubble code gates
      // on this flag).
      isDirectChat: widget.isDirectChat,
      inviteFamilyId: null,
      // Kin Thread / PR2 T3: the unread divider snapshot (captured by
      // the provider before marking read; null when the chat opened
      // fully read). Only rendered if the id is present in THIS chat's
      // filtered message list.
      unreadDividerMessageId: chatState.unreadDividerMessageId,
      unreadDividerCount: chatState.unreadDividerCount,
      scrollController: _scrollController,
      onReply: (msg) {
        ref.read(chatProvider(widget.familyId).notifier).setReplyTo(msg);
      },
      onReact: (msg) => _showReactionPicker(msg.id),
      onLongPress: (msg) => _showMessageActions(msg),
      onReplyPreviewTap: (msg) {
        if (msg.replyToId != null) _scrollToMessage(msg.replyToId!);
      },
      // v6.0 — Selection mode state (Image 3 reference).
      selectionMode: _selectionMode,
      selectedMessageIds: _selectedMessageIds,
      onToggleSelection: _toggleMessageSelection,
    );
  }

  // ── Scroll-to-bottom FAB ─────────────────────────────────────────

  Widget _buildScrollFab() {
    // v3.4: the FAB's rendering was MOVED to the shared ScrollToBottomFab
    // widget (see chat_meta.dart) so the DM renders the same FAB with the
    // same position/size/styling. Identical to the previous inline version.
    return ScrollToBottomFab(onTap: _scrollToBottom);
  }

  // ── Typing Indicator ─────────────────────────────────────────────

  Widget _buildTypingIndicator(ChatState chatState, ChatEngagementState engagement) {
    // Feature 7: use the locale-aware typing label (Hindi/Marathi/Tamil/etc.)
    // Falls back to English if localization is unavailable.
    final l10n = S.of(context);
    // Prefer the Socket.IO engagement layer's label (supports multiple typers
    // and is sub-second fresh). Fall back to the Supabase typing status
    // result (v3.5: ChatTypingStatus realtime now populates it).
    final label = engagement.isSomeoneTyping
        ? engagement.typingLabelLocalized(l10n)
        : (l10n?.chatTypingSingle(chatState.typingUserName ?? 'Someone') ??
            '${chatState.typingUserName ?? 'Someone'} is typing');
    final firstInitial = engagement.isSomeoneTyping
        ? (engagement.typingUserNames.values.isNotEmpty
            ? engagement.typingUserNames.values.first
            : 'Someone')
        : (chatState.typingUserName ?? 'Someone');
    // v3.5: the indicator's rendering was MOVED to the shared
    // TypingIndicator widget (see typing_indicator.dart) so the DM
    // screen renders the SAME indicator (avatar initial + label +
    // bouncing dots, same animation). Identical rendering to the
    // previous inline version — the group just supplies its label.
    return TypingIndicator(
      name: firstInitial,
      label: label,
    );
  }

  // ── Reply Preview Bar ────────────────────────────────────────────

  Widget _buildReplyPreview(ChatMessage replyTo) {
    // v3.4: the bar's rendering was MOVED to the shared ReplyPreviewBar
    // widget (see reply_preview_bar.dart) so the DM screen renders the
    // SAME bar with the same layout/spacing/typography/colors. The group
    // passes its provider's clearReplyTo as the close action — identical
    // behavior to the previous inline version.
    return ReplyPreviewBar(
      replyTo: replyTo,
      onClose: () {
        ref.read(chatProvider(widget.familyId).notifier).clearReplyTo();
      },
    );
  }

  // ── Input Bar ────────────────────────────────────────────────────

  Widget _buildInputBar() {
    // v133 PREMIUM COMPOSER
    // Design language: all controls live inside ONE unified capsule
    // (attachment + emoji + text field + voice/send) so the composer
    // reads as a single designed component rather than separate
    // buttons floating next to a text field. Mirrors iMessage +
    // Telegram's unified pill aesthetic.
    //
    // v3.3: the visual rendering was EXTRACTED into the shared
    // ChatInputBar widget (see chat_input_bar.dart) so the DM screen
    // can render the same composer. This screen owns all the state
    // (controllers, focus, composing flag, callbacks) and passes it
    // in. The group passes all flags true → identical behavior.
    //
    // The recording bar variant is handled here (before delegating to
    // ChatInputBar) because it's group-only — the DM backend doesn't
    // support voice messages.
    if (_isRecording) {
      return _buildRecordingBar();
    }

    return ChatInputBar(
      textController: _textController,
      focusNode: _focusNode,
      isComposing: _isComposing,
      onSend: _sendMessage,
      showAttach: true,
      showEmoji: true,
      showStickers: true,
      showPoll: true,
      showVoice: true,
      onAttach: () => _showAttachmentMenu(),
      onEmojiToggle: _toggleStickerPanel,
      emojiActive: _showStickerPanel,
      onStickerPacks: _openStickerPacks,
      onPoll: _openPollComposer,
      onStartRecording: _startRecording,
      isSendingVoice: _isSendingVoice,
      inputLayerLink: _inputLayerLink,
    );
  }

  // ── Phase 13: Voice recording bar ──────────────────────────────────

  Widget _buildRecordingBar() {
    // v133: Premium recording bar — matches the unified capsule
    // aesthetic of the input bar. Same gradient surface, same hairline
    // top border, same elevated inner capsule.
    final minutes = _recordingDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _recordingDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      decoration: BoxDecoration(
        // PERF (Flat): solid color + no shadow in flat mode.
        color: KinrelFx.rich ? null : const Color(0xFF0A0B16),
        gradient: KinrelFx.gradient(
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0E0F1C),
              Color(0xFF0A0B16),
            ],
          ),
        ),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
        boxShadow: KinrelFx.shadows([
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ]),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Container(
            // v133: Inner capsule matches the text-field capsule.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.25),
                width: 0.75,
              ),
            ),
            child: Row(
              children: [
                // Pulsing red recording dot.
                // PERF (Part C3): wrapped in a RepaintBoundary so the
                // recording dot's 900ms pulse animation (which repaints
                // ~every 16ms while recording) doesn't bleed into the
                // rest of the chat header / message list.
                const RepaintBoundary(child: RecordingDot()),
                const SizedBox(width: 12),
                // Timer
                Text(
                  '$minutes:$seconds',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Recording',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12.5,
                    color: KinrelColors.textDim,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                // Cancel button — matches the refined button style
                GestureDetector(
                  onTap: _cancelRecording,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: KinrelColors.textSilver,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button — premium gradient with glow
                GestureDetector(
                  onTap: _sendRecording,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KinrelGradients.igniteGradient, // EXEMPT — primary orange CTA
                      // PERF (Flat): no shadow in flat mode.
                      boxShadow: KinrelFx.shadows([
                        BoxShadow(
                          color: KinrelColors.orange.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            const SnackBar(
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
      });
    } catch (e) {
      debugPrint('⚠️ _cancelRecording failed: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingDuration = Duration.zero;
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
        });
      }
    } catch (e) {
      debugPrint('⚠️ _sendRecording failed: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isSendingVoice = false;
          _recordingDuration = Duration.zero;
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

  /// Tier 2 — Show the attachment menu (Photo / Document / Location / GIF).
  /// Replaces the previous direct-to-photo-picker behavior. The user
  /// now picks what kind of attachment they want, then the appropriate
  /// picker / sheet opens.
  Future<void> _showAttachmentMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Attach',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined,
                  color: KinrelColors.ember),
              title: const Text('Photo',
                  style: TextStyle(color: KinrelColors.textWhite)),
              subtitle: const Text('From gallery',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: KinrelColors.ember),
              title: const Text('Document',
                  style: TextStyle(color: KinrelColors.textWhite)),
              subtitle: const Text('PDF, DOC, XLS, etc.',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'document'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: KinrelColors.ember),
              title: const Text('Location',
                  style: TextStyle(color: KinrelColors.textWhite)),
              subtitle: const Text('Share your current location',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'location'),
            ),
            ListTile(
              leading: const Icon(Icons.gif_box_outlined,
                  color: KinrelColors.ember),
              title: const Text('GIF',
                  style: TextStyle(color: KinrelColors.textWhite)),
              subtitle: const Text('Search Giphy',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'gif'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    switch (choice) {
      case 'photo':
        await _pickAndSendAttachment();
        break;
      case 'document':
        await _pickAndSendDocument();
        break;
      case 'location':
        await _shareCurrentLocation();
        break;
      case 'gif':
        if (mounted) {
          await GifSearchSheet.show(
            context,
            onGifSelected: (gif) {
              ref.read(chatProvider(widget.familyId).notifier).sendGif(
                    gifUrl: gif.fullUrl,
                    title: gif.title.isNotEmpty ? gif.title : 'GIF',
                  );
            },
          );
        }
        break;
    }
  }

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
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.orange,
                  ),
                ),
                SizedBox(width: 12),
                Text('Sending attachment...'),
              ],
            ),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 10),
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
          const SnackBar(
            content: Text('Attachment sent'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
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

  /// Tier 2 / Document attachments — pick a file (any type) via
  /// file_selector, upload to chat-attachments storage bucket, and
  /// send as a MessageType.document message.
  Future<void> _pickAndSendDocument() async {
    try {
      // Use file_selector's openFile (works on web + native).
      final xfile = await openFile();
      if (xfile == null) return;
      final fileName = xfile.name.isNotEmpty
          ? xfile.name
          : 'document_${DateTime.now().millisecondsSinceEpoch}';
      final filePath = xfile.path;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: KinrelColors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Uploading "$fileName"...'),
              ],
            ),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 30),
          ),
        );
      }

      final client = ref.read(supabaseProvider);
      if (client == null) {
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
        return;
      }

      final storagePath = '${widget.familyId}/docs/$fileName';
      // Supabase's upload() expects a File on native, or a Uint8List
      // on web. Use File() (from dart:io) for native; on web, fall back
      // to uploadBinary with the file's bytes.
      if (kIsWeb) {
        final bytes = await xfile.readAsBytes();
        await client.storage
            .from('chat-attachments')
            .uploadBinary(storagePath, bytes);
      } else {
        await client.storage
            .from('chat-attachments')
            .upload(storagePath, File(filePath));
      }
      final publicUrl = client.storage
          .from('chat-attachments')
          .getPublicUrl(storagePath);

      await ref.read(chatProvider(widget.familyId).notifier).sendDocument(
            documentUrl: publicUrl,
            fileName: fileName,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document sent'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send document: $e'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Tier 2 / Live location sharing — get the current GPS location via
  /// geolocator and send as a MessageType.location message.
  Future<void> _shareCurrentLocation() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: KinrelColors.orange,
                  ),
                ),
                SizedBox(width: 12),
                Text('Getting your location...'),
              ],
            ),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 15),
          ),
        );
      }

      // geolocator is already in pubspec.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      await ref.read(chatProvider(widget.familyId).notifier).sendLocation(
            lat: position.latitude,
            lng: position.longitude,
            label: 'My location',
          );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location shared'),
            backgroundColor: KinrelColors.darkCard,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get location: $e'),
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
    // Tier 1 / Forward Picker — replaced the old single-target picker
    // with the new multi-select ForwardPickerSheet (family chats + DMs).
    // The sheet calls ChatNotifier.forwardMessageToTargets which hits
    // the fn_forward_message RPC. The RPC handles validation, the
    // forwardedFrom field, and resets poll votes / reactions on copies.
    ForwardPickerSheet.show(
      context,
      messageId: message.id,
      currentFamilyId: widget.familyId,
    );
  }

  // ── Edit Message Dialog (v109.10) ──────────────────────────────────

  void _showEditDialog(ChatMessage message) {
    final editController = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: const Text('Edit Message',
            style: TextStyle(color: KinrelColors.textWhite)),
        content: TextField(
          controller: editController,
          maxLines: null,
          autofocus: true,
          style: const TextStyle(color: KinrelColors.textWhite),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: KinrelColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: KinrelColors.orange),
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
            child: const Text('Save', style: TextStyle(color: KinrelColors.orange)),
          ),
        ],
      ),
    );
  }

  // ── Message Actions Bottom Sheet ─────────────────────────────────

  void _showMessageActions(ChatMessage message) {
    final isMe = _isMine(message);

    // v122: Check if current user is admin/creator (for Pin permission).
    final currentUserId = _currentUserId;
    final detailAsync = ref.read(familyDetailProvider(widget.familyId));
    final family = detailAsync.valueOrNull?.family;
    final isCreator = family?.createdBy != null &&
        family?.createdBy == currentUserId;
    final membershipsAsync =
        ref.read(familyMembershipsProvider(widget.familyId));
    final memberships = membershipsAsync.valueOrNull ?? [];
    final currentUserMembership = memberships
        .where((m) => m.userId == currentUserId)
        .firstOrNull;
    final isAdminOrCreator = isCreator ||
        currentUserMembership?.isAdmin == true;

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
              // Quick reactions row — v3.5: MOVED to the shared
              // MessageActionQuickReactions widget (reaction_picker.dart)
              // so the DM long-press sheet renders the SAME row. The
              // group passes its provider's toggleReaction — identical
              // behavior to the previous inline version.
              MessageActionQuickReactions(
                reactions: message.reactions,
                currentUserId: currentUserId,
                onToggle: (emoji) {
                  ref
                      .read(chatProvider(widget.familyId).notifier)
                      .toggleReaction(message.id, emoji);
                  Navigator.pop(context);
                },
                onMoreTap: () {
                  // Pop the message-actions sheet first, then
                  // open the full emoji picker as a new sheet.
                  Navigator.pop(context);
                  _showFullEmojiPicker(message.id);
                },
              ),
              const SizedBox(height: 8),
              const Divider(
                color: Color(0xFF3A3A4A),
                height: 1,
                thickness: 0.5,
              ),
              // Tier 3 / Peek Preview — opens a full-screen overlay
              // showing the message in a larger format (especially
              // useful for long text messages / photos that are
              // truncated in the bubble).
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
                  Navigator.pop(context);
                  _showMessagePreview(message);
                },
              ),
              // Reply action
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
                  Navigator.pop(context);
                  ref
                      .read(chatProvider(widget.familyId).notifier)
                      .setReplyTo(message);
                },
              ),
              // Select action — enters multi-select mode with this
              // message pre-selected (Image 3 reference).
              ListTile(
                leading: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: const Text(
                  'Select',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _enterSelectionMode(message.id);
                },
              ),
              // Copy action
              ListTile(
                leading: const Icon(
                  Icons.copy_rounded,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: const Text(
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
                leading: const Icon(
                  Icons.forward,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: const Text(
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
              // v125: Share (native share sheet)
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
                  Navigator.pop(context);
                  // Share text content or image URL via native share sheet.
                  if (message.messageType == MessageType.photo &&
                      message.mediaUrl != null &&
                      message.mediaUrl!.isNotEmpty) {
                    Share.share(
                      message.mediaUrl!,
                      subject: message.content.isNotEmpty
                          ? message.content
                          : 'Photo from ${message.senderName}',
                    );
                  } else if (message.content.isNotEmpty) {
                    Share.share(
                      message.content,
                      subject: 'Message from ${message.senderName}',
                    );
                  }
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
                  style: const TextStyle(
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
              // v122: Pin / Unpin — group rule is admin/creator (RPC
              // enforces too); Kin Thread / C2: EITHER person may pin in
              // a direct chat.
              if (isAdminOrCreator || widget.isDirectChat)
                ListTile(
                  leading: Icon(
                    message.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    color: message.isPinned
                        ? KinrelColors.orange
                        : KinrelColors.textSilver,
                    size: 22,
                  ),
                  title: Text(
                    message.isPinned ? 'Unpin' : 'Pin',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final service = ref.read(chatEnhancementServiceProvider);
                    await service.pinMessage(message.id, !message.isPinned);
                    ref.read(chatProvider(widget.familyId).notifier).refreshMessages();
                  },
                ),
              // Edit (only for own text messages)
              if (isMe && message.messageType == MessageType.text)
                ListTile(
                  leading: const Icon(
                    Icons.edit_outlined,
                    color: KinrelColors.textSilver,
                    size: 22,
                  ),
                  title: const Text(
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
                leading: const Icon(
                  Icons.delete_outline,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: const Text(
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
              // Tier 2 / Message Info — opens the MessageInfoSheet
              // showing "Delivered to" + "Read by" lists per family
              // member. Shown for everyone (not just the sender) so
              // any member can see who's read the message. Hidden for
              // non-text message types.
              // v6.0 — Now enabled in direct chats too (DM message
              // info shows delivery/read status for the 2 participants).
              if (message.messageType == MessageType.text ||
                  message.messageType == MessageType.photo)
                ListTile(
                  leading: const Icon(
                    Icons.info_outline_rounded,
                    color: KinrelColors.textSilver,
                    size: 22,
                  ),
                  title: const Text(
                    'Info',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    MessageInfoSheet.show(context, messageId: message.id);
                  },
                ),
              // Delete for Everyone (only for own messages)
              if (isMe)
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: KinrelColors.error,
                    size: 22,
                  ),
                  title: const Text(
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
                        title: const Text('Delete for Everyone?',
                            style: TextStyle(color: KinrelColors.textWhite)),
                        content: const Text(
                            'This message will be deleted for everyone in the chat.',
                            style: TextStyle(color: KinrelColors.textSilver)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete',
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

  /// Tier 3 / Peek Preview — opens a full-screen overlay showing the
  /// message in a larger format. Useful for long text messages that are
  /// truncated in the bubble, or for getting a closer look at photos.
  /// Dismissed by tapping outside the card.
  void _showMessagePreview(ChatMessage message) {
    // v3.4: the dialog's rendering was MOVED to the shared
    // showMessagePeekPreview function (see message_preview_dialog.dart)
    // so the DM long-press sheet can offer the SAME Preview action.
    // Identical rendering + dismissal behavior to the previous inline
    // version.
    showMessagePeekPreview(context, message);
  }

  /// v113: Opens a full emoji picker (emoji_picker_flutter) as a bottom
  /// sheet, themed to match the app's dark palette. When an emoji is
  /// selected, calls the SAME toggleReaction(messageId, emoji) used by
  /// the quick-react buttons, then pops the sheet. This gives users
  /// access to ALL emojis for reactions, not just the 6 quick-react
  /// defaults.
  void _showFullEmojiPicker(String messageId) {
    // v3.5: the sheet's rendering was MOVED to the shared
    // showFullEmojiSheet function (see reaction_picker.dart) so the DM
    // opens the SAME sheet. The group passes its provider's
    // toggleReaction as the emoji handler — identical behavior to the
    // previous inline version.
    showFullEmojiSheet(
      context,
      onEmojiSelected: (emoji) {
        ref
            .read(chatProvider(widget.familyId).notifier)
            .toggleReaction(messageId, emoji);
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Selection Mode (multi-select) — Image 3 reference
  // ═══════════════════════════════════════════════════════════════════════

  /// Enter selection mode with [initialMessageId] pre-selected.
  /// Called from the long-press handler when the user picks "Select"
  /// from the actions sheet, OR from a direct long-press on a bubble
  /// when an alternative gesture is used.
  void _enterSelectionMode(String initialMessageId) {
    HapticService.selection();
    setState(() {
      _selectionMode = true;
      _selectedMessageIds.clear();
      _selectedMessageIds.add(initialMessageId);
    });
  }

  /// Exit selection mode and clear the selection.
  void _exitSelectionMode() {
    if (!_selectionMode) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  /// Toggle a message's selection state. Called when the user taps a
  /// bubble while in selection mode.
  void _toggleMessageSelection(String messageId) {
    HapticService.tap();
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        // If the user deselects the last message, keep selection mode
        // active (per Image 3 which shows "1 selected" — but allow
        // empty state so the user can re-pick). Exit only via X.
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  /// Bulk reply — uses the most-recently selected message as the reply
  /// target, then exits selection mode and focuses the input.
  void _bulkReply() {
    if (_selectedMessageIds.isEmpty) return;
    // Find the most-recently-selected message in the messages list.
    final chatState = ref.read(chatProvider(widget.familyId));
    final selected = chatState.messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (selected.isEmpty) return;
    final target = selected.first;
    _exitSelectionMode();
    ref.read(chatProvider(widget.familyId).notifier).setReplyTo(target);
    // Focus the input so the user can type their reply.
    _focusNode.requestFocus();
  }

  /// Bulk forward — opens the forward picker with all selected messages.
  void _bulkForward() {
    if (_selectedMessageIds.isEmpty) return;
    final chatState = ref.read(chatProvider(widget.familyId));
    final selected = chatState.messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    _exitSelectionMode();
    // Reuse the existing forward picker (single-message variant) for
    // the first selected message — multi-message forwarding is a server
    // limitation. The user can forward one at a time.
    if (selected.isNotEmpty) {
      _showForwardFamilyPicker(selected.first);
    }
  }

  /// Bulk star — toggles star on all selected messages.
  void _bulkStar() async {
    if (_selectedMessageIds.isEmpty) return;
    final service = ref.read(chatEnhancementServiceProvider);
    final chatState = ref.read(chatProvider(widget.familyId));
    final selected = chatState.messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    for (final msg in selected) {
      await service.starMessage(msg.id, !msg.isStarred);
    }
    ref.read(chatProvider(widget.familyId).notifier).refreshMessages();
    _exitSelectionMode();
  }

  /// Bulk delete — deletes all selected messages for the current user.
  void _bulkDelete() async {
    if (_selectedMessageIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: Text(
          'Delete ${_selectedMessageIds.length} message${_selectedMessageIds.length == 1 ? '' : 's'}?',
          style: const TextStyle(color: KinrelColors.textWhite),
        ),
        content: const Text(
          'These messages will be deleted for you. Other participants will still see them.',
          style: TextStyle(color: KinrelColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete for me',
                style: TextStyle(color: KinrelColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = ref.read(chatEnhancementServiceProvider);
    final ids = Set<String>.from(_selectedMessageIds);
    _exitSelectionMode();
    for (final id in ids) {
      await service.deleteForMe(id);
    }
    ref.read(chatProvider(widget.familyId).notifier).refreshMessages();
  }

  /// Bulk more actions — shows a bottom sheet with Pin, Copy, Share.
  void _bulkMore() {
    if (_selectedMessageIds.isEmpty) return;
    final chatState = ref.read(chatProvider(widget.familyId));
    final selected = chatState.messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.content_copy, color: KinrelColors.orange),
              title: const Text('Copy text',
                  style: TextStyle(color: KinrelColors.textWhite)),
              subtitle: const Text('Concatenate text from all selected messages',
                  style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
              onTap: () {
                final text = selected
                    .where((m) => m.messageType == MessageType.text)
                    .map((m) => m.content)
                    .join('\n\n');
                if (text.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: text));
                }
                Navigator.pop(ctx);
                _exitSelectionMode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined, color: KinrelColors.orange),
              title: const Text('Pin messages',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () async {
                Navigator.pop(ctx);
                final service = ref.read(chatEnhancementServiceProvider);
                for (final msg in selected) {
                  await service.pinMessage(msg.id, !msg.isPinned);
                }
                ref.read(chatProvider(widget.familyId).notifier).refreshMessages();
                _exitSelectionMode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: KinrelColors.orange),
              title: const Text('Share outside Kinrel',
                  style: TextStyle(color: KinrelColors.textWhite)),
              onTap: () {
                Navigator.pop(ctx);
                final text = selected.map((m) => m.content).join('\n\n');
                Share.share(text);
                _exitSelectionMode();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // v3.3: date grouping + date separator rendering was MOVED to the
  // shared ChatMessageList widget (see chat_message_list.dart). The
  // group chat now delegates to ChatMessageList via _buildMessagesList
  // above.
}

// ═══════════════════════════════════════════════════════════════════════
// Message Bubble Widget
// ═══════════════════════════════════════════════════════════════════════

