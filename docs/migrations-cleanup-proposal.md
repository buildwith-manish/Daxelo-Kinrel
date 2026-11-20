# Migrations cleanup proposal

**Status: PROPOSAL ONLY.** No migration file was squashed, merged, renamed, reordered or deleted to produce this document.

## How this was made (and what it cannot tell you)

- Inputs: the **filenames** in `supabase/migrations/` (contents were not read), and `CHANGELOG.md` for any migration it names or any backfill/deploy note.
- Count: 342 files = 339 on `feature-registry` + 3 added by the unmerged `fix/2a`, `fix/3a`, `fix/4a` branches (batch M).
- **Prod migration history was checked read-only via the Supabase MCP (2026-11-20); results are in the "Prod check" section below.** Staging was not checked. The batch table's "squash candidate" column still reflects the filename-only analysis; the Prod check section says what changed.
- Dates are the timestamps in the filenames. They may not match real calendar dates (for example, the CHANGELOG ties the `20260909*` files to v5.192.x), so "age" is by filename order, not wall-clock months.

## Hygiene findings (apply regardless of any squash)

1. **22 duplicated version numbers.** Several files share the same 14-digit version prefix (e.g. `20260711000001`, `…000002`, `…000003`, `20260712000000`, `20260919100000`, `20261019120000`). Supabase keys applied migrations by version, so a duplicate can make `supabase db push` / `db reset` fail or skip a file on a fresh database.
2. **20 `*_rollback.sql` files live inside `supabase/migrations/`** (all in batch F, Track C / ML). The CLI treats every file in this folder as a forward migration, so on a fresh database a rollback file can run right after the migration it is meant to undo. This is an inference from the names; the file contents were not checked.
3. **One non-standard version:** `20260715_create_place_table.sql` has an 8-digit version (every other file has 14 digits).
4. Content-level duplicates exist by name (e.g. several `fix_*_rls_recursion` files in batch A, two `*_sparq_enhancement_*` files at the same timestamp), which a baseline would collapse.

## Batches

| Batch | Version range | Files | Theme (from names) | Squash candidate? | Risk |
|---|---|---|---|---|---|
| A | 20260603 – 20260609 | 24 | `production_sync`, RLS recursion/deadlock firefighting, `fix_duplicate_policies`, early indexes, orphan-family cleanup, `delete_family_forever_rpc` | **Yes**, first to go. Many files are fix-on-fix of the same RLS policies, so only the final state matters. | **Medium.** RLS history is easy to get subtly wrong; the baseline must come from a real schema dump, never hand-merged SQL. |
| B | 20260611 – 20260612 | 22 | `kinrel_v5_master_fix` sections 0–9, sparq enhancement, `graph_v2_1` steps 1–7 | **Yes** (same method). | **Medium.** Contains triggers, RPC functions, storage resync, realtime; verify those survive the dump. |
| C | 20260614 – 20260628 | 28 | RLS/advisor fixes, `person_link_invitation`, `viewer_perspective_graph`, `create_chat_messages`, `backfill_orphan_auth_users` (20260618) | **Yes**, with a check that the backfill already ran on prod (a one-time data fix; a schema dump does not replay it). | **Medium.** |
| D | 20260701 – 20260705 | 33 | dead kinship table drops, `custom_kinship_support`, ~20 `*_game` tables, calendar, game nights | **Yes.** | **Low–Medium.** Mostly additive `CREATE TABLE`; `drop_dead_kinship_tables` must be confirmed applied on prod so the baseline does not resurrect the tables. |
| E | 20260708 – 20260710 | 16 | aura/pulse/pitru tables, invite-RPC fixes, `thinking_of_you` | **Yes.** | **Low–Medium.** `20260711000002_rename_aura_to_kinrel` (batch F) depends on batch E objects, so the cut must fall exactly between E and F. |
| F | 20260711 – 20260712 | 56 | Track C (constitution, family decision, timeline, learning, search, partitioning, pg_boss) and ML tables, each with a rollback file; presence/shared lists; `family_os_phase_1_to_14` | **Later, not first.** Needs the hygiene fixes above (duplicate versions, 20 rollback files in the folder) before it can be squashed or even replayed. | **High.** Partitioned tables, triggers, RLS tightening, plus the duplicate-version/rollback problem. Needs a staging rehearsal. |
| G | 20260713 – 20260715 | 5 | viewer graph DOB/date of death, paginated graph RPC, `family_health_condition`, `create_place_table` (8-digit version) | Later, together with F. | **Medium.** Fix the 8-digit version first. |
| H | 20260807 – 20260831 | 44 | invite lifecycle, `thinking_of_you` iterations, family management/permissions, groups, graph pending invitations, `backfill_anchor_linkedUserId` (20260823), `sibling_backfill_isPlaceholder` (20260830) | **Keep separate for now.** Contains data backfills and a review queue; revisit once prod state is confirmed. | **Medium–High.** |
| I | 20260904 – 20260911 | 20 | proximity graph RPCs, chat tier 1/2, graph v2.2 broadcast triggers, `ensure_creator_person_rpc` (0908), `ensure_invited_person_rpc` (0909), `fix_graph_invitation_inverse_gender_aware` (0909), `backfix_cross_family_graph_invite_edges` (0909) | **Must stay separate.** The CHANGELOG (including the v5.192.1 entry) explicitly says these must be applied to prod, and the 20260909140000 backfill is data-correcting with a stated verification query. | **High.** |
| J | 20260912 – 20260924 | 68 | multiplayer rooms, family arena, ~25 more games, prediction battle v0→v1, coin economy, deprecation migrations | **Keep separate.** Large and recent; includes `*_deprecation` and `hard_delete` files whose final state a dump would capture, but they are the newest churn. | **High.** Re-evaluate after the next release cycle. |
| K | 20261001 – 20261021 | 22 | perf indexes, `rewrite_get_family_graph_cte_union_all`, DM rebuild, chat block/report, scheduled messages, mentions | **Must stay separate** (recent). | **High.** |
| L | 20261101 | 1 | `create_circles` | **Must stay separate.** | **High.** |
| M | 20261120 | 3 | story audience/thumbnail, shareablelink userId, familypostcomment (from unmerged `fix/2a`, `fix/3a`, `fix/4a`) | **Must stay separate.** Not applied anywhere; each needs staging review per `docs/fix-progress.md`. Not on `feature-registry` yet. | **High** (unapplied). |

