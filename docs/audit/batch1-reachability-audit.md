# Kinrel Final Audit — Batch 1 Report

**Date:** 2026-07-15
**Branch:** main (commit 37414d6d)
**Method:** Per Section 2 of kinrel_final_audited_prompt_v2.md

## 1. Reachability audit results

Scanned all 144 `*_screen.dart` files in `lib/features/**`. Found **6 unreachable screens** (5 from the prompt + 1 additional).

### Confirmed unreachable (zero references outside own file)

| # | Screen | File | Constructor | Category |
|---|--------|------|-------------|----------|
| 1 | `StoryModeScreen` | `lib/features/story_mode/presentation/story_mode_screen.dart` | `required familyId` | **A** |
| 2 | `HealthHeritageScreen` | `lib/features/health_heritage/presentation/health_heritage_screen.dart` | no required params | **G** (backend blocked) |
| 3 | `CommunityDiscoveryScreen` | `lib/features/community/presentation/community_discovery_screen.dart` | no required params | **A** |
| 4 | `PulseLearningProfileScreen` | `lib/features/profile/presentation/pulse_learning_profile_screen.dart` | no required params | **A** |
| 5 | `FamilySettingsScreen` | `lib/features/family/presentation/family_settings_screen.dart` | `required familyId` | **A** |
| 6 | `ShareAppHelper` | `lib/features/profile/presentation/share_app_screen.dart` | helper, not a screen | **H** (dead code) |

### Additional findings

- `ExploreScreen` — route DELETED (KIN-25). **Category C (superseded)** — do not wire.
- `MembersAddedScreen` + `RelationsScreen` — actually REACHABLE (routed at app_router.dart lines 1671, 1730).

## 2. Category A — Production-ready but unwired (4 screens to wire)

1. **StoryModeScreen** — provider exists, no debug gates, family-scoped. Wire: `/family/:id/story-mode`
2. **CommunityDiscoveryScreen** — provider + NestJS backend exist. Wire: `/community`
3. **PulseLearningProfileScreen** — dio calls exist, user-scoped (not family). Wire: `/profile/pulse-learning`
4. **FamilySettingsScreen** — dio calls + NestJS families endpoint exist. Wire: `/family/:id/settings`

## 3. Category G — Backend blocked (1 screen, do NOT wire)

**HealthHeritageScreen** — `_loadDemoData()` loads hardcoded "Sharma family" medical data (14 conditions, 4 generations). No backend table exists. Wiring would show fake medical data to all users. **Privacy risk — do not wire until backend exists.**

## 4. Wiring plan (Batch 2)

Add 4 routes to `app_router.dart` + entry points in family home / profile screens. Each gets a focused widget test.
