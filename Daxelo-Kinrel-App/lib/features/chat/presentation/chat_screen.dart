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
import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cross_file/cross_file.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_edge_style.dart';
import '../../family/data/relationship_label_provider.dart';
import '../../../core/utils/web_keyboard_height.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/chat_enhancement_service.dart';
import '../providers/chat_provider.dart';
import 'voice_message_player.dart';
import 'sticker_panel.dart';
import '../../family/presentation/family_space_floating_nav.dart';
import '../../profile/presentation/member_profile_sheet.dart';
import '../data/chat_wallpaper_provider.dart';
import '../data/wallpaper_picker.dart';
import 'widgets/chat_background.dart';
import 'widgets/chat_background_theme.dart';
import 'widgets/chat_theme_picker_sheet.dart';
import 'widgets/full_screen_image_viewer.dart';

// ═══════════════════════════════════════════════════════════════════════
// Chat Screen
// ═══════════════════════════════════════════════════════════════════════

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.familyId,
    required this.familyName,
    this.showFamilyNav = true,
    this.groupId,
    this.groupName,
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
      // v112: Load saved wallpaper color so it's applied on first render.
      _loadWallpaperColor();
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
          .sendMessage(text, replyToId: replyToId, groupId: widget.groupId);
    });

    _textController.clear();
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
        // v113: "+" button → remove the overlay and open the full
        // emoji picker bottom sheet for access to ALL emojis.
        onMoreTap: () {
          entry.remove();
          _showFullEmojiPicker(messageId);
        },
      ),
    );

    overlay.insert(entry);
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.familyId));
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
      // v132: The background is now rendered by ChatBackground (a
      // multi-layer ambient gradient + optional blurred wallpaper).
      // The Scaffold background is a flat dark color that only shows
      // behind the AppBar/input bar — the messages area is fully
      // covered by ChatBackground.
      backgroundColor: const Color(0xFF0A0B16),
      // v126: Explicitly enable keyboard resizing so the input bar
      // moves above the keyboard (WhatsApp-style).
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(chatState),
      // v115: Only show the Family Space bottom nav when this screen
      // is the tab destination (showFamilyNav=true). When opened as a
      // pushed conversation from the chat list, the bottom nav is
      // hidden so the chat is full-screen (WhatsApp/Telegram style).
      bottomNavigationBar: widget.showFamilyNav
          ? FamilySpaceFloatingNav(familyId: widget.familyId)
          : null,
      body: Column(
        children: [
          // v132: Messages list wrapped with ChatBackground — a
          // multi-layer ambient gradient (base + accent glow +
          // vignette) plus optional blurred custom wallpaper.
          // Gives the chat space depth without competing with bubbles.
          Expanded(
            child: ChatBackground(
              chatId: widget.familyId,
              child: bodyContent,
            ),
          ),
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
          // v128: On Flutter Web, resizeToAvoidBottomInset doesn't detect
          // the mobile keyboard. We add explicit bottom padding equal to
          // the visualViewport-measured keyboard height so the input bar
          // is always visible above the keyboard.
          if (kIsWeb && _webKeyboardHeight > 0)
            SizedBox(height: _webKeyboardHeight),
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

  /// v124: Builds the default letter avatar (fallback when no image).
  Widget _buildLetterAvatar() {
    return Text(
      (widget.familyName.isNotEmpty
              ? widget.familyName.substring(0, 1)
              : 'F')
          .toUpperCase(),
      style: TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ChatState chatState) {
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
    final familyDetail = ref.watch(familyDetailProvider(widget.familyId)).valueOrNull;
    final memberCount = familyDetail?.family.memberCount ?? chatState.members.length;

    return PreferredSize(
      preferredSize: const Size.fromHeight(72),
      child: Container(
        decoration: BoxDecoration(
          // v134: Vertical gradient matches ChatBackground + composer
          // for full-screen cohesion. Top is slightly lighter (lit
          // from above), bottom darker.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF11132A), // top — warm dark navy
              Color(0xFF0A0B16), // bottom — base dark
            ],
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
                  icon: Icon(
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
                // v135: Tapping navigates to the Family Hub (intermediate
                // screen), NOT the Family Space directly.
                GestureDetector(
                  onTap: () => context.push('/family/${widget.familyId}/hub'),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // v134: Soft ember ambient glow — felt behind the
                      // avatar, suggests warmth + human connection.
                      boxShadow: [
                        BoxShadow(
                          color: KinrelColors.ember.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 0),
                        ),
                      ],
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
                                    errorBuilder: (_, __, ___) =>
                                        _buildLetterAvatar(),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                    width: 46,
                                    height: 46,
                                    placeholder: (_, __) =>
                                        _buildLetterAvatar(),
                                    errorWidget: (_, __, ___) =>
                                        _buildLetterAvatar(),
                                  ))
                            : Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: KinrelGradients.igniteGradient,
                                ),
                                child: Center(child: _buildLetterAvatar()),
                              ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // ── Identity + relationship + status column ───────────
                // Visual hierarchy: name (primary) → relationship chip
                // (Kinrel signature) → presence status (supporting).
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/family/${widget.familyId}/hub'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Name ──────────────────────────────────────
                        // v139: Show group name if this is a group chat,
                        // otherwise the family name.
                        Text(
                          widget.groupName ?? widget.familyName,
                          style: TextStyle(
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
                            Container(
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
                                  Icon(
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
                            // ── Presence indicator ────────────────────
                            // v134: Refined status — small glowing dot
                            // (with subtle ambient glow, not flat) +
                            // letter-spaced count text. Feels integrated
                            // rather than a generic green dot.
                            if (chatState.onlineCount > 0) ...[
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
                                '${chatState.onlineCount} active',
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
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Action buttons (visually balanced, secondary) ────
                // v134: Actions use a softer icon style (outline, 20px,
                // silver) so they never compete with the identity column.
                // The members button is dropped — redundant with tapping
                // the avatar/header which navigates to family detail.
                // Video + voice + more remain, but more compact.
                _HeaderActionButton(
                  icon: Icons.videocam_outlined,
                  size: 20,
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
                _HeaderActionButton(
                  icon: Icons.call_outlined,
                  size: 18,
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
                // More menu — settings, wallpaper, mute, etc.
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: KinrelColors.textSilver, size: 20),
                  color: KinrelColors.darkCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'theme':
                        _showThemePicker();
                        break;
                      case 'wallpaper':
                        _showImageWallpaperPicker(context, widget.familyId);
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
                    const PopupMenuItem(
                        value: 'theme', child: Text('Chat Atmosphere')),
                    const PopupMenuItem(
                        value: 'wallpaper', child: Text('Custom Wallpaper')),
                    const PopupMenuItem(
                        value: 'wallpaper_color', child: Text('Solid Color')),
                    const PopupMenuItem(
                        value: 'mute', child: Text('Mute notifications')),
                    const PopupMenuItem(
                        value: 'starred', child: Text('Starred messages')),
                    const PopupMenuItem(
                        value: 'pinned', child: Text('Pinned messages')),
                  ],
                ),
                const SizedBox(width: 4),
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
  void _showMembersList() {
    final chatState = ref.read(chatProvider(widget.familyId));
    final members = chatState.members;

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      isScrollControlled: true,
      useSafeArea: true,
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
                  'Family Members',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No members online',
                  style: TextStyle(color: KinrelColors.textDim),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (ctx, index) {
                    final m = members[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            KinrelColors.orange.withValues(alpha: 0.15),
                        child: Text(
                          m.initials,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                      title: Text(
                        m.name,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      trailing: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: m.isOnline
                              ? KinrelColors.success
                              : KinrelColors.textDim,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        MemberProfileSheet.show(context, m.id);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // v132: Opens the curated theme picker sheet. Each theme is a
  // multi-layer ambient gradient (base + accent glow + vignette)
  // that gives the chat space a curated atmosphere. Stored as
  // "theme:<id>" in chatWallpaperProvider.
  void _showThemePicker() {
    showChatThemePickerSheet(
      context,
      chatId: widget.familyId,
      onPickCustomWallpaper: () =>
          _showImageWallpaperPicker(context, widget.familyId),
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
            Text('Chat Wallpaper',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                )),
            const SizedBox(height: 4),
            Text(
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
                    _wallpaperColor!.value == 0xFF000000 + colorValue;
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
                        ? Center(
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
            // Option A: Choose from Gallery
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
            // Option B: Remove Wallpaper (only if one is set)
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
            // Option C: Set as Default Wallpaper
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.push_pin, size: 18, color: KinrelColors.orange),
                const SizedBox(width: 6),
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
                  ? Center(
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
                                  Icon(Icons.push_pin,
                                      size: 14, color: KinrelColors.orange),
                                  const SizedBox(width: 4),
                                  Text(msg.senderName,
                                      style: TextStyle(
                                        fontFamily: KinrelTypography.bodyFont,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: KinrelColors.orange,
                                      )),
                                  const Spacer(),
                                  Text(msg.formattedTime,
                                      style: TextStyle(
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
                                style: TextStyle(
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
    // Group messages by date for separators
    final grouped = _groupByDate(messages);

    // v130: Bottom padding reserves space for the scroll-to-bottom FAB
    // (40px tall, 8px from bottom = 48px footprint) plus a 16px buffer
    // so the most recent message — including full-size 64px sticker
    // emoji messages — is never obscured by the floating button when
    // the user scrolls slightly up from the bottom and the FAB is
    // visible. In a reversed ListView, padding.bottom is applied at
    // the visual bottom of the viewport (where index 0 / newest
    // message renders).
    const fabClearance = 64.0; // FAB(40) + margin(8) + buffer(16)

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, fabClearance),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final group = grouped[index];
        return Column(
          children: [
            // v127: Date separator pill
            _buildDateSeparator(group.dateLabel),
            const SizedBox(height: 8),
            // Messages for this date — v127: with sender grouping
            ...group.messages.asMap().entries.map((entry) {
              final i = entry.key;
              final msg = entry.value;
              final isMe = _isMine(msg);

              // v127: Compute isFirstInGroup + isLastInGroup.
              // First in group if: first message OR previous message
              // is from a different sender OR >60s gap.
              final isFirstInGroup = i == 0 ||
                  group.messages[i - 1].senderId != msg.senderId ||
                  msg.timestamp.difference(group.messages[i - 1].timestamp).inSeconds.abs() > 60;

              // Last in group if: last message OR next message
              // is from a different sender OR >60s gap.
              final isLastInGroup = i == group.messages.length - 1 ||
                  group.messages[i + 1].senderId != msg.senderId ||
                  group.messages[i + 1].timestamp.difference(msg.timestamp).inSeconds.abs() > 60;

              // v127: Tighter spacing within groups (2px) vs between
              // groups (8px).
              final bottomPadding = isLastInGroup ? 8.0 : 2.0;

              return Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: _MessageBubble(
                  message: msg,
                  isMe: isMe,
                  familyId: widget.familyId,
                  isFirstInGroup: isFirstInGroup,
                  isLastInGroup: isLastInGroup,
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
    // v132: Premium day divider — softer glass appearance with a
    // refined shape. Uses a frosted-glass effect (semi-transparent
    // dark + hairline white border) so it feels integrated with the
    // ambient background rather than floating as a hard pill.
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          // v132: Frosted glass — dark with low alpha so the ambient
          // gradient shows through subtly.
          color: const Color(0xFF13141E).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textSilver.withValues(alpha: 0.9),
            letterSpacing: 0.8,
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
    // v133 PREMIUM COMPOSER
    // Design language: all controls live inside ONE unified capsule
    // (attachment + emoji + text field + voice/send) so the composer
    // reads as a single designed component rather than separate
    // buttons floating next to a text field. Mirrors iMessage +
    // Telegram's unified pill aesthetic.
    //
    // Depth: outer bar uses a soft gradient (top lighter → bottom
    // darker) + hairline white top border + subtle top shadow so the
    // composer feels elevated from the chat content below. Inner
    // capsule uses a slightly elevated surface with hairline border.
    //
    // Transformation: the trailing button smoothly morphs mic → send
    // via AnimatedSwitcher (scale + fade, 220ms) when the user types.
    if (_isRecording) {
      return _buildRecordingBar();
    }

    return Container(
      // v133: Soft gradient surface — top is slightly lighter (lit
      // from above by the AppBar glow), bottom is the base dark.
      // Matches the v132 ChatBackground palette for cohesion.
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0E0F1C),
            Color(0xFF0A0B16),
          ],
        ),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
        boxShadow: [
          // v133: Subtle top shadow lifts the composer off the chat
          // content. 18% alpha, 8 blur — felt, not seen.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Attachment button ────────────────────────────────
              _AttachmentButton(onTap: () => _pickAndSendAttachment()),
              const SizedBox(width: 6),
              // ── Sticker / emoji toggle ──────────────────────────
              _StickerButton(
                isActive: _showStickerPanel,
                onTap: _toggleStickerPanel,
              ),
              const SizedBox(width: 8),
              // ── Unified text capsule ────────────────────────────
              // Contains the TextField + the trailing mic/send button
              // so they feel like one continuous pill. The TextField
              // has no border/fill of its own — the capsule provides
              // the visual container.
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    // v133: Elevated capsule surface — slightly
                    // lighter than the outer bar so the capsule
                    // reads as a distinct interactive element.
                    color: const Color(0xFF1A1D2E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? KinrelColors.ember.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                      width: _focusNode.hasFocus ? 1.2 : 0.75,
                    ),
                    boxShadow: _focusNode.hasFocus
                        ? [
                            // v133: Focus glow — soft ember ambient
                            // light when the field is active.
                            BoxShadow(
                              color: KinrelColors.ember
                                  .withValues(alpha: 0.10),
                              blurRadius: 12,
                              offset: const Offset(0, 0),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Text field — no decoration of its own
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 15,
                            color: KinrelColors.textWhite,
                            height: 1.45,
                          ),
                          decoration: InputDecoration(
                            // v133: Refined placeholder — shorter,
                            // softer, more professional.
                            hintText: 'Message',
                            hintStyle: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 15,
                              color: KinrelColors.textDim
                                  .withValues(alpha: 0.7),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.only(
                              left: 18,
                              right: 12,
                              top: 13,
                              bottom: 13,
                            ),
                          ),
                        ),
                      ),
                      // ── Trailing mic/send button ───────────────────
                      // Lives INSIDE the capsule so it feels
                      // connected to the text field. AnimatedSwitcher
                      // smoothly morphs mic → send → spinner.
                      Padding(
                        padding: const EdgeInsets.only(
                            right: 5, bottom: 5),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                            scale: Tween<double>(begin: 0.6, end: 1.0)
                                .animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutBack,
                            )),
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          ),
                          child: _isSendingVoice
                              ? const SizedBox(
                                  key: ValueKey('spinner'),
                                  width: 38,
                                  height: 38,
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: KinrelColors.orange,
                                      ),
                                    ),
                                  ),
                                )
                              : _isComposing
                                  ? _SendButton(
                                      key: const ValueKey('send'),
                                      isActive: true,
                                      onTap: _sendMessage,
                                    )
                                  : _MicButton(
                                      key: const ValueKey('mic'),
                                      onTap: _startRecording,
                                    ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0E0F1C),
            Color(0xFF0A0B16),
          ],
        ),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
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
                // Pulsing red recording dot
                const _RecordingDot(),
                const SizedBox(width: 12),
                // Timer
                Text(
                  '$minutes:$seconds',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
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
                    child: Icon(
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
                      gradient: KinrelGradients.igniteGradient,
                      boxShadow: [
                        BoxShadow(
                          color: KinrelColors.orange.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
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
              // Quick reactions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ..._reactionEmojis.map((emoji) {
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
                    }),
                    // v113: "+" button — opens the full emoji picker so
                    // users can react with ANY emoji, not just the 6
                    // quick-react defaults. Styled identically to the
                    // emoji buttons (44x44, circular) for consistency.
                    GestureDetector(
                      onTap: () {
                        // Pop the message-actions sheet first, then
                        // open the full emoji picker as a new sheet.
                        Navigator.pop(context);
                        _showFullEmojiPicker(message.id);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkElevated,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.add,
                            color: KinrelColors.textSilver,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
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
              // v125: Share (native share sheet)
              ListTile(
                leading: Icon(
                  Icons.share_outlined,
                  color: KinrelColors.textSilver,
                  size: 22,
                ),
                title: Text(
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
              // v122: Pin / Unpin (admin/creator only — RPC enforces too)
              if (isAdminOrCreator)
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
                    style: TextStyle(
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

  /// v113: Opens a full emoji picker (emoji_picker_flutter) as a bottom
  /// sheet, themed to match the app's dark palette. When an emoji is
  /// selected, calls the SAME toggleReaction(messageId, emoji) used by
  /// the quick-react buttons, then pops the sheet. This gives users
  /// access to ALL emojis for reactions, not just the 6 quick-react
  /// defaults.
  void _showFullEmojiPicker(String messageId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'React with an emoji',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  ref
                      .read(chatProvider(widget.familyId).notifier)
                      .toggleReaction(messageId, emoji.emoji);
                  Navigator.pop(context);
                },
                config: Config(
                  height: MediaQuery.of(context).size.height * 0.45,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: KinrelColors.darkCard,
                    emojiSizeMax: 28,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: KinrelColors.darkCard,
                    iconColor: KinrelColors.textSilver,
                    iconColorSelected: KinrelColors.orange,
                    indicatorColor: KinrelColors.orange,
                    backspaceColor: KinrelColors.textSilver,
                  ),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: KinrelColors.darkCard,
                    buttonIconColor: KinrelColors.textSilver,
                    hintText: 'Search emoji',
                    hintTextStyle: TextStyle(
                      color: KinrelColors.textDim,
                      fontSize: 14,
                    ),
                    inputTextStyle: TextStyle(
                      color: KinrelColors.textWhite,
                      fontSize: 14,
                    ),
                  ),
                  skinToneConfig: const SkinToneConfig(
                    dialogBackgroundColor: Color(0xFF202338),
                    indicatorColor: KinrelColors.orange,
                  ),
                ),
              ),
            ),
          ],
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

    // v112: Within each date group, sort messages ascending (oldest
    // first, newest last) so they render top-to-bottom correctly inside
    // that day's Column. The day-GROUPS themselves remain in descending
    // order (newest day first) for correct placement in the reversed
    // ListView — only the intra-day order is fixed here.
    //
    // ROOT CAUSE: chat_provider sorts the master list newest-first
    // (descending). _groupByDate iterated that list and appended to
    // each group in the same descending order, so within a single day
    // the newest message ended up at group.messages[0] and rendered at
    // the TOP of that day's block — backwards. This sort fixes that
    // without affecting the between-day ordering.
    for (final g in groups) {
      g.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
    required this.familyId,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.animateIn = false,
  });

  final ChatMessage message;
  final bool isMe;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onLongPress;

  /// v139: Family ID used to resolve the sender's relationship label
  /// to the current viewer via the K-Graph. Only family/group chats
  /// pass this — 1-on-1 DMs pass null and skip the relationship label.
  final String? familyId;

  /// v127: Whether this is the first message in a consecutive group
  /// from the same sender. Controls avatar + sender name visibility.
  final bool isFirstInGroup;

  /// v127: Whether this is the last message in a consecutive group.
  /// Controls bubble tail (asymmetric radius) + inline timestamp.
  final bool isLastInGroup;

  /// v127: Whether to play the send-in animation (scale + fade).
  final bool animateIn;

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

    // v140: Kinship-category generation bands. Resolve the sender's
    // relationship key to the current viewer, classify it into a
    // KinshipEdgeCategory, and map to a generation-band color. The
    // color is applied as a 3px left border + 6% background fill on
    // the message bubble. Only for family/group chats, not DMs, and
    // only for received messages (not isMe). Self/indirect → no band.
    Color? kinshipBandColor;
    if (familyId != null && !isMe && !isSticker) {
      final rawKey = ref.watch(relationshipKeyProvider(
        (familyId: familyId!, senderUserId: message.senderId),
      ));
      if (rawKey != null) {
        final category = KinshipEdgeClassifier.classify(rawKey);
        kinshipBandColor = _kinshipCategoryColor(category);
      }
    }

    // v122: Swipe-to-reply — user can swipe right on any message to
    // quote-reply to it. Uses a horizontal drag gesture with a
    // threshold. When the swipe exceeds the threshold, onReply is
    // called (which calls setReplyTo in the provider). A visual
    // reply icon appears during the drag for feedback.
    double _dragX = 0;
    bool _replyTriggered = false;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return GestureDetector(
          onLongPress: onLongPress,
          onHorizontalDragUpdate: (details) {
            if (details.delta.dx > 0 && !_replyTriggered) {
              _dragX += details.delta.dx;
              if (_dragX > 40) {
                _replyTriggered = true;
                onReply();
                HapticFeedback.selectionClick();
              }
            }
          },
          onHorizontalDragEnd: (_) {
            _dragX = 0;
            _replyTriggered = false;
          },
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // v122: Reply icon shown during swipe (left side).
                if (_dragX > 5 && !isSticker)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.reply_rounded,
                      size: 20,
                      color: KinrelColors.orange
                          .withValues(alpha: (_dragX / 40).clamp(0.0, 1.0)),
                    ),
                  ),
                // v127: Avatar only on first message in group.
                // Non-first messages get an invisible spacer for alignment.
                if (!isMe && !isSticker && isFirstInGroup)
                  GestureDetector(
                    onTap: () => MemberProfileSheet.show(
                      context,
                      message.senderId,
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 8, bottom: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KinrelColors.orange.withValues(alpha: 0.15),
                      ),
                      child: Center(
                        child: Text(
                          (message.senderName.isNotEmpty
                              ? message.senderName[0].toUpperCase()
                              : '?'),
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!isMe && !isSticker && !isFirstInGroup)
                  const SizedBox(width: 40), // invisible spacer for alignment
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                margin: EdgeInsets.only(
                    left: isMe ? 48 : 0, right: isMe ? 0 : 48),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Reply preview (if replying to a message)
                    if (message.replyToId != null) _buildReplyPreview(),
                    // v131 PREMIUM: Redesigned bubble system.
                    // Design language: soft gradient fills for depth,
                    // organic asymmetric corners (22px base / 6px tail)
                    // for a crafted silhouette instead of a mechanical
                    // rounded rectangle, layered shadows for gentle
                    // elevation, and generous padding for readability.
                    // Inspired by iMessage's softness + Telegram's tail.
                    Container(
                      padding: isSticker
                          ? const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8)
                          : const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                      decoration: BoxDecoration(
                        // v131: Subtle vertical gradient — top slightly
                        // lighter (lit-from-above), bottom darker. Stays
                        // within the tinted-glass palette so the ember
                        // accent remains understated, not saturated.
                        gradient: isSticker
                            ? null
                            : (isMe
                                ? LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      KinrelColors.ember.withValues(alpha: 0.18),
                                      KinrelColors.ember.withValues(alpha: 0.08),
                                    ],
                                  )
                                : kinshipBandColor != null
                                    // v140: Blend 6% kinship band color
                                    // into the received-message gradient
                                    // so the generation band is felt as
                                    // a subtle background tint, not just
                                    // the left border.
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color.lerp(
                                            const Color(0xFF2E3150),
                                            kinshipBandColor,
                                            0.06)!,
                                          Color.lerp(
                                            const Color(0xFF23263B),
                                            kinshipBandColor,
                                            0.06)!,
                                        ],
                                      )
                                    : const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0xFF2E3150),
                                          Color(0xFF23263B),
                                        ],
                                      )),
                        color: isSticker ? Colors.transparent : null,
                        // v131: Organic corners — 22px base, tail corner
                        // drops to 6px on isLastInGroup. Less mechanical
                        // than equal radii; mirrors Telegram's silhouette.
                        // Stickers get a soft 18px pill so they feel
                        // integrated rather than floating.
                        borderRadius: isSticker
                            ? BorderRadius.circular(18)
                            : BorderRadius.only(
                                topLeft: const Radius.circular(22),
                                topRight: const Radius.circular(22),
                                bottomLeft: Radius.circular(
                                    isMe ? 22 : (isLastInGroup ? 6 : 22)),
                                bottomRight: Radius.circular(
                                    isMe ? (isLastInGroup ? 6 : 22) : 22),
                              ),
                        // v131: Hairline border for definition. Sent:
                        // ember at 28% (softer than v129's 35%). Received:
                        // white at 6% (subtle edge to lift off wallpaper).
                        // v140: When a kinship band color is resolved,
                        // replace the uniform border with an asymmetric
                        // Border that has a 3px left side in the kinship
                        // color + hairline on the other 3 sides.
                        border: isSticker
                            ? null
                            : (isMe
                                ? Border.all(
                                    color: KinrelColors.ember
                                        .withValues(alpha: 0.28),
                                    width: 0.75,
                                  )
                                : kinshipBandColor != null
                                    ? Border(
                                        left: BorderSide(
                                            color: kinshipBandColor,
                                            width: 3),
                                        top: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            width: 0.75),
                                        right: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            width: 0.75),
                                        bottom: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.06),
                                            width: 0.75),
                                      )
                                    : Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.06),
                                        width: 0.75,
                                      )),
                        // v131: Layered elevation shadows for soft depth.
                        // Received: deeper shadow anchors it to the wall.
                        // Sent: gentler shadow lifts it + a faint ember
                        // ambient glow for warmth. Stickers: none.
                        boxShadow: isSticker
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: isMe ? 0.18 : 0.30),
                                  blurRadius: isMe ? 8 : 12,
                                  offset: Offset(0, isMe ? 2 : 4),
                                ),
                                if (isMe)
                                  BoxShadow(
                                    color: KinrelColors.ember
                                        .withValues(alpha: 0.10),
                                    blurRadius: 14,
                                    offset: const Offset(0, 0),
                                  ),
                              ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          // v127: Sender name only on first message in group
                          if (!isMe && !isSticker && isFirstInGroup)
                            _buildSenderName(ref),
                          // Message content
                          _buildMessageContent(),
                          // v127: Inline timestamp only on last-in-group
                          if (!isSticker && isLastInGroup) _buildTimeRow(),
                          if (isSticker) _buildStickerTimeRow(),
                        ],
                      ),
                    ),
                    // v127: Reaction chips positioned overlapping bubble bottom
                    if (message.reactions.isNotEmpty)
                      _buildReactionChips(currentUserId),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ); // close GestureDetector
      }, // close StatefulBuilder builder
    ); // close StatefulBuilder
  }

  Widget _buildReplyPreview() {
    // v131: Premium reply preview — softer background, refined accent
    // bar, gentler radius. Sits naturally above the bubble without
    // feeling like a separate floating card.
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
              color: KinrelColors.orange.withValues(alpha: 0.7), width: 2.5),
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
              color: KinrelColors.orange.withValues(alpha: 0.95),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToContent ?? '',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textSilver.withValues(alpha: 0.85),
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSenderName(WidgetRef ref) {
    // v131: Premium sender label — slightly larger, letter-spaced,
    // with a refined online dot. Reads as a quiet header above the
    // message rather than competing with it.
    //
    // v139: Relationship-aware sender labels — Kinrel's signature
    // differentiator. For family/group chats (familyId != null),
    // resolve the sender's relationship to the current viewer from
    // the K-Graph (e.g. "Chacha", "Bhaiya", "Nani"). The relationship
    // label appears as a small amber tag BEFORE the sender's name.
    // Falls back to sender name only if no relationship is found.
    //
    // Viewer-specific: the label changes based on who is logged in.
    // Not applied to 1-on-1 DMs (familyId == null).
    String? relationshipLabel;
    if (familyId != null && !isMe) {
      relationshipLabel = ref.watch(relationshipLabelProvider(
        (familyId: familyId!, senderUserId: message.senderId),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Online dot — softer presence dot, slightly larger for elegance
          if (message.isOnline)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.success,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.success.withValues(alpha: 0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),
          // v139: Relationship label (amber, small, before the name)
          // — the Kinrel signature differentiator. Only shown for
          // family/group chats where a relationship was resolved.
          if (relationshipLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: KinrelColors.ember.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.30),
                  width: 0.5,
                ),
              ),
              child: Text(
                relationshipLabel,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.ember,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
          Text(
            message.senderName,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: relationshipLabel != null
                  ? KinrelColors.textSilver.withValues(alpha: 0.85)
                  : KinrelColors.orange,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent() {
    switch (message.messageType) {
      case MessageType.text:
        // v131: Premium typography — comfortable line height (1.5),
        // generous size (15px), subtle letter-spacing for elegance.
        // Reads effortlessly across long paragraphs without fatigue.
        return Text(
          message.content,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 15,
            color: KinrelColors.textWhite,
            height: 1.5,
            letterSpacing: 0.1,
          ),
        );

      case MessageType.photo:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo — render the actual image if mediaUrl is present,
            // otherwise fall back to the placeholder. Mirrors the
            // voiceNote case below which correctly branches on
            // mediaUrl. Previously this ALWAYS showed the placeholder
            // and never checked message.mediaUrl.
            if (message.mediaUrl != null &&
                message.mediaUrl!.isNotEmpty)
              Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => FullScreenImageViewer.show(
                    ctx,
                    imageUrl: message.mediaUrl!,
                    senderName: message.senderName,
                    timestamp: message.timestamp,
                  ),
                  child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  message.mediaUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: double.infinity,
                      height: 200,
                      color: const Color(0xFF202338),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            value: loadingProgress.expectedTotalBytes !=
                                    null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            color: KinrelColors.orange,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFF202338),
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 36,
                          color: KinrelColors.textSilver
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Failed to load',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textSilver
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                ),
              )
            else
              // Legacy message with no mediaUrl — keep the placeholder.
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF202338),
                  borderRadius: BorderRadius.circular(14),
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
              const SizedBox(height: 8),
              Text(
                message.content,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14.5,
                  color: KinrelColors.textWhite,
                  height: 1.45,
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
        // v131: Reduced from 64→46px so emoji feels integrated into
        // the chat rhythm rather than floating as an oversized anomaly.
        // Still expressive, now proportional to the bubble padding.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            message.content,
            style: const TextStyle(
              fontSize: 46,
              height: 1.0,
            ),
          ),
        );

      case MessageType.familyEvent:
        // Phase 18: Thinking of You messages are stored as familyEvent
        // with messageSubType='thinking_of_you'. Render them with a
        // special heart-themed bubble instead of the generic celebration
        // card, so recipients immediately recognize the message type.
        if (message.messageSubType == 'thinking_of_you') {
          return _buildThinkingOfYouBubble();
        }
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

  /// Phase 18: Thinking of You bubble — a warm, heart-themed card that
  /// stands out from regular text messages. Renders the sender's name
  /// and the warm message in a soft pink/orange card.
  Widget _buildThinkingOfYouBubble() {
    // Use a warm pink-coral accent for Thinking of You (distinct from
    // the orange used for regular family events).
    const accent = Color(0xFFE91E63); // pink
    const accentDim = Color(0x1FE91E63); // 12% alpha
    const accentBorder = Color(0x33E91E63); // 20% alpha

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentDim,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: accentBorder,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Heart icon in a pink circle
          Container(
            width: 32,
            height: 32,
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
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          // Message text
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
                  // content is the warm message (e.g. "is thinking of you.")
                  // Prefix with the sender's first name so it reads naturally:
                  //   "Manish is thinking of you."
                  '${message.senderName.split(' ').first} ${message.content}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textWhite,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRow() {
    // v131: Refined timestamp — smaller, dimmer, letter-spaced.
    // Reads as supporting information, not a primary element.
    // Aligned tightly with the read-receipt for visual balance.
    return Padding(
      padding: const EdgeInsets.only(top: 5),
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
              fontSize: 9.5,
              color: KinrelColors.textDim.withValues(alpha: 0.85),
              letterSpacing: 0.3,
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
    // v131: Sticker timestamp matches the refined text-bubble timestamp
    // style for consistency across message types.
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          message.formattedTime,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9.5,
            color: KinrelColors.textDim.withValues(alpha: 0.85),
            letterSpacing: 0.3,
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

  /// v127: Reaction chips positioned overlapping the bubble's bottom edge.
  /// Uses a Transform.translate to shift the chips down so they overlap.
  Widget _buildReactionChips(String? currentUserId) {
    final grouped = message.groupedReactions;
    return Transform.translate(
      offset: const Offset(0, 10),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
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
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: hasMyReaction
                      ? KinrelColors.orange.withValues(alpha: 0.15)
                      : const Color(0xFF202338),
                  borderRadius: BorderRadius.circular(11),
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
                    Text(entry.key, style: const TextStyle(fontSize: 12)),
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
      color = KinrelColors.gold; // Kinrel premium accent (replaces WhatsApp blue)
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

/// v140: Maps a [KinshipEdgeCategory] to its generation-band color
/// for the message bubble left border + background tint.
///
/// Returns null for `self` and `indirect` (no band shown).
Color? _kinshipCategoryColor(KinshipEdgeCategory category) {
  switch (category) {
    case KinshipEdgeCategory.parent:
      return KinshipEdgeColors.parent;
    case KinshipEdgeCategory.child:
      return KinshipEdgeColors.child;
    case KinshipEdgeCategory.sibling:
      return KinshipEdgeColors.sibling;
    case KinshipEdgeCategory.spouse:
      return KinshipEdgeColors.spouseEdge;
    case KinshipEdgeCategory.grandparent:
      return KinshipEdgeColors.grandparent;
    case KinshipEdgeCategory.auntUncle:
      return KinshipEdgeColors.auntUncle;
    case KinshipEdgeCategory.cousin:
      return KinshipEdgeColors.cousin;
    case KinshipEdgeCategory.inLaw:
      return KinshipEdgeColors.inLaw;
    case KinshipEdgeCategory.extended:
      return KinshipEdgeColors.extended;
    case KinshipEdgeCategory.self:
    case KinshipEdgeCategory.indirect:
      return null; // No band for self or indirect
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Send Button (Ignite Gradient Circle)
// ═══════════════════════════════════════════════════════════════════════

class _SendButton extends StatelessWidget {
  const _SendButton({super.key, required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // v133: Premium send button — lives INSIDE the unified capsule,
    // so it's smaller (38px) than the old 44px standalone version.
    // IgniteGradient + ember glow shadow communicates it's the primary
    // action. AnimatedContainer provides smooth press feedback.
    return GestureDetector(
      onTap: isActive ? onTap : null,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        width: 38,
        height: 38,
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
                    color: KinrelColors.orange.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.send_rounded,
          size: 18,
          color: isActive ? Colors.white : KinrelColors.textDim,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Header Action Button (v134 — Kinrel signature header)
// ═══════════════════════════════════════════════════════════════════════

/// A soft, secondary action button for the Kinrel chat header.
///
/// v134: Header actions (video call, voice call) use this refined
/// button style so they never compete with the identity column.
/// Softer than a standard IconButton — smaller (36px), silver icon,
/// no background fill, gentle press feedback via AnimatedContainer.
class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.onPressed,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: Icon(
          icon,
          size: size,
          color: KinrelColors.textSilver,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Attachment Button
// ═══════════════════════════════════════════════════════════════════════

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // v133: Refined attachment button — sits OUTSIDE the capsule
    // (to the left), so it keeps the 44px touch target. Soft surface
    // with hairline border + subtle shadow for depth. Gentle press
    // feedback via AnimatedContainer.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A1D2E),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.75,
          ),
        ),
        child: Icon(
          Icons.attach_file_rounded,
          size: 21,
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
  const _MicButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // v133: Premium mic button — lives INSIDE the capsule, so it's
    // smaller (38px). Soft surface with hairline border for a quiet,
    // premium look. AnimatedContainer for smooth press feedback.
    // The mic icon is the default state of the trailing button —
    // when the user types, it morphs into the send button via
    // AnimatedSwitcher in _buildInputBar.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: Icon(
          Icons.mic_rounded,
          size: 19,
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
  const _StickerButton({super.key, required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // v133: Refined sticker/emoji button — sits OUTSIDE the capsule
    // (to the left, next to attachment). Same 44px target, same soft
    // surface as attachment. When active, fills with a subtle ember
    // tint + border so the user sees the panel is open.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? KinrelColors.ember.withValues(alpha: 0.15)
              : const Color(0xFF1A1D2E),
          border: isActive
              ? Border.all(
                  color: KinrelColors.ember.withValues(alpha: 0.4),
                  width: 1)
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.75,
                ),
        ),
        child: Icon(
          Icons.emoji_emotions_rounded,
          size: 21,
          color: isActive ? KinrelColors.orange : KinrelColors.textSilver,
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
    this.onMoreTap,
  });

  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onDismiss;

  /// v113: Called when the "+" button is tapped — opens the full emoji
  /// picker. Null-safe so the overlay still works without it, but the
  /// chat screen always wires it.
  final VoidCallback? onMoreTap;

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
                    children: [
                      ..._emojis.map((emoji) {
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
                      }),
                      // v113: "+" button — opens the full emoji picker
                      // so users can react with ANY emoji. Styled the
                      // same as the emoji buttons (42x42, circular).
                      if (onMoreTap != null)
                        GestureDetector(
                          onTap: onMoreTap,
                          child: Container(
                            width: 42,
                            height: 42,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: KinrelColors.darkElevated,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.add,
                                color: KinrelColors.textSilver,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                    ],
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
