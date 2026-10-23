# Feature Registry Summary

Single source of truth: every feature flag in the Daxelo-Kinrel app.
Source: `lib/core/features/feature_registry.dart` (`enum AppFeature`,
`_defaults`, `_parents`, `routeFeatureMap`).

## Phase wiring

| Phase | What it shipped |
|---|---|
| **1** | Feature Registry foundation: `AppFeature` enum (65 entries), `_defaults` map (all-true for zero behavior change), `_parents` dependency map, `routeFeatureMap`, `Features` facade (`isOn` / `isRouteDisabled` / `setDebugOverride` / `clearDebugOverride` / `initDebugOverrides`), `featureProvider` + `remoteConfigUpdateProvider`, debug `FeatureSwitchesScreen`, public `RemoteConfigService.getBool()` + `hasKey()`, `@Deprecated` annotations on old `kEnable*` consts. |
| **2** | Data-driven UI: bottom nav (`_BottomNav` → `ConsumerWidget`), family space floating nav (`FamilySpaceFloatingNav` → `ConsumerWidget`), HighlightsRow (`HighlightsRow` → `ConsumerWidget`), hero icons (`hero_section.dart` HeroSection gating Graph+Map via `ref.watch` ternary), top-bar notification bell (early-return when OFF), `withGaps` helper. |
| **3** | Route guard: `Features.isRouteDisabled(path)` wired into `_handleRedirect` so any navigation to an OFF-feature route redirects to `/home`. Catches taps, deep links, push taps, cold-start route restore. `/debug/features` route registered. `Features.initDebugOverrides()` wired in `main.dart` initState. `remoteConfigUpdateProvider` bumped after RC init. |
| **4** | Lean defaults: `_defaults` flipped to 20 ON / 44 OFF / 1 untouched (`unifiedTimeline`). RC `feature_*` keys synced to match. Phase 1 unit tests updated to assert the lean ON/OFF sets. Phase 3 route-guard test updated to assert which routes redirect under lean defaults. |
| **5** | Background gating: client-side push filter (`shouldShowPush` in `push_notification_service.dart`) drops gated FCM pushes in foreground + background + terminated tap handlers. Server-side `FEATURE_*` env var gates in 3 Supabase edge functions short-circuit the send entirely. Android widget `setPredictionWidgetEnabled` method channel on `MainActivity.kt` calls `PackageManager.setComponentEnabledSetting` on `PredictionWidgetProvider`. `_syncPredictionWidgetEnabled()` in `main.dart` syncs the widget state to `AppFeature.predictionBattle`. |
| **6** | Tests + summary table: widget tests for HighlightsRow / FamilySpaceFloatingNav / _BottomNav (Phase 4 lean defaults render the correct subset), route redirect integration test, this summary table. |

## Resolution order

```
debug override (debug builds only, persisted to SharedPreferences)
    ↓ fallthrough
Remote Config value for `feature_<name>` (if key deployed to RC console)
    ↓ fallthrough
compiled default from `_defaults` map
    ↓ then
parent cascade — if any ancestor in `_parents` is OFF, force OFF
```

## Dependency map (`_parents`)

If a parent is OFF, the child is forced OFF regardless of its own
value. The child's own debug override does NOT bypass the parent
cascade.

| Child | Parent |
|---|---|
| `predictionBattle` | `coinPool` |
| `gameInvitePush` | `games` |
| `premiumInsights` | `paywall` |
| `familyJourney` | `familyMap` |
| `memories` | `activities` (master switch rule) |
| `memberTimeline` | `activities` (master switch rule) |

## Lean ON set (20)

The daily-use surface. Per Phase 4 defaults, these are `true` in
both `_defaults` and the `feature_*` RC keys.

