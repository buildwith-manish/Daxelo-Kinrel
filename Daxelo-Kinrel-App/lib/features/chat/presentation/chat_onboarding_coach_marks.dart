// lib/features/chat/presentation/chat_onboarding_coach_marks.dart
//
// DAXELO KINREL — Feature 7: Chat Onboarding Coach Marks
//
// A lightweight tooltip/coach-mark sequence shown ONCE after a user sends
// their FIRST message ever in any chat. Highlights:
//   1. Streaks (🔥 badge in the header)
//   2. Reactions (long-press a message to react)
//   3. Voice notes (hold-to-record button)
//
// The sequence is skippable (a "Skip" button on each coach mark) + shown
// only once (the hasSeenChatOnboarding flag is persisted in SharedPreferences).
//
// Trigger: the chat_screen watches the first_message_in_chat analytics
// event (Feature 1). When the user's first message is sent, the onboarding
// sequence is triggered. The analytics event is the source of truth —
// NOT a hardcoded screen count — so the onboarding is driven by real usage.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The coach-mark steps. Each step highlights a different feature.
enum ChatOnboardingStep {
  streaks,
  reactions,
  voiceNotes,
}

extension ChatOnboardingStepX on ChatOnboardingStep {
  String get title {
    switch (this) {
      case ChatOnboardingStep.streaks:
        return 'Chat Streaks 🔥';
      case ChatOnboardingStep.reactions:
        return 'Reactions';
      case ChatOnboardingStep.voiceNotes:
        return 'Voice Notes';
    }
  }

  String get description {
    switch (this) {
      case ChatOnboardingStep.streaks:
        return 'Message your family daily to build a streak. '
            'The flame badge in the header shows your current streak — '
            'don\'t break the chain!';
      case ChatOnboardingStep.reactions:
        return 'Long-press any message to react with an emoji. '
            'Reactions appear under the message for everyone to see.';
      case ChatOnboardingStep.voiceNotes:
        return 'Hold the mic button to record a voice note. '
            'Release to send, or swipe to cancel. Voice notes play inline.';
    }
  }

  IconData get icon {
    switch (this) {
      case ChatOnboardingStep.streaks:
        return Icons.local_fire_department;
      case ChatOnboardingStep.reactions:
        return Icons.emoji_emotions_outlined;
      case ChatOnboardingStep.voiceNotes:
        return Icons.mic;
    }
  }
}

/// SharedPreferences key for the hasSeenChatOnboarding flag.
const _kHasSeenChatOnboardingKey = 'hasSeenChatOnboarding';

/// Riverpod provider that exposes whether the onboarding has been seen.
/// The chat_screen watches this + triggers the onboarding when the
/// first_message_in_chat analytics event fires AND this is false.
final hasSeenChatOnboardingProvider = StateProvider<bool>((ref) {
  // Loaded asynchronously in main.dart; default to false until loaded.
  return false;
});

/// Load the hasSeenChatOnboarding flag from SharedPreferences at app start.
/// Called from main.dart.
Future<void> loadHasSeenChatOnboarding(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getBool(_kHasSeenChatOnboardingKey) ?? false;
  ref.read(hasSeenChatOnboardingProvider.notifier).state = seen;
}

/// Mark the onboarding as seen (persisted to SharedPreferences).
/// Called after the user completes or skips the onboarding.
///
/// QA fix 2026-09-19: the only call site is the ConsumerState's `_complete`
/// which passes its `WidgetRef` — the previous `Ref` parameter made the call
/// a compile error (argument_type_not_assignable). WidgetRef is the correct
/// type for widget-level ref access.
Future<void> markChatOnboardingSeen(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kHasSeenChatOnboardingKey, true);
  ref.read(hasSeenChatOnboardingProvider.notifier).state = true;
}

/// The coach-mark overlay widget. Shown as a modal overlay on top of the
/// chat screen. Steps through [steps] one at a time with Next/Skip buttons.
class ChatOnboardingCoachMarks extends ConsumerStatefulWidget {
  const ChatOnboardingCoachMarks({
    super.key,
    required this.onComplete,
  });

  /// Called when the user completes the sequence (or skips).
  final VoidCallback onComplete;

  @override
  ConsumerState<ChatOnboardingCoachMarks> createState() =>
      _ChatOnboardingCoachMarksState();
}

class _ChatOnboardingCoachMarksState
    extends ConsumerState<ChatOnboardingCoachMarks> {
  int _currentIndex = 0;
  static const _steps = ChatOnboardingStep.values;

  void _next() {
    if (_currentIndex < _steps.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      _complete();
    }
  }

  void _skip() {
    _complete();
  }

  void _complete() {
    markChatOnboardingSeen(ref).then((_) {
      widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentIndex];
    final isLast = _currentIndex == _steps.length - 1;

    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Step indicator ───────────────────────────────────────
              Text(
                'Step ${_currentIndex + 1} of ${_steps.length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              // ── Icon in a circle ─────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE8612A).withValues(alpha: 0.15),
                  border: Border.all(
                    color: const Color(0xFFE8612A).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  step.icon,
                  size: 32,
                  color: const Color(0xFFE8612A),
                ),
              ),
              const SizedBox(height: 20),

              // ── Title ────────────────────────────────────────────────
              Text(
                step.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // ── Description ─────────────────────────────────────────
              Text(
                step.description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Buttons ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _skip,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8612A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(isLast ? 'Got it' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
