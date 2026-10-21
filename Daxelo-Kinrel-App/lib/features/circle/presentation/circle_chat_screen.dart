// lib/features/circle/presentation/circle_chat_screen.dart
//
// DAXELO KINREL — Circle Conversation Screen (Phase 3 — mockup 10)
//
// The circle conversation screen. Reuses the existing visual language
// (dark cards, orange accents, Ignite gradient) + the existing message
// bubble + composer patterns from chat_screen.dart, but purpose-built
// for circles (keyed by circleId, not familyId).
//
// States:
//   • Loading — spinner
//   • Active — message list + composer + pinned bar
//   • Only admins can post — disabled composer with a clear message
//   • Removed — "You are no longer in this circle" friendly state
//   • Error — retry button
//
// Header: icon tile (rounded-square), circle name, subtitle "{n} people",
// info button (→ CircleInfoScreen, Phase 3 follow-up).
//
// Sender labels: the senderName field (snapshotted at send time) is
// used for Phase 3. The kinship-term resolution (Phase 0 Sub-option 1:
// resolve against the viewer's primary family, fall back to the name)
// is a follow-up enhancement that requires the precomputed
// kinshipTermsForFamilyProvider map for each sender's family.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/haptic_service.dart';
import '../providers/circle_chat_provider.dart';

class CircleChatScreen extends ConsumerStatefulWidget {
  const CircleChatScreen({
    super.key,
    required this.circleId,
  });

  final String circleId;

  @override
  ConsumerState<CircleChatScreen> createState() => _CircleChatScreenState();
}

class _CircleChatScreenState extends ConsumerState<CircleChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 100) {
      ref.read(circleChatProvider(widget.circleId).notifier).loadMore();
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    HapticService.tap();
    setState(() => _isSending = true);

    final success = await ref
        .read(circleChatProvider(widget.circleId).notifier)
        .sendMessage(content: content);

