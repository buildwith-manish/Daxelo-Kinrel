// lib/features/family_map/widgets/map_timeline_scrubber.dart
//
// P10.7 — Map Timeline Scrubber.
//
// Horizontal slider at the bottom of the map. Drag to change the
// viewing year; the map updates in real time (pins / places / paths
// filter via JourneyProvider.filterMapPins + filterMapPlaces).
//
// Play button auto-advances 1 year per
// MapVisualConstants.timelinePlayInterval (tunable — Rule 16).
//
// Memory markers on the scrubber reuse the P7.3 pattern (small dots
// above the slider at years with memories).
//
// Reduced motion: jump-cut between years (no smooth transition).
//
// Rule 13 (Performance): If filtering + crossfade drops below 60 FPS,
// the screen debounces the drag (100ms) and simplifies the crossfade
// to instant swap. The scrubber itself is always responsive.
//
// Rule 15 (Offline): Timeline works entirely from in-memory data.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../l10n/app_localizations.dart';
import '../../family_journey/providers/journey_provider.dart';
import '../config/map_visual_constants.dart';

/// The timeline scrubber widget. Sits at the bottom of the map.
class MapTimelineScrubber extends ConsumerStatefulWidget {
  const MapTimelineScrubber({
    super.key,
    this.onYearChanged,
    this.reducedMotion = false,
  });

  /// Optional callback invoked on every year change (drag or play).
  /// The screen uses this to trigger the crossfade + refilter.
  final ValueChanged<int>? onYearChanged;

  final bool reducedMotion;

  @override
  ConsumerState<MapTimelineScrubber> createState() =>
      _MapTimelineScrubberState();
}

class _MapTimelineScrubberState extends ConsumerState<MapTimelineScrubber> {
  late final TextEditingController _yearFieldController;

  @override
  void initState() {
    super.initState();
    final current = ref.read(journeyProvider).selectedYear;
    _yearFieldController = TextEditingController(text: current.toString());
  }

  @override
  void dispose() {
    _yearFieldController.dispose();
    super.dispose();
  }

  void _setYear(int year) {
    final state = ref.read(journeyProvider);
    final clamped = year.clamp(state.minYear, state.maxYear);
    ref.read(journeyProvider.notifier).setYear(clamped);
    _yearFieldController.text = clamped.toString();
    widget.onYearChanged?.call(clamped);
  }

  void _togglePlay() {
    final state = ref.read(journeyProvider);
    if (state.isPlaying) {
      ref.read(journeyProvider.notifier).pause();
    } else {
      ref.read(journeyProvider.notifier).play();
    }
  }

  void _stepYear(int delta) {
    final state = ref.read(journeyProvider);
    _setYear(state.selectedYear + delta);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(journeyProvider);
    final theme = Theme.of(context);
    final l10n = S.of(context);
    final semanticsLabel =
        l10n?.familyMapTimelineLabel(state.selectedYear) ??
        'Family timeline. Currently viewing ${state.selectedYear}. Drag to change.';

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                MapVisualConstants.timelineShadowOpacity,
              ),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Play / Pause
                _PlayButton(
                  isPlaying: state.isPlaying,
                  onTap: _togglePlay,
                  playLabel: l10n?.familyMapTimelinePlay ?? 'Play timeline',
                  pauseLabel: l10n?.familyMapTimelinePause ?? 'Pause timeline',
                ),
                const SizedBox(width: 8),
                // Previous year
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white70),
                  onPressed: () => _stepYear(-1),
                  tooltip:
                      l10n?.familyMapTimelinePreviousYear ?? 'Previous year',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                ),
                // Year display + editable field
                Expanded(
                  child: _YearDisplay(
                    controller: _yearFieldController,
                    selectedYear: state.selectedYear,
                    onSubmitted: (text) {
                      final parsed = int.tryParse(text);
                      if (parsed != null) _setYear(parsed);
                    },
                  ),
                ),
                // Next year
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white70),
                  onPressed: () => _stepYear(1),
                  tooltip: l10n?.familyMapTimelineNextYear ?? 'Next year',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n?.familyMapTimelineRange(state.minYear, state.maxYear) ??
                      '${state.minYear}–${state.maxYear}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                    fontFamily: KinrelTypography.bodyFont,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Slider with memory markers
            _ScrubberSlider(
              minYear: state.minYear,
              maxYear: state.maxYear,
              selectedYear: state.selectedYear,
              memoryMarkers: state.memoryMarkers,
              reducedMotion: widget.reducedMotion,
              onChanged: _setYear,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.onTap,
    required this.playLabel,
    required this.pauseLabel,
  });
  final bool isPlaying;
  final VoidCallback onTap;
  final String playLabel;
  final String pauseLabel;

  @override
  Widget build(BuildContext context) {
    final label = isPlaying ? pauseLabel : playLabel;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: KinrelColors.orange,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YearDisplay extends StatelessWidget {
  const _YearDisplay({
    required this.controller,
    required this.selectedYear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final int selectedYear;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontFamily: KinrelTypography.displayFont,
        ),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthInputFormatter(4),
        ],
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _ScrubberSlider extends StatelessWidget {
  const _ScrubberSlider({
    required this.minYear,
    required this.maxYear,
    required this.selectedYear,
    required this.memoryMarkers,
    required this.reducedMotion,
    required this.onChanged,
  });

  final int minYear;
  final int maxYear;
  final int selectedYear;
  final Map<int, String> memoryMarkers;
  final bool reducedMotion;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = selectedYear.toDouble();
    final min = minYear.toDouble();
    final max = maxYear.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: KinrelColors.orange,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: KinrelColors.orange.withOpacity(
                  MapVisualConstants.timelineSliderOverlayOpacity,
                ),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: (max - min).toInt(),
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
            // Memory markers (small dots above the slider).
            ..._buildMemoryDots(constraints.maxWidth),
          ],
        );
      },
    );
  }

  List<Widget> _buildMemoryDots(double width) {
    if (memoryMarkers.isEmpty) return const [];
    final range = maxYear - minYear;
    if (range == 0) return const [];
    return memoryMarkers.entries.map((e) {
      final year = e.key;
      if (year < minYear || year > maxYear) return const SizedBox.shrink();
      final fraction = (year - minYear) / range;
      final left = fraction * width;
      return Positioned(
        left: left - 3,
        top: -8,
        child: Tooltip(
          message: e.value,
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: KinrelColors.orange,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }).toList();
  }
}

class LengthInputFormatter extends TextInputFormatter {
  LengthInputFormatter(this.maxLength);
  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maxLength) {
      return newValue;
    }
    return TextEditingValue(
      text: newValue.text.substring(0, maxLength),
      selection: TextSelection.collapsed(offset: maxLength),
    );
  }
}
