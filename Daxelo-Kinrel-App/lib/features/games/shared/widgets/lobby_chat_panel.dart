// lib/features/games/shared/widgets/lobby_chat_panel.dart
//
// Universal Lobby Chat — shared across ALL multiplayer games.
//
// Features:
//   • Real-time messages (Socket.IO broadcast per game room)
//   • 4 quick-tap emoji reactions (👍 😂 🔥 👋)
//   • Text input with send button + Enter-to-send
//   • Typing indicator ("Manish is typing…")
//   • Unread count badge when chat is collapsed
//   • Auto-join on mount, auto-leave on dispose
//   • Spectator vs. player badge on each message
//   • Connection status indicator
//   • Cap of 100 messages to avoid memory bloat
//   • Auto-scroll to bottom on new message (with smart pause if user scrolled up)
//
// Usage in any lobby (the same widget works for every game):
//   LobbyChatPanel(
//     gameTable: 'bingo_games',  // or 'redlight_rounds', etc.
//     gameId: state.game!.id,
//     familyId: widget.familyId,
//     isSpectator: false,
//   )
//
// Server-side events (handled by NestJS gateway):
//   game:chat:join     → client joins the chat room for a game
//   game:chat:leave    → client leaves the chat room
//   game:chat:message  → broadcast a message to everyone in the room
//   game:chat:typing   → broadcast a typing indicator (throttled server-side)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/supabase_service.dart';

class LobbyChatPanel extends ConsumerStatefulWidget {
  const LobbyChatPanel({
    super.key,
    required this.gameTable,
    required this.gameId,
    required this.familyId,
    this.isSpectator = false,
    this.maxHeight = 240,
    this.initiallyExpanded = true,
  });

  /// e.g. 'bingo_games', 'redlight_rounds'
  final String gameTable;
  final String gameId;
  final String familyId;
  final bool isSpectator;
  final double maxHeight;

  /// If false, the chat starts collapsed (only the header + unread count
  /// is shown). User taps to expand. Useful for lobby screens with a lot
  /// of other content.
  final bool initiallyExpanded;

  @override
  ConsumerState<LobbyChatPanel> createState() => _LobbyChatPanelState();
}

