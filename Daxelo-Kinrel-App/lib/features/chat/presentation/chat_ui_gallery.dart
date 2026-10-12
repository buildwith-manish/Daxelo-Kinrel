// lib/features/chat/presentation/chat_ui_gallery.dart
//
// DAXELO KINREL — Chat UI Gallery (Chat UI Reference, section E)
//
// A DEBUG-ONLY screen that renders the real chat widgets with sample
// data — no Supabase, no services, no navigation. It exists so the
// unified chat UI can be inspected pixel-by-pixel against the
// reference images without a backend.
//
// Boot gate (main.dart): only reachable when the app is built with
//   --dart-define=UI_GALLERY=true
// (see the ui_gallery input of .github/workflows/perf-profile-apk.yml,
// which produces a *-gallery APK).
//
// Pages (swipe or click the dots):
//   1. Group chat — D1 header, D3/D5 bubbles with kinship bands and
//      sender pills, D8 date chip, D9 system notice, D10 unread pill,
//      D11 thinking-of-you, D7 ticks, D12 composer, kinship legend.
//   2. Invite states — D18a active card, D18b result card (Rematch),
//      D18c expired one-liner, collapsed run.
//   3. Selection mode — D14 toolbar, D15 reaction bar, D16 selected
//      row tint, D17 context menu card.
//   4. Direct chat — D1 direct header, D4 bubbles WITHOUT bands or
//      sender pills, D12 composer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../family/data/relationship_label_provider.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../providers/chat_provider.dart';
import 'chat_ui_tokens.dart';
import 'widgets/chat_header_bar.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_system_notice.dart';
import 'widgets/deleted_message_ghost.dart';
import 'widgets/delivery_mark.dart';
import 'widgets/game_invite_card.dart';
import 'widgets/message_bubble.dart';
import 'widgets/selection_mode_toolbar.dart';
import 'widgets/thread_markers.dart';
import 'widgets/typing_indicator.dart';

/// The gallery family id (kept out of the real id space).
const String _kGalleryFamily = 'gallery-family';

/// Sample viewer id — messages from this sender render as "me".
const String _kGalleryMe = 'gallery-me';

/// The gallery root: provider overrides for sample data + a dark
/// MaterialApp. Standalone — no Supabase, no router.
class ChatUiGallery extends StatelessWidget {
  const ChatUiGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        chatCurrentUserIdProvider.overrideWith((ref) => _kGalleryMe),
        // Sample kinship keys + labels for the group page pills/bands.
        relationshipKeyProvider((
          familyId: _kGalleryFamily,
          senderUserId: 'gallery-papa',
        )).overrideWith((ref) => 'parent'),
        relationshipKeyProvider((
          familyId: _kGalleryFamily,
          senderUserId: 'gallery-nani',
        )).overrideWith((ref) => 'grandparent'),
        relationshipKeyProvider((
          familyId: _kGalleryFamily,
          senderUserId: 'gallery-meera',
        )).overrideWith((ref) => 'cousin'),
        relationshipLabelProvider((
          familyId: _kGalleryFamily,
          senderUserId: 'gallery-papa',
        )).overrideWith((ref) => 'Father'),
        relationshipLabelProvider((
          familyId: _kGalleryFamily,
          senderUserId: 'gallery-nani',
        )).overrideWith((ref) => 'Grandmother'),
        relationshipLabelProvider((
          familyId: _kGalleryFamily,
          senderUserId: 'gallery-meera',
        )).overrideWith((ref) => 'Cousin'),
      ],
      child: MaterialApp(
        title: 'Kinrel Chat UI Gallery',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ChatUi.chatBackground,
          fontFamily: KinrelTypography.bodyFont,
        ),
        home: const _GalleryPager(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Pager + dots
// ═══════════════════════════════════════════════════════════════════════

class _GalleryPager extends StatefulWidget {
  const _GalleryPager();

  @override
  State<_GalleryPager> createState() => _GalleryPagerState();
}

class _GalleryPagerState extends State<_GalleryPager> {
  final _controller = PageController();
  int _page = 0;

  static const _titles = [
    'Group chat',
    'Invite states',
    'Selection mode',
    'Direct chat',
    'Signature details', // v143 / §I
    'Deleted messages', // v143 / §I
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatUi.chatBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Gallery header — title + page indicator.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kinrel Chat UI Gallery',
                          style: ChatUi.titleText.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_page + 1} of ${_titles.length} · ${_titles[_page]}',
                          style: ChatUi.subtitleText,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _GroupChatPage(),
                  _InviteStatesPage(),
                  _SelectionModePage(),
                  _DirectChatPage(),
                  _SignatureDetailsPage(),
                  _DeletedMessagesPage(),
                ],
              ),
            ),
            // Page dots (orange active).
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _titles.length; i++)
                    GestureDetector(
                      onTap: () => _controller.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                      ),
                      child: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? ChatUi.accent
                              : ChatUi.textMeta.withValues(alpha: 0.4),
                        ),
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

