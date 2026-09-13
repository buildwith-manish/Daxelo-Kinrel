// lib/features/games/shared/widgets/lobby_chat_panel.dart
//
// Lightweight chat / emoji-reaction panel for any game's lobby.
// Uses the existing Socket.IO connection (SocketService) for live chat
// messages AND subscribes to game_room_events for system messages
// (join/leave/ready/cancel/auto_close) so they're interleaved with chat.
//
// Features:
//   • 4 quick-tap emoji reactions (👍 😂 🔥 👋)
//   • Optional short text input
//   • Spectator vs. player badge on each message
//   • System messages rendered italicized (e.g. "John joined the room.")
//   • Auto-joins the chat room on mount, auto-leaves on dispose
//   • Persists chat messages via fn_post_room_chat RPC so reconnects
//     restore history (no more ephemeral-only messages)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  /// Unified message list: chat messages from Socket.IO + system events
  /// from game_room_events (via Supabase Realtime). Each entry has a
  /// 'kind' field ('chat' | 'system') so we can render them differently.
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  VoidCallback? _unsub;
  Timer? _joinRetry;
  Timer? _historyLoadRetry;
  RealtimeChannel? _eventsChannel;

  static const _quickEmojis = ['👍', '😂', '🔥', '👋'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attach();
      _loadHistory();
      _subscribeToRoomEvents();
    });
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

  /// Load persisted chat + system events from the server so reconnects
  /// restore history. Single RPC call to fn_get_room_state.
  Future<void> _loadHistory() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final result = await client.rpc('fn_get_room_state', params: {
        'p_game_table': widget.gameTable,
        'p_game_id': widget.gameId,
      });
      if (result is! Map) return;
      final events = result['events'];
      if (events is! List) return;
      if (!mounted) return;
      setState(() {
        _messages.clear();
        for (final e in events) {
          final map = Map<String, dynamic>.from(e as Map);
          final eventType = (map['eventType'] ?? 'system') as String;
          if (eventType == 'chat') {
            final payload = map['payload'] is Map
                ? Map<String, dynamic>.from(map['payload'] as Map)
                : <String, dynamic>{};
            _messages.add({
              'kind': 'chat',
              'type': payload['chatType'] ?? 'text',
              'content': payload['content'] ?? '',
              'senderName': map['userName'] ?? 'Family member',
              'isSpectator': payload['isSpectator'] == true,
              'timestamp': map['createdAt'],
            });
          } else {
            _messages.add({
              'kind': 'system',
              'eventType': eventType,
              'userName': map['userName'],
              'payload': map['payload'] ?? {},
              'timestamp': map['createdAt'],
            });
          }
        }
      });
      _scrollToBottom();
    } catch (e) {
      // Best-effort history load — don't surface to user.
      debugPrint('[LobbyChatPanel] history load failed (non-fatal): $e');
    }
  }

  void _subscribeToRoomEvents() {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    _eventsChannel?.unsubscribe();
    _eventsChannel = client
        .channel('room_events:${widget.gameTable}:${widget.gameId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_room_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: widget.gameId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            final eventType = (record['eventType'] ?? 'system') as String;
            final userName = record['userName'] as String?;
            final payloadMap = record['payload'] is Map
                ? Map<String, dynamic>.from(record['payload'] as Map)
                : <String, dynamic>{};
            if (eventType == 'chat') {
              _onMessage({
                'gameTable': widget.gameTable,
                'gameId': widget.gameId,
                'type': payloadMap['chatType'] ?? 'text',
                'content': payloadMap['content'] ?? '',
                'senderName': userName ?? 'Family member',
                'isSpectator': payloadMap['isSpectator'] == true,
                'timestamp': record['createdAt'],
              });
            } else {
              if (!mounted) return;
              setState(() {
                _messages.add({
                  'kind': 'system',
                  'eventType': eventType,
                  'userName': userName,
                  'payload': payloadMap,
                  'timestamp': record['createdAt'],
                });
              });
              _scrollToBottom();
              if (_messages.length > 50) {
                setState(() => _messages.removeRange(0, _messages.length - 50));
              }
            }
          },
        )
        .subscribe();
  }

  void _onMessage(Map<String, dynamic> msg) {
    // Filter to this room (the socket broadcasts to all subscribers)
    if (msg['gameTable'] != widget.gameTable || msg['gameId'] != widget.gameId) {
      return;
    }
    if (!mounted) return;
    // Dedup: if we already have a message with the same content + sender +
    // timestamp (within 1s), skip it. The persisted copy from
    // game_room_events may arrive slightly before/after the socket copy.
    final timestamp = msg['timestamp'];
    final sender = msg['senderName'];
    final content = msg['content'];
    final alreadyExists = _messages.any((m) =>
        m['kind'] == 'chat' &&
        m['senderName'] == sender &&
        m['content'] == content &&
        (timestamp == null || m['timestamp'] == timestamp));
    if (alreadyExists) return;

    setState(() {
      _messages.add({
        ...msg,
        'kind': 'chat',
      });
    });
    _scrollToBottom();
    if (_messages.length > 50) {
      setState(() => _messages.removeRange(0, _messages.length - 50));
    }
  }

  void _scrollToBottom() {
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

  Future<void> _send({required String type, required String content}) async {
    if (content.trim().isEmpty) return;
    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id ?? '';
    final myName =
        (client?.auth.currentUser?.userMetadata?['name'] as String?) ??
            'Family member';
    try {
      // Persist via RPC (so reconnects restore it) — this INSERT triggers
      // the realtime fan-out to all subscribers, including us.
      await client?.rpc('fn_post_room_chat', params: {
        'p_game_table': widget.gameTable,
        'p_game_id': widget.gameId,
        'p_family_id': widget.familyId,
        'p_user_id': myId,
        'p_user_name': myName,
        'p_content': content.trim(),
        'p_is_spectator': widget.isSpectator,
        'p_chat_type': type,
      });
    } catch (e) {
      // Fallback: send via socket only (won't persist on reconnect)
      try {
        final socket = ref.read(socketServiceProvider);
        await socket.sendGameChatMessage(
          gameTable: widget.gameTable,
          gameId: widget.gameId,
          familyId: widget.familyId,
          type: type,
          content: content.trim(),
          senderName: myName,
          isSpectator: widget.isSpectator,
        );
      } catch (_) {}
    }
    if (type == 'text') _textCtrl.clear();
  }

  @override
  void dispose() {
    _joinRetry?.cancel();
    _historyLoadRetry?.cancel();
    _unsub?.call();
    _eventsChannel?.unsubscribe();
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
    final kind = (msg['kind'] ?? 'chat') as String;

    // ── System message (join / leave / ready / cancel / auto_close) ──
    if (kind == 'system') {
      final eventType = (msg['eventType'] ?? 'system') as String;
      final userName = (msg['userName'] ?? 'Someone') as String;
      final payload = msg['payload'] is Map
          ? Map<String, dynamic>.from(msg['payload'] as Map)
          : <String, dynamic>{};
      final text = _formatSystemMessage(eventType, userName, payload);
      if (text == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // ── Chat message ────────────────────────────────────────────────
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

  /// Format a system event as a human-readable italic message.
  String? _formatSystemMessage(
      String eventType, String userName, Map<String, dynamic> payload) {
    switch (eventType) {
      case 'join':
        return '$userName joined the room.';
      case 'leave':
        final wasHost = payload['wasHost'] == true;
        final reason = payload['reason'];
        if (reason == 'disconnected') {
          return '$userName disconnected.';
        }
        return wasHost
            ? '$userName (host) left the room.'
            : '$userName left the room.';
      case 'spectator_join':
        return '$userName is now watching.';
      case 'spectator_leave':
        return '$userName stopped watching.';
      case 'ready':
        return '$userName is ready.';
      case 'not_ready':
        return '$userName is not ready.';
      case 'cancel':
        return 'Room closed by host.';
      case 'auto_close':
        return 'Room auto-closed (time expired).';
      default:
        return null;
    }
  }
}