Batches A–E total **123 files** (everything up to 20260710). A–G total 184.

## Referenced by CHANGELOG.md (must stay as separate files regardless of age)

- `20260823160000_fix_invited_member_not_appearing`
- `20260908120000_ensure_creator_person_rpc` (must be applied to prod for auto-recovery)
- `20260909120000_ensure_invited_person_rpc`
- `20260909130000_fix_graph_invitation_inverse_gender_aware`
- `20260909140000_backfix_cross_family_graph_invite_edges` (backfill; "MUST be applied to prod")

All five fall in batches H–I, which are already on the keep-separate list.

## Top recommendation

**Squash batches A–E (123 files, up to `20260710000001`) into one baseline, and leave everything from `20260711` on untouched for now.**

Suggested method (not performed):
1. Confirm against prod's `supabase_migrations.schema_migrations` that all 123 are applied.
2. Generate the baseline from a **schema-only dump of prod** (not by concatenating the SQL files), restricted to what those 123 files created.
3. Mark the 123 old versions as applied with `supabase migration repair` on prod and staging, and move the old files to an archive folder (do not delete them).
4. Prove it on a **fresh staging project**: baseline + the remaining files must produce a schema that diffs clean against prod.

**Risk level: Medium.** The old files are superseded fix-on-fix history (low value to keep), but RLS policies, triggers and storage settings are exactly what a lossy dump can drop, and I could not verify prod's applied state or read file contents. Do not run this on prod without the step-4 rehearsal.

**Do before or alongside it (low risk, high value):** resolve the 22 duplicate versions, move the 20 rollback files out of the migrations folder, and fix the 8-digit `20260715_` version. These are what currently make a fresh `db reset` unreliable.

## Not verified

- Applied state on **staging** (only the single prod project was visible). Prod's *history table* is checked below; object-level checks were spot checks, not a full schema diff.
- File contents (names only were read), so "theme" is inferred from filenames.
- That `docs/MIGRATIONS.md` (referenced by CONTRIBUTING.md) is consistent with this proposal; it was not read.

## Prod check (Supabase MCP, read-only SELECTs; nothing was written to prod)

Project `promxswvsnvilplmrtsj` (Daxelo-Kinrel, the only project visible). `supabase_migrations.schema_migrations` has **176 rows**. Compared by version number against the 342 repo files (320 distinct versions):

