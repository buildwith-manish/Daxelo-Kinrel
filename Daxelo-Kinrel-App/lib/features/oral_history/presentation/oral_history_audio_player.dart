// lib/features/oral_history/presentation/oral_history_audio_player.dart
//
// DAXELO KINREL — Oral History Audio Player
//
// v93 (transcription removal + recording/playback correctness):
// Real audio playback via `just_audio` — replaces the previous fake
// Timer-based "playback" that simulated progress with no actual audio
// streaming. This widget:
//
//   - Streams the actual stored audio file from `story.audioUrl`
//     (the public Supabase Storage URL of the uploaded .m4a file).
//   - Discovers the REAL duration via just_audio's `durationStream`
//     (replaces the hardcoded `story.audioDuration` value that was
//     a guess for legacy/demo rows).
//   - Tracks the REAL position via `positionStream` for the seek bar
//     and the time labels (M:SS / M:SS).
//   - Surfaces a buffering/loading state when the audio is loading
//     or when the network is intermittent, so the user sees a clear
//     "loading..." state instead of a broken player.
//   - Surfaces a clear error state with a retry button if the audio
//     URL can't be loaded (e.g., 404, network down).
//   - Auto-increments the story's play count via the notifier when
//     playback starts (the notifier persists this to AncestralMemory).
//   - Cleans up the AudioPlayer on dispose (releases the underlying
//     resource).
//
// The waveform visualization uses `story.effectiveWaveformData` — for
// real recordings this is populated from the `record` package's
// onAmplitudeChanged stream during recording (REAL amplitudes). For
// legacy/demo rows without real amplitude data, the waveform is a
// clearly-decorative deterministic fallback (no claim that it
// represents the actual audio).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/theme/kinrel_fx.dart';
import '../providers/oral_history_provider.dart';

/// Real audio player for oral history stories.
///
/// Constructed with a [StoryModel] that has a non-null `audioUrl`. The
/// player streams the audio from that URL using `just_audio` and
/// surfaces real duration/position/loading/error state.
///
/// The widget is self-contained — it manages its own AudioPlayer
/// instance and disposes it on widget dispose. Callers should NOT
/// reuse the same AudioPlayer across stories.
class OralHistoryAudioPlayer extends ConsumerStatefulWidget {
  const OralHistoryAudioPlayer({
    super.key,
    required this.story,
    this.compact = false,
  });

  /// The story to play. Must have a non-null `audioUrl` for real
  /// playback. If `audioUrl` is null (legacy/demo row), the player
  /// shows a clear "Audio not available" state instead of attempting
  /// to play nothing.
  final StoryModel story;

  /// Compact mode: hides the rewind/forward buttons and the speed
  /// control, used by the StoryCard preview. Full mode (default)
  /// shows the complete player UI in the StoryDetailPlayer.
  final bool compact;

  @override
  ConsumerState<OralHistoryAudioPlayer> createState() =>
      _OralHistoryAudioPlayerState();
}

