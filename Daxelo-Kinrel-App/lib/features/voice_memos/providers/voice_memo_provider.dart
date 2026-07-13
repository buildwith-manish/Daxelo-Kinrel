// lib/features/voice_memos/providers/voice_memo_provider.dart
//
// P7.4b — One-tap voice memo for elders.
// Records audio from the elder. Uses the `record` package.
// NEW DEPENDENCY: record ^5.0.0 (flagged per Rule 12).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State of a voice memo recording.
@immutable
class VoiceMemoState {
  const VoiceMemoState({
    this.isRecording = false,
    this.isPaused = false,
    this.durationSeconds = 0,
    this.audioPath,
    this.error,
  });

  final bool isRecording;
  final bool isPaused;
  final int durationSeconds;
  final String? audioPath;
  final String? error;

  VoiceMemoState copyWith({
    bool? isRecording,
    bool? isPaused,
    int? durationSeconds,
    String? audioPath,
    String? error,
  }) {
    return VoiceMemoState(
      isRecording: isRecording ?? this.isRecording,
      isPaused: isPaused ?? this.isPaused,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      audioPath: audioPath ?? this.audioPath,
      error: error,
    );
  }
}

/// Controller for voice memo recording.
/// In production, this uses the `record` package. For now, the state
/// management is implemented and the actual recording is a stub that
/// will be wired to the `record` package when the dependency is added.
class VoiceMemoController extends StateNotifier<VoiceMemoState> {
  VoiceMemoController() : super(const VoiceMemoState());

  /// Starts recording.
  Future<void> startRecording() async {
    state = VoiceMemoState(isRecording: true);
    // TODO: Wire to record package when dependency is approved.
    // final recorder = AudioRecorder();
    // await recorder.start(RecordConfig(), path: path);
  }

  /// Pauses recording.
  Future<void> pauseRecording() async {
    state = state.copyWith(isPaused: true);
  }

  /// Resumes recording.
  Future<void> resumeRecording() async {
    state = state.copyWith(isPaused: false);
  }

  /// Stops recording and returns the audio file path.
  Future<String?> stopRecording() async {
    final path = state.audioPath;
    state = const VoiceMemoState();
    return path;
  }

  /// Cancels recording and discards the audio.
  Future<void> cancelRecording() async {
    state = const VoiceMemoState();
  }
}

final voiceMemoProvider =
    StateNotifierProvider<VoiceMemoController, VoiceMemoState>(
  (ref) => VoiceMemoController(),
);