| Batch(es) | Repo files | Version recorded on prod | Notes |
|---|---|---|---|
| A–E (≤ 20260710) | 123 | **123 / 123** | The top recommendation's step 1 is confirmed for the history table. |
| F–G (20260711–20260715) | 61 | 61 / 61 | Track C is recorded as 27 rows all named `trackc_manual` (versions `…000001`–`…000027`), so prod's names do not match the repo's file names for those; versions do. |
| H (202608) | 44 | **1 / 44** (only `20260831120000`) | |
| I (20260904–11) | 20 | **2 / 20** (`20260908120000`, `20260909120000`, both named "applied out-of-band") | |
| J (20260912–24) | 68 | **9 / 68**, several unnamed rows | |
| K (202610) | 22 | **0 / 22** | |
| L–M (202611) | 4 | 1 / 4 (`20261101120000`, "applied out-of-band") | |

No prod version lacks a repo file.

**Main finding: prod's migration history is out of sync with the repo for batches H–K (about 145 files).** The schema objects from those batches do exist on prod, so they were applied some other way (SQL editor / manual) without being recorded. Spot checks that exist on prod: graph invitation functions (`fn_accept_graph_invitation`, `fn_cancel_graph_invitation`, `fn_ensure_creator_person`, `fn_ensure_invited_person`), `fn_check_username_available`, `get_family_tree`, coin economy tables/functions, Circle tables and circle helper functions, `ChatMention`, `ChatScheduledMessage`, `BlockedUser`, Group tables, `DirectMessage`, the tug-of-war / flick arena / impostor / memory match / connect4 / ashta chamma tables, and `pb-v1-*` cron jobs. (Prediction battle *tables* did not show up under a `%predict%` name search; the cron jobs did. Not investigated.)

**What this changes in the recommendation**
- Squashing A–E is now confirmed safe *as far as the history table goes* (all 123 recorded). Risk stays **Medium**: object-level drift in A–E was not checked, so the staging rehearsal (step 4) is still required.
- **Do not run `supabase db push` against prod as things stand.** The CLI sees ~145 repo versions as unapplied and would try to re-run them. Many are idempotent, but that is not guaranteed. Reconcile history first (`supabase migration repair --status applied <version>` per verified version, or a single reviewed bulk repair).
- The repair must be **per-migration verified**, not blanket: marking a never-applied migration as applied makes it silently never run. That is why no repair was performed here.
- **Batch M:** `FamilyPostComment` does **not** exist on prod (the 4a migration is genuinely unapplied). `Story.audience`, `Story.thumbnailUrl` and `ShareableLink.userId` already exist on prod, so the 2a and 3a migrations are expected no-ops (they were written idempotent).

Not checked in this pass: staging; a full prod-vs-repo schema diff; security/performance advisors; contents of the Track C `trackc_manual` rows.

## File hygiene

**Findings only. Nothing in `supabase/migrations/` was renamed, moved, merged or deleted.** Counts: **22 duplicate version numbers (44 files), 20 rollback files, 1 malformed (8-digit) version.** The 20 rollback files are the same files as 20 of the 22 duplicate pairs, so the number of distinct files affected is 45, not 85. This section refines the shorter "Hygiene findings" list near the top of this document.

### (a) Duplicate version numbers: 22 pairs

"Recorded on prod" = that version exists in prod's `supabase_migrations.schema_migrations` (see "Prod check" below).

