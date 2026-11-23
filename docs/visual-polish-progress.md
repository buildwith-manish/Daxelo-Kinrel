# Visual polish progress

Branch: `fix/visual-polish` (Flutter app only, `Daxelo-Kinrel-App/lib/**`).
Status values: `not started` | `in progress (<resume note>)` | `done (merged <sha>)`.

## Findings read before starting

- Canonical tokens live in `lib/core/constants/brand_colors.dart` (`KinrelColors`, `KinrelGradients`),
  `brand_typography.dart`, `brand_spacing.dart`, `app_tokens.dart` (NOT under `lib/core/theme/`).
  `lib/core/theme/app_theme.dart` holds `KinrelThemeExtension`, which is built from `KinrelColors`.
- Access pattern actually used app-wide: `KinrelColors.<token>` static consts (410 files).
  `Theme.of(context).extension<KinrelThemeExtension>()` is used in **zero** files outside its definition,
  so Part 1 uses `KinrelColors.*` (no new access pattern invented).
- Baseline: `Flutter Analyze` was RED on main (10 pre-existing warnings in
  `chat/presentation/widgets/family_event_card.dart` and `blocked_message_placeholder.dart`:
  dead `?? 0` on non-nullable ints, missing `const`). Fixed in the first commit on this branch so
  CI can go green; this is the only change outside the four parts.
- Other CI jobs (Backend CI, Flutter Test) were red/cancelled on the base before this branch;
  see per-part notes for what was actually observed.

## Part 1 - color token sweep
Status: done (all folders under lib/features, lib/presentation, lib/shared swept; ambiguous items listed in A-C below; merged fb29a901)
Files touched: 146 Dart files under `Daxelo-Kinrel-App/lib/` (full list: `git diff --name-only main..fix/visual-polish`); about 515 changed lines now referencing `KinrelColors.*`.

What was replaced (value-preserving, existing `KinrelColors.<token>` pattern, relative import to
`core/constants/brand_colors.dart` added where missing):
- Exact matches: E8612A->orange, 191B2C->darkCard, EF4444->red, F59240->amber, C9B4A8->textSilver, D4AF37->gold,
  2A2A3D->border, 202338->darkElevated, 131416->darkBackground, 13141E->darkSurface, 4CAF7A->success,
  C44A18->ember, 60A5FA->info, FFD700->brightGold, F04E2A->error, FF6B6B->coral, 3B82F6->blue,
  F5A623->warning, 8A8A9E->textMutedDark, E8E8ED->lightSurface.
- F5F0EE (is both `textWhite` and `lightElevated`): resolved by property/declaration name (`_textPrimary` etc ->
  textWhite; ternary against darkCard -> lightElevated). Two left, listed in C below.
- Near-duplicates (channel diff <= 2, imperceptible): 1A1C2E/1A1D2E/1A1A2E/1A1B2E->darkCard,
  20233A/1F2236->darkElevated, 2A2D45->elevation3 (29 sites).

Needs a human look:
- **Token conflict:** `darkBackground` is `131416` (and is what `app_theme.dart` uses as the dark scaffold/surface),
  but `elevation0` and `darkSurface` are documented as the "page bg" at `13141E`. Both are one hex digit apart
  and both are used as page backgrounds (24 vs 20 literal sites). I mapped each literal to the token of its own value,
  so nothing changed visually; which one is the real page background is a design call.
- **Stale dim-text literal:** `8A7A72` appears 55 times. It is the OLD `textDim` (KIN-08 raised the token to `C9B4A8`
  because `8A7A72` fails AA on dark). Swapping literal -> token would lighten 55 spots and would look wrong on any
  light-mode surface, so I left them. They are the same contrast problem noted in Part 3.
- `3A3A4A` (67x) and `11132A` (29x) are very common but match no token; candidates for new tokens if wanted.
- Pre-existing, unrelated to this branch: 63 relative imports across lib/ do not resolve by path arithmetic (for example
  `lib/features/chat/presentation/widgets/message_bubble.dart` imports `../../../../../core/...`, one `../` too many; also
  `pb_v1_rank_badge.dart`, `chat_meta.dart`, `game_invite_status_chip.dart`). CI's analyze output does not appear to flag them
  (see CI note), so I did not touch them, but they merit a look.

### A. Near-miss literals NOT replaced (channel diff 3-6 from a token) - need a human look