    if (success && mounted) {
      _messageController.clear();
    }
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(circleChatProvider(widget.circleId));

    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: _buildAppBar(chatState),
      body: !chatState.isMember
          ? _buildRemovedState()
          : chatState.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: KinrelColors.orange),
                )
              : chatState.error != null && chatState.messages.isEmpty
                  ? _buildErrorState(chatState.error!)
                  : Column(
                      children: [
                        // Pinned message bar
                        if (chatState.pinnedMessage != null)
                          _buildPinnedBar(chatState.pinnedMessage!),
                        // Message list
                        Expanded(child: _buildMessageList(chatState)),
                        // Composer
                        _buildComposer(chatState),
                      ],
                    ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(CircleChatState chatState) {
    return AppBar(
      backgroundColor: KinrelColors.darkBackground,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: KinrelColors.textWhite),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          // Rounded-square icon tile
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: KinrelGradients.igniteGradient,
            ),
            child: const Icon(Icons.group_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chatState.circleName ?? 'Circle',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${chatState.memberCount} ${chatState.memberCount == 1 ? 'person' : 'people'}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline_rounded,
              color: KinrelColors.textSilver, size: 22),
          onPressed: () {
            // Phase 3 follow-up: push to CircleInfoScreen
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Circle info screen — coming soon.'),
                backgroundColor: KinrelColors.darkCard,
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Pinned message bar ──────────────────────────────────────────

  Widget _buildPinnedBar(CircleChatMessage msg) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, size: 14, color: KinrelColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg.content.isNotEmpty
                  ? msg.content
                  : '${msg.messageType.toUpperCase()} message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Message list ────────────────────────────────────────────────

  Widget _buildMessageList(CircleChatState chatState) {
    final client = Supabase.instance.client;
    final myUserId = client.auth.currentUser?.id;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: 8),
      itemCount: chatState.messages.length +
          (chatState.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == chatState.messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: KinrelColors.orange,
                ),
              ),
            ),
          );
        }
        // Reverse index (newest at bottom = reversed list)
        final msgIndex = chatState.messages.length - 1 - index;
        final msg = chatState.messages[msgIndex];
        final isMe = msg.senderId == myUserId;

        return _MessageBubble(
          message: msg,
          isMe: isMe,
        );
      },
    );
  }

  // ── Composer ────────────────────────────────────────────────────

  Widget _buildComposer(CircleChatState chatState) {
    // Disabled composer when onlyAdminsPost && non-admin
    if (chatState.onlyAdminsPost && chatState.myRole != 'admin') {
      return Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 18, color: KinrelColors.textDim),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Only admins can post in this circle',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        left: KinrelSpacing.base,
        right: KinrelSpacing.base,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: KinrelColors.textSilver, size: 24),
              onPressed: () {
                // Phase 3 follow-up: attachment picker
              },
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite,
                ),
                decoration: InputDecoration(
                  hintText: 'Message ${chatState.circleName ?? 'circle'}',
                  hintStyle: const TextStyle(color: KinrelColors.textDim),
                  filled: true,
                  fillColor: KinrelColors.darkElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  isDense: true,
                ),
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                _isSending ? Icons.hourglass_top_rounded : Icons.send_rounded,
                color: KinrelColors.orange,
                size: 24,
              ),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  // ── Removed member state ───────────────────────────────────────

  Widget _buildRemovedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_off_rounded,
                size: 56, color: KinrelColors.textDim),
            const SizedBox(height: 16),
            const Text(
              'You are no longer in this circle',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can no longer see messages or send new ones.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to chats'),
              style: FilledButton.styleFrom(
                backgroundColor: KinrelColors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: KinrelColors.error),
            const SizedBox(height: 12),
            Text(error,
                style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => ref
                  .invalidate(circleChatProvider(widget.circleId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Message bubble — simple but matches the existing visual language
// ═══════════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe});

  final CircleChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final isDeleted = message.isDeletedForEveryone;
    final isPhoto = message.messageType == 'photo';
    final isVoice = message.messageType == 'voiceNote';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: KinrelColors.darkElevated,
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.orange,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Sender label (not shown for own messages)
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      message.senderName,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
                // Bubble
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? KinrelColors.orange
                        : KinrelColors.darkCard,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: isDeleted
                      ? Text(
                          'This message was deleted',
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.6)
                                : KinrelColors.textDim,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : isVoice
                          ? _buildVoiceBubble()
                          : isPhoto && message.mediaUrl != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        message.mediaUrl!,
                                        width: 200,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox(height: 100),
                                      ),
                                    ),
                                    if (message.content.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        message.content,
                                        style: TextStyle(
                                          fontFamily: KinrelTypography.bodyFont,
                                          fontSize: 14,
                                          color: isMe
                                              ? Colors.white
                                              : KinrelColors.textWhite,
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : Text(
                                  message.content,
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 14,
                                    color: isMe
                                        ? Colors.white
                                        : KinrelColors.textWhite,
                                  ),
                                ),
                ),
                // Timestamp
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 10,
                      color: KinrelColors.textDim,
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

  Widget _buildVoiceBubble() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.play_arrow_rounded,
          size: 20,
          color: isMe ? Colors.white : KinrelColors.orange,
        ),
        const SizedBox(width: 8),
        Container(
          width: 80,
          height: 20,
          child: CustomPaint(
            painter: _SimpleWaveformPainter(
              color: isMe ? Colors.white : KinrelColors.orange,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${message.voiceMessageDuration ?? 0}s',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            color: isMe ? Colors.white : KinrelColors.textSilver,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
}

/// Simple decorative waveform for voice messages.
class _SimpleWaveformPainter extends CustomPainter {
  _SimpleWaveformPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final barWidth = 2.0;
    final gap = 3.0;
    final bars = (size.width / (barWidth + gap)).floor();

    for (int i = 0; i < bars; i++) {
      final x = i * (barWidth + gap);
      final height = 4.0 + (i % 3) * 6.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, size.height / 2),
            width: barWidth,
            height: height,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleWaveformPainter old) =>
      old.color != color;
}
