// lib/features/family_map/widgets/map_search_bar.dart
//
// DAXELO KINREL — Map Search Bar (jump-to-location).
//
// P13 — Top-of-map search field that lets the user jump to any city
// in the bundled kCityCoordinates lookup OR any family member pin.
// Matches the reference's "search / jump-to-location support" pillar.
//
// Behavior:
//   • The search field is collapsed by default — a pill button with a
//     search icon + the family map title hint.
//   • Tapping the pill expands it into a full TextField with a
//     suggestions dropdown below.
//   • Suggestions include up to [searchMaxSuggestions] (6) results,
//     matching the query against:
//       - City names (from kCityCoordinates)
//       - Family member pins (by name)
//   • Selecting a city suggestion flies the camera to that lat/lng
//     at zoom 11 (city-level view).
//   • Selecting a member suggestion flies the camera to that pin at
//     zoom 16.5 (focus-mode zoom, where 3D buildings are visible).
//
// Performance (Rule 13): the suggestion list is computed synchronously
// on each query change — kCityCoordinates has ~150 entries, so a
// linear scan is cheap. Family member pins are typically <100.
//
// Localization: the search field uses localized hints via S.of(context).
//
// Integration: the parent screen passes the [MapController] and the
// current [MapPin] list. The screen owns the controller; this widget
// only triggers camera animations.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:maplibre/maplibre.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/widgets/cached_avatar.dart';
import '../../../l10n/app_localizations.dart';
import '../config/map_visual_constants.dart';
import '../data/city_coordinates.dart';
import '../providers/family_map_provider.dart';
import 'map_initials.dart';

/// Top-of-map search bar with city + member suggestions.
class MapSearchBar extends StatefulWidget {
  const MapSearchBar({
    super.key,
    required this.mapController,
    required this.pins,
    required this.reducedMotion,
    this.onMemberSelected,
  });

  /// The maplibre controller used to animate the camera.
  final MapController? mapController;

  /// Current family member pins. Used for member suggestions.
  final List<MapPin> pins;

  /// True when the user has enabled reduced motion.
  final bool reducedMotion;

  /// Optional callback invoked when a member suggestion is selected.
  /// The screen can use this to enter focus mode on that member.
  final void Function(MapPin pin)? onMemberSelected;