- `0F0E17` ~ `131416` (darkBackground), diff 6: lib/features/games/ghost_painter/ghost_painter_join_screen.dart:81
- `0F1318` ~ `131416` (darkBackground), diff 4: lib/features/family/presentation/widgets/kinship_language_selector.dart:46
- `0F1814` ~ `131416` (darkBackground), diff 4: lib/features/chat/presentation/widgets/chat_background_theme.dart:193
- `111111` ~ `131416` (darkBackground), diff 5: lib/features/games/sketch_telephone/sketch_telephone_card.dart:227, lib/features/games/sketch_telephone/sketch_telephone_card.dart:297
- `131110` ~ `131416` (darkBackground), diff 6: lib/features/chat/presentation/widgets/chat_background_theme.dart:242
- `141119` ~ `131416` (darkBackground), diff 3: lib/features/games/carrom/carrom_board_screen.dart:246
- `151219` ~ `131416` (darkBackground), diff 3: lib/features/gaming_ecosystem/presentation/gaming_player_profile_screen.dart:198
- `161218` ~ `131416` (darkBackground), diff 3: lib/features/gaming_ecosystem/presentation/match_ecosystem_summary.dart:322
- `191218` ~ `131416` (darkBackground), diff 6: lib/features/gaming_ecosystem/presentation/match_ecosystem_summary.dart:191
- `0F1424` ~ `13141E` (darkSurface/elevation0), diff 6: lib/features/games/stickman_heist/stickman_heist_game_screen.dart:827, lib/features/games/flick_arena/flick_arena_game_screen.dart:804
- `0F1A1E` ~ `13141E` (darkSurface/elevation0), diff 6: lib/features/games/crystal_bridge/crystal_bridge_game_screen.dart:1407
- `101220` ~ `13141E` (darkSurface/elevation0), diff 3: lib/features/chat/presentation/widgets/chat_background_theme.dart:103
- `10141C` ~ `13141E` (darkSurface/elevation0), diff 3: lib/features/games/night_falls/night_falls_game_screen.dart:1162
- `141821` ~ `13141E` (darkSurface/elevation0), diff 4: lib/features/gaming_ecosystem/presentation/gaming_milestones_screen.dart:158
- `16131B` ~ `13141E` (darkSurface/elevation0), diff 3: lib/features/chat/presentation/widgets/chat_background_theme.dart:258
- `16181F` ~ `13141E` (darkSurface/elevation0), diff 4: lib/features/games/presentation/games_hub_screen.dart:696
- `191420` ~ `13141E` (darkSurface/elevation0), diff 6: lib/features/gaming_ecosystem/presentation/gaming_challenges_screen.dart:118
- `14162A` ~ `191B2C` (darkCard/elevation1), diff 5: lib/features/family/presentation/create_group_screen.dart:580, lib/features/family/presentation/family_groups_screen.dart:231, lib/features/family/presentation/group_hub_screen.dart:337, lib/features/family/presentation/group_hub_screen.dart:647 (+2 more)
- `16182B` ~ `191B2C` (darkCard/elevation1), diff 3: lib/features/chat/presentation/widgets/chat_background_theme.dart:102, lib/features/games/stickman_heist/stickman_heist_game_screen.dart:828, lib/features/games/flick_arena/flick_arena_game_screen.dart:805
- `191D29` ~ `191B2C` (darkCard/elevation1), diff 3: lib/features/family_map/config/map_visual_constants.dart:45
- `1A1B26` ~ `191B2C` (darkCard/elevation1), diff 6: lib/features/games/shared/icons/game_icons.dart:812, lib/features/games/connect4/connect4_game_screen.dart:55
- `1A1C27` ~ `191B2C` (darkCard/elevation1), diff 5: lib/features/chat/presentation/widgets/constellation_pattern.dart:46
- `1A1F2B` ~ `191B2C` (darkCard/elevation1), diff 4: lib/features/family/presentation/family_graph_screen.dart:2649, lib/features/family/presentation/family_graph_screen.dart:2720, lib/features/family/presentation/widgets/kinship_language_selector.dart:93
- `1A1F2E` ~ `191B2C` (darkCard/elevation1), diff 4: lib/shared/widgets/kinrel_toast.dart:216
- `1E2029` ~ `191B2C` (darkCard/elevation1), diff 5: lib/features/gaming_ecosystem/presentation/gaming_milestones_screen.dart:158, lib/features/games/presentation/games_hub_screen.dart:696
- `1A2533` ~ `202338` (darkElevated/elevation2), diff 6: lib/features/family_map/config/map_visual_constants.dart:503
- `1F2937` ~ `202338` (darkElevated/elevation2), diff 6: lib/features/games/chess/chess_board_screen.dart:225, lib/features/games/chess/chess_board_screen.dart:369, lib/shared/painters/kinrel_icon_painter.dart:78
- `23263E` ~ `202338` (darkElevated/elevation2), diff 6: lib/shared/painters/kinrel_icon_painter.dart:56
- `2A2D48` ~ `282B44` (elevation3), diff 4: lib/features/chat/presentation/chat_ui_tokens.dart:38
- `2A2F4A` ~ `282B44` (elevation3), diff 6: lib/features/games/stickman_heist/stickman_heist_game_screen.dart:835, lib/features/games/flick_arena/flick_arena_game_screen.dart:828
- `2A3040` ~ `282B44` (elevation3), diff 5: lib/features/family/presentation/widgets/kinship_language_selector.dart:108, lib/features/family/presentation/widgets/kinship_language_selector.dart:117
- `2A2440` ~ `2A2A3D` (border), diff 6: lib/features/family_map/config/map_visual_constants.dart:48
- `2A2638` ~ `2A2A3D` (border), diff 5: lib/features/family_map/config/map_visual_constants.dart:65
- `2A2B38` ~ `2A2A3D` (border), diff 5: lib/shared/widgets/kinrel_logo.dart:129
- `2A2D3F` ~ `2A2A3D` (border), diff 3: lib/features/home/presentation/widgets/streak_badge.dart:103, lib/shared/widgets/kinrel_skeleton.dart:76
- `2E3150` ~ `303450` (elevation4), diff 3: lib/features/chat/presentation/chat_ui_tokens.dart:57
- `343853` ~ `303450` (elevation4), diff 4: lib/features/chat/presentation/chat_ui_tokens.dart:50
- `4A5568` ~ `4B5563` (nodeAnonymous), diff 5: lib/features/profile/presentation/settings/settings_category_screen.dart:834
- `4E5462` ~ `4B5563` (nodeAnonymous), diff 3: lib/features/games/memorymatch/memorymatch_card_faces.dart:1674
- `5A3E2A` ~ `5A4030` (textSecondaryLight), diff 6: lib/features/cameo/style/cameo_color_palette.dart:128
- `5E4630` ~ `5A4030` (textSecondaryLight), diff 6: lib/features/games/memorymatch/memorymatch_card_faces.dart:1233, lib/features/games/memorymatch/memorymatch_card_faces.dart:1625
- `8C8C99` ~ `8A8A9E` (textMutedDark), diff 5: lib/features/games/memorymatch/memorymatch_card_faces.dart:743
- `E5E7EB` ~ `E8E8ED` (lightSurface), diff 3: lib/features/profile/presentation/settings/settings_category_screen.dart:835, lib/features/profile/presentation/settings/settings_widgets.dart:90, lib/features/profile/presentation/settings/settings_widgets.dart:116, lib/presentation/widgets/skeletons/timeline_skeleton.dart:71 (+3 more)
- `ECEAF2` ~ `E8E8ED` (lightSurface), diff 5: lib/features/chat/presentation/chat_ui_tokens.dart:63
- `E84393` ~ `EC4899` (nodeChild/spouseHeartColor), diff 6: lib/features/games/memorymatch/memorymatch_card_faces.dart:290, lib/features/games/memorymatch/memorymatch_card_faces.dart:332, lib/features/games/memorymatch/memorymatch_card_faces.dart:402, lib/features/games/memorymatch/memorymatch_card_faces.dart:736 (+7 more)
- `F5F5F5` ~ `F8F5F0` (warmBackground), diff 5: lib/features/profile/presentation/sessions_screen.dart:511, lib/features/games/memorymatch/memorymatch_card_faces.dart:1653, lib/presentation/widgets/skeletons/search_skeleton.dart:40, lib/presentation/widgets/skeletons/member_list_skeleton.dart:44 (+3 more)
- `F9FAFB` ~ `FFFAF8` (lightBackground), diff 6: lib/shared/painters/kinrel_icon_painter.dart:79
- `FFFCF4` ~ `FFFAF8` (lightBackground), diff 4: lib/features/games/carrom/carrom_board_screen.dart:1230
- `FFFDF6` ~ `FFFAF8` (lightBackground), diff 3: lib/features/games/nameplace/nameplace_results_screen.dart:94, lib/features/games/nameplace/nameplace_answer_screen.dart:114, lib/features/games/nameplace/nameplace_letter_pick_screen.dart:118

