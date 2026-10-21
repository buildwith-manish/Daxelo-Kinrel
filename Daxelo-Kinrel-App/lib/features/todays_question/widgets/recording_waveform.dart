// lib/features/todays_question/widgets/recording_waveform.dart
//
// DAXELO KINREL — Phase B — Recording waveform.
//
// Paints the live amplitude bars from `RecordingState.amplitudes`.
// Reused during recording (live bars) and in the preview state
// (final static waveform). No animation when the user has reduced
// motion enabled (handled by the parent — this widget is a pure
// paint and respects a `reducedMotion` flag for the optional glow).

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';

const _cOrange = KinrelColors.orange;
const _cAmber = KinrelColors.amber;
const _cDim = KinrelColors.textDim;

/// A horizontal waveform of normalized amplitude bars (0.0..1.0).
///
/// Empty input → renders 24 faint baseline bars so the widget has
/// visual weight during the brief moment before the first amplitude
/// sample arrives (~100ms after recording starts).
class RecordingWaveform extends StatelessWidget {
  const RecordingWaveform({
    super.key,
    required this.amplitudes,
    this.active = true,
    this.barWidth = 3.0,
    this.barGap = 3.0,
    this.maxBars = 50,
    this.height = 48.0,
  });

  final List<double> amplitudes;

  /// When false (preview state), the bars use the dim color and no
  /// glow. When true (live recording), bars use the orange→amber
  /// gradient.
  final bool active;

  final double barWidth;
  final double barGap;
  final int maxBars;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Take only the last `maxBars` amplitudes so older samples scroll
    // off the left edge (matches Instagram/WhatsApp voice-messaging
    // visual language).
    final source = amplitudes.length > maxBars
        ? amplitudes.sublist(amplitudes.length - maxBars)
        : amplitudes;
    final bars = source.isEmpty ? List.filled(24, 0.06) : source;

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WaveformPainter(
          bars: bars,
          active: active,
          barWidth: barWidth,
          barGap: barGap,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.active,
    required this.barWidth,
    required this.barGap,
  });

  final List<double> bars;
  final bool active;
  final double barWidth;
  final double barGap;

  @override
  void paint(Canvas canvas, Size size) {
    final totalWidth = bars.length * barWidth + (bars.length - 1) * barGap;
    final startX = (size.width - totalWidth) / 2;
    final centerY = size.height / 2;

    for (var i = 0; i < bars.length; i++) {
      final x = startX + i * (barWidth + barGap);
      // Even silence gets a small visible baseline (≥ 4% of height)
      // so the user can tell the mic is alive.
      final normalized = bars[i].clamp(0.04, 1.0);
      final barHeight = normalized * size.height;

      // Color: gradient from amber (left) → orange (right) when
      // active, solid dim when in preview.
      final color = active
          ? Color.lerp(_cAmber, _cOrange, i / bars.length)!
          : _cDim;

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.bars != bars || old.active != active;
}
