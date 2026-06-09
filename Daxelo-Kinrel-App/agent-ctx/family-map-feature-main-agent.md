# Task: Family Map Feature - Daxelo-Kinrel App

## Task ID: family-map-feature

## Agent: Main Agent

## Summary

Created the complete Family Map feature for the Daxelo-Kinrel Flutter app, consisting of three production-ready Dart files.

## Files Created

### 1. `lib/features/family_map/data/city_coordinates.dart`
- Bundled Dart constant map: `const Map<String, (double, double)> kCityCoordinates`
- **200 city entries** with Dart 3 record syntax: `'mumbai': (19.0760, 72.8777)`
- Coverage: 28 Indian state capitals, tier-1/tier-2 cities, 70+ diaspora cities across Middle East, Europe, North America, Oceania, Asia, Africa, and Caribbean
- No duplicate keys verified

### 2. `lib/features/family_map/providers/family_map_provider.dart`
- `MapPin` class: personId, name, city, photoUrl, lat, lng
- `FamilyMapResult` class: pins, unpinnedMembers, unpinnedCount, distinctCityCount
- `UnpinnedMember` class: personId, name, city, photoUrl
- `familyMapProvider` (FutureProvider): watches `familyListProvider` for first family, then `familyMembersProvider(familyId)`, resolves each member's city via `kCityCoordinates` lookup

### 3. `lib/features/family_map/presentation/family_map_screen.dart`
- `FamilyMapScreen` (ConsumerStatefulWidget) with `DKScaffold`
- AppBar: "Family Map" title + pinned/cities subtitle
- flutter_map with OpenStreetMap tiles (no API key), darkened tiles overlay
- Initial position: India center (20.5937, 78.9629), zoom 4.5
- 44x44 circular pin markers with CachedAvatar + orange 2px border + glow
- Initials fallback on darkCard background
- Pin tap → bottom sheet: 80px avatar, name (Outfit Bold 18), city with amber location pin icon, "View Profile" button → `/member/:id`
- Legend overlay (bottom-left): semi-transparent darkCard, pinned/unpinned counts, tap opens unpinned members sheet
- Empty states: no members, no cities, error with retry
- Loading: orange CircularProgressIndicator
- flutter_animate for pin fade-in/scale and legend slide animations

## Design System Compliance
- Uses KinrelColors (orange, amber, darkCard, darkBackground, darkElevated, textWhite, textSilver, textDim, orangeGlow)
- Uses KinrelTypography (displayFont, bodyFont)
- Uses KinrelSpacing, KinrelRadius tokens
- Uses DK components: DKScaffold, DKCard, DKButton, DKButtonVariant, DKButtonSize
- Uses CachedAvatar from core/widgets
