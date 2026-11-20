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
Status: in progress (all folders under lib/features, lib/presentation, lib/shared swept; awaiting CI verification before merge)
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
Status: not started
Files touched: (none yet)

## Part 3 - accessibility pass
Status: not started
Files touched: (none yet)
Contrast failures for design decision: (none yet)
Fixed-height containers that would clip under text scale: (none yet)

## Part 4 - flourishes
Status: not started
Files touched: (none yet)
