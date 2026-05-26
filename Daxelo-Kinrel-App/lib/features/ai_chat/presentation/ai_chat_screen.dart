import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/kinrel_icon.dart';
import '../providers/ai_chat_provider.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    ref.read(aiChatSendMessageProvider)(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(aiChatMessagesProvider);
    final isLoading = ref.watch(aiChatLoadingProvider);
    final suggestionsAsync = ref.watch(aiChatSuggestionsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkCard,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: KinrelColors.textWhite, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Row(
          children: [
            KinrelIcon(size: 28),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kinrel AI',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                Text(
                  'Indian Kinship Expert',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: KinrelColors.textSilver.withValues(alpha: 0.7),
                size: 20),
            onPressed: () {
              ref.read(aiChatClearSessionProvider)();
            },
            tooltip: 'Clear chat',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: KinrelColors.darkSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Suggestion Chips ─────────────────────────────────────
          if (messages.isEmpty)
            suggestionsAsync.when(
              data: (suggestions) => _SuggestionChips(
                suggestions: suggestions,
                onTap: (suggestion) {
                  _textController.text = suggestion;
                  ref.read(aiChatSendMessageProvider)(suggestion);
                  _scrollToBottom();
                },
              ),
              loading: () => SizedBox.shrink(),
              error: (_, __) => SizedBox.shrink(),
            ),

          // ── Messages List ────────────────────────────────────────
          Expanded(
            child: messages.isEmpty
                ? _EmptyState(onSuggestionTap: (suggestion) {
                    _textController.text = suggestion;
                    ref.read(aiChatSendMessageProvider)(suggestion);
                    _scrollToBottom();
                  })
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base,
                      vertical: KinrelSpacing.md,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _ChatBubble(
                        message: msg,
                        isUser: msg.isUser,
                      );
                    },
                  ),
          ),

          // ── Typing Indicator ─────────────────────────────────────
          if (isLoading) const _TypingIndicator(),

          // ── Input Bar ────────────────────────────────────────────
          _InputBar(
            controller: _textController,
            focusNode: _focusNode,
            onSend: _sendMessage,
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────────────

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.onSuggestionTap});

  final void Function(String) onSuggestionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(aiChatSuggestionsProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.xxxl,
          vertical: KinrelSpacing.xxl,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.purple.withValues(alpha: 0.1),
                border: Border.all(
                  color: KinrelColors.purple.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: KinrelColors.purple,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Ask me about Indian\nkinship terms',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'I can help you understand family\nrelationships in 15 Indian languages',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textDim,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            suggestionsAsync.when(
              data: (suggestions) => Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: suggestions
                    .take(4)
                    .map((s) => _SuggestionChip(
                          text: s,
                          onTap: () => onSuggestionTap(s),
                        ))
                    .toList(),
              ),
              loading: () => SizedBox.shrink(),
              error: (_, __) => SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Suggestion Chips Row ─────────────────────────────────────────────

class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({
    required this.suggestions,
    required this.onTap,
  });

  final List<String> suggestions;
  final void Function(String) onTap;


  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => SizedBox(width: 8),
        itemBuilder: (context, index) {
          return _SuggestionChip(
            text: suggestions[index],
            onTap: () => onTap(suggestions[index]),
          );
        },
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: KinrelColors.purple.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: KinrelColors.textSilver,
          ),
        ),
      ),
    );
  }
}

// ── Chat Bubble ──────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isUser});

  final ChatMessage message;
  final bool isUser;


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: KinrelSpacing.md),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? KinrelColors.purple
                  : KinrelColors.darkCard,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: isUser
                    ? Radius.circular(16)
                    : Radius.circular(4),
                bottomRight: isUser
                    ? Radius.circular(4)
                    : Radius.circular(16),
              ),
              border: isUser
                  ? null
                  : Border.all(
                      color: KinrelColors.darkSurface.withValues(alpha: 0.6),
                    ),
              boxShadow: isUser
                  ? [
                      BoxShadow(
                        color:
                            KinrelColors.purple.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: KinrelColors.purple.withValues(alpha: 0.8),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Kinrel AI',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.purple.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                if (!isUser) const SizedBox(height: 6),
                Text(
                  message.content,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: isUser ? Colors.white : KinrelColors.textWhite,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Kinship cards
          if (message.kinshipData != null &&
              message.kinshipData!.isNotEmpty)
            ...message.kinshipData!.map(
              (k) => _KinshipCard(data: k),
            ),

          // Timestamp
          Padding(padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
            child: Text(
              _formatTime(message.timestamp),
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                color: KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

// ── Kinship Card ─────────────────────────────────────────────────────

class _KinshipCard extends StatelessWidget {
  const _KinshipCard({required this.data});

  final KinshipCardData data;


  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KinrelColors.amber.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.amber.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.amber.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.family_restroom_rounded,
                  color: KinrelColors.amber,
                  size: 16,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column (
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.englishTerm,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Text(
                      data.relationshipKey.replaceAll('_', ' '),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              // Gender badge
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: data.gender == 'male'
                      ? KinrelColors.info.withValues(alpha: 0.12)
                      : data.gender == 'female'
                          ? KinrelColors.holiPink.withValues(alpha: 0.12)
                          : KinrelColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  data.gender.toUpperCase(),
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: data.gender == 'male'
                        ? KinrelColors.info
                        : data.gender == 'female'
                            ? KinrelColors.holiPink
                            : KinrelColors.amber,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Lineage & Category row
          Row(
            children: [
              _InfoBadge(
                label: data.lineage,
                color: KinrelColors.purple,
              ),
              SizedBox(width: 8),
              _InfoBadge(
                label: data.relationshipCategory.replaceAll('_', ' '),
                color: KinrelColors.ember,
              ),
            ],
          ),
    // Translations
          if (data.translations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'TRANSLATIONS',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textDim,
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: data.translations.entries.take(4).map((entry) {
                return Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkSurface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: KinrelColors.darkSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.purple,
                          letterSpacing: 0.3,
                        ),),
                      SizedBox(width: 6),
                      Text(
                        entry.value.native,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label, required this.color});

  final String label;
  final Color color;


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

// ── Typing Indicator ─────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: 4,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: KinrelColors.darkSurface.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: KinrelColors.purple.withValues(alpha: 0.8),
                  size: 14,
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (index) {
                        final progress =
                            (_controller.value * 3 - index) % 1.0;
                        final scale = 0.5 + 0.5 * (1 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: KinrelColors.purple
                                    .withValues(alpha: 0.4 + 0.6 * scale),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input Bar ────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.isLoading,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool isLoading;


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          top: BorderSide(
            color: KinrelColors.darkSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: KinrelColors.darkSurface.withValues(alpha: 0.6),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textWhite,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask about kinship terms...',
                    hintStyle: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textDim,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  enabled: !isLoading,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: isLoading ? null : onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isLoading
                      ? null
                      : const LinearGradient(
                          colors: [KinrelColors.purple, KinrelColors.violet],
                        ),
                  color: isLoading
                      ? KinrelColors.darkSurface
                      : null,
                  boxShadow: isLoading
                      ? null
                      : [
                          BoxShadow(
                            color: KinrelColors.purple
                                .withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KinrelColors.textDim,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