### B. Exact-token-value literals deliberately NOT replaced

- `8A7A72` x55: lib/features/profile/presentation/my_families_screen.dart:28, lib/features/profile/presentation/invitations_screen.dart:35, lib/features/profile/presentation/members_added_screen.dart:22 ...
- `3A3A4A` x67: lib/features/auth/presentation/sign_up_screen.dart:103, lib/features/auth/presentation/sign_up_screen.dart:660, lib/features/gamification/presentation/achievements_screen.dart:210 ...
- `11132A` x29: lib/features/chat/presentation/group_info_screen.dart:141, lib/features/chat/presentation/group_info_screen.dart:331, lib/features/chat/presentation/chat_search_screen.dart:297 ...
- `F5F0EE` x2: lib/features/games/memorymatch/memorymatch_card_faces.dart:1681, lib/features/games/dotsboxes/dotsboxes_board_screen.dart:260
- `FFFFFF` x17: lib/features/social/presentation/screens/sparq_create_screen.dart:427, lib/features/social/presentation/screens/sparq_create_screen.dart:890, lib/features/social/presentation/screens/sparq_create_screen.dart:1022 ...

Tailwind-palette values that coincide with *relationship-node* tokens (nodeCousin 10B981, nodeInLaw F59E0B, nodeSibling 8B5CF6, nodeAuntUncle 06B6D4, nodeChild EC4899, edgeIndirect 6B7280, nodeGrandparent 6366F1, nodeSpouse F97316, nodeExtended 64748B) - left as literals, counts:
- `10B981` x34; top files: lib/features/games/stickman_heist/stickman_heist_game_screen.dart (9), lib/features/relation_riddles/presentation/relation_riddle_screen.dart (7), lib/features/relation_riddles/presentation/relation_riddle_card.dart (5)
- `F59E0B` x32; top files: lib/features/games/shared/icons/game_icons.dart (6), lib/features/chat/presentation/chat_ui_tokens.dart (3), lib/features/family/presentation/family_detail_screen.dart (3)
- `8B5CF6` x32; top files: lib/features/games/shared/icons/game_icons.dart (4), lib/features/health_heritage/providers/health_heritage_provider.dart (3), lib/features/family/presentation/family_detail_screen.dart (3)
- `06B6D4` x29; top files: lib/features/hot_seat/presentation/hot_seat_screen.dart (9), lib/features/hot_seat/presentation/hot_seat_card.dart (8), lib/features/family/presentation/family_detail_screen.dart (2)
- `EC4899` x28; top files: lib/features/games/ghost_painter/ghost_painter_card.dart (5), lib/features/games/ghost_painter/ghost_painter_join_screen.dart (4), lib/features/family/presentation/family_detail_screen.dart (2)
- `6B7280` x27; top files: lib/features/profile/presentation/settings/settings_widgets.dart (11), lib/features/profile/presentation/settings/settings_actions.dart (8), lib/features/profile/presentation/profile_screen.dart (3)
- `6366F1` x9; top files: lib/features/health_heritage/providers/health_heritage_provider.dart (1), lib/features/chat/presentation/chat_ui_tokens.dart (1), lib/features/family/presentation/family_detail_screen.dart (1)
- `F97316` x6; top files: lib/features/health_heritage/providers/health_heritage_provider.dart (3), lib/features/health_heritage/presentation/health_heritage_screen.dart (2), lib/features/games/crystal_bridge/crystal_bridge_game_screen.dart (1)
- `64748B` x5; top files: lib/features/chat/presentation/chat_ui_tokens.dart (1), lib/features/family/presentation/family_detail_screen.dart (1), lib/features/games/shared/icons/game_icon_tokens.dart (1)