// ═══════════════════════════════════════════════════════════════════════
// Sample data
// ═══════════════════════════════════════════════════════════════════════

DateTime _at(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

ChatMessage _msg(
  String id,
  String senderId,
  String name,
  String text,
  int hour,
  int minute, {
  MessageType type = MessageType.text,
  String? subType,
  bool isRead = true,
  List<MessageReaction> reactions = const [],
  String? gameType,
  String? gameId,
  String? roomCode,
  int? maxPlayers,
  int? currentPlayers,
  String? inviteStatus,
  String? winner,
  // v143 / Signature §I gallery extras:
  String? forwardedFrom,
  bool isDeletedForEveryone = false,
  String? deletedByUserId,
  String? replyToId,
  String? replyToContent,
  String? replyToSenderName,
  String? messageStatus,
}) {
  return ChatMessage(
    id: id,
    senderId: senderId,
    senderName: name,
    content: text,
    messageType: type,
    timestamp: _at(hour, minute),
    isRead: isRead,
    reactions: reactions,
    messageSubType: subType,
    messageStatus: messageStatus ?? 'sent',
    gameType: gameType,
    gameId: gameId,
    roomCode: roomCode,
    gameMaxPlayers: maxPlayers,
    gameCurrentPlayers: currentPlayers,
    gameInviteStatus: inviteStatus,
    gameWinnerName: winner,
    forwardedFrom: forwardedFrom,
    isDeletedForEveryone: isDeletedForEveryone,
    deletedByUserId: deletedByUserId,
    replyToId: replyToId,
    replyToContent: replyToContent,
    replyToSenderName: replyToSenderName,
  );
}

/// A quiet bubble wrapper that fires no callbacks — the gallery is
/// visual only.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMe,
    this.isDirect = false,
    this.isFirstInGroup = true,
  });

  final ChatMessage message;
  final bool isMe;
  final bool isDirect;
  final bool isFirstInGroup;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: MessageBubble(
        message: message,
        isMe: isMe,
        onReply: () {},
        onReact: () {},
        onLongPress: () {},
        familyId: isDirect ? null : _kGalleryFamily,
        inviteFamilyId: isDirect ? _kGalleryFamily : null,
        isDirectChat: isDirect,
        isFirstInGroup: isFirstInGroup,
      ),
    );
  }
}

Widget _padded({required Widget child, double bottom = 2}) =>
    Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, bottom), child: child);

Widget _sectionLabel(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: ChatUi.subtitleText),
  ),
);

Widget _dateChip(String label) => ThreadDateMarker(label: label);

// (Removed the old _unreadPill helper — the gallery now uses the new
// UnreadMarker widget from thread_markers.dart everywhere the unread
// divider used to be drawn.)

Widget _notice(String text, {bool withAction = true}) =>
    ChatSystemNotice(content: text, onViewInTree: withAction ? () {} : null);