| Feature | Surfaces gated | Phase |
|---|---|---|
| `home` | Bottom nav Home tab, `/home` route | 2 + 3 |
| `familyMap` | Bottom nav Family tab, Family Space, hero icons | 2 + 3 |
| `kinrel` | `/kinrel` route | 3 |
| `sparqTray` | `/sparq` route | 3 |
| `feed` | Home feed | 2 |
| `chat` | Bottom nav Chat tab, `/chat` route | 2 + 3 |
| `familyChat` | Family Space floating nav Family Chat tab, `/family/:id/chats` | 2 + 3 |
| `members` | Family Space floating nav Members tab, `/family/:id/members` | 2 + 3 |
| `calendar` | Family Space floating nav Calendar tab, `/family/:id/calendar` | 2 + 3 |
| `profile` | Bottom nav Me tab, `/profile` route | 2 + 3 |
| `profileEditing` | Profile edit + add-relative flows | 1 |
| `findOnKinrel` | Bottom nav Search tab, `/find-on-kinrel` route | 2 + 3 |
| `activities` | Master switch — gates `memories` + `memberTimeline` | 1 (parent) |
| `memories` | HighlightsRow Memories + Activity tiles, `/memories` + `/memory-vault` + `/memory` routes | 2 + 3 |
| `memberTimeline` | `/timeline` + `/member-timeline` routes | 3 |
| `oralHistory` | HighlightsRow Oral History tile, `/oral-history` route | 2 + 3 |
| `todaysQuestion` | Today's Question card on Home, `/todays-question` route | 1 + 3 |
| `inviteBanner` | Home invite banner | 1 |
| `topBarNotifications` | Home notification bell, `/notifications` route | 2 + 3 |
| `topBarSettings` | Top-bar settings icon, `/settings` route | 1 + 3 |

## Lean OFF set (44)

Premium / experimental / occasional-use / push channels. Per Phase 4
defaults, these are `false` in both `_defaults` and the `feature_*`
RC keys. Flip from the RC console by setting `feature_<name>=true`,
or from the debug screen at `/debug/features` (debug builds only).

| Feature | Parent | Surfaces gated | Phase |
|---|---|---|---|
| `familyJourney` | `familyMap` | `/family-journey` route | 1 + 3 |
| `sparqRunNavigation` | — | Sparq run sub-route | 1 |
| `circle` | — | `/circle` route | 1 + 3 |
| `communities` | — | `/communities` route | 1 + 3 |
| `games` | — | Family Space Games tab, `/games` route | 2 + 3 |
| `gameInvitePush` | `games` | `/game-invite` route, FCM `game_invite` push type | 1 + 3 + 5 |
| `achievements` | — | HighlightsRow Achievements tile, `/achievements` route | 2 + 3 |
| `lists` | — | HighlightsRow Lists tile, `/lists` route | 2 + 3 |
| `governanceTimeline` | — | `/governance` route (NEW per spec) | 1 + 3 |
| `heroFamilyMap` | — | Hero Graph + Map flanking icons | 2 |
| `heroKinrel` | — | Hero Kinrel icon | 2 |
| `heroFindOnKinrel` | — | Hero Find-on-Kinrel icon | 2 |
| `heroAddMember` | — | Hero Add-Member icon | 2 |
| `cameoFallback` | — | 2D Cameo portrait painter | 1 |
| `live3DCameo` | — | 3D Cameo runtime (B1 verification incomplete) | 1 |
| `cameoStudio` | — | `/studio` route | 1 + 3 |
| `voiceMessages` | — | Chat voice message | 1 |
| `scheduledMessages` | — | Chat scheduled messages, FCM `scheduled_message` push type | 1 + 3 + 5 |
| `chatMentions` | — | Chat @-mention picker | 1 |
| `chatBlockReport` | — | Chat block/report sheet | 1 |
| `chatReactions` | — | Chat message reactions | 1 |
| `chatTypingIndicator` | — | Chat typing indicator | 1 |
| `chatGallery` | — | Chat media gallery | 1 |
| `graphShareExport` | — | Graph PNG share/export | 1 |
| `photoPicker` | — | Avatar photo picker (camera/gallery) | 1 |
| `qrJoin` | — | Join-a-family via QR code | 1 |
| `languagePicker` | — | Kinship term language picker | 1 |
| `audioPronunciation` | — | Kinship term TTS pronunciation | 1 |
| `autoKinshipInference` | — | Auto-derived relationship edges | 1 |
| `kinshipRingRow` | — | Home kinship ring row | 1 |
| `paywall` | — | `/paywall` + `/premium` routes | 1 + 3 |
| `premiumInsights` | `paywall` | Family insights dashboard | 1 |
| `premiumExport` | — | GEDCOM export | 1 |
| `premiumAiKinship` | — | AI kinship discovery (currently FREE) | 1 |
| `memoryVault` | — | Memory vault screens | 1 |
| `memoryVaultFreeMonthlyCap` | — | Free-tier monthly upload cap | 1 |
| `maxFreeMembers` | — | Free-tier member cap (OFF = no cap) | 1 |
| `maxFreeFamilies` | — | Free-tier family cap (OFF = no cap) | 1 |
| `coinPool` | — | `/coin-pool` route | 1 + 3 |
| `predictionBattle` | `coinPool` | `/prediction-battle` route, Android prediction widget | 1 + 3 + 5 |
| `pushGameInvite` | — | FCM `game_invite` push type, server edge function | 5 |
| `pushReEngagement` | — | FCM `re_engagement` push type, server edge function | 5 |
| `pushMention` | — | FCM `chat_mention` / `mention` push type | 5 |
| `pushScheduledMessage` | — | FCM `scheduled_message` push type | 5 |
| `referralOnProfile` | — | Profile referral section | 1 |
| `retentionNudge` | — | Day-N retention nudge | 1 |
| `aiSuggestions` | — | AI-powered suggestions | 1 |
| `onboarding` | — | Onboarding flow | 1 |