  @override
  State<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _expanded = false;
  List<_SearchSuggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _controller.text.isEmpty) {
        setState(() => _expanded = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    final out = <_SearchSuggestion>[];

    // Match cities.
    for (final entry in kCityCoordinates.entries) {
      if (entry.key.contains(q)) {
        out.add(_CitySuggestion(
          cityName: entry.key,
          lat: entry.value.$1,
          lng: entry.value.$2,
        ));
        if (out.length >= MapVisualConstants.searchMaxSuggestions) break;
      }
    }

    // Match members (if we still have capacity).
    if (out.length < MapVisualConstants.searchMaxSuggestions) {
      for (final pin in widget.pins) {
        if (pin.name.toLowerCase().contains(q) ||
            pin.city.toLowerCase().contains(q)) {
          out.add(_MemberSuggestion(pin: pin));
          if (out.length >= MapVisualConstants.searchMaxSuggestions) break;
        }
      }
    }

    setState(() => _suggestions = out);
  }

  void _expand() {
    setState(() => _expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _collapse() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _expanded = false;
      _suggestions = const [];
    });
  }

  Future<void> _selectSuggestion(_SearchSuggestion s) async {
    await HapticFeedback.selectionClick();
    final controller = widget.mapController;
    if (controller == null) {
      _collapse();
      return;
    }
    if (s is _CitySuggestion) {
      controller.animateCamera(
        center: Geographic(lon: s.lng, lat: s.lat),
        zoom: 11.0,
        pitch: 0.0,
        nativeDuration: const Duration(milliseconds: 720),
      );
    } else if (s is _MemberSuggestion) {
      controller.animateCamera(
        center: Geographic(lon: s.pin.lng, lat: s.pin.lat),
        zoom: MapVisualConstants.focusMinZoom,
        pitch: MapVisualConstants.focusPitch,
        nativeDuration: const Duration(milliseconds: 720),
      );
      widget.onMemberSelected?.call(s.pin);
    }
    _collapse();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top +
          MapVisualConstants.searchBarTopPadding,
      left: MapVisualConstants.searchBarHorizontalMargin,
      right: MapVisualConstants.searchBarHorizontalMargin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Search field / collapsed pill ──────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: MapVisualConstants.searchBarHeight,
            decoration: BoxDecoration(
              color: KinrelColors.darkCard.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(KinrelRadius.full),
              border: Border.all(
                color: _expanded
                    ? KinrelColors.orange.withValues(alpha: 0.6)
                    : KinrelColors.darkElevated,
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                if (_expanded)
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(width: KinrelSpacing.md),
                Icon(
                  _expanded ? Icons.arrow_back_rounded : Icons.search_rounded,
                  size: 20,
                  color: _expanded
                      ? KinrelColors.orange
                      : KinrelColors.textDim,
                ),
                SizedBox(width: KinrelSpacing.sm),
                Expanded(
                  child: _expanded
                      ? TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            color: KinrelColors.textWhite,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: l10n?.familyMapSearchHint ??
                                'Search city or family member',
                            hintStyle: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              color: KinrelColors.textDim,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) {
                            if (_suggestions.isNotEmpty) {
                              _selectSuggestion(_suggestions.first);
                            }
                          },
                        )
                      : GestureDetector(
                          onTap: _expand,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n?.familyMapSearchCollapsed ??
                                  'Search city or family member',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                color: KinrelColors.textDim,
                              ),
                            ),
                          ),
                        ),
                ),
                if (_expanded)
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: KinrelColors.textDim,
                    ),
                    onPressed: _collapse,
                    tooltip: l10n?.familyMapSearchClear ?? 'Clear',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                  )
                else
                  SizedBox(width: KinrelSpacing.md),
              ],
            ),
          ),

          // ── Suggestions dropdown ───────────────────────────────────
          if (_expanded && _suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: BoxConstraints(
                maxHeight: 320,
              ),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                border: Border.all(color: KinrelColors.darkElevated),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => Divider(
                  color: KinrelColors.darkElevated,
                  height: 1,
                ),
                itemBuilder: (context, i) {
                  final s = _suggestions[i];
                  return _SuggestionTile(
                    suggestion: s,
                    onTap: () => _selectSuggestion(s),
                  );
                },
              ),
            )
                .animate()
                .fadeIn(duration: 180.ms)
                .slideY(begin: -0.05, end: 0, duration: 180.ms),
        ],
      ),
    );
  }
}

/// A single suggestion row.
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.onTap});

  final _SearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (suggestion is _CitySuggestion) {
      final c = suggestion as _CitySuggestion;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.md,
            vertical: KinrelSpacing.sm + 2,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.orangeGlowSubtle,
                ),
                child: Icon(
                  Icons.location_city_rounded,
                  size: 16,
                  color: KinrelColors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _titleCase(c.cityName),
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                    Text(
                      S.of(context)?.familyMapSearchCityHint ?? 'City',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.north_east_rounded,
                size: 16,
                color: KinrelColors.textDim,
              ),
            ],
          ),
        ),
      );
    }
    final m = suggestion as _MemberSuggestion;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md,
          vertical: KinrelSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1A1A22),
              ),
              child: m.pin.photoUrl != null && m.pin.photoUrl!.isNotEmpty
                  ? ClipOval(
                      child: CachedAvatar(
                        imageUrl: m.pin.photoUrl,
                        radius: 14,
                      ),
                    )
                  : Center(
                      child: Text(
                        initials(m.pin.name),
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textSilver,
                          height: 1,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.pin.name,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  if (m.pin.city.isNotEmpty)
                    Text(
                      m.pin.city,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: KinrelColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.north_east_rounded,
              size: 16,
              color: KinrelColors.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Suggestion model ─────────────────────────────────────────────────

abstract class _SearchSuggestion {}

class _CitySuggestion implements _SearchSuggestion {
  _CitySuggestion({
    required this.cityName,
    required this.lat,
    required this.lng,
  });
  final String cityName;
  final double lat;
  final double lng;
}

class _MemberSuggestion implements _SearchSuggestion {
  _MemberSuggestion({required this.pin});
  final MapPin pin;
}

// ── Helpers ──────────────────────────────────────────────────────────

String _titleCase(String input) {
  if (input.isEmpty) return input;
  final words = input.split(RegExp(r'\s+'));
  return words
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
