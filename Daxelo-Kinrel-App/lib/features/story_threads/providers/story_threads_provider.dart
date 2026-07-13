// lib/features/story_threads/providers/story_threads_provider.dart
//
// P7.4a — Family Story Threads.
// 60-second story prompts about specific family members.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class StoryThread {
  const StoryThread({
    required this.id,
    required this.personId,
    required this.personName,
    required this.prompt,
    required this.createdAt,
    this.audioUrl,
    this.textContent,
    this.authorId,
    this.authorName,
    this.durationSeconds,
  });

  final String id;
  final String personId;
  final String personName;
  final String prompt;
  final DateTime createdAt;
  final String? audioUrl;
  final String? textContent;
  final String? authorId;
  final String? authorName;
  final int? durationSeconds;
}

@immutable
class StoryThreadsState {
  const StoryThreadsState({
    this.threads = const [],
    this.isLoading = false,
    this.error,
  });

  final List<StoryThread> threads;
  final bool isLoading;
  final String? error;

  StoryThreadsState copyWith({
    List<StoryThread>? threads,
    bool? isLoading,
    String? error,
  }) {
    return StoryThreadsState(
      threads: threads ?? this.threads,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class StoryThreadsController extends StateNotifier<StoryThreadsState> {
  StoryThreadsController() : super(const StoryThreadsState());

  void addThread(StoryThread thread) {
    state = state.copyWith(threads: [...state.threads, thread]);
  }

  void removeThread(String id) {
    state = state.copyWith(
      threads: state.threads.where((t) => t.id != id).toList(),
    );
  }
}

final storyThreadsProvider =
    StateNotifierProvider<StoryThreadsController, StoryThreadsState>(
  (ref) => StoryThreadsController(),
);

/// Curated story prompts (NOT AI-generated). Neutral, open-ended.
const List<String> storyPrompts = [
  'Share a memory about a time [person] made you laugh.',
  'What is [person]\'s most memorable quality?',
  'Describe a tradition [person] started in your family.',
  'What lesson did [person] teach you?',
  'Share a story about [person]\'s kindness.',
];
