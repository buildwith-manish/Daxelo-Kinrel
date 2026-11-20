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

## H-K verification (read-only, awaiting approval to repair)

**Status: LIST FOR HUMAN APPROVAL ONLY.** Task 7e, run 2026-11-20 against Supabase project `promxswvsnvilplmrtsj` through the Supabase MCP using only `SELECT` statements. Nothing was written to prod. No `supabase migration repair`, `db push` or `migration up` was run. No file in `supabase/migrations/` was touched.

### Counts

| Classification | Files |
|---|---|
| confirmed applied | **98** |
| confirmed NOT applied | **3** |
| uncertain | **41** |
| **Total classified** | **142** |

Scope: the repo has 154 files with versions 20260807..20261021 (batches H-K). 12 of them have a version that already has a row in prod's `supabase_migrations.schema_migrations` (11 versions; `20260919100000` is shared by two files) and are excluded; the remaining 142 are classified below. (The earlier "~145" in the Prod check was an estimate; the exact number of unrecorded files is 142.) Excluded files: `20260831120000_get_member_branch_generic_type.sql`, `20260908120000_ensure_creator_person_rpc.sql`, `20260909120000_ensure_invited_person_rpc.sql`, `20260915160000_ghost_painter_ecosystem.sql`, `20260915170000_truthordare_archive_on_end.sql`, `20260915180000_truthordare_participant_fallback.sql`, `20260916100000_tugofwar_game.sql`, `20260916110000_tugofwar_rematch_rls.sql`, `20260917100000_memorymatch_game.sql`, `20260919100000_bingo_fix.sql`, `20260919100000_tugofwar_auto_teams.sql`, `20260922100000_tugofwar_broadcast_persist.sql`.

### How each file was checked (and what that does NOT prove)

