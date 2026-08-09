// lib/features/chat/presentation/voice_message_player.dart
//
// DAXELO KINREL — Voice Message Player Widget (Phase 13)
//
// A self-contained audio playback widget for voice message bubbles.
// Uses `just_audio` to stream the audio file from the mediaUrl
// (Supabase public URL of the uploaded voice file).
//
// Features:
//   - Play / pause toggle with Ignite gradient button
//   - Animated waveform bars that fill as the audio plays
//   - Seek bar (tap to seek)
//   - Duration display "0:00 / 0:12"
//   - Loading spinner while the audio is buffering
//   - Auto-stops playback when the widget is disposed
//
// One AudioPlayer instance is created per message. When the user starts
// playing a new message while another is still playing, the previous
// player is NOT paused — this is intentional, matching WhatsApp which
// only plays one at a time. To enforce single-playback, see the
// `_VoiceMessagePlayerRegistry` below.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

/// A registry that ensures only one voice message plays at a time.
/// When a new voice message starts playing, any previously-playing
/// voice message is automatically paused.
class _VoiceMessagePlayerRegistry {
  _VoiceMessagePlayerRegistry._();
  static final _VoiceMessagePlayerRegistry instance = _VoiceMessagePlayerRegistry._();

  AudioPlayer? _current;
  String? _currentMessageId;

  /// Register a player as the active one. If another message is
  /// currently playing, it is paused (and its UI will receive the
  /// pause event via its own stream listener).
  void register(String messageId, AudioPlayer player) {
    if (_current != null && _currentMessageId != messageId) {
      try {
        _current!.pause();
      } catch (e) {
        debugPrint('⚠️ registry pause failed: $e');
      }
    }
    _current = player;
    _currentMessageId = messageId;
  }

  /// Clear the active registration (called when a player is disposed
  /// or finishes playback).
  void unregister(String messageId) {
    if (_currentMessageId == messageId) {
      _current = null;
      _currentMessageId = null;
    }
  }
}

/// A voice message player widget that renders inside a chat bubble.
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.messageId,
    required this.mediaUrl,
    required this.durationSeconds,
    required this.isMe,
  });

  /// Unique ID of the chat message — used to dedupe players.
  final String messageId;

  /// Public URL of the audio file in Supabase Storage.
  final String mediaUrl;

  /// Duration in seconds (from `voiceMessageDuration` column).
  /// Used as a hint for the seek bar before the audio loads.
  final int? durationSeconds;

  /// Whether this message was sent by the current user (changes colors).
  final bool isMe;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _hasError = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _duration = widget.durationSeconds != null
        ? Duration(seconds: widget.durationSeconds!)
        : Duration.zero;

    _setupAudio();
    _listenToPlayer();
  }

  Future<void> _setupAudio() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await _player.setUrl(widget.mediaUrl);
      // After loading, the actual duration is known
      final d = _player.duration;
      if (d != null && d.inMilliseconds > 0) {
        if (mounted) setState(() => _duration = d);
      }
    } catch (e) {
      debugPrint('⚠️ VoiceMessagePlayer setUrl failed: $e');
      if (mounted) setState(() => _hasError = true);
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
          setState(() => _isLoading = false);
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
          // Reset to start so the user can play again
          _player.seek(Duration.zero);
          _VoiceMessagePlayerRegistry.instance.unregister(widget.messageId);
          break;
      }
    });

    _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });

    _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
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
      _VoiceMessagePlayerRegistry.instance.unregister(widget.messageId);
    } else {
      _VoiceMessagePlayerRegistry.instance.register(widget.messageId, _player);
      try {
        await _player.play();
      } catch (e) {
        debugPrint('⚠️ VoiceMessagePlayer play failed: $e');
        if (mounted) setState(() => _hasError = true);
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
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _VoiceMessagePlayerRegistry.instance.unregister(widget.messageId);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause button
          GestureDetector(
            onTap: _isLoading ? null : _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: KinrelGradients.igniteGradient,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orange.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          // Waveform + duration
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform with seek
                GestureDetector(
                  onTapDown: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final localPos = details.localPosition;
                    final fraction = (localPos.dx / box.size.width).clamp(0.0, 1.0);
                    _seekToFraction(fraction);
                  },
                  child: SizedBox(
                    height: 28,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        progress: progress,
                        isMe: widget.isMe,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                      ),
                    ),
                    Text(
                      ' / ${_formatDuration(_duration)}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim.withValues(alpha: 0.6),
                      ),
                    ),
                    if (_hasError) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.error_outline,
                        size: 11,
                        color: KinrelColors.error,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A waveform-style painter that draws 30 vertical bars. Bars before
/// `progress` are accent-colored (orange for sender, silver for
/// receiver); bars after are dim.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.progress, required this.isMe});

  final double progress;
  final bool isMe;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 30;
    final barWidth = size.width / (barCount * 1.5); // bar + gap
    final gap = barWidth * 0.5;

    // Pseudo-random heights — deterministic per-bar so the waveform looks
    // the same on every rebuild.
    final heights = List<double>.generate(barCount, (i) {
      // Mix of sines for a natural-looking waveform
      final v = (i * 7.13) % 1.0;
      final v2 = (i * 13.7) % 1.0;
      final h = 0.3 + (0.5 * v + 0.5 * v2) * 0.7;
      return h.clamp(0.2, 1.0);
    });

    final activeColor = isMe
        ? KinrelColors.orange
        : KinrelColors.textSilver;
    final inactiveColor = isMe
        ? KinrelColors.orange.withValues(alpha: 0.25)
        : KinrelColors.textSilver.withValues(alpha: 0.25);

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      final barHeight = heights[i] * size.height;
      final y = (size.height - barHeight) / 2;
      final rect = Rect.fromLTWH(x, y, barWidth, barHeight);
      final paint = Paint()
        ..color = (i / barCount) < progress ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isMe != isMe;
  }
}