| Version | Files | Kind | Recorded on prod |
|---|---|---|---|
| `20260711000001` | `20260711000001_trackc_create_constitution.sql`<br>`20260711000001_trackc_create_constitution_rollback.sql` | forward + rollback | yes |
| `20260711000002` | `20260711000002_trackc_create_family_decision.sql`<br>`20260711000002_trackc_create_family_decision_rollback.sql` | forward + rollback | yes |
| `20260711000003` | `20260711000003_04_trackc_timeline_rollback.sql`<br>`20260711000003_trackc_create_aura_timeline.sql` | forward + rollback | yes |
| `20260711000005` | `20260711000005_trackc_create_ai_insight.sql`<br>`20260711000005_trackc_create_ai_insight_rollback.sql` | forward + rollback | yes |
| `20260711000006` | `20260711000006_07_trackc_learning_rollback.sql`<br>`20260711000006_trackc_create_learning_signal.sql` | forward + rollback | yes |
| `20260711000008` | `20260711000008_10_trackc_reminder_memory_artifact_rollback.sql`<br>`20260711000008_trackc_create_smart_reminder.sql` | forward + rollback | yes |
| `20260711000011` | `20260711000011_12_trackc_search_rollback.sql`<br>`20260711000011_trackc_create_search_index.sql` | forward + rollback | yes |
| `20260711000013` | `20260711000013_trackc_create_analytics_snapshot.sql`<br>`20260711000013_trackc_create_analytics_snapshot_rollback.sql` | forward + rollback | yes |
| `20260711000014` | `20260711000014_17_trackc_partitioning_rollback.sql`<br>`20260711000014_trackc_partition_family_decision.sql` | forward + rollback | yes |
| `20260711000018` | `20260711000018_20_trackc_rls_pgboss_seed_rollback.sql`<br>`20260711000018_trackc_rls_all_tables.sql` | forward + rollback | yes |
| `20260711000023` | `20260711000023_trackc_tighten_constitution_rls_writes.sql`<br>`20260711000023_trackc_tighten_constitution_rls_writes_rollback.sql` | forward + rollback | yes |
| `20260711000024` | `20260711000024_trackc_create_search_embedding.sql`<br>`20260711000024_trackc_create_search_embedding_rollback.sql` | forward + rollback | yes |
| `20260711000025` | `20260711000025_ml_user_engagement_profile.sql`<br>`20260711000025_ml_user_engagement_profile_rollback.sql` | forward + rollback | yes |
| `20260711000026` | `20260711000026_ml_brief_engagement.sql`<br>`20260711000026_ml_brief_engagement_rollback.sql` | forward + rollback | yes |
| `20260711000027` | `20260711000027_ml_learned_closeness_weights.sql`<br>`20260711000027_ml_learned_closeness_weights_rollback.sql` | forward + rollback | yes |
| `20260711000301` | `20260711000301_kinrel_neutral_archetype_defaults.sql`<br>`20260711000301_kinrel_neutral_archetype_defaults_rollback.sql` | forward + rollback | yes |
| `20260711000401` | `20260711000401_family_map_last_known_location.sql`<br>`20260711000401_family_map_last_known_location_rollback.sql` | forward + rollback | yes |
| `20260712000000` | `20260712000000_fix_relationship_isactive_trigger.sql`<br>`20260712000000_fix_relationship_isactive_trigger_rollback.sql` | forward + rollback | yes |
| `20260712000001` | `20260712000001_add_notification_timing_optin.sql`<br>`20260712000001_add_notification_timing_optin_rollback.sql` | forward + rollback | yes |
| `20260712000002` | `20260712000002_add_bridge_role_optin.sql`<br>`20260712000002_add_bridge_role_optin_rollback.sql` | forward + rollback | yes |
| `20260919100000` | `20260919100000_bingo_fix.sql`<br>`20260919100000_tugofwar_auto_teams.sql` | **two unrelated forward migrations** | yes |
| `20261019120000` | `20261019120000_bridge_disconnected_test_family_components.sql`<br>`20261019120000_chat_family_event_cards.sql` | **two unrelated forward migrations** | **no** |

