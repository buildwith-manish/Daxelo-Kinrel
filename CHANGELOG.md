# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **fix(graph): onboarding overlay, single-node render, FAB, kinship edge labels**
  - BUG-1: Onboarding overlay dismissal now persists via `onboardingDismissedProvider`; tapping "Skip" correctly sets `_permanentlyDismissed` and updates the Riverpod state so the overlay never reappears for that family
  - BUG-2: Single-member graph renders the anchor node instead of a blank screen; viewport culling fallback ensures `_visibleNodeIds.isEmpty` falls back to all nodes in `_personMap`
  - BUG-3: FloatingActionButton with `Icons.person_add_alt_1_rounded` is always present on `FamilyGraphScreen`, independent of onboarding state or member count; tapping navigates to `/family/:familyId/add-person`
  - BUG-4: Kinship terms flow into graph edge labels; `KinshipService.getRelationship()` and `getKinshipTerm()` return correct native-language names (e.g. Hindi 'पिता' for 'father') for edge rendering

### Added

- Regression tests for all 4 graph bugs (Agent-08):
  - `test/graph/widgets/onboarding_flow_dismissal_test.dart` — onboarding overlay skip + persistence
  - `test/graph/widgets/single_member_graph_test.dart` — single-node rendering, no blank screen
  - `test/features/family/family_graph_screen_fab_test.dart` — FAB presence and navigation
  - `test/graph/widgets/graph_kinship_edge_label_test.dart` — kinship term lookup and edge label data
