// lib/features/games/shared/widgets/lobby_chat_panel.dart
//
// Lightweight chat / emoji-reaction panel for any game's lobby.
// Uses the existing Socket.IO connection (SocketService) — no persistence.
// Messages are ephemeral, scoped to the lobby's (gameTable, gameId) room.
//
// Features:
//   • 4 quick-tap emoji reactions (👍 😂 🔥 👋)
//   • Optional short text input
//   • Spectator vs. player badge on each message
//   • Auto-joins the chat room on mount, auto-leaves on dispose
//
// Usage in any lobby:
//   LobbyChatPanel(
//     gameTable: 'bingo_games',
//     gameId: state.game!.id,
//     familyId: widget.familyId,
//     isSpectator: false,
//   )

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
    this.maxHeight = 220,
  });

  final String gameTable; // e.g. 'bingo_games', 'redlight_rounds'
  final String gameId;
  final String familyId;
  final bool isSpectator;
  final double maxHeight;

  @override
  ConsumerState<LobbyChatPanel> createState() => _LobbyChatPanelState();
}

class _LobbyChatPanelState extends ConsumerState<LobbyChatPanel> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  VoidCallback? _unsub;
  Timer? _joinRetry;

  static const _quickEmojis = ['👍', '😂', '🔥', '👋'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    final socket = ref.read(socketServiceProvider);
    _unsub = socket.onGameChatMessage(_onMessage);
    socket.joinGameChatRoom(
      gameTable: widget.gameTable,
      gameId: widget.gameId,
    );
    // Retry join after 2s in case socket wasn't connected yet
    _joinRetry = Timer(const Duration(seconds: 2), () {
      ref.read(socketServiceProvider).joinGameChatRoom(
            gameTable: widget.gameTable,
            gameId: widget.gameId,
          );
    });
  }

  void _onMessage(Map<String, dynamic> msg) {
    // Filter to this room (the socket broadcasts to all subscribers)
    if (msg['gameTable'] != widget.gameTable || msg['gameId'] != widget.gameId) {
      return;
    }
    if (!mounted) return;
    setState(() => _messages.add(msg));
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
    // Cap at 50 messages to avoid memory bloat
    if (_messages.length > 50) {
      setState(() => _messages.removeRange(0, _messages.length - 50));
    }
  }

  Future<void> _send({required String type, required String content}) async {
    if (content.trim().isEmpty) return;
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
        content: content.trim(),
        senderName: myName,
        isSpectator: widget.isSpectator,
      );
      // Sender doesn't echo locally — the server broadcasts back to everyone
      // in the room including us, so the message will appear via _onMessage.
    } catch (_) {}
    if (type == 'text') _textCtrl.clear();
  }

  @override
  void dispose() {
    _joinRetry?.cancel();
    _unsub?.call();
    ref.read(socketServiceProvider).leaveGameChatRoom(
          gameTable: widget.gameTable,
          gameId: widget.gameId,
        );
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: KinrelColors.border, width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline,
                    color: KinrelColors.orange, size: 14),
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
                const Spacer(),
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
          // Messages list
          Expanded(
            child: _messages.isEmpty
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
                    itemBuilder: (_, i) => _messageRow(_messages[i]),
                  ),
          ),
          // Emoji bar
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.sm, vertical: 4),
            decoration: const BoxDecoration(
              border:
                  Border(top: BorderSide(color: KinrelColors.border, width: 1)),
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
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Send',
                ),
              ],
            ),
          ),
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
                      text: '$senderName: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
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
}