// ═══════════════════════════════════════════════════════════════════════
// Page 1 — Group chat
// ═══════════════════════════════════════════════════════════════════════

class _GroupChatPage extends StatelessWidget {
  const _GroupChatPage();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChatUi.chatBackground,
      child: Column(
        children: [
          ChatHeaderBar(
            title: 'Tf family',
            subtitle: '5 members · 2 online',
            avatarInitial: 'Tf family',
            onBack: () {},
            onPhoneTap: () {},
            onMoreTap: () {},
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 12),
              children: [
                _padded(
                  bottom: 8,
                  child: _notice('Meera joined as your cousin'),
                ),
                _dateChip('Monday'),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'g1',
                      'gallery-nani',
                      'Nani',
                      'Reached home safely.',
                      19,
                      38,
                    ),
                    isMe: false,
                  ),
                ),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'g2',
                      'gallery-papa',
                      'Papa',
                      'Dinner at 8, everyone coming?',
                      19,
                      42,
                    ),
                    isMe: false,
                  ),
                ),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'g3',
                      _kGalleryMe,
                      'Me',
                      'Yes, on my way.',
                      19,
                      46,
                      reactions: [
                        const MessageReaction(
                          emoji: '❤️',
                          userId: 'gallery-nani',
                        ),
                      ],
                    ),
                    isMe: true,
                  ),
                ),
                _padded(
                  bottom: 8,
                  child: _Bubble(
                    message: _msg(
                      'g4',
                      'gallery-nani',
                      'Nani',
                      'I will bring the sweets.',
                      19,
                      44,
                    ),
                    isMe: false,
                    isFirstInGroup: false,
                  ),
                ),
                _padded(
                  bottom: 8,
                  child: _Bubble(
                    message: _msg(
                      'g5',
                      'gallery-nani',
                      'Nani',
                      'Nani is thinking of you',
                      19,
                      45,
                      type: MessageType.familyEvent,
                      subType: 'thinking_of_you',
                    ),
                    isMe: false,
                  ),
                ),
                _padded(
                  bottom: 8,
                  child: const UnreadMarker(count: 1),
                ),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'g6',
                      'gallery-meera',
                      'Meera',
                      'Save me a seat near the window.',
                      19,
                      45,
                    ),
                    isMe: false,
                  ),
                ),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'g7',
                      'gallery-meera',
                      'Meera',
                      'Good. Call me tomorrow.',
                      19,
                      47,
                    ),
                    isMe: false,
                    isFirstInGroup: false,
                  ),
                ),
                _sectionLabel('Kinship colors'),
                const _KinshipLegend(),
              ],
            ),
          ),
          const _GalleryComposer(),
        ],
      ),
    );
  }
}

class _KinshipLegend extends StatelessWidget {
  const _KinshipLegend();