### C. F5F0EE left as literal (text vs background unclear)

- lib/features/games/memorymatch/memorymatch_card_faces.dart:1681
- lib/features/games/dotsboxes/dotsboxes_board_screen.dart:260


**CI note (Part 1):** `Flutter Analyze` was already red on `main` before this branch (and the `CI` run also contains `Backend CI`,
which fails within seconds in `server/`, untouched here). GitHub only shows the first 10 analyzer annotations and the job log is
served from a blob-storage domain the sandbox blocks, so the full pre-existing warning list is not visible from here.
Clearing the first 10 (commit 1) exposed the next 10 (`prefer_const_constructors` in `report_message_sheet.dart`,
`schedule_message_sheet.dart`, `family_event_card.dart:431`), none in files this sweep touched. See the final report.

## Part 2 - loading-state standardization
Status: done (merged fb29a901)
Decision: no new widget. `lib/shared/widgets/kinrel_skeleton.dart` already provides the shimmer skeleton system
(`KinrelSkeletonList`, `KinrelSkeletonCard`, reduced-motion aware), and 23 places already use it. A second widget would
duplicate it, so the bare `CircularProgressIndicator` loading states were swapped to `const KinrelSkeletonList()`.
Files touched (18): family/{family_members,family_activity,family_chat_list,family_groups}_screen.dart,
chat/archived_chats_screen.dart, community/community_discovery_screen.dart,
pulse/{blessing_chain,memorials,time_capsule,silent_alarms,family_chronicle,family_quests}_screen.dart,
gaming_ecosystem/{leaderboard,match_history,activity_feed,achievements}_screen.dart,
trackc/decisions_list_screen.dart, shared_list/shared_list_screen.dart.
Deliberately NOT swapped (human/visual check needed): family_list_screen.dart:1296, chat_inbox_screen.dart:167 (nested layout
not verified), trackc timeline_screen.dart (two), gaming_milestones/season/player_profile, relationship_* pickers,
single-item detail screens, and the inline spinner in shared_list_screen.dart:182. 
Loading announcement for screen readers: the old spinner had implicit progress semantics; the skeleton has none. Adding one
needs a new l10n string (generated files cannot be regenerated here) - flagged for Part 3 / human.

