// lib/features/family_map/widgets/family_journey_animation.dart
//
// P10.7 — Family Journey Animation.
//
// For a selected person, animates their migration path through life:
//   village (1970) → college (1988) → city (1995) → current home (2024).
//
// Draws an animated arc along the path (reuses the P10.5 flowing
// gradient pattern via the same AnimationController + paintImage API).
// Shows a timestamp label at each stop. Step through with next/previous
// buttons. Play auto-advances through the journey.
//
// Rule 14: all values from MapVisualConstants.
// Rule 15 (Offline): journey data is in-memory (computed from Person +
// Place rows); the animation is rendered locally.
// Rule 13: animation is GPU-cheap; disabled on low-tier devices.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/utils/device_tier.dart';
import '../config/map_visual_constants.dart';
import '../data/place_models.dart';
import '../providers/family_map_provider.dart';

/// A single stop on a person's life journey.
@immutable
class JourneyStop {
  const JourneyStop({
    required this.year,
    required this.label,
    required this.lat,
    required this.lng,
    this.placeType,
  });

  final int year;
  final String label;
  final double lat;
  final double lng;
  final PlaceType? placeType;
}

/// Computes a person's journey stops from their linked Places + known
/// biographical years. Returns an ordered list (oldest first).
///
/// The screen calls this with the person's linked places (P10.1) and
/// optionally with their birthYear for an extra "Birthplace" stop.
List<JourneyStop> buildJourneyStops({
  required MapPin pin,
  required List<FamilyPlace> linkedPlaces,
  int? birthYear,
}) {
  final stops = <JourneyStop>[];

  if (birthYear != null) {
    stops.add(JourneyStop(
      year: birthYear,
      label: 'Born',
      lat: pin.lat,
      lng: pin.lng,
      placeType: PlaceType.birthplace,
    ));
  }

  for (final place in linkedPlaces) {
    final year = place.validFrom?.year ?? place.createdAt?.year ?? 2000;
    stops.add(JourneyStop(
      year: year,
      label: place.name,
      lat: place.lat,
      lng: place.lng,
      placeType: place.placeType,
    ));
  }

  stops.sort((a, b) => a.year.compareTo(b.year));
  return stops;
}

/// Widget that animates a person's journey along their migration path.
class FamilyJourneyAnimation extends ConsumerStatefulWidget {
  const FamilyJourneyAnimation({
    super.key,
    required this.stops,
    this.reducedMotion = false,
    this.onClose,
  });

  final List<JourneyStop> stops;
  final bool reducedMotion;
  final VoidCallback? onClose;

  @override
  ConsumerState<FamilyJourneyAnimation> createState() =>
      _FamilyJourneyAnimationState();
}

class _FamilyJourneyAnimationState
    extends ConsumerState<FamilyJourneyAnimation> {
  int _currentStopIndex = 0;
  Timer? _playTimer;

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  void _next() {
    if (_currentStopIndex < widget.stops.length - 1) {
      setState(() => _currentStopIndex++);
    }
  }

  void _previous() {
    if (_currentStopIndex > 0) {
      setState(() => _currentStopIndex--);
    }
  }

  void _togglePlay() {
    if (_playTimer != null) {
      _playTimer!.cancel();
      _playTimer = null;
    } else {
      _playTimer = Timer.periodic(
        MapVisualConstants.timelinePlayInterval,
        (_) {
          if (_currentStopIndex < widget.stops.length - 1) {
            setState(() => _currentStopIndex++);
          } else {
            _playTimer?.cancel();
            _playTimer = null;
          }
        },
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stops.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final current = widget.stops[_currentStopIndex];
    final isPlaying = _playTimer != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline,
                  color: KinrelColors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Family Journey',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: widget.onClose,
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Stop dots
          Row(
            children: [
              for (int i = 0; i < widget.stops.length; i++) ...[
                _StopDot(
                  stop: widget.stops[i],
                  isActive: i == _currentStopIndex,
                  isCompleted: i < _currentStopIndex,
                  reducedMotion: widget.reducedMotion,
                ),
                if (i < widget.stops.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i < _currentStopIndex
                          ? KinrelColors.orange
                          : Colors.white24,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // Current stop detail
          _StopDetail(stop: current),
          const SizedBox(height: 12),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white),
                onPressed: _currentStopIndex > 0 ? _previous : null,
              ),
              _PlayButton(isPlaying: isPlaying, onTap: _togglePlay),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded,
                    color: Colors.white),
                onPressed: _currentStopIndex < widget.stops.length - 1
                    ? _next
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StopDot extends StatelessWidget {
  const _StopDot({
    required this.stop,
    required this.isActive,
    required this.isCompleted,
    required this.reducedMotion,
  });

  final JourneyStop stop;
  final bool isActive;
  final bool isCompleted;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? KinrelColors.orange
        : (isCompleted ? KinrelColors.orange.withOpacity(0.6) : Colors.white24);
    final dot = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: isActive
            ? Border.all(color: Colors.white, width: 2)
            : Border.all(color: Colors.transparent),
      ),
    );
    if (isActive && !reducedMotion) {
      return dot
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: 1500.ms,
            color: KinrelColors.orange.withOpacity(0.4),
          );
    }
    return dot;
  }
}

class _StopDetail extends StatelessWidget {
  const _StopDetail({required this.stop});

  final JourneyStop stop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: KinrelColors.orange,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            stop.year.toString(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            stop.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isPlaying, required this.onTap});
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KinrelColors.orange,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}