  static const _rows = <(String, Color)>[
    ('Parent', KinrelColors.nodeParent),
    ('Sibling', KinrelColors.nodeSibling),
    ('Child', KinrelColors.nodeChild),
    ('Grandparent', KinrelColors.nodeGrandparent),
    ('Aunt or uncle', KinrelColors.nodeAuntUncle),
    ('Cousin', KinrelColors.nodeCousin),
    ('In-law', KinrelColors.nodeInLaw),
    ('Spouse', KinrelColors.nodeSpouse),
    ('Self', KinrelColors.nodeSelf),
    ('Extended', KinrelColors.nodeExtended),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (final (label, color) in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(label, style: ChatUi.pillText),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 2 — Invite states
// ═══════════════════════════════════════════════════════════════════════

class _InviteStatesPage extends StatelessWidget {
  const _InviteStatesPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        _sectionLabel('Active invite'),
        _padded(
          bottom: 8,
          child: GameInviteCard(
            message: _msg(
              'i1',
              'gallery-papa',
              'Papa',
              '',
              21,
              5,
              type: MessageType.gameInvite,
              gameType: 'tictactoe',
              gameId: 'gallery-game-1',
              roomCode: '554E61',
              maxPlayers: 2,
              currentPlayers: 1,
              inviteStatus: 'pending',
            ),
            isMe: false,
            routeFamilyId: _kGalleryFamily,
          ),
        ),
        _sectionLabel('Finished game'),
        _padded(
          bottom: 8,
          child: GameInviteCard(
            message: _msg(
              'i2',
              'gallery-papa',
              'Papa',
              '',
              21,
              20,
              type: MessageType.gameInvite,
              gameType: 'tictactoe',
              gameId: 'gallery-game-2',
              inviteStatus: 'completed',
              winner: 'Papa',
            ),
            isMe: false,
            routeFamilyId: _kGalleryFamily,
            scoreLine: '3 to 2',
          ),
        ),
        _sectionLabel('Expired one liner'),
        _padded(
          bottom: 8,
          child: GameInviteCard(
            message: _msg(
              'i3',
              'gallery-meera',
              'Meera',
              '',
              21,
              55,
              type: MessageType.gameInvite,
              gameType: 'sos',
              inviteStatus: 'expired',
            ),
            isMe: false,
            routeFamilyId: _kGalleryFamily,
          ),
        ),
        _sectionLabel('Collapsed'),
        _padded(
          bottom: 8,
          child: CollapsedGameInvites(
            messages: [
              _msg(
                'c1',
                'gallery-meera',
                'Meera',
                '',
                20,
                1,
                type: MessageType.gameInvite,
                gameType: 'bingo',
                inviteStatus: 'expired',
              ),
              _msg(
                'c2',
                'gallery-papa',
                'Papa',
                '',
                20,
                15,
                type: MessageType.gameInvite,
                gameType: 'carrom',
                inviteStatus: 'expired',
              ),
              _msg(
                'c3',
                'gallery-meera',
                'Meera',
                '',
                20,
                30,
                type: MessageType.gameInvite,
                gameType: 'checkers',
                inviteStatus: 'cancelled',
              ),
            ],
            isMe: false,
            routeFamilyId: _kGalleryFamily,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 3 — Selection mode
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
              ListView(
                padding: const EdgeInsets.only(top: 10, bottom: 12),
                children: [
                  _padded(
                    bottom: 8,
                    child: _notice(
                      'Meera joined as your cousin',
                      withAction: false,
                    ),
                  ),
                  // D16: the whole row width tinted while selected.
                  Container(
                    width: double.infinity,
                    color: ChatUi.chatSelectedRow,
                    padding: const EdgeInsets.fromLTRB(12, 3, 12, 8),
                    child: _Bubble(
                      message: _msg(
                        's1',
                        'gallery-papa',
                        'Papa',
                        'Dinner at 8, everyone coming?',
                        19,
                        42,
                      ),
                      isMe: false,
                    ),
                  ),
                  _padded(
                    child: _Bubble(
                      message: _msg(
                        's2',
                        'gallery-nani',
                        'Nani',
                        'I will bring the sweets.',
                        19,
                        44,
                      ),
                      isMe: false,
                    ),
                  ),
                ],
              ),
              // D15: the reaction bar pill, as it appears on long-press.
              Positioned(
                left: 12,
                right: 12,
                top: 260,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ChatUi.chatMenu,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final emoji in const [
                          '❤️',
                          '😂',
                          '👍',
                          '😮',
                          '😢',
                          '🙏',
                        ])
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.add,
                            size: 22,
                            color: ChatUi.reactionPlus,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // D17: the context menu card, anchored demo.
              Positioned(
                top: 120,
                right: 12,
                child: Container(
                  width: ChatUi.menuWidth,
                  decoration: BoxDecoration(
                    color: ChatUi.chatMenu,
                    borderRadius: BorderRadius.circular(ChatUi.menuRadius),
                    border: Border.all(
                      color: ChatUi.chatCardBorder,
                      width: ChatUi.cardBorderWidth,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, item) in const [
                        (Icons.copy, 'Copy'),
                        (Icons.star_outline, 'Star'),
                        (Icons.push_pin_outlined, 'Pin'),
                        (Icons.info_outline, 'Message info'),
                        (Icons.share, 'Share outside Kinrel'),
                      ].indexed)
                        Container(
                          decoration: BoxDecoration(
                            border: i == 0
                                ? null
                                : Border(
                                    top: BorderSide(
                                      color: ChatUi.chatCardBorder,
                                      width: 0.5,
                                    ),
                                  ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.$1,
                                  size: ChatUi.menuIconSize,
                                  color: ChatUi.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Text(item.$2, style: ChatUi.menuText),
                              ],
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
    return ColoredBox(
      color: ChatUi.chatBackground,
      child: Column(
        children: [
          ChatHeaderBar(
            title: 'Papa',
            subtitle: 'Father · online',
            avatarInitial: 'Papa',
            isDirect: true,
            initialColor: KinrelColors.nodeParent,
            onBack: () {},
            onPhoneTap: () {},
            onMoreTap: () {},
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 12),
              children: [
                _dateChip('Yesterday'),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'd1',
                      'gallery-papa',
                      'Papa',
                      'Did you eat dinner?',
                      22,
                      41,
                    ),
                    isMe: false,
                    isDirect: true,
                  ),
                ),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'd2',
                      'gallery-papa',
                      'Papa',
                      'Good. Call me tomorrow.',
                      22,
                      49,
                    ),
                    isMe: false,
                    isDirect: true,
                    isFirstInGroup: false,
                  ),
                ),
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'd3',
                      _kGalleryMe,
                      'Me',
                      'Reached home safely.',
                      22,
                      52,
                    ),
                    isMe: true,
                    isDirect: true,
                  ),
                ),
                _notice('Manish joined the family.', withAction: false),
              ],
            ),
          ),
          const _GalleryComposer(isDirect: true),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared gallery composer (real ChatInputBar, callbacks are no-ops)
// ═══════════════════════════════════════════════════════════════════════

class _GalleryComposer extends StatefulWidget {
  const _GalleryComposer({this.isDirect = false});

  final bool isDirect;

  @override
  State<_GalleryComposer> createState() => _GalleryComposerState();
}

class _GalleryComposerState extends State<_GalleryComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
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
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatInputBar(
      textController: _controller,
      focusNode: _focus,
      isComposing: _composing,
      onSend: () {
        _controller.clear();
      },
      onAttach: () {},
      onEmojiToggle: () {},
      onThinkingOfYou: () {},
      onStartRecording: () {},
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 5 — Signature details (v143 / §I)
// ═══════════════════════════════════════════════════════════════════════

class _SignatureDetailsPage extends StatelessWidget {
  const _SignatureDetailsPage();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChatUi.chatBackground,
      child: Column(
        children: [
          ChatHeaderBar(
            title: 'Tf family',
            subtitle: '5 members · 2 online',
            avatarInitial: 'Tf family',
            onBack: () {},
            onPhoneTap: () {},
            onMoreTap: () {},
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 12),
              children: [
                // Date marker "Today" (§D).
                _padded(
                  bottom: 8,
                  child: const ThreadDateMarker(label: 'Today'),
                ),
                // Received Papa bubble with the Passed along label +
                // "Dinner at 8, everyone coming?" 7:42 PM (§F).
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'sig1',
                      'gallery-papa',
                      'Papa',
                      'Dinner at 8, everyone coming?',
                      19,
                      42,
                      forwardedFrom: 'Aunt Riya',
                    ),
                    isMe: false,
                  ),
                ),
                // Sent bubble with a reply quote (Papa, Father, Dinner
                // at 8, everyone coming?) + "Yes, on my way." 7:46 PM
                // + the read mark (§G + §C).
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'sig2',
                      _kGalleryMe,
                      'Me',
                      'Yes, on my way.',
                      19,
                      46,
                      replyToId: 'sig1',
                      replyToSenderName: 'Papa',
                      replyToContent: 'Dinner at 8, everyone coming?',
                      isRead: true,
                      messageStatus: 'read',
                    ),
                    isMe: true,
                  ),
                ),
                // Unread marker "2 new messages" (§E).
                _padded(
                  bottom: 8,
                  child: const UnreadMarker(count: 2),
                ),
                // Received Nani bubble "I will bring the sweets." 7:48 PM
                // (grandparent color).
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'sig3',
                      'gallery-nani',
                      'Nani',
                      'I will bring the sweets.',
                      19,
                      48,
                    ),
                    isMe: false,
                  ),
                ),
                // Typing indicator for Nani (§H).
                _padded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TypingIndicator(
                      name: 'Nani',
                      label: 'Nani is typing',
                      familyId: _kGalleryFamily,
                      typistSenderId: 'gallery-nani',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Legend row of the four delivery marks (§C).
                _sectionLabel('Delivery marks'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    children: [
                      _DeliveryLegend(
                          status: DeliveryMarkStatus.sending, label: 'Sending'),
                      _DeliveryLegend(
                          status: DeliveryMarkStatus.sent, label: 'Sent'),
                      _DeliveryLegend(
                          status: DeliveryMarkStatus.delivered,
                          label: 'Delivered'),
                      _DeliveryLegend(
                          status: DeliveryMarkStatus.read, label: 'Read'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact legend cell: the DeliveryMark painter + a 12/textSecondary
/// label below it. Used in the Signature details page (§I).
class _DeliveryLegend extends StatelessWidget {
  const _DeliveryLegend({required this.status, required this.label});

  final DeliveryMarkStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            DeliveryMark(status: status),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: ChatUi.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page 6 — Deleted messages (v143 / §I)
// ═══════════════════════════════════════════════════════════════════════

class _DeletedMessagesPage extends StatelessWidget {
  const _DeletedMessagesPage();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChatUi.chatBackground,
      child: Column(
        children: [
          ChatHeaderBar(
            title: 'Tf family',
            subtitle: '5 members · 2 online',
            avatarInitial: 'Tf family',
            onBack: () {},
            onPhoneTap: () {},
            onMoreTap: () {},
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 12),
              children: [
                _padded(
                  bottom: 8,
                  child: const ThreadDateMarker(label: 'Today'),
                ),
                // A normal Papa bubble (for visual contrast against the
                // ghost variants below).
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'del1',
                      'gallery-papa',
                      'Papa',
                      'Did you finish your homework?',
                      15,
                      30,
                    ),
                    isMe: false,
                  ),
                ),
                // A normal sent bubble.
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'del2',
                      _kGalleryMe,
                      'Me',
                      'Almost done.',
                      15,
                      32,
                      isRead: true,
                      messageStatus: 'read',
                    ),
                    isMe: true,
                  ),
                ),
                // The own ghost: "You took this back" 3:40 PM.
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'del3',
                      _kGalleryMe,
                      'Me',
                      '',
                      15,
                      40,
                      isDeletedForEveryone: true,
                      deletedByUserId: _kGalleryMe,
                    ),
                    isMe: true,
                  ),
                ),
                // The Papa ghost: "Papa took this back" 7:44 PM.
                _padded(
                  child: _Bubble(
                    message: _msg(
                      'del4',
                      'gallery-papa',
                      'Papa',
                      '',
                      19,
                      44,
                      isDeletedForEveryone: true,
                      deletedByUserId: 'gallery-papa',
                    ),
                    isMe: false,
                  ),
                ),
                // Collapsed row: 3 messages were taken back (§B).
                _padded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CollapsedDeletedGhostsRow(
                      count: 3,
                      onTap: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