## Part 3 - accessibility pass
Status: done for icon-only `IconButton`s, text-scale and contrast review; icon-only GestureDetector/InkWell/Image semantics NOT done (see below). merged fb29a901

### Done: tooltips (= screen-reader labels) on icon-only `IconButton`s
- 280 `IconButton`s outside grandparent mode had no `tooltip`. 239 now have one, in 167 files, using Flutter's built-in,
  already-translated `MaterialLocalizations` strings (no new `.arb` keys, which could not be regenerated here):
  back x149, close x50, share x28, next/previous page x5, more x3, delete x2, cancel x1, copy x1.
- Only applied where `context` is provably in scope (inside `build(BuildContext context)` or a `State` method) and not in a const context.
- Follow-up pass: 25 more icon-only `IconButton`s labeled with plain English `tooltip:` strings (no localized string exists and the
  `.arb` + generated `app_localizations_*.dart` files cannot be regenerated here; the codebase already has ~98 hardcoded English tooltips).
  **Human call:** move these to l10n keys (send, clear search, refresh, add, edit, etc.) so non-English screen readers hear their language.
  Files: sparq_viewer, follow_requests, b1_verification, help_center, trackc search/decision_create (x2), shared_list, hot_seat (x2), chat_inbox (x2),
  join_family, kinrel_user_search, family_groups, relationship_quick_pick/picker sheets, person_detail_sheet, story_mode (x2), thinking_inbox,
  ghost_painter_guess, circle_chat (x2), event_detail.
- Still unlabeled: lib/features/games/freeze_auction/freeze_auction_lobby_screen.dart:59 and games/color_trap/color_trap_lobby_screen.dart:60
  (`Icons.share_outlined`, const context) and lib/core/utils/accessibility_utils.dart:123 (`Icons.close`, context not provably in scope).
- NOT done: icon-only `GestureDetector`/`InkWell` taps, `Image`s without `semanticLabel`, custom painter widgets. The `Semantics` audit is incomplete.
- Note: a tooltip on a button already wrapped in its own `Semantics(label:)` could be announced twice; not checked.