class _OralHistoryAudioPlayerState
    extends ConsumerState<OralHistoryAudioPlayer> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playCounted = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    // Use the recorded duration as a hint before the real duration
    // is discovered. just_audio will replace this with the actual
    // file duration via durationStream once the file loads.
    _duration = widget.story.audioDuration;

    _setupAudio();
    _listenToPlayer();
  }

  Future<void> _setupAudio() async {
    final url = widget.story.audioUrl;
    if (url == null || url.isEmpty) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Audio not available for this story. This may be a demo '
              'or legacy recording that was never uploaded.';
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    try {
      await _player.setUrl(url);
      // After loading, the actual duration is reported via
      // durationStream listener (see _listenToPlayer).
    } catch (e) {
      debugPrint('⚠️ OralHistoryAudioPlayer setUrl failed: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Could not load audio. Please check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenToPlayer() {
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      switch (state.processingState) {
        case ProcessingState.idle:
        case ProcessingState.loading:
          setState(() => _isLoading = true);
          break;
        case ProcessingState.buffering:
          // Keep the play/pause button tappable during buffering, but
          // also show a loading indicator alongside the play icon.
          setState(() => _isLoading = true);
          break;
        case ProcessingState.ready:
          setState(() {
            _isLoading = false;
            _isPlaying = state.playing;
          });
          break;
        case ProcessingState.completed:
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
          // Reset to start so the user can play again.
          _player.seek(Duration.zero);
          break;
      }
    });

    _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });

    _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      // v93: this is the REAL duration of the actual stored file,
      // discovered by just_audio after the file loads. Replaces the
      // recorded-duration hint that was used before loading.
      setState(() => _duration = d);
    });
  }

  Future<void> _togglePlay() async {
    if (_hasError) {
      // Try reloading
      await _setupAudio();
      if (_hasError) return;
    }
    if (_isPlaying) {
      await _player.pause();
    } else {
      // Increment play count on first play (only once per widget
      // instance — re-mounting the player for the same story will
      // count again, which matches the "Played Nx" semantics).
      if (!_playCounted) {
        _playCounted = true;
        // Best-effort: don't await — the user wants to start playback
        // immediately, the play-count persistence is a side effect.
        final future = ref
            .read(oralHistoryProvider.notifier)
            .incrementPlayCount(widget.story.id);
        unawaited(future);
      }
      try {
        await _player.play();
      } catch (e) {
        debugPrint('⚠️ OralHistoryAudioPlayer play failed: $e');
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Playback failed. Please try again.';
          });
        }
      }
    }
  }

  /// Seek to a fraction of the total duration (0.0 – 1.0).
  Future<void> _seekToFraction(double fraction) async {
    if (_duration.inMilliseconds == 0) return;
    final target = Duration(
      milliseconds: (fraction * _duration.inMilliseconds).toInt(),
    );
    await _player.seek(target);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final waveform = story.effectiveWaveformData;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    // ── Error state ──────────────────────────────────────────────────
    if (_hasError) {
      return Container(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: KinrelColors.coral.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: KinrelColors.coral,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage ?? 'Audio not available.',
                style: KinrelTypography.bodySmall.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = null;
                });
                _setupAudio();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
                child: Text(
                  'Retry',
                  style: KinrelTypography.labelSmall.copyWith(
                    color: KinrelColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Main player UI ───────────────────────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Waveform with seek ──────────────────────────────────────
        GestureDetector(
          onTapDown: (details) {
            final localPos = details.localPosition;
            final waveWidth = localPos.dx;
            final totalWidth =
                MediaQuery.of(context).size.width - 2 * KinrelSpacing.xl;
            _seekToFraction((waveWidth / totalWidth).clamp(0.0, 1.0));
          },
          child: SizedBox(
            height: widget.compact ? 32 : 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(
                waveform.length.clamp(1, 60),
                (index) {
                  final barCount = waveform.length.clamp(1, 60);
                  final heightFactor = waveform[index];
                  final height = widget.compact
                      ? 6.0 + heightFactor * 22.0
                      : 12.0 + heightFactor * 56.0;
                  final isPast = index / barCount <= progress;

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: height,
                      decoration: BoxDecoration(
                        color: isPast
                            ? KinrelColors.orange
                            : KinrelColors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),

        // ── Seek bar (Slider) ───────────────────────────────────────
        if (!widget.compact) ...[
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: KinrelColors.orange,
              inactiveTrackColor: KinrelColors.darkElevated,
              thumbColor: KinrelColors.orange,
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: progress,
              onChanged: _seekToFraction,
            ),
          ),
          // Time labels
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: KinrelTypography.labelSmall.copyWith(
                  color: KinrelColors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_isLoading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor:
                            AlwaysStoppedAnimation(KinrelColors.textDim),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'loading',
                      style: KinrelTypography.labelSmall.copyWith(
                        color: KinrelColors.textDim,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              Text(
                _formatDuration(_duration),
                style: KinrelTypography.labelSmall.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // ── Play / Pause Controls ───────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Rewind 15s (full mode only)
            if (!widget.compact) ...[
              GestureDetector(
                onTap: () => _seekToFraction(
                  (progress - 15 / _duration.inSeconds).clamp(0.0, 1.0),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.darkCard,
                  ),
                  child: const Icon(
                    Icons.replay_10_rounded,
                    color: KinrelColors.textSilver,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 20),
            ],

            // Play / Pause
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: widget.compact ? 44 : 64,
                height: widget.compact ? 44 : 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                  boxShadow: KinrelFx.shadows([
                    BoxShadow(
                      color: KinrelColors.orangeGlowIntense,
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ]),
                ),
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: widget.compact ? 22 : 32,
                      ),
              ),
            ),

            // Forward 15s (full mode only)
            if (!widget.compact) ...[
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => _seekToFraction(
                  (progress + 15 / _duration.inSeconds).clamp(0.0, 1.0),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: KinrelColors.darkCard,
                  ),
                  child: const Icon(
                    Icons.forward_10_rounded,
                    color: KinrelColors.textSilver,
                    size: 22,
                  ),
                ),
              ),
            ],
          ],
        ),

        // ── Speed Control (full mode only) ─────────────────────────
        if (!widget.compact) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [0.5, 1.0, 1.5, 2.0].map((speed) {
              final isActive = _player.speed == speed;
              return GestureDetector(
                onTap: () => _player.setSpeed(speed),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? KinrelColors.orange.withValues(alpha: 0.2)
                        : KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                    border: Border.all(
                      color: isActive
                          ? KinrelColors.orange
                          : const Color(0xFF3A3A4A),
                    ),
                  ),
                  child: Text(
                    '${speed}x',
                    style: KinrelTypography.labelSmall.copyWith(
                      color: isActive
                          ? KinrelColors.orange
                          : KinrelColors.textSilver,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
