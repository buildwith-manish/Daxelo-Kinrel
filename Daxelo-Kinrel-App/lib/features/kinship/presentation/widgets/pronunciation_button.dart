// lib/features/kinship/presentation/widgets/pronunciation_button.dart
//
// DAXELO KINREL — Pronunciation Button
//
// A small icon button that speaks the given [text] in the given [languageCode]
// via [KinshipPronunciationService]. Self-contained stateful widget that
// shows a playing state while TTS is active.
//
// Gated by `kEnableAudioPronunciation` — when the flag is `false`, this
// widget renders as `SizedBox.shrink()` so call sites can include it
// unconditionally without their own flag check.

import 'package:flutter/material.dart';

import '../../../../core/constants/feature_flags.dart';
import '../../../../core/services/kinship_pronunciation_service.dart';

/// A self-contained pronounce button.
///
/// Renders nothing when `kEnableAudioPronunciation` is `false`.
class PronunciationButton extends StatefulWidget {
  const PronunciationButton({
    super.key,
    required this.text,
    this.languageCode = 'en',
    this.tooltip,
    this.iconSize = 22.0,
    this.color,
  });

  /// Text to speak aloud when tapped.
  final String text;

  /// ISO 639-1 language code (e.g., 'hi', 'en').
  final String languageCode;

  /// Optional tooltip; defaults to 'Pronounce'.
  final String? tooltip;

  /// Icon size; defaults to 22.
  final double iconSize;

  /// Optional icon color.
  final Color? color;

  @override
  State<PronunciationButton> createState() => _PronunciationButtonState();
}

class _PronunciationButtonState extends State<PronunciationButton> {
  final KinshipPronunciationService _service = KinshipPronunciationService();
  bool _isPlaying = false;

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _service.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    if (mounted) setState(() => _isPlaying = true);
    try {
      await _service.speak(widget.text, languageCode: widget.languageCode);
    } finally {
      // Give TTS a moment to actually finish; FlutterTts doesn't expose a
      // reliable completion future across platforms, so we use a coarse
      // estimate based on text length.
      final estimatedMs = (widget.text.length * 90) + 400;
      await Future<void>.delayed(Duration(milliseconds: estimatedMs));
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kEnableAudioPronunciation) return const SizedBox.shrink();

    final icon = _isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded;
    return IconButton(
      icon: Icon(icon, size: widget.iconSize, color: widget.color),
      tooltip: widget.tooltip ?? 'Pronounce',
      onPressed: _toggle,
    );
  }
}