### Text scale
- `main.dart` applies `TextScaler.linear(effectiveFontScale(...))`: it follows the system scale. Two caveats for a human:
  (1) an in-app override *replaces* the system scale instead of multiplying it (`theme_provider.dart:62`); (2) nothing clamps the
  upper end, so 3x+ iOS accessibility sizes will hit every fixed-height box below. Not changed.
- Fixed-height boxes directly wrapping `Text` (height 20-64) that can clip when scaled up. Flagged, not fixed:
- lib/features/presence/presentation/presence_widget.dart:143 height 36
- lib/features/festival_cards/presentation/festival_cards_screen.dart:265 height 56
- lib/features/chat/presentation/chat_ui_gallery.dart:338 height 40
- lib/features/chat/presentation/chat_search_screen.dart:483 height 36
- lib/features/chat/presentation/widgets/typing_indicator.dart:102 height 20
- lib/features/chat/presentation/widgets/chat_meta.dart:245 height 40
- lib/features/chat/presentation/widgets/chat_header_bar.dart:111 height 34
- lib/features/gaming_ecosystem/presentation/gaming_match_history_screen.dart:128 height 46
- lib/features/gaming_ecosystem/presentation/widgets/gaming_kit.dart:547 height 26
- lib/features/pulse/presentation/pulse_hub_screen.dart:175 height 48
- lib/features/family/presentation/join_family_screen.dart:1031 height 20
- lib/features/memory_vault/presentation/memory_create_screen.dart:271 height 40
- lib/features/feed/presentation/post_create_screen.dart:194 height 40
- lib/features/feed/presentation/widgets/feed_post_card.dart:234 height 36
- lib/features/games/shared/multiplayer/widgets/lobby_view.dart:419 height 32
- lib/features/games/shared/widgets/family_leaderboard_widget.dart:187 height 32
- lib/features/games/shared/widgets/invite_family_sheet.dart:1934 height 44
- lib/features/games/shared/widgets/pending_invites_section.dart:194 height 28
- lib/features/games/shared/widgets/recent_players_section.dart:232 height 28
- lib/features/games/impostor/impostor_game_screen.dart:211 height 28
- lib/features/games/impostor/impostor_game_screen.dart:270 height 32
- lib/features/games/nameplace/nameplace_answer_screen.dart:163 height 36
- lib/features/calendar/presentation/family_calendar_screen.dart:403 height 48

### Contrast (WCAG AA 4.5:1 normal text), computed from `KinrelColors`; brand colors NOT changed
Passing: textWhite / textSilver / textMutedDark on dark bg, card, elevated (min 4.57); textDark and textSecondaryLight on all light surfaces (min 8.4);
orange text on dark bg/card (5.42/5.00); amber, gold, success, warning, info on all dark surfaces.
Failing - needs a design decision:
- Light mode `lightTextDim` (`C9B4A8`) on light bg/card/elevated: **1.92 / 1.99 / 1.76**.
- Light mode accent colors used as text on `FFFAF8`/white: orange `E8612A` 3.28/3.40, error `F04E2A` 3.48/3.60, gold 2.03/2.10,
  success 2.63/2.72, warning 1.96/2.03, info 2.46/2.54. (Fine for icons/large UI parts at 3:1 only where >= 3.0: orange, error.)
- Light mode ember `C44A18` on `elevated F5F0EE`: 4.28 (passes on bg and card: 4.67 / 4.84).
- Dark mode `ember C44A18` as text: **3.81 / 3.52 / 3.19** on bg / card / elevated. `error F04E2A` on elevated `202338`: 4.29.
- White text on an orange `E8612A` CTA: **3.40** (passes only as large/bold text, >= 3:1); on ember `C44A18`: 4.84 (passes).
- Legacy literal `8A7A72` (55 sites, Part 1): 4.48 / 4.14 / 3.76 on dark bg / card / elevated, 3.97-4.11 on light.
- Also outside Part 1's folders: `main.dart:1295-1296` hardcodes `131416` and a light scaffold `F5F7FA`, which is not `lightBackground` (`FFFAF8`).

## Part 4 - flourishes
Status: done (merged fb29a901)
Files touched (1): `lib/shared/widgets/dk_components.dart`.
- `DKButton`: light haptic (`HapticService.tap()`) on every enabled tap, fired before `onPressed`; the existing 0.96 press-scale is now skipped when the OS "Reduce Motion" setting (`accessibleNavigation`) is on.
- `DKSuggestionChip`: selection haptic (`HapticService.selection()`) on tap.
- Not done: a success-moment animation (no single clearly-abrupt success moment was identified without running the app).

