// lib/features/chat/presentation/chat_ui_gallery.dart
//
// DAXELO KINREL — Chat UI Gallery (Chat UI Reference, section E)
//
// A debug/profile-only screen for visual comparison of the shared chat
// widgets against the five reference images. Reachable ONLY when the
// compile-time define UI_GALLERY=true (bool.fromEnvironment) — in that
// mode main() boots straight into this gallery instead of the app.
//
// It is a PageView of 4 screens drawn with FIXED sample data and the
// REAL widgets (ChatHeaderBar, MessageBubble, ChatSystemNotice,
// GameInviteCard, CollapsedGameInvites, ChatInputBar,
// SelectionModeToolbar, ChatOverflowMenuCard) — no network, no real
// providers: the few providers the real widgets watch internally
// (current user id, relationship key/label) are overridden with sample
// values in the enclosing ProviderScope.
//
// Pages:
//   1) Group chat (+ kinship color legend)
//   2) Selection mode (selection bar, reaction bar, selected row,
//      open overflow menu)
//   3) Invite states (active / result / expired one-liner / collapsed)
//   4) Direct chat

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../family/data/relationship_label_provider.dart';
import '../providers/chat_provider.dart';
import 'chat_ui_tokens.dart';
import 'widgets/chat_header_bar.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_system_notice.dart';
import 'widgets/constellation_pattern.dart';
import 'widgets/game_invite_card.dart';
import 'widgets/message_bubble.dart';
import 'widgets/selection_mode_toolbar.dart';

/// Compile-time gate — true only when built with
/// `--dart-define=UI_GALLERY=true`.
const bool kChatUiGallery = bool.fromEnvironment('UI_GALLERY');

/// The sample "family id" the gallery messages use. The relationship
/// providers are overridden for this id in [chatUiGalleryOverrides].
const String _galleryFamilyId = 'gallery-family';

/// Sample sender ids.
const String _me = 'gallery-me';
const String _papa = 'gallery-papa';
const String _nani = 'gallery-nani';
const String _meera = 'gallery-meera';

/// Provider overrides that let the REAL widgets resolve sample data
/// without any network or database access.
List<Override> chatUiGalleryOverrides() {
  return [
    chatCurrentUserIdProvider.overrideWith((ref) => _me),
    relationshipKeyProvider(
      const (familyId: _galleryFamilyId, senderUserId: _papa),
    ).overrideWith((ref) => 'father'),
    relationshipKeyProvider(
      const (familyId: _galleryFamilyId, senderUserId: _nani),
    ).overrideWith((ref) => 'maternal_grandmother'),
    relationshipKeyProvider(
      const (familyId: _galleryFamilyId, senderUserId: _meera),
    ).overrideWith((ref) => 'cousin'),
    relationshipLabelProvider(
      const (familyId: _galleryFamilyId, senderUserId: _papa),
    ).overrideWith((ref) => 'Father'),
    relationshipLabelProvider(
      const (familyId: _galleryFamilyId, senderUserId: _nani),
    ).overrideWith((ref) => 'Maternal grandmother'),
    relationshipLabelProvider(
      const (familyId: _galleryFamilyId, senderUserId: _meera),
    ).overrideWith((ref) => 'Cousin'),
  ];
}

/// Boots the gallery instead of the full app (used by main() when
/// UI_GALLERY=true).
class ChatUiGalleryApp extends StatelessWidget {
  const ChatUiGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: chatUiGalleryOverrides(),
      child: MaterialApp(
        title: 'Kinrel Chat UI Gallery',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ChatUi.chatBackground,
          colorScheme: const ColorScheme.dark(
            primary: KinrelColors.orange,
            surface: ChatUi.chatBar,
          ),
          fontFamily: 'DMSans',
        ),
        home: const ChatUiGallery(),
      ),
    );
  }
}

/// The 4-page gallery.
class ChatUiGallery extends StatefulWidget {
  const ChatUiGallery({super.key});

  @override
  State<ChatUiGallery> createState() => _ChatUiGalleryState();
}