class _LobbyChatPanelState extends ConsumerState<LobbyChatPanel> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final Set<String> _typingUsers = {};
  /// Caches the display name of each typing user so the typing indicator
  /// can show "Manish is typing…" instead of just "Someone is typing…".
  final Map<String, String> _typingNames = {};

  /// True if the user has scrolled up (so we don't auto-scroll on new msgs).
  bool _userScrolledUp = false;

  /// Number of messages received since the user last scrolled to bottom.
  int _unreadCount = 0;

  /// True if the chat panel is collapsed (only header visible).
  /// Toggled by tapping the header.
  bool _collapsed = false;

  /// True if we've successfully joined the chat room (waits for socket
  /// to connect if needed).
  bool _joined = false;

  /// Connection status — reflected in the header.
  bool _socketConnected = false;

  VoidCallback? _unsubMessage;
  VoidCallback? _unsubTyping;
  VoidCallback? _unsubConnect;
  Timer? _joinRetry;
  Timer? _typingStopTimer;
  Timer? _typingEmitThrottle;
  bool _lastEmittedTyping = false;

  static const _quickEmojis = ['👍', '😂', '🔥', '👋'];
  static const _maxMessages = 100;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final distFromBottom =
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels;
    final atBottom = distFromBottom < 50;
    if (atBottom) {
      _userScrolledUp = false;
      if (_unreadCount > 0) {
        setState(() => _unreadCount = 0);
      }
    } else if (!_userScrolledUp) {
      _userScrolledUp = true;
    }
  }

  void _attach() {
    final socket = ref.read(socketServiceProvider);

    // Subscribe to incoming chat messages.
    _unsubMessage = socket.onGameChatMessage(_onMessage);

    // Subscribe to typing indicators.
    _unsubTyping = socket.onGameChatTyping(_onTyping);

    // Subscribe to connection status changes.
    _unsubConnect = socket.onConnectionChange((connected) {
      if (!mounted) return;
      setState(() => _socketConnected = connected);
      if (connected) _tryJoin();
    });
    _socketConnected = socket.isConnected;

    _tryJoin();
  }

  void _tryJoin() {
    final socket = ref.read(socketServiceProvider);
    socket.joinGameChatRoom(
      gameTable: widget.gameTable,
      gameId: widget.gameId,
    );
    // Retry join after 2s in case socket wasn't connected yet.
    _joinRetry?.cancel();
    _joinRetry = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      ref.read(socketServiceProvider).joinGameChatRoom(
            gameTable: widget.gameTable,
            gameId: widget.gameId,
          );
      setState(() => _joined = true);
    });
  }

  void _onMessage(Map<String, dynamic> msg) {
    // Filter to this room (the socket broadcasts to all subscribers).
    if (msg['gameTable'] != widget.gameTable ||
        msg['gameId'] != widget.gameId) {
      return;
    }
    if (!mounted) return;

    // Clear typing indicator if the typing user just sent a real message.
    // (Side-effect: Set.remove returns true if the element was present.)
    final senderId = msg['senderId'] as String?;
    if (senderId != null) {
      _typingUsers.remove(senderId);
    }

    setState(() {
      _messages.add(msg);
      if (_messages.length > _maxMessages) {
        _messages.removeRange(0, _messages.length - _maxMessages);
      }
      if (_userScrolledUp) {
        _unreadCount++;
      }
    });

    if (!_userScrolledUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _onTyping(Map<String, dynamic> payload) {
    if (payload['gameTable'] != widget.gameTable ||
        payload['gameId'] != widget.gameId) {
      return;
    }
    if (!mounted) return;

    final userId = payload['userId'] as String?;
    final userName = payload['userName'] as String? ?? 'Someone';
    final isTyping = payload['isTyping'] as bool? ?? false;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    if (userId == null || userId == myId) return;

    setState(() {
      if (isTyping) {
        _typingUsers.add(userId);
        // Cache the name on the entry so we can display "X is typing".
        _typingNames[userId] = userName;
      } else {
        _typingUsers.remove(userId);
      }
    });

    // Auto-clear stale typing indicator after 5s (in case the stop event was lost).
    if (isTyping) {
      Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _typingUsers.remove(userId));
      });
    }
  }

  Future<void> _send({required String type, required String content}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final socket = ref.read(socketServiceProvider);
    final myId =
        ref.read(supabaseProvider)?.auth.currentUser?.id ?? '';
    final myName =
        (ref.read(supabaseProvider)?.auth.currentUser?.userMetadata?['name']
                as String?) ??
            'Family member';
    try {
      await socket.sendGameChatMessage(
        gameTable: widget.gameTable,
        gameId: widget.gameId,
        familyId: widget.familyId,
        type: type,
        content: trimmed,
        senderName: myName,
        isSpectator: widget.isSpectator,
      );
      // Sender doesn't echo locally — the server broadcasts back to everyone
      // in the room including us, so the message will appear via _onMessage.
      // Optimistically clear the typing indicator for ourselves.
      _stopTyping();
    } catch (_) {}
    if (type == 'text') _textCtrl.clear();
  }

  void _onTextChanged(String v) {
    // Throttle typing emissions to once per 2s.
    if (_typingEmitThrottle?.isActive ?? false) return;
    _typingEmitThrottle = Timer(const Duration(seconds: 2), () {
      _typingEmitThrottle = null;
    });
    _emitTyping(isTyping: v.isNotEmpty);
    if (v.isNotEmpty) {
      // Auto-stop typing indicator after 4s of no new edits.
      _typingStopTimer?.cancel();
      _typingStopTimer = Timer(const Duration(seconds: 4), _stopTyping);
    } else {
      _stopTyping();
    }
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    _emitTyping(isTyping: false);
  }

  void _emitTyping({required bool isTyping}) {
    if (isTyping == _lastEmittedTyping) return; // no-op if no change
    _lastEmittedTyping = isTyping;
    final socket = ref.read(socketServiceProvider);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id ?? '';
    final myName =
        (ref.read(supabaseProvider)?.auth.currentUser?.userMetadata?['name']
                as String?) ??
            'Family member';
    socket.emitGameChatTyping(
      gameTable: widget.gameTable,
      gameId: widget.gameId,
      userId: myId,
      userName: myName,
      isTyping: isTyping,
    );
  }

  @override
  void dispose() {
    _joinRetry?.cancel();
    _typingStopTimer?.cancel();
    _typingEmitThrottle?.cancel();
    _unsubMessage?.call();
    _unsubTyping?.call();
    _unsubConnect?.call();
    ref.read(socketServiceProvider).leaveGameChatRoom(
          gameTable: widget.gameTable,
          gameId: widget.gameId,
        );
    _textCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _typingLabel {
    if (_typingUsers.isEmpty) return '';
    if (_typingUsers.length == 1) {
      final id = _typingUsers.first;
      final name = _typingNames[id] ?? 'Someone';
      return '$name is typing…';
    }
    if (_typingUsers.length == 2) {
      final ids = _typingUsers.toList();
      final n1 = _typingNames[ids[0]] ?? 'Someone';
      final n2 = _typingNames[ids[1]] ?? 'Someone';
      return '$n1 and $n2 are typing…';
    }
    return '${_typingUsers.length} people are typing…';
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    setState(() {
      _userScrolledUp = false;
      _unreadCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final typingLabel = _typingLabel;
    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      margin: const EdgeInsets.only(top: KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border, width: 1),
      ),
      child: Column(
        children: [
          // Header — tap to collapse / expand
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: KinrelColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  Icon(
                    _collapsed
                        ? Icons.expand_more
                        : Icons.chat_bubble_outline,
                    color: KinrelColors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Lobby chat',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Connection status dot
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _socketConnected
                          ? KinrelColors.success
                          : KinrelColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Spacer(),
                  if (_unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: KinrelColors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_unreadCount new',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          color: KinrelColors.textWhite,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Text(
                      '${_messages.length} msgs',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_collapsed) ...[
            // Messages list
            Expanded(
              child: Stack(
                children: [
                  _messages.isEmpty
                      ? Center(
                          child: Text(
                            'Say hi 👋 or send a quick reaction',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              color: KinrelColors.textDim,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: KinrelSpacing.md, vertical: 6),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) =>
                              _messageRow(_messages[i]),
                        ),
                  // "Jump to bottom" pill when there are unread messages
                  if (_unreadCount > 0)
                    Positioned(
                      bottom: 6,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _scrollToBottom,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: KinrelColors.orange,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: KinrelColors.orange
                                      .withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_unreadCount new',
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.monoFont,
                                    fontSize: 10,
                                    color: KinrelColors.textWhite,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_downward,
                                    size: 12, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Typing indicator row
            if (typingLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.only(
                    left: KinrelSpacing.md,
                    top: 2,
                    bottom: 2),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      typingLabel,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            // Emoji bar + text input
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.sm, vertical: 4),
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: KinrelColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  ..._quickEmojis.map((e) => IconButton(
                        icon: Text(e, style: const TextStyle(fontSize: 18)),
                        onPressed: () => _send(type: 'emoji', content: e),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        tooltip: 'Send $e',
                      )),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      onChanged: _onTextChanged,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textWhite,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        hintStyle: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        filled: true,
                        fillColor: KinrelColors.darkCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelRadius.sm),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (v) => _send(type: 'text', content: v),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send,
                        color: KinrelColors.orange, size: 16),
                    onPressed: () =>
                        _send(type: 'text', content: _textCtrl.text),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _messageRow(Map<String, dynamic> msg) {
    final type = (msg['type'] ?? 'text') as String;
    final content = (msg['content'] ?? '') as String;
    final senderName = (msg['senderName'] ?? 'Family member') as String;
    final isSpectator = (msg['isSpectator'] ?? false) as bool;
    final isEmoji = type == 'emoji';
    final timestamp = (msg['timestamp'] ?? '') as String;
    final timeLabel = _formatTime(timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSpectator)
            Container(
              margin: const EdgeInsets.only(top: 2, right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'WATCH',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: isEmoji ? 18 : 12,
                  color: KinrelColors.textWhite,
                ),
                children: [
                  if (!isEmoji)
                    TextSpan(
                      text: '$senderName ',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    ),
                  if (!isEmoji)
                    TextSpan(
                      text: '· ',
                      style: TextStyle(
                        color: KinrelColors.textDim.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  if (!isEmoji && timeLabel.isNotEmpty)
                    TextSpan(
                      text: '$timeLabel  ',
                      style: TextStyle(
                        color: KinrelColors.textDim.withValues(alpha: 0.6),
                        fontSize: 9,
                      ),
                    ),
                  TextSpan(text: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String isoTimestamp) {
    if (isoTimestamp.isEmpty) return '';
    final dt = DateTime.tryParse(isoTimestamp);
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