## Merge status
- `Flutter Analyze` is green on this branch (run 44719111901 on `c991c585`; re-checked after the Part 4 commit, see git log).
- `Backend CI` (server/, untouched) fails and `Flutter Test` hits its 25-minute timeout on `main` too, so no run of this branch can be fully green until those are fixed separately. Parts 1-4 are therefore pushed but NOT merged pending a human call on accepting the analyzer gate.


## Session log - CI re-check (resume point) - STALE: superseded by the 'Merged' section at the end of this file

- Commit `5e713b7a`: fixed a real bug from the Part 1 sweep. In `family_map/widgets/avatar_marker_generator.dart` (6 sites) and
  `avatar_marker_overlay.dart` (1 site) the replacement produced `ui.KinrelColors.*`, which does not exist (analyzer errors:
  `KinrelColors isn't a class`, `expected_token`). Now `KinrelColors.*`. A repo-wide grep finds no other prefixed uses.
- `Flutter Analyze` on `5e713b7a` (run 44716160806) is still `failure`, but the **errors are gone**. What remains is 10 visible
  PRE-EXISTING warnings (GitHub only shows 10 annotations per job) in files this branch never touched, all outside `lib/` except one:
  `test/shared/widgets/kinrel_logo_test.dart` (3x prefer_const_constructors), `test/features/chat/chat_unified_inbox_test.dart:17`
  (unused import), `chat_family_event_card_test.dart:295` (unused `_StubCalendarNotifier`), `chat_block_report_test.dart`
  (const at 293, unused fields 39/60/62), `lib/graph/widgets/family_graph_engine_view.dart:149` (unused shown name `kWedgeDeclutterEdges`).
- Not fixed here: the task scope is `lib/**` only, and clearing warnings 10 at a time without log access is open-ended.
  Backend CI also fails on every commit (server/, untouched). `Flutter Test` had not finished when this was written.
- Parts 1-3 therefore remain UNMERGED (no green gate). Part 4 not started (budget/priority).
- Resume: decide whether to (a) clean the remaining baseline warnings in a separate branch off main, then re-run CI here, or
  (b) accept `Flutter Analyze` as a known-red baseline and merge on a human call. Also review sections A-C and the Part 3 flag lists.


## Merged (2026-11-23)

- Merged into `main` as `fb29a901` (`git merge --no-ff`, branch tip `bf35d834`; the merged tree is identical to that tip). Owner instruction: accept the Flutter Analyze baseline and merge; re-check first, stop on any new warning/error in a touched file.
- **Re-check result: no new warnings or errors, and no baseline warnings were left to accept.** `Flutter Analyze` on the tip (CI run 44737723187) = **success** (`--fatal-warnings`, so 0 warnings / 0 errors). The warnings listed in the stale "Session log" above (kinrel_logo_test, chat_unified_inbox_test, chat_family_event_card_test, chat_block_report_test, family_graph_engine_view) had already been cleared by later commits on this branch (8706d743, 2204143f, c991c585, 01951483, 2f99308e). So nothing was silently ignored: the baseline simply no longer existed.
- Commit `49cc03a8` (25 more tooltips) had put 3 tooltip args outside their `IconButton` (`undefined_named_parameter`, which broke Flutter Analyze and the Vercel build); `bf35d834` fixed it. That fix is what CI verified.
- **Part 4 IS in this merge** (`ceffe443`: `DKButton` / `DKSuggestionChip` haptics, `DKButton` press-scale honours Reduce Motion; file `lib/shared/widgets/dk_components.dart`). The "Part 4 not started" line in the Session log was stale.
- Known baseline, NOT fixed here (explicitly out of scope): `Flutter Test (fast)` was cancelled at its 25-minute timeout on the tip run, so the main unit suite never completed against these 283 changed Dart files (`Flutter Test (native_maps)` passed); `Backend CI` was skipped (no server files changed) and its typecheck failure (`predictions.scheduler.ts`) remains.
- Still open: the human-review lists in Part 1 (A-C), Part 3 (unlabeled icons, l10n of the 25 English tooltips, fixed-height boxes, contrast failures), and Part 4's missing success-moment animation.