class _ChatUiGalleryState extends State<ChatUiGallery> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      final p = _pageController.page?.round() ?? 0;
      if (p != _page) setState(() => _page = p);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatUi.chatBackground,
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              children: const [
                _GroupChatPage(),
                _SelectionModePage(),
                _InviteStatesPage(),
                _DirectChatPage(),
              ],
            ),
          ),
          // Page dots — tap to jump between the 4 reference screens
          // (swiping also works on touch devices).
          SafeArea(
            top: false,
            child: SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    GestureDetector(
                      onTap: () => _pageController.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 48,
                        height: 40,
                        alignment: Alignment.center,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page
                                ? ChatUi.accent
                                : ChatUi.textMeta,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared building blocks
// ═══════════════════════════════════════════════════════════════════════

ChatMessage _msg(
  String id,
  String senderId,
  String senderName,
  String content,
  TimeOfDay time, {
  MessageType type = MessageType.text,
  bool isRead = false,
  String status = 'sent',
  String? subType,
  String? gameType,
  String? gameId,
  String? roomCode,
  int? maxPlayers,
  int? currentPlayers,
  String? inviteStatus,
  String? winner,
}) {
  final now = DateTime.now();
  return ChatMessage(
    id: id,
    senderId: senderId,
    senderName: senderName,
    content: content,
    messageType: type,
    timestamp: DateTime(now.year, now.month, now.day, time.hour, time.minute),
    isRead: isRead,
    messageStatus: status,
    messageSubType: subType,
    gameType: gameType,
    gameId: gameId,
    roomCode: roomCode,
    gameMaxPlayers: maxPlayers,
    gameCurrentPlayers: currentPlayers,
    gameInviteStatus: inviteStatus,
    gameWinnerName: winner,
  );
}

/// A real MessageBubble row with the padding the message list applies.
Widget _bubbleRow(ChatMessage msg,
    {bool isMe = false,
    bool direct = false,
    bool selected = false,
    bool selection = false,
    bool first = true,
    bool last = true,
    double bottom = 8}) {
  final bubble = MessageBubble(
    message: msg,
    isMe: isMe,
    onReply: () {},
    onReact: () {},
    onLongPress: () {},
    familyId: direct ? null : _galleryFamilyId,
    isDirectChat: direct,
    isFirstInGroup: first,
    isLastInGroup: last,
    selectionMode: selection,
    isSelected: selected,
    onToggleSelection: () {},
  );
  final wrapped = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: bubble,
  );
  // D16: full-width selected-row tint.
  if (selected) {
    return Container(
      width: double.infinity,
      color: ChatUi.chatSelectedRow,
      padding: EdgeInsets.fromLTRB(12, 3, 12, 3 + bottom),
      child: bubble,
    );
  }
  return Padding(
    padding: EdgeInsets.only(left: 12, right: 12, bottom: bottom),
    child: wrapped,
  );
}

/// D8 static date pill.
Widget _dateChip(String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: ChatUi.chatCard,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: ChatUi.pillText),
        ),
      ),
    );

/// D8 floating date chip (static replica of FloatingDateIndicator's
/// pill — the real indicator needs a live scroll controller).
Widget _floatingChip(String label) => Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: ChatUi.chatReceived,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: ChatUi.floatingDateText),
      ),
    );

/// D10 unread pill.
Widget _unreadPill(String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: ChatUi.chatReceived,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: ChatUi.unreadPillText),
        ),
      ),
    );

/// D15 reaction bar (the real ReactionOverlay is a full-screen
/// dismissal overlay; the pill below is built from the same tokens).
Widget _reactionBar() => Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ChatUi.chatMenu,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in const ['❤️', '😂', '👍', '😮', '😢', '🙏'])
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
              ),
            const SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(Icons.add, size: 22, color: ChatUi.reactionPlus),
              ),
            ),
          ],
        ),
      ),
    );

/// A composer built with local state (no providers).
class _GalleryComposer extends StatefulWidget {
  const _GalleryComposer();