## Untouched (1)

| Feature | Reason |
|---|---|
| `unifiedTimeline` | No UI screen yet. Per spec ("leave it alone"), default stays `true`. Flipping it has no user-visible effect. |

## Server-side env var gates (Phase 5)

| Edge function | Env var | Default |
|---|---|---|
| `supabase/functions/send-game-invite-push/index.ts` | `FEATURE_GAME_INVITE_PUSH` | `false` |
| `supabase/functions/process-scheduled-game-nights/index.ts` | `FEATURE_GAMES` | `false` |
| `supabase/functions/send-re-engagement-push/index.ts` | `FEATURE_RE_ENGAGEMENT_PUSH` | `false` |

Flip by setting the env var to `true` in the Supabase Edge Function
secrets (Project Settings → Edge Functions → Secrets).

## Android widget (Phase 5)

| Receiver | Class | Gating feature |
|---|---|---|
| `PredictionWidgetProvider` | `com.daxelo.kinrel.PredictionWidgetProvider` | `AppFeature.predictionBattle` (cascades from `coinPool`) |

Toggled via `setPredictionWidgetEnabled` method on the `kinrel/device`
MethodChannel from `lib/main.dart`'s `_syncPredictionWidgetEnabled()`,
which runs after `Features.initDebugOverrides()` so debug overrides
propagate.

## Tests

| Test file | Covers |
|---|---|
| `test/core/features/feature_registry_test.dart` | `_defaults` map (Phase 4 lean ON set: 20, OFF set: 44, untouched: 1). `hasKey` for every `feature_<name>` RC key. Dependency map structure. Parent cascade forces child OFF (incl. activities master-switch rule). |
| `test/core/features/feature_route_guard_test.dart` | `Features.isRouteDisabled` for known ON + OFF routes. Longest-prefix match (`/family/123/games` → games, not familyMap). Activities master-switch rule on `/memories` + `/memory-vault` + `/timeline` + `/member-timeline` routes. Other dependency cascades via routes. |
| `test/core/features/feature_push_filter_test.dart` | `pushTypeToFeature` + `shouldShowPush`. Phase 4 default state: gated types dropped, daily-use shown. Debug override flips. Defensive on malformed data. |
| `test/features/family/feature_registry_highlights_test.dart` | Widget test: HighlightsRow renders exactly the lean-ON tile set (Memories + Activity + Oral History = 3). Debug override reveals hidden Achievements tile. |
| `test/features/family/feature_registry_family_space_nav_test.dart` | Widget test: FamilySpaceFloatingNav renders exactly the lean-ON tab set (Family Chat + Members + Calendar = 3, Games hidden). Debug override reveals Games tab. |
| `test/core/routing/feature_registry_bottom_nav_test.dart` | Widget test: 5 bottom-nav tabs render under lean ON defaults. Debug override of chat OFF hides the Chat tab. |
| `test/core/routing/feature_registry_route_redirect_test.dart` | Integration test: GoRouter with the Phase 3 redirect logic. Lean-OFF routes redirect to /home. Lean-ON routes don't. Debug override flips behavior. Pre-auth + debug routes are skipped. |

## Cumulative gating contract

A disabled feature is:
1. **Invisible** (Phase 2 UI filter — bottom nav tab, family space tab, highlights tile, hero icon, top-bar bell all hidden)
2. **Unreachable** (Phase 3 route guard — `/feature-route` redirects to `/home` from any entry point: tap, deep link, push tap, cold-start restore)
3. **Silent** (Phase 5 push filter — gated FCM types are silently dropped at the foreground/background/terminated handlers; server-side `FEATURE_*` env vars prevent the send in the first place)
4. **Disconnected from home screen** (Phase 5 widget enable/disable — Android `PredictionWidgetProvider` component is disabled so it stops appearing in the picker AND existing instances stop updating)

Four layers of gating for full control.