- **Not every file was read line by line.** An extractor (regex) pulled out of each file: `CREATE TABLE` (+ columns), `ALTER TABLE ... ADD COLUMN`, `CREATE FUNCTION`, `CREATE INDEX`, `CREATE POLICY`, `CREATE TRIGGER`, `cron.schedule`, plus every `DROP`. The 13 files with no extractable objects were read by hand.
- Prod was then queried read-only for: table and column existence; function existence by name + argument count, and **function body** (whitespace-normalized md5 of the file's `$$` body vs prod `prosrc`, compared against the *last* file in the folder that defines that function); index, policy and trigger existence **by name**; `cron.job` names; replica identity and `supabase_realtime` membership for the realtime tables; RLS flags; the 11 named constraints; column-level grants on 3 tables; and a few data post-conditions.
- A function that a later file replaces is only counted as evidence for the earlier file when prod matches the later body; otherwise the earlier file is `uncertain`. Five functions differ from the repo only in comments/whitespace and are treated as matching: `_fn_broadcast_graph_invitation_change`, `_fn_broadcast_person_change`, `fn_search_kinrel_users`, `fn_sync_family_event_chat_cards`, `fn_touch_game_activity`.
- **Not compared:** column types, defaults, NOT NULL; index definitions (names only); policy and trigger bodies (names only); `COMMENT ON`; top-level seed `INSERT`s (except where named below); grants other than the 3 tables below; storage bucket rows other than `voice-messages`. So "confirmed applied" means *the named objects exist and (for functions) the bodies match*, not a full schema diff. A final prod-vs-repo schema diff is still needed before a bulk repair.
- "Low risk" in an uncertain line means marking the version applied cannot change prod behaviour (the object was later dropped, or a later definition supersedes it), only that the file's own application cannot be observed.

### Uncertain files (need the closest look before any repair)

- `20260807000000_invite_search_infra_verification.sql`: 3 objects match but 4 do not: column FamilyInvite.usedCount; function fn_generate_family_invite/4; policy FamilyInvite insert policy; +1 more.
- `20260808010000_family_invite_accept_reject_rpc.sql`: only evidence is function bodies that later files replaced: function fn_send_family_invite_notification/5 (superseded by 20260808030000_complete_invite_lifecycle.sql, prod matches that body); function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808020000_fix_invite_accept_trigger_and_chat.sql`: only evidence is function bodies that later files replaced: function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808040000_family_membership_sync.sql`: only evidence is function bodies that later files replaced: function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808060000_fix_thinking_of_you_rls.sql`: only evidence is function bodies that later files replaced: function fn_get_family_kinrel_members/1 (superseded by 20260808140000_fix_thinking_of_you_self_filter.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808070000_direct_messages_thinking_of_you.sql`: 27 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808080000_remove_thinking_from_notifications.sql`: 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808110000_chat_enhancement_schema.sql`: 71 object match but 2 do not: function fn_delete_message_for_everyone/1 (body differs from this file); function fn_toggle_reaction/2 (body differs from this file).
- `20260808150000_thinking_of_you_to_family_chat.sql`: 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808160000_fix_invite_accept_actionurl_quoting.sql`: only evidence is function bodies that later files replaced: function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808170000_fix_thinking_of_you_initials_and_cooldown.sql`: 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808180000_thinking_of_you_private_1to1.sql`: 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260816000000_fix_relationship_inverse_gender_aware.sql`: UNIQUE constraint RelationshipInverse_relationshipType_key exists and the table has 82 rows, but the 36 seeded (relationshipType, inverseType) upsert values were not compared row by row.
- `20260818130000_graph_invitation_recipient_user_id.sql`: 2 objects match but 1 do not: function fn_create_graph_pending_invitation/9 (body differs from this file).
- `20260818140000_return_recipient_user_id.sql`: only evidence is function bodies that later files replaced: function fn_get_pending_graph_invitations/1 (superseded by 20260825020000_add_updatedAt_to_get_pending.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260823160000_fix_invited_member_not_appearing.sql`: Its only trace is DROP INDEX Person_linkedUserId_unique (index is absent on prod, consistent) plus data/DDL that leaves no checkable object; CHANGELOG says this one matters, review by hand.
- `20260823200000_backfill_anchor_linkedUserId.sql`: Data backfill: 5 non-deleted anchor Person rows still have linkedUserId NULL although their Family.createdBy is set, so the backfill either did not run or those rows appeared afterwards.
- `20260824000000_fix_invitation_rpc.sql`: Drops the 8-arg fn_create_graph_pending_invitation (absent on prod, consistent) but the 9-arg function it relies on does not match any repo body on prod.
- `20260825000000_resend_invitation_and_cancel_notification.sql`: only evidence is function bodies that later files replaced: function fn_resend_graph_invitation/1 (superseded by 20260825010000_fix_invitation_rpc_record_case.sql, prod matches that body); function fn_cancel_graph_invitation/1 (superseded by 20260910100000_fix_fn_cancel_graph_invitation_plan_cache.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260904120000_proximity_graph_rpc.sql`: only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260904130000_proximity_rpc_ring3.sql`: only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260904140000_proximity_rpc_all_edges.sql`: only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260907130000_fix_viewer_graph_rpc_creator_unlinked.sql`: only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260907150000_remove_duplicate_backfill_for_family_creators.sql`: Data cleanup: 0 duplicate creator backfill Person rows remain (post-condition holds), but a DELETE/UPDATE leaves no trace, so this cannot distinguish applied from never needed.
- `20260907190000_fix_fn_accept_graph_invitation.sql`: only evidence is function bodies that later files replaced: function fn_accept_graph_invitation/1 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260909130000_fix_graph_invitation_inverse_gender_aware.sql`: only evidence is function bodies that later files replaced: function fn_accept_graph_invitation/1 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260909140000_backfix_cross_family_graph_invite_edges.sql`: Data backfill flagged "MUST be applied" in CHANGELOG: the file's own verification query returns 0 remaining cross-family edges on prod (post-condition holds), but that cannot distinguish applied from never needed.
- `20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql`: 1 object match but 1 do not: function get_viewer_family_graph/3 (body differs from this file).
- `20260919140000_prediction_battle.sql`: everything it creates was later dropped (table prediction_history (dropped by 20260923000000_prediction_battle_v0_deprecation.sql)); its own application cannot be observed. Low risk: the dropping migration is reflected on prod.
- `20260921120000_prediction_window_update.sql`: everything it creates was later dropped (function fn_prediction_get_active/1 (dropped by 20260923000000_prediction_battle_v0_deprecation.sql)); its own application cannot be observed. Low risk: the dropping migration is reflected on prod.
- `20260922120000_prediction_daily_refresh.sql`: prediction-battle v0 file: function fn_prediction_daily_tick/0, cron prediction-daily-tick-close, cron prediction-daily-tick-open absent on prod; the v0 feature was removed by 20260923000000 (reflected on prod), so absence fits applied-then-removed but cannot be told apart from never applied. Low risk: repair is moot if both are recorded.
- `20260922130000_prediction_index_audit.sql`: everything it creates was later dropped (index idx_prediction_leaderboard_family_points (table dropped by 20260923000000_prediction_battle_v0_deprecation.sql)); its own application cannot be observed. Low risk: the dropping migration is reflected on prod.
- `20260922140000_consolidate_edge_functions.sql`: 1 object match but 1 do not: function fn_process_scheduled_game_nights/0.
- `20260923120000_prediction_battle_v1_history_rpc.sql`: only evidence is function bodies that later files replaced: function fn_pb_v1_get_history/3 (superseded by 20260924020000_fix_history_rpc_cte_scope.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260923130000_prediction_battle_v1_history_leaderboard.sql`: only evidence is function bodies that later files replaced: function fn_pb_v1_get_history/3 (superseded by 20260924020000_fix_history_rpc_cte_scope.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260924000000_fix_question_row_to_json.sql`: only evidence is function bodies that later files replaced: function fn_pb_v1_get_next_question/1 (superseded by 20260924010000_fix_question_json_wrapper_v2.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20261001170000_rewrite_get_family_graph_cte_union_all.sql`: only evidence is function bodies that later files replaced: function get_family_graph/3 (superseded by 20261016120000_enforce_graph_rpc_membership.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20261004100000_game_room_lifecycle_state_machine.sql`: 3 objects match but 1 do not: function fn_sync_game_invite_status/5.
- `20261007000000_dm_game_invite_unified_lifecycle.sql`: 5 objects match but 1 do not: function fn_sync_game_invite_status/5.
- `20261011120000_dm_rebuild_direct_groups.sql`: 25 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20261016120000_enforce_graph_rpc_membership.sql`: 0 objects match but 2 do not: function get_family_graph/3 (body differs from this file); function get_member_branch/3 (body differs from this file).

### Findings that matter beyond the list

- **Possibly broken cron on prod:** `fn_process_scheduled_game_nights()` (20260922140000, 20261001180000) is absent while cron job `scheduled-game-nights-process` exists. Check the cron run history.
- **20261020120000_voice_messages_private_bucket is NOT applied:** the `voice-messages` bucket is still `public = true` on prod. Do not mark this version applied; it also needs staging review (it adds `AncestralMemory.storagePath`).
- **Rest of the CHANGELOG-flagged backfills:** `20260823200000` left 5 anchor Persons with `linkedUserId` NULL; `20260909140000` post-condition holds (0 cross-family edges).
- **FamilyInvite** on prod uses `useCount`/`currentUses` and differently named policies, not `usedCount` and `FamilyInvite insert/select policy` from `20260807000000`; `fn_generate_family_invite` exists with 3 args, not the file's 4. `fn_sync_game_invite_status` exists with 6 args, not the files' 5.
- **RelationshipReviewFlag** has RLS disabled on prod. Its creating file (`20260830120000`) does not enable RLS either, so this matches the file, but it is worth a separate look.
- 6 functions differ from every repo body (not just comments): `fn_create_graph_pending_invitation/9`, `fn_delete_message_for_everyone/1`, `fn_toggle_reaction/2`, `get_family_graph/3`, `get_member_branch/3`, `get_viewer_family_graph/3`. Someone edited them on prod or a later file was applied differently; diff them before trusting any repair.

### Full classified list (one line per file)

- `20260807000000_invite_search_infra_verification.sql`: **uncertain**. 3 objects match but 4 do not: column FamilyInvite.usedCount; function fn_generate_family_invite/4; policy FamilyInvite insert policy; +1 more.
- `20260808000000_username_availability_rpc.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260808010000_family_invite_accept_reject_rpc.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_send_family_invite_notification/5 (superseded by 20260808030000_complete_invite_lifecycle.sql, prod matches that body); function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808020000_fix_invite_accept_trigger_and_chat.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808030000_complete_invite_lifecycle.sql`: **confirmed applied**. Verified on prod: 2 functions.
- `20260808040000_family_membership_sync.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808050000_thinking_of_you_enhancement.sql`: **confirmed applied**. Verified on prod: 1 table, 7 columns, 3 indexes, 2 policies.
- `20260808060000_fix_thinking_of_you_rls.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_get_family_kinrel_members/1 (superseded by 20260808140000_fix_thinking_of_you_self_filter.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808070000_direct_messages_thinking_of_you.sql`: **uncertain**. 27 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808080000_remove_thinking_from_notifications.sql`: **uncertain**. 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808090000_family_management_system.sql`: **confirmed applied**. Verified on prod: 2 tables, 24 columns, 4 functions, 2 indexes, 5 policies.
- `20260808100000_family_management_enforcement.sql`: **confirmed applied**. Verified on prod: 3 functions.
- `20260808110000_chat_enhancement_schema.sql`: **uncertain**. 71 object match but 2 do not: function fn_delete_message_for_everyone/1 (body differs from this file); function fn_toggle_reaction/2 (body differs from this file).
- `20260808120000_voice_messages_storage.sql`: **confirmed applied**. Verified on prod: 4 policies.
- `20260808130000_family_management_permissions.sql`: **confirmed applied**. Verified on prod: 3 functions.
- `20260808140000_fix_thinking_of_you_self_filter.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260808150000_thinking_of_you_to_family_chat.sql`: **uncertain**. 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808160000_fix_invite_accept_actionurl_quoting.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_accept_family_invite/3 (superseded by 20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260808170000_fix_thinking_of_you_initials_and_cooldown.sql`: **uncertain**. 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808180000_thinking_of_you_private_1to1.sql`: **uncertain**. 10 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20260808190000_user_public_profile_rpc.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260811000000_fix_avatar_storage_rls.sql`: **confirmed applied**. Verified on prod: 4 policies.
- `20260813000000_create_family_groups.sql`: **confirmed applied**. Verified on prod: 2 tables, 19 columns, 6 functions, 6 indexes, 12 policies, 4 triggers.
- `20260815000000_v4_fundamental_edge_constraint.sql`: **confirmed applied**. Verified on prod: constraint relationship_fundamental_edge_check exists.
- `20260816000000_fix_relationship_inverse_gender_aware.sql`: **uncertain**. UNIQUE constraint RelationshipInverse_relationshipType_key exists and the table has 82 rows, but the 36 seeded (relationshipType, inverseType) upsert values were not compared row by row.
- `20260816020000_fix_duplicate_persons_and_add_constraint.sql`: **confirmed applied**. Verified on prod: 1 index.
- `20260816030000_relationship_rls_permissions.sql`: **confirmed applied**. Verified on prod: 2 policies.
- `20260816040000_profile_visibility_check_permissions.sql`: **confirmed applied**. Verified on prod: 2 columns, 2 functions, 3 policies.
- `20260817000000_graph_layout_state_edge_waypoints.sql`: **confirmed applied**. Verified on prod: 1 column.
- `20260818120000_graph_pending_invitations.sql`: **confirmed applied**. Verified on prod: 1 table, 18 columns, 1 function, 6 indexes, 4 policies.
- `20260818130000_graph_invitation_recipient_user_id.sql`: **uncertain**. 2 objects match but 1 do not: function fn_create_graph_pending_invitation/9 (body differs from this file).
- `20260818140000_return_recipient_user_id.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_get_pending_graph_invitations/1 (superseded by 20260825020000_add_updatedAt_to_get_pending.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260818160000_auto_set_edge_type.sql`: **confirmed applied**. Verified on prod: 1 function, 1 trigger.
- `20260823160000_fix_invited_member_not_appearing.sql`: **uncertain**. Its only trace is DROP INDEX Person_linkedUserId_unique (index is absent on prod, consistent) plus data/DDL that leaves no checkable object; CHANGELOG says this one matters, review by hand.
- `20260823200000_backfill_anchor_linkedUserId.sql`: **uncertain**. Data backfill: 5 non-deleted anchor Person rows still have linkedUserId NULL although their Family.createdBy is set, so the backfill either did not run or those rows appeared afterwards.
- `20260824000000_fix_invitation_rpc.sql`: **uncertain**. Drops the 8-arg fn_create_graph_pending_invitation (absent on prod, consistent) but the 9-arg function it relies on does not match any repo body on prod.
- `20260825000000_resend_invitation_and_cancel_notification.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_resend_graph_invitation/1 (superseded by 20260825010000_fix_invitation_rpc_record_case.sql, prod matches that body); function fn_cancel_graph_invitation/1 (superseded by 20260910100000_fix_fn_cancel_graph_invitation_plan_cache.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260825010000_fix_invitation_rpc_record_case.sql`: **confirmed applied**. Verified on prod: 2 functions.
- `20260825020000_add_updatedAt_to_get_pending.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260827000000_graph_layout_state_expanded_branches.sql`: **confirmed applied**. Verified on prod: 1 column.
- `20260828120000_chat_game_invite_card.sql`: **confirmed applied**. Verified on prod: 6 columns, 1 index.
- `20260829120000_create_get_family_tree_rpc.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260830120000_add_sibling_backfill_isPlaceholder_and_review_queue.sql`: **confirmed applied**. Verified on prod: 1 table, 14 columns, 5 indexes.
- `20260904120000_proximity_graph_rpc.sql`: **uncertain**. only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260904130000_proximity_rpc_ring3.sql`: **uncertain**. only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260904140000_proximity_rpc_all_edges.sql`: **uncertain**. only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260906180000_tier1_chat_features.sql`: **confirmed applied**. Verified on prod: 1 table, 4 columns, 2 functions, 3 policies.
- `20260906190000_tier2_disappearing_and_msginfo.sql`: **confirmed applied**. Verified on prod: 1 column, 4 functions.
- `20260907120000_auto_create_anchor_person_on_family_insert.sql`: **confirmed applied**. Verified on prod: 1 function, 1 trigger.
- `20260907130000_fix_viewer_graph_rpc_creator_unlinked.sql`: **uncertain**. only evidence is function bodies that later files replaced: function get_viewer_family_graph/3 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260907140000_fix_invite_accept_person_creation_and_stale_notifs.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260907150000_remove_duplicate_backfill_for_family_creators.sql`: **uncertain**. Data cleanup: 0 duplicate creator backfill Person rows remain (post-condition holds), but a DELETE/UPDATE leaves no trace, so this cannot distinguish applied from never needed.
- `20260907160000_graph_v2_2_broadcast_triggers.sql`: **confirmed applied**. Verified on prod: 2 functions, 2 policies, 2 triggers. Note: function _fn_broadcast_person_change/0 (body differs only in comments/whitespace).
- `20260907170000_graph_invitation_broadcast_trigger.sql`: **confirmed applied**. Verified on prod: 1 function, 1 trigger. Note: function _fn_broadcast_graph_invitation_change/0 (body differs only in comments/whitespace).
- `20260907180000_fix_graph_invite_member_count.sql`: **confirmed applied**. Verified on prod: 1 function, 1 trigger.
- `20260907190000_fix_fn_accept_graph_invitation.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_accept_graph_invitation/1 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260909130000_fix_graph_invitation_inverse_gender_aware.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_accept_graph_invitation/1 (superseded by 20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260909140000_backfix_cross_family_graph_invite_edges.sql`: **uncertain**. Data backfill flagged "MUST be applied" in CHANGELOG: the file's own verification query returns 0 remaining cross-family edges on prod (post-condition holds), but that cannot distinguish applied from never needed.
- `20260909150000_fix_inverse_label_target_gender_and_bfs_cap.sql`: **uncertain**. 1 object match but 1 do not: function get_viewer_family_graph/3 (body differs from this file).
- `20260910100000_fix_fn_cancel_graph_invitation_plan_cache.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260911140000_add_member_creation_idempotency.sql`: **confirmed applied**. Verified on prod: 1 function, 1 trigger.
- `20260912120000_temporary_game_rooms.sql`: **confirmed applied**. Verified on prod: 6 functions, 2 crons.
- `20260913120000_unified_multiplayer_room_lifecycle.sql`: **confirmed applied**. Verified on prod: 1 table, 12 columns, 6 functions, 4 indexes, 3 policies.
- `20260913130000_fix_multiplayer_rpcs_for_inline_player_tables.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260913140000_universal_family_achievements.sql`: **confirmed applied**. Verified on prod: 3 functions.
- `20260913150000_enable_pg_cron_for_auto_close.sql`: **confirmed applied**. Verified on prod: 2 crons.
- `20260914060000_room_close_hard_delete.sql`: **confirmed applied**. Verified on prod: 2 functions.
- `20260914080000_invite_dm_presence_realtime.sql`: **confirmed applied**. Verified on prod: 1 function, 1 cron.
- `20260914120000_family_invite_membership_source.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260914150000_autoclose_hard_delete.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260914160000_board_game_realtime_full_identity.sql`: **confirmed applied**. Verified on prod: REPLICA IDENTITY FULL on all 9 board-game tables it targets.
- `20260915100000_family_gaming_ecosystem.sql`: **confirmed applied**. Verified on prod: 10 tables, 103 columns, 11 functions, 19 indexes, 10 policies.
- `20260917140000_family_arena_privacy_and_participation.sql`: **confirmed applied**. Verified on prod: 6 functions, 3 policies.
- `20260917140001_column_level_privacy_game_match_history.sql`: **confirmed applied**. Verified on prod: column-level SELECT grants for authenticated on game_match_history, game_match_players and game_user_stats match the file exactly and no table-level SELECT remains.
- `20260917150000_family_arena_3zone_restructure.sql`: **confirmed applied**. Verified on prod: 1 table, 6 columns, 3 functions, 3 indexes, 3 policies.
- `20260917160000_family_arena_ux_refinements.sql`: **confirmed applied**. Verified on prod: 2 functions.
- `20260918100000_game_psychology.sql`: **confirmed applied**. Verified on prod: 1 table, 11 columns, 3 functions, 2 indexes, 1 policy.
- `20260918140000_ashtachamma_game.sql`: **confirmed applied**. Verified on prod: 2 tables, 39 columns, 4 functions, 3 indexes, 7 policies, 1 trigger.
- `20260918150000_connect4_game.sql`: **confirmed applied**. Verified on prod: 2 tables, 33 columns, 5 functions, 3 indexes, 7 policies, 1 trigger.
- `20260919120000_retention_systems.sql`: **confirmed applied**. Verified on prod: 6 tables, 44 columns, 7 functions, 3 indexes, 11 policies, 1 trigger.
- `20260919130000_impostor_game.sql`: **confirmed applied**. Verified on prod: 2 tables, 36 columns, 7 functions, 2 indexes, 7 policies, 1 trigger.
- `20260919140000_prediction_battle.sql`: **uncertain**. everything it creates was later dropped (table prediction_history (dropped by 20260923000000_prediction_battle_v0_deprecation.sql)); its own application cannot be observed. Low risk: the dropping migration is reflected on prod.
- `20260919150000_color_trap_game.sql`: **confirmed applied**. Verified on prod: 2 tables, 33 columns, 3 functions, 2 indexes, 7 policies, 1 trigger.
- `20260919160000_freeze_auction_game.sql`: **confirmed applied**. Verified on prod: 2 tables, 35 columns, 5 functions, 2 indexes, 7 policies, 1 trigger.
- `20260920100000_board_games_create_room_flow.sql`: **confirmed applied**. Verified on prod: 8 columns, 1 function.
- `20260920120000_flick_arena_game.sql`: **confirmed applied**. Verified on prod: 2 tables, 55 columns, 3 functions, 3 indexes, 5 policies, 1 trigger.
- `20260920140000_secret_heist_game.sql`: **confirmed applied**. Verified on prod: 3 tables, 44 columns, 9 functions, 3 indexes, 11 policies, 1 trigger.
- `20260920160000_mind_match_game.sql`: **confirmed applied**. Verified on prod: 5 tables, 53 columns, 8 functions, 5 indexes, 14 policies, 1 trigger.
- `20260920180000_code_clues_game.sql`: **confirmed applied**. Verified on prod: 3 tables, 38 columns, 7 functions, 3 indexes, 8 policies, 1 trigger.
- `20260920200000_night_falls_game.sql`: **confirmed applied**. Verified on prod: 3 tables, 46 columns, 10 functions, 3 indexes, 11 policies, 1 trigger.
- `20260920220000_sketch_telephone_game.sql`: **confirmed applied**. Verified on prod: 4 tables, 46 columns, 7 functions, 5 indexes, 12 policies, 1 trigger.
- `20260920240000_word_forge_game.sql`: **confirmed applied**. Verified on prod: 6 tables, 58 columns, 10 functions, 6 indexes, 18 policies, 1 trigger.
- `20260921000000_family_arena_qa_fixes.sql`: **confirmed applied**. Verified on prod: 1 column, 17 functions.
- `20260921020000_stickman_heist_game.sql`: **confirmed applied**. Verified on prod: 3 tables, 42 columns, 4 functions, 3 indexes, 11 policies, 1 trigger.
- `20260921040000_crystal_bridge_game.sql`: **confirmed applied**. Verified on prod: 2 tables, 33 columns, 8 functions, 2 indexes, 7 policies, 1 trigger.
- `20260921120000_prediction_window_update.sql`: **uncertain**. everything it creates was later dropped (function fn_prediction_get_active/1 (dropped by 20260923000000_prediction_battle_v0_deprecation.sql)); its own application cannot be observed. Low risk: the dropping migration is reflected on prod.
- `20260922000000_game_invites_inbox.sql`: **confirmed applied**. Verified on prod: 2 columns, 1 index.
- `20260922120000_prediction_daily_refresh.sql`: **uncertain**. prediction-battle v0 file: function fn_prediction_daily_tick/0, cron prediction-daily-tick-close, cron prediction-daily-tick-open absent on prod; the v0 feature was removed by 20260923000000 (reflected on prod), so absence fits applied-then-removed but cannot be told apart from never applied. Low risk: repair is moot if both are recorded.
- `20260922130000_prediction_index_audit.sql`: **uncertain**. everything it creates was later dropped (index idx_prediction_leaderboard_family_points (table dropped by 20260923000000_prediction_battle_v0_deprecation.sql)); its own application cannot be observed. Low risk: the dropping migration is reflected on prod.
- `20260922140000_consolidate_edge_functions.sql`: **uncertain**. 1 object match but 1 do not: function fn_process_scheduled_game_nights/0.
- `20260922150000_reduce_prediction_recovery_cron.sql`: **confirmed applied**. File body is only SELECT 1 (no-op), so there is nothing to apply; safe to record.
- `20260922160000_prediction_battle_v1_scheduled.sql`: **confirmed applied**. Verified on prod: 5 tables, 29 columns, 2 functions, 5 indexes, 6 policies, 3 crons.
- `20260923000000_prediction_battle_v0_deprecation.sql`: **confirmed applied**. Verified on prod: the 5 prediction_* v0 tables and 4 fn_prediction_* functions it drops are all absent.
- `20260923100000_truth_streak_deprecation.sql`: **confirmed applied**. Verified on prod: the 4 truth_streak_* tables it drops are absent and none is in the supabase_realtime publication.
- `20260923110000_notification_predictions_idempotency_index.sql`: **confirmed applied**. Verified on prod: 1 index.
- `20260923120000_prediction_battle_v1_history_rpc.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_pb_v1_get_history/3 (superseded by 20260924020000_fix_history_rpc_cte_scope.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260923130000_prediction_battle_v1_history_leaderboard.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_pb_v1_get_history/3 (superseded by 20260924020000_fix_history_rpc_cte_scope.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260923140000_prediction_battle_v1_fix_dependencies.sql`: **confirmed applied**. Verified on prod: 1 table, 8 columns, 2 indexes, 2 policies.
- `20260923150000_coin_economy.sql`: **confirmed applied**. Verified on prod: 2 tables, 13 columns, 3 functions, 4 indexes, 2 policies.
- `20260923160000_prediction_battle_v1_wire_coin_economy.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260923170000_prediction_battle_v1_user_questions.sql`: **confirmed applied**. Verified on prod: 1 table, 16 columns, 4 functions, 3 indexes, 2 policies.
- `20260923180000_prediction_battle_v1_feature_moment_spend.sql`: **confirmed applied**. Verified on prod: 1 column, 1 function, 1 index.
- `20260923190000_prediction_battle_v1_weekly_recap.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260923200000_prediction_battle_v1_difficulty_and_pool.sql`: **confirmed applied**. Verified on prod: 1 table, 7 columns, 1 function, 1 index, 1 policy.
- `20260923210000_prediction_battle_v1_lifecycle_change.sql`: **confirmed applied**. Verified on prod: 1 function, 3 crons.
- `20260924000000_fix_question_row_to_json.sql`: **uncertain**. only evidence is function bodies that later files replaced: function fn_pb_v1_get_next_question/1 (superseded by 20260924010000_fix_question_json_wrapper_v2.sql, prod matches that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20260924010000_fix_question_json_wrapper_v2.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260924020000_fix_history_rpc_cte_scope.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260924030000_thinking_stats_rpc.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20260924040000_thinking_of_you_emotion_and_inbox.sql`: **confirmed applied**. Verified on prod: 2 columns, 3 functions, 1 index.
- `20261001160000_add_missing_perf_indexes.sql`: **confirmed NOT applied**. none of its objects exist on prod: index Person_linkedUserId_idx; index User_email_trgm_idx; index idx_userpresence_updatedat_online (no equivalent index under another name found on Person, User or UserPresence).
- `20261001170000_rewrite_get_family_graph_cte_union_all.sql`: **uncertain**. only evidence is function bodies that later files replaced: function get_family_graph/3 (superseded by 20261016120000_enforce_graph_rpc_membership.sql; prod matches neither this nor that body). Cannot verify this file's own version; the effect is moot only if the final definer is verified.
- `20261001180000_fix_scheduled_game_nights_race_condition.sql`: **confirmed NOT applied**. fn_process_scheduled_game_nights/0 does not exist on prod at all, yet cron job scheduled-game-nights-process (which calls it) does exist: check whether that cron job is currently failing.
- `20261004100000_game_room_lifecycle_state_machine.sql`: **uncertain**. 3 objects match but 1 do not: function fn_sync_game_invite_status/5.
- `20261004120000_chat_game_invite_spectators_enabled.sql`: **confirmed applied**. Verified on prod: 1 column, 1 index.
- `20261004130000_room_expiry_15_min_inactivity.sql`: **confirmed applied**. Verified on prod: 1 function. Note: function fn_touch_game_activity/2 (body differs only in comments/whitespace).
- `20261004140000_fix_sweep_orphans_abandoned_inprogress.sql`: **confirmed applied**. Verified on prod: 1 function, 1 cron.
- `20261005120000_memories_image_vault_integration.sql`: **confirmed applied**. Verified on prod: 1 table, 19 columns, 1 function, 5 indexes, 7 policies, 1 trigger.
- `20261005160000_ancestral_memory_member_write_rls.sql`: **confirmed applied**. Verified on prod: 4 columns, 1 function, 3 policies, 1 trigger.
- `20261007000000_dm_game_invite_unified_lifecycle.sql`: **uncertain**. 5 objects match but 1 do not: function fn_sync_game_invite_status/5.
- `20261007080000_dm_reply_threading.sql`: **confirmed applied**. Verified on prod: 3 columns, 1 index.
- `20261007100000_dm_reactions_typing.sql`: **confirmed applied**. Verified on prod: 2 tables, 10 columns, 3 indexes, 6 policies.
- `20261011120000_dm_rebuild_direct_groups.sql`: **uncertain**. 25 objects match but 2 do not: policy TOE insert; policy TOE select.
- `20261016120000_enforce_graph_rpc_membership.sql`: **uncertain**. 0 objects match but 2 do not: function get_family_graph/3 (body differs from this file); function get_member_branch/3 (body differs from this file).
- `20261017120000_chat_block_and_report.sql`: **confirmed applied**. Verified on prod: 1 function, 2 indexes, 1 policy.
- `20261018120000_chat_scheduled_messages.sql`: **confirmed applied**. Verified on prod: 1 table, 13 columns, 1 function, 3 indexes, 4 policies, 1 cron.
- `20261019120000_bridge_disconnected_test_family_components.sql`: **confirmed applied**. File contains only comments (no executable SQL), so there is nothing to apply; safe to record. Shares version 20261019120000 with chat_family_event_cards.
- `20261019120000_chat_family_event_cards.sql`: **confirmed applied**. Verified on prod: 10 columns, 1 function, 1 index, 6 triggers. Note: function fn_sync_family_event_chat_cards/0 (body differs only in comments/whitespace).
- `20261020120000_voice_messages_private_bucket.sql`: **confirmed NOT applied**. voice-messages bucket is still public=true on prod, AncestralMemory.storagePath and ancestralmemory_family_topic_idx do not exist, and policy voice_messages_select_family_scoped is absent (prod has voice_messages_select_circle_scoped instead).
- `20261021051801_chat_mention_notify_and_group.sql`: **confirmed applied**. Verified on prod: 5 columns, 3 indexes.
- `20261021100000_enforce_mentions_rpc.sql`: **confirmed applied**. Verified on prod: 1 function.
- `20261021120000_chatmessage_scope_indexes.sql`: **confirmed applied**. Verified on prod: 2 indexes.