  @override
  State<_GalleryComposer> createState() => _GalleryComposerState();
}

class _GalleryComposerState extends State<_GalleryComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _composing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final c = _controller.text.trim().isNotEmpty;
      if (c != _composing) setState(() => _composing = c);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatInputBar(
      textController: _controller,
      focusNode: _focusNode,
      isComposing: _composing,
      onSend: () {},
      onAttach: () {},
      onEmojiToggle: () {},
      onStartRecording: () {},
      onThinkingOfYou: () {},
    );
  }
}

/// The phone-screen frame the gallery pages share: header slot on top,
/// scrollable chat area over the Constellation wallpaper, composer at
/// the bottom.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({
    required this.header,
    required this.body,
    this.footer,
    this.floating,
  });

  final Widget header;
  final Widget body;
  final Widget? footer;
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        header,
        Expanded(
          child: Stack(
            children: [
              // Wall: chatBackground + the real Constellation motif.
              const Positioned.fill(
                child: _GalleryWallpaper(),
              ),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 10, bottom: 12),
                  child: body,
                ),
              ),
              if (floating != null)
                Positioned(top: 8, left: 0, right: 0, child: floating!),
            ],
          ),
        ),
        if (footer != null) footer!,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 1 — Group chat
// ═══════════════════════════════════════════════════════════════════════

class _GroupChatPage extends StatelessWidget {
  const _GroupChatPage();

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      header: ChatHeaderBar(
        title: 'Tt family',
        subtitle: '5 members · 2 online',
        avatarInitial: 'T',
        onBack: () {},
        onAvatarTap: () {},
        onPhoneTap: () {},
        onMoreTap: () {},
      ),
      floating: _floatingChip('Monday'),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: ChatSystemNotice(
              content: 'Meera joined as your cousin',
              onViewInTree: _galleryNoop,
            ),
          ),
          _bubbleRow(
              _msg('g1', _papa, 'Papa', 'Dinner at 8, everyone coming?',
                  const TimeOfDay(hour: 19, minute: 42)),
              bottom: 8),
          _bubbleRow(_msg('g2', _nani, 'Nani', 'I will bring the sweets.',
              const TimeOfDay(hour: 19, minute: 44)),
              bottom: 8),
          _bubbleRow(
              _msg('g3', _meera, 'Meera',
                  'Save me a seat near the window.',
                  const TimeOfDay(hour: 19, minute: 45)),
              bottom: 8),
          _bubbleRow(
              _msg('g4', _me, 'You', 'Yes, on my way.',
                  const TimeOfDay(hour: 19, minute: 46),
                  isRead: true,
                  status: 'read'),
              isMe: true,
              bottom: 8),
          const SizedBox(height: 16),
          const _KinshipLegend(),
          const SizedBox(height: 24),
        ],
      ),
      footer: const _GalleryComposer(),
    );
  }
}

/// Legend row of the 7 kinship colors (11 / textSecondary, 9 dp dots).
class _KinshipLegend extends StatelessWidget {
  const _KinshipLegend();