- **20 of the 22 pairs are a forward migration plus its own rollback** (rollback file shares the forward file's version).
- **2 pairs are two unrelated forward migrations sharing one timestamp** (the ones that need a human decision, since neither is a rollback):
  - `20260919100000`: `bingo_fix` vs `tugofwar_auto_teams`
  - `20261019120000`: `bridge_disconnected_test_family_components` vs `chat_family_event_cards`
- Supabase records one row per version, so a duplicate version cannot be tracked as two applied migrations. Prod shows the effect: the 27 Track C versions are recorded as `trackc_manual` rows (applied by hand), and the unnamed `20260919100000` row cannot say which of its two files it stands for.

### (b) Rollback files: 20

All 20 live in batches F–G (`20260711`–`20260712`). For every one, the forward migration it undoes **still exists** in the folder (checked by filename). Exact files:

| Rollback file | What it rolls back | Forward migration still exists? |
|---|---|---|
| `20260711000001_trackc_create_constitution_rollback.sql` | drops 4 updated_at triggers + the 4 constitution tables (FamilyConstitution, ConstitutionVersion, ConstitutionArticle, ConstitutionClause) | yes — `20260711000001_trackc_create_constitution.sql` |
| `20260711000002_trackc_create_family_decision_rollback.sql` | drops trigger + `DecisionVote` + `FamilyDecision` | yes — `20260711000002_trackc_create_family_decision.sql` |
| `20260711000003_04_trackc_timeline_rollback.sql` | drops append-only triggers/function + `AURATimelineEvent` (header: undoes 000003 + 000004) | yes — `20260711000003_trackc_create_aura_timeline.sql`, `20260711000004_trackc_create_timeline_triggers.sql` — **sorts BEFORE its forward file** |
| `20260711000005_trackc_create_ai_insight_rollback.sql` | drops trigger + `AIInsight` | yes — `20260711000005_trackc_create_ai_insight.sql` |
| `20260711000006_07_trackc_learning_rollback.sql` | drops `LearningSignal`, `FamilyBehaviorProfile`, `FamilyBehaviorProfileHistory` (header: 06 + 07) | yes — `20260711000006_trackc_create_learning_signal.sql`, `20260711000007_trackc_create_family_behavior_profile.sql` — **sorts BEFORE its forward file** |
| `20260711000008_10_trackc_reminder_memory_artifact_rollback.sql` | drops `SmartReminder`, `DecisionMemory`/`DecisionImpact`, `MeetingArtifact` + triggers (header: 08 + 09 + 10) | yes — `20260711000008_trackc_create_smart_reminder.sql`, `20260711000009_trackc_create_decision_memory.sql`, `20260711000010_trackc_create_meeting_artifact.sql` — **sorts BEFORE its forward file** |
| `20260711000011_12_trackc_search_rollback.sql` | drops `search_index_tsvector_gin`, `SearchIndex.search_tsvector`, trigger, `SearchIndex` (header: 11 + 12) | yes — `20260711000011_trackc_create_search_index.sql`, `20260711000012_trackc_create_search_tsvector.sql` — **sorts BEFORE its forward file** |
| `20260711000013_trackc_create_analytics_snapshot_rollback.sql` | drops `FamilyAnalyticsSnapshot` | yes — `20260711000013_trackc_create_analytics_snapshot.sql` |
| `20260711000014_17_trackc_partitioning_rollback.sql` | 105 lines; swaps the 4 partitioned tables back to non-partitioned. Own header: **destructive if partitions hold data**, run only in a maintenance window (header: 14-17) | yes — `20260711000014_trackc_partition_family_decision.sql`, `20260711000015_trackc_partition_timeline.sql`, `20260711000016_trackc_partition_ai_insight.sql`, `20260711000017_trackc_partition_learning_signal.sql` — **sorts BEFORE its forward file** |
| `20260711000018_20_trackc_rls_pgboss_seed_rollback.sql` | drops all Track C RLS policies, pg-boss schema objects and seed; own header: **"Drops all Track C tables. Use only for full uninstall."** (header: 18 + 19 + 20) | yes — `20260711000018_trackc_rls_all_tables.sql`, `20260711000019_trackc_pg_boss_schema.sql`, `20260711000020_trackc_seed_global_defaults.sql` — **sorts BEFORE its forward file** |
| `20260711000023_trackc_tighten_constitution_rls_writes_rollback.sql` | restores the permissive any-active-member INSERT/UPDATE/DELETE policies on the 4 constitution tables | yes — `20260711000023_trackc_tighten_constitution_rls_writes.sql` |
| `20260711000024_trackc_create_search_embedding_rollback.sql` | drops `SearchEmbedding` | yes — `20260711000024_trackc_create_search_embedding.sql` |
| `20260711000025_ml_user_engagement_profile_rollback.sql` | drops `UserEngagementProfile` | yes — `20260711000025_ml_user_engagement_profile.sql` |
| `20260711000026_ml_brief_engagement_rollback.sql` | drops `BriefEngagement` | yes — `20260711000026_ml_brief_engagement.sql` |
| `20260711000027_ml_learned_closeness_weights_rollback.sql` | drops `LearnedClosenessWeights` | yes — `20260711000027_ml_learned_closeness_weights.sql` |
| `20260711000301_kinrel_neutral_archetype_defaults_rollback.sql` | resets the Kinrel archetype / inner-pattern column defaults back to `lotus`. **Header cites a non-existent file** `20260711000300_kinrel_neutral_archetype_defaults.sql`; the real forward file is version `…000301` (version `…000300` is `presence_and_shared_lists`) | yes — `20260711000301_kinrel_neutral_archetype_defaults.sql` |
| `20260711000401_family_map_last_known_location_rollback.sql` | drops `MemberLocation` trigger, function, indexes, policies (table) | yes — `20260711000401_family_map_last_known_location.sql` |
| `20260712000000_fix_relationship_isactive_trigger_rollback.sql` | drops trigger `trg_ensure_relationship_isactive_default` + its function | yes — `20260712000000_fix_relationship_isactive_trigger.sql` |
| `20260712000001_add_notification_timing_optin_rollback.sql` | drops column `notificationTimingOptIn` | yes — `20260712000001_add_notification_timing_optin.sql` |
| `20260712000002_add_bridge_role_optin_rollback.sql` | drops column `Family.bridgeRoleOptIn` | yes — `20260712000002_add_bridge_role_optin.sql` |

Findings beyond the list:
1. **Six rollbacks cover a range of forward migrations but carry only one version** (`000003`, `000006`, `000008`, `000011`, `000014`, `000018`). They do not map one-to-one to a forward file, which is why the pair table above shows them sharing a version with just the first forward file in each range.
2. **Those same six sort before their forward file by filename** (`…000003_04_trackc_timeline_rollback.sql` < `…000003_trackc_create_aura_timeline.sql`, because a digit sorts before a letter). If the folder were ever replayed in filename order, the `…000018_20_…rollback.sql` file (which its own header says drops all Track C tables) would run after the Track C creates of `000001`–`000017` and before the `000018` RLS file, so the RLS migration would then find no tables. In practice the duplicate version key is likely to stop a replay earlier; either way a fresh `db reset` from this folder cannot be trusted. Not tested here.
3. **One stale reference:** `20260711000301_kinrel_neutral_archetype_defaults_rollback.sql` points at `20260711000300_kinrel_neutral_archetype_defaults.sql`, which does not exist (the forward file is `…000301`). No other rollback header cites a missing file.
4. Two rollbacks warn in their own header about data loss (the partitioning one and the full Track C uninstall), and most of the rest are plain `DROP TABLE`/`DROP COLUMN` scripts. They are safe only as manual, deliberately-run scripts, not as migrations.

### (c) The 8-digit version: 1 file

`20260715_create_place_table.sql` (every other file uses 14 digits).

- **What it is:** P10.1, creates the `Place` table (Family Atlas) with RLS. It only references `Family` and `Person`, which exist since June, so its position does not matter for dependencies.
- **Where it sorts today:** plain filename order puts it last among its neighbors (`_` sorts after digits), i.e. *after* `20260715120000_create_family_health_condition_table.sql`. Compared as version strings it would sort *before* `20260715120000`, and compared as a number (`20260715`) it would sort before every other migration. The three orderings disagree, which is the real problem.
- **What its version probably should have been:** it was committed on **2026-07-13 at 16:18 UTC** (commit `e45bb416`), after `20260713140000_add_date_of_death.sql` (committed 2026-07-13 11:16 UTC) and before `20260715120000_create_family_health_condition_table.sql` (2026-07-15 11:57 UTC). So it belongs between those two. Best guess: **`20260713160000`** (hour-rounded like its neighbors; the exact commit time would be `20260713161800`). Any value strictly between `20260713140000` and `20260715120000` sorts correctly.
- **Prod caveat:** prod already has this version recorded as `20260715` (named `create_place_table`) and the `Place` table exists there. Renaming the file later means also repairing prod's history (`supabase migration repair`: mark `20260715` reverted and the new version applied), otherwise prod and the repo disagree again.

### Overlap with "Prod check" (section above)

- **Yes, they overlap.** 21 of the 22 duplicate versions are recorded on prod (all 20 forward+rollback pairs, plus `20260919100000`); the one not recorded is `20261019120000`, which is in batch K (0 of 22 recorded).
- All 20 rollback files fall inside the F–G block that "Prod check" shows as 61/61 versions recorded. Prod's rows for them are the 27 `trackc_manual` entries (`…000001`–`…000027`) plus `…000301`, `…000401`, `…0712*`; they do not carry the repo's file names.
- The 8-digit file is the prod row `20260715` / `create_place_table`.
- So any rename or move of these files has to be paired with a history repair on prod. That makes cleanup of batch F–G a prod-history task as well as a folder task.