  static const _entries = <(Color, String)>[
    (KinrelColors.nodeParent, 'Parent'),
    (KinrelColors.nodeSibling, 'Sibling'),
    (KinrelColors.nodeChild, 'Child'),
    (KinrelColors.nodeGrandparent, 'Grandparent'),
    (KinrelColors.nodeAuntUncle, 'Aunt or uncle'),
    (KinrelColors.nodeCousin, 'Cousin'),
    (KinrelColors.nodeInLaw, 'In-law'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final (color, label) in _entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: ChatUi.pillText.copyWith(fontSize: 11),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 2 — Selection mode
// ═══════════════════════════════════════════════════════════════════════

class _SelectionModePage extends StatelessWidget {
  const _SelectionModePage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SelectionModeToolbar(
          selectedCount: 1,
          onClose: () {},
          onReply: () {},
          onForward: () {},
          onStar: () {},
          onDelete: () {},
          onMore: () {},
        ),
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: _GalleryWallpaper()),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 10, bottom: 12),
                  child: Column(
                    children: [
                      _reactionBar(),
                      _bubbleRow(
                          _msg('s1', _nani, 'Nani',
                              'I will bring the sweets.',
                              const TimeOfDay(hour: 19, minute: 44)),
                          bottom: 8),
                      _bubbleRow(
                          _msg('s2', _papa, 'Papa',
                              'Dinner at 8, everyone coming?',
                              const TimeOfDay(hour: 19, minute: 42)),
                          selection: true,
                          selected: true,
                          bottom: 8),
                      _bubbleRow(
                          _msg('s3', _me, 'You', 'Yes, on my way.',
                              const TimeOfDay(hour: 19, minute: 46),
                              isRead: true,
                              status: 'read'),
                          isMe: true,
                          selection: true,
                          bottom: 8),
                      _bubbleRow(
                          _msg('s4', _meera, 'Meera',
                              'Save me a seat near the window.',
                              const TimeOfDay(hour: 19, minute: 45)),
                          selection: true,
                          bottom: 8),
                      const SizedBox(height: 16),
                      // The D17 overflow menu, open (real card widget).
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ChatOverflowMenuCard(
                            items: [
                              const ChatOverflowMenuItem(
                                  label: 'Copy',
                                  icon: Icons.copy,
                                  onTap: _galleryNoop),
                              const ChatOverflowMenuItem(
                                  label: 'Star',
                                  icon: Icons.star_outline,
                                  onTap: _galleryNoop),
                              const ChatOverflowMenuItem(
                                  label: 'Pin',
                                  icon: Icons.push_pin_outlined,
                                  onTap: _galleryNoop),
                              const ChatOverflowMenuItem(
                                  label: 'Message info',
                                  icon: Icons.info_outline,
                                  onTap: _galleryNoop),
                              const ChatOverflowMenuItem(
                                  label: 'Share outside Kinrel',
                                  icon: Icons.share,
                                  onTap: _galleryNoop),
                            ],
                            onItemTap: (_) {},
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 3 — Invite states
// ═══════════════════════════════════════════════════════════════════════

class _InviteStatesPage extends StatelessWidget {
  const _InviteStatesPage();

  Widget _caption(String text) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4, top: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: ChatUi.timeText),
        ),
      );

  /// Wraps an active/result card in a bubble-colored container (the
  /// real chat renders them inside the message bubble).
  Widget _inBubble(Widget child, {bool sent = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.only(left: 14, top: 6, right: 10, bottom: 5),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: sent ? ChatUi.chatSent : ChatUi.chatReceived,
              borderRadius: BorderRadius.circular(14),
              border: sent
                  ? Border.all(color: ChatUi.chatSentBorder, width: 0.75)
                  : null,
            ),
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header so the page reads as a chat screen.
        ChatHeaderBar(
          title: 'Tt family',
          subtitle: '5 members · 2 online',
          avatarInitial: 'T',
          onBack: () {},
          onAvatarTap: () {},
          onPhoneTap: () {},
          onMoreTap: () {},
        ),
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: _GalleryWallpaper()),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 10, bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _caption('Active invite'),
                      _inBubble(
                        GameInviteCard(
                          message: _msg(
                            'i1',
                            _papa,
                            'Papa',
                            '',
                            const TimeOfDay(hour: 20, minute: 10),
                            type: MessageType.gameInvite,
                            gameType: 'tic-tac-toe',
                            gameId: 'game-1',
                            roomCode: '554E61',
                            maxPlayers: 2,
                            currentPlayers: 1,
                            inviteStatus: 'pending',
                          ),
                          isMe: false,
                          routeFamilyId: _galleryFamilyId,
                        ),
                      ),
                      _caption('Finished game'),
                      _inBubble(
                        GameInviteCard(
                          message: _msg(
                            'i2',
                            _papa,
                            'Papa',
                            '',
                            const TimeOfDay(hour: 20, minute: 40),
                            type: MessageType.gameInvite,
                            gameType: 'tic-tac-toe',
                            gameId: 'game-2',
                            inviteStatus: 'completed',
                            winner: 'Papa',
                          ),
                          isMe: false,
                          routeFamilyId: _galleryFamilyId,
                          scoreLine: '3 to 2',
                        ),
                      ),
                      _caption('Expired one line'),
                      _bubbleRow(
                        _msg(
                          'i3',
                          _papa,
                          'Papa',
                          '',
                          const TimeOfDay(hour: 21, minute: 55),
                          type: MessageType.gameInvite,
                          gameType: 'sos',
                          gameId: 'game-3',
                          inviteStatus: 'expired',
                        ),
                        bottom: 8,
                      ),
                      _caption('Collapsed'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: CollapsedGameInvites(
                          messages: [
                            _msg('c1', _papa, 'Papa', '',
                                const TimeOfDay(hour: 21, minute: 30),
                                type: MessageType.gameInvite,
                                gameType: 'sos',
                                gameId: 'game-4',
                                inviteStatus: 'expired'),
                            _msg('c2', _papa, 'Papa', '',
                                const TimeOfDay(hour: 21, minute: 40),
                                type: MessageType.gameInvite,
                                gameType: 'dotsboxes',
                                gameId: 'game-5',
                                inviteStatus: 'expired'),
                            _msg('c3', _papa, 'Papa', '',
                                const TimeOfDay(hour: 21, minute: 50),
                                type: MessageType.gameInvite,
                                gameType: 'checkers',
                                gameId: 'game-6',
                                inviteStatus: 'expired'),
                          ],
                          isMe: false,
                          routeFamilyId: _galleryFamilyId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 4 — Direct chat
// ═══════════════════════════════════════════════════════════════════════

class _DirectChatPage extends StatelessWidget {
  const _DirectChatPage();

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      header: ChatHeaderBar(
        title: 'Papa',
        subtitle: 'Father · online',
        avatarInitial: 'P',
        isDirect: true,
        initialColor: KinrelColors.nodeParent,
        onBack: () {},
        onAvatarTap: () {},
        onPhoneTap: () {},
        onMoreTap: () {},
      ),
      body: Column(
        children: [
          _dateChip('Yesterday'),
          _bubbleRow(
              _msg('d1', _me, 'You', 'Reached home safely.',
                  const TimeOfDay(hour: 22, minute: 49),
                  isRead: true,
                  status: 'read'),
              isMe: true,
              direct: true,
              bottom: 2),
          _bubbleRow(
              _msg('d2', _me, 'You', '',
                  const TimeOfDay(hour: 22, minute: 49)),
              isMe: true,
              direct: true,
              bottom: 8,
              first: false,
              last: false),
          _bubbleRow(
              _msg('d3', _papa, 'Papa', 'Good. Call me tomorrow.',
                  const TimeOfDay(hour: 22, minute: 52)),
              direct: true,
              bottom: 8),
          _unreadPill('2 unread messages'),
          _bubbleRow(
              _msg('d4', _papa, 'Papa', 'Papa is thinking of you',
                  const TimeOfDay(hour: 22, minute: 53),
                  type: MessageType.familyEvent,
                  subType: 'thinking_of_you'),
              direct: true,
              bottom: 8),
          _bubbleRow(
              _msg('d5', _papa, 'Papa', 'Did you eat dinner?',
                  const TimeOfDay(hour: 20, minute: 59)),
              direct: true,
              bottom: 8),
        ],
      ),
      footer: const _GalleryComposer(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Wallpaper (the real Constellation motif over chatBackground)
// ═══════════════════════════════════════════════════════════════════════

class _GalleryWallpaper extends StatelessWidget {
  const _GalleryWallpaper();

  @override
  Widget build(BuildContext context) {
    // chatBackground base + the real Constellation motif (D13).
    return const ColoredBox(
      color: ChatUi.chatBackground,
      child: ConstellationPattern(),
    );
  }
}

void _galleryNoop() {}
