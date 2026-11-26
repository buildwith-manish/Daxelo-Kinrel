# Graph UX progress

Flutter app only (`Daxelo-Kinrel-App/lib/`). Engine = `lib/graph`. Branch model: `fix/<TASKID>` from `main`, merged `--no-ff` after CI is green.
Status values: `not started` | `in progress (<resume note>)` | `done (merged <sha>)`.

| ID | Status | Notes |
|---|---|---|
| G1a | done (merged 891d6eb9) | read-only audit + this file; no code changed |
| G1b | in progress (code on fix/G1b @ 551e934f, Analyze green; unit test not yet run by CI; NOT merged - see G1b log) | one-sentence summary at top of the info sheet |
| G1c | done (merged b7ea7c0f; Analyze + native_maps green, Test (fast) not green: known baseline) | path highlight while the info sheet is open |
| G2a | done (merged db52ba67) | read-only audit: default camera, default collapse, recenter call, collapsed look, size threshold |
| G2b | in progress (code pushed on `fix/G2b` @ 3961baf1, NOT merged: waiting for owner because `Flutter Test (fast)` cannot go green, known baseline) | large-tree first-open default |

> Scope note: the file `graph-ux-implementation-prompts` that defines G1b/G1c was not available to the G1a session. The plan below is organised
> by the gaps this audit found (A = label/terms, B = path + sheet UI, C = "me"), and the "likely G1b / likely G1c" mapping is an assumption.
> Re-map it when the real G1b/G1c text is read.

All paths below are relative to `Daxelo-Kinrel-App/lib/`. Everything here was established by READING code; no Dart was run (no Flutter SDK in the sandbox),
so statements about runtime behaviour are marked **(by reading)** where I could not execute them.

---

## G1 audit

### 1. How a relationship label is computed today

There are two label paths, and they differ.

**(a) Edge label, one hop: stored type string.** `RelationshipInfoSheet.show(relationshipKey: ...)` receives the stored edge type (e.g. `father`).
The sheet formats it with `_formatKey` and builds the inverse with `genderAwareInverse(relationshipKey, targetGender)` (imported from
`core/family/relationship_edge_builder.dart`). No path is involved.

**(b) Viewer to target, any number of hops: path + structural classifier.** This is the one that yields a PATH.

1. `RelationshipEngine.instance.resolvePath(viewerPersonId, targetPersonId, persons, relationships)` in `core/relationship/relationship_engine.dart`
   (delegates to `GraphService.findPath`, BFS). Returns `List<PathStep>?` (`core/graph/graph_service.dart:43`):
   `PathStep{personId, personName, type, direction}`. `null`/empty = unreachable.
2. `GraphPathFocusNotifier.resolve(...)` in `graph/interaction/graph_kinship_path_focus.dart:243` wraps that and returns
   `GraphKinshipPathFocus?`. Inputs: `viewerPersonId`, `targetPersonId`, `edges` (deduped), `persons` (`GraphPerson` incl. `gender`),
   `relationships` (`{fromId,toId,type}`), `graphRevision`, optional pre-computed `StructuralClassification`.
   Short-circuits to `null` when viewer or target is null or viewer == target.
3. Label: `StructuralKinshipClassifier.classify(path: List<String>, targetGender, viewerGender)` in
   `core/kinship/structural_kinship_classifier.dart:122`. Returns `StructuralClassification{category, label, key}`; never null.
   `GraphPathFocusNotifier._computeClassification` (line ~457) feeds it the BFS step types after `_invertForTarget(...)`.
   Other callers: `core/relationship/relationship_engine.dart` (100, 157, 166), `graph/interaction/proximity_graph_state.dart:447`,
   `graph/widgets/engine/subtree_mixin.dart:369`, `graph/engine/viewer_wedge_layout.dart` (single-key, category only).

**Does it already yield a path? YES.** `GraphKinshipPathFocus` (`graph_kinship_path_focus.dart:113`) carries:
`steps: List<GraphPathFocusStep{personId, personName, relationshipType, edgeId, direction}>` (first step = viewer, `edgeId == null`),
`orderedPersonIds`, `orderedEdgeIds`, `resolvedRelationshipKey`, `resolvedRelationshipLabel`, `resolvedCategory`, `graphRevision`,
plus `stepCount` and `isMultiHop`. So path data (persons + edges) and the label both exist; G1b/G1c do not need a new BFS.
Unresolvable hops are skipped with a `debugPrint` (an edge missing from the deduped list), so `orderedEdgeIds` can be shorter than the path.

**Where the label loses information (the main finding).** `_invertForTarget` collapses `father`/`mother` into a role (`parent`) BEFORE the classifier
runs, and the classifier works on roles + generation counts. Its labels are neutral English: `Uncle`/`Aunt`, `Grandfather`/`Grandmother`,
`Cousin`, `Nephew`/`Niece`, `Brother-in-law`, `Mother-in-law`, ... (see lines ~166-300 and ~480-575). Only gender of the TARGET is used.
It never emits "paternal" or "maternal" and never distinguishes elder/younger. **(by reading)** the side information is recoverable
upstream: step 1 of a path that goes up through a parent is the viewer's parent, and `GraphPerson.gender` for that person says father vs mother.

### 2. Kinship languages and terms

**Language picker** (`features/family/presentation/widgets/kinship_language_selector.dart`; note: it lives under `presentation/widgets/`, not `presentation/`):
a pill showing `Auto` or the upper-cased code; tap opens a bottom sheet with search, a "Show English underneath" switch and a radio list built from
`languageCodeToName` (`core/kinship/language_code_map.dart`). Preference is `kinshipTermLanguageProvider` (`core/kinship/kinship_term_language_provider.dart`),
`'auto'` = follow app language. The info sheet treats `auto` as `en`.

**The picker is not mounted anywhere (grep for `KinshipLanguageSelector` outside its own file = 0 hits), and it is the ONLY code that calls
`kinshipTermLanguageProvider.notifier`.** So in the current build nothing in the UI can change the preference away from `auto`, and the info sheet maps `auto` to `en`:
native-language terms on the sheet are not reachable by a user today, independent of the vocabulary problems below. (If a settings screen sets it through some other API I did not find,
this is wrong; the grep covered `lib/**/*.dart` for `kinshipTermLanguageProvider.notifier`.)

**Two independent definitions of the same provider names (duplicate-provider hazard).** `kinshipTermLanguageProvider` and `showEnglishSubtitleProvider` are each declared twice, in
`core/kinship/kinship_term_language_provider.dart` (lines 24, 38; persists to SecureStorage keys `kinship_term_language` / `show_english_subtitle`) and in `core/kinship/kinship_term_providers.dart`
(lines 173, 180; has its own load/set notifier; its storage key I did not check). They are different provider objects. Consumers split:
- imports the `kinship_term_language_provider.dart` one: `graph/widgets/relationship_info_sheet.dart`, `features/home/providers/kinship_terms_for_family_provider.dart`, and the selector widget;
- imports the `kinship_term_providers.dart` one: `features/todays_question/*`, `features/chat/data/mention_candidates_provider.dart`, `mention_candidates_sync_provider.dart`.
Even once the selector is mounted, it would drive only the first group. Any G1 work that adds language-dependent UI must pick ONE of them (the sheet's, i.e. `kinship_term_language_provider.dart`) and must not "fix" the duplication
without being asked, since 6 files depend on the split.

**22 codes are selectable (if the picker were reachable):** hi, bn, te, mr, ta, gu, kn, ml, pa, or, as, ur, sa, sd, en, zh, ja, ko, ar, es, fr, de.

**Which have term data in the table the info sheet uses (`core/kinship/v4/vocabulary_data.dart`, `VocabularyData.seeds`):** 11 = en, hi, ta, te, kn, ml, bn, mr, gu, pa, ur.
76 seeds; 75 of them carry all 11 language keys (my regex matched 75, one seed has a different shape, not inspected). The other 11 selectable codes
(or, as, sa, sd, zh, ja, ko, ar, es, fr, de) have NO entry in this table, so the info sheet always falls back to English for them. There are separate
`global_kinship_*` / `country_kinship_*` files in `core/kinship/` (zh/ja/ko/ar/es/fr/de are labelled "P8.1: Global kinship languages"); I did not read them, so whether
they feed any graph UI is unknown.

**Maternal vs paternal coverage in the vocab seeds** (`side: FamilySide.paternal` = 12 seeds, `maternal` = 10 seeds). The distinction exists ONLY for these relations:

| Relation (pathPattern) | Seeds | Terms (hi / ta / te / kn / ml / bn / mr / gu / pa / ur) |
|---|---|---|
| grandfather `UP_PARENT_UP_PARENT` | pat, mat | pat: Dada / Thatha / Thata / Ajja / Achachan / Dadu / Ajoba / Dada / Dada / Dada. mat: **Nana** / Thatha / Thata / Ajja / Achachan / Dadu / Ajoba / **Nana** / **Nana** / **Nana** |
| grandmother | pat, mat | pat: Dadi / Paatti / Naayana / Ajji / Ammamma / Thakurma / Aaji / Dadi / Dadi / Dadi. mat: **Nani** / Paatti / **Ammaamma** / Ajji / Ammamma / **Didima** / Aaji / **Nani** / **Nani** / **Nani** |
| uncle `UP_PARENT_UP_PARENT_DOWN_CHILD` (parent's brother) | pat (plain, elder = Tau, younger = Chacha), mat | pat: Chacha / Appa / Baava / Appa / Achachan / Jyethu / Kaka / Kaka / Chacha / Chacha. mat: **Mama** / Mama / Menamama / Mava / Achachan / Mama / Mama / Mama / Mama / Mama |
| aunt (parent's sister) | pat, mat | pat: Bua / Athai / Baammavi / Atthe / Achamma / Pishi / Atya / Foi / Bhua / Phuphi. mat: **Mausi** / Mami / Menamma / Atthe / Ammayi / Mashi / Mavshi / Masi / Masi / Khala |
| uncle's wife / aunt's husband (`..._SPOUSE`) | pat, mat | hi: Chachi / Mami (aunt), Phupha / Mausa (uncle) |
| nephew / niece (`UP_PARENT_DOWN_CHILD_DOWN_CHILD`) | pat (brother's child), mat (sister's child) | hi: Bhatija, Bhatiji / Bhanja, Bhanji |
| cousin (`..._DOWN_CHILD_DOWN_CHILD`) | pat, mat | English "Cousin (Paternal)" / "(Maternal)"; hi both "Cousin Bhai"/"Cousin Bahen" (no split) |

Data-quality flags for a native-speaker review (NOT changed): Tamil paternal uncle = "Appa" (the father term), Tamil maternal aunt = "Mami" (reads like mother's brother's wife),
Malayalam uses "Achachan" for paternal uncle, maternal uncle AND grandfather; several languages use one grandparent term for both sides (ta, kn, ml, mr, and bn/te for one gender).
`Dada`/`Nana` and `Chacha`/`Mama` are present in hi, pa, ur (and gu/mr in part). Everything not in the table above (great-grandparents, in-laws, step, extended) has no sided term.

**The label never reaches those terms today. (by reading, not executed):** the info sheet translates with
`VocabularyTable.resolveByEnglishTerm(englishTerm: <classifier label>, locale)` (`relationship_info_sheet.dart:217`, also `subtree_mixin.dart:160`,
`canvas_mixin.dart:2288`, `features/home/providers/kinship_terms_for_family_provider.dart:86`). That function reads a reverse index keyed `"<locale>_<englishTerm>"`
(`vocabulary_table.dart:532`). Two problems:
1. The sided seeds' English names are `Uncle (Paternal)`, `Grandfather (Maternal)`, `Aunt (Maternal)`, ... but the classifier emits plain `Uncle`, `Aunt`, `Grandfather`,
   `Grandmother`, `Cousin`, `Nephew`, `Niece`. There is no English seed with those exact names, so the lookup returns null and the sheet shows the English label.
   In-law labels (`Brother-in-law`, ...) also have no exact English seed. Only exact-name seeds (`Father`, `Mother`, `Brother`, `Sister`, `Son`, `Daughter`, `Husband`, `Wife`,
   `Grandson`, `Granddaughter`) can match.
2. The index builder (`_ensureReverseIndex`) keeps ONE English entry per `pathPattern` (`englishTerms[entry.pathPattern] = entry`, last wins) and maps every native entry of that pattern to that one
   English name, so male/female and paternal/maternal variants of a pattern overwrite each other. Even exact names like `Father` vs `Mother` (same pattern `UP_PARENT`) may collide; I could not run it to
   confirm which wins.
Net: Hindi "Chacha / Mama / Dada / Nana" exist in the data and are unreachable from the graph UI. There is a signature-based resolver (`VocabularyTable.resolve(pathPattern, generationDelta, side, ...)`,
plus `core/kinship/v3` and `v4` engines) that DOES take `side`, but nothing outside `core/kinship/v3|v4` calls it (grep `VocabularyTable.resolve(` / `DeterministicKinshipEngine` / `VocabularyMapper`).

### 3. What the info sheet shows today

File: `graph/widgets/relationship_info_sheet.dart` (1487 lines). **It opens from an EDGE (connection midpoint) long-press, or from the "View relationship" action, NOT from a plain person tap.**
- Plain tap on a person: `_handleNodeTapDown` (`graph/widgets/engine/interaction_mixin.dart:1281`) only haptic-ticks and sets `selectedNodeProvider` (highlight + dim). It deliberately opens nothing.
- Long-press on a person: opens `GraphQuickActions` (member info / quick actions), which includes "View relationship" -> `_onViewRelationship(targetPersonId)` (`graph/widgets/engine/relationship_view.dart`, "How are we related?").
- Long-press on an edge midpoint (`interaction_mixin.dart:~1229`): opens the sheet with that edge's own key and, if a path is focused, the path data + "Path step X of Y".

Contents (top to bottom, **by reading**): two avatars (initials + name, gender-coloured), a dashed connector with the label at its midpoint, two sentences ("A is the father of B" / "B is the son of A", gender-aware
inverse via `genderAwareInverse`), native-language variants when `kinshipTermLanguageProvider != auto/en` (see section 2 for why this mostly falls back), `Change relationship` / `Remove relationship` buttons
(only if `familyId`, `edgeId`, `ref` are all given AND the user is admin/owner or the edge involves them), and, when `pathFocus != null`, `_PathFocusSection`: the resolved label (`resolvedRelationshipLabel ?? 'Related'`),
optional "Step X of Y" badge, "N relationship step(s)", an ordered path chip row (`_OrderedPathChip`, person NAMES joined), and a "Focus path" button (only when multi-hop).
Unresolved path: `_onViewRelationship` opens the sheet with `relationshipKey: 'unknown'` plus a snackbar "No confirmed family relationship path found.".
Screen-reader label: "Relationship between A and B, <fwd>. <label>. Path has N steps.".
Gaps: the path chips list names only (no per-hop relation words, no paternal/maternal), all strings are hard-coded English (the sheet has no `S.of(context)`), step count text is built with
a plural ternary, and the tap-target / 200% text scale behaviour of the chips and buttons was not checked.

### 4. Where "me" is determined

- Provider: `viewerPersonIdProvider(familyId)` in `core/viewer/viewer_provider.dart:145` (`FutureProvider.autoDispose.family<String?, String>`).
  It watches `currentUserProvider`, then queries Supabase `Person` where `familyId = <family>`, `linkedUserId = <auth user id>`, `deletedAt IS NULL`, limit 1 (Step 1).
  Fallbacks: offline cache if Supabase is not ready; creator fallback (family `createdBy == user` and the anchor person is unlinked -> the anchor); otherwise `null` (no "You" node).
  A user with no linked Person gets `null`, not the anchor (deliberate, v5.77).
- Consumers: `graph/widgets/engine/relationship_view.dart` `_onViewRelationship` reads it (`.valueOrNull`), shows a red snackbar if null and "This is you!" if viewer == target;
  the sheet's `_canEditRelationship` also reads it; the engine mixins receive `viewerPersonId` as a parameter.
- Not "me"-aware: the sheet itself never labels the viewer "You" (step 0 is named from `GraphPerson.name`, falling back to `'You'` only when the person is missing).
- A viewer with several Persons per family is not modelled (`limit(1)`).

### 5. Plan

Unknowns first: G1b/G1c text not seen (see scope note). The plan covers the gaps; split it however G1b/G1c actually divide.

**Plan A (likely G1b): side-aware terms (paternal/maternal) reaching the UI.**
Prerequisite (decide before coding): native terms only show when `kinshipTermLanguageProvider` (the `kinship_term_language_provider.dart` one) is not `auto`/`en`, and today nothing mounts
`KinshipLanguageSelector`. Either mount it (e.g. in the family graph app bar; it is 32dp tall, so it would need a 48dp tap target per rule 9) or have G1b show the sided term another way
(e.g. an English "Paternal uncle" label that needs no language setting). Do not unify the two duplicate providers unless asked.
Files: `core/kinship/structural_kinship_classifier.dart` (do NOT change its public `classify` signature; add side detection beside it) or, preferably, a new small file
`core/kinship/kinship_side.dart`; `graph/interaction/graph_kinship_path_focus.dart` (`resolve`/`_computeClassification`: derive `side` from the first up-hop person's `GraphPerson.gender` and expose it on
`GraphKinshipPathFocus`, e.g. new optional `final KinshipSide? side`); `core/kinship/v4/vocabulary_table.dart` (add a side-aware lookup that does NOT replace `resolveByEnglishTerm`);
`graph/widgets/relationship_info_sheet.dart` (use it).
New functions: `KinshipSide? detectSide(List<GraphPathFocusStep> steps, List<GraphPerson> persons)` (paternal if the first parent hop is male, maternal if female, null otherwise);
`String? VocabularyTable.resolveForLabel({required String classifierKey, required KinshipSide? side, required String genderAnchor, required String locale})` mapping classifier keys (`uncle`, `aunt`, `grandfather`, `grandmother`,
`nephew`, `niece`, `cousin`) to the sided pathPattern + `FamilySide` and calling the existing indexed lookup. Fix the reverse index collision in `_ensureReverseIndex` only if G1b says so (it is a shared function used by 4 other callers; change = risk).
Do first, before coding: write down expected outputs for the table in section 2 (hi: paternal uncle -> Chacha/Tau, maternal uncle -> Mama, ...) as unit tests in `test/` (these CAN run in CI, unlike widget behaviour).
Not solvable in code: native-speaker review of the flagged ta/ml/te terms.
ARB keys (template `lib/l10n/app_en.arb`, class `S`, 22 locale ARBs exist): `kinshipSidePaternal` = "Paternal", `kinshipSideMaternal` = "Maternal", `kinshipSideUnknown` = "Side unknown" (only if shown as a caption next to the term).
English fallback label keys like `Uncle (Paternal)` come from the vocab table, not ARB.

**Plan B (likely G1c): "how are we related" sheet shows the path with relation words, accessibly.**
Files: `graph/widgets/relationship_info_sheet.dart` only (`_PathFocusSection`, `_OrderedPathChip`, `_FocusPathButton`; it already receives the whole `GraphKinshipPathFocus`).
New functions: `String _hopPhrase(GraphPathFocusStep step, String? gender)` (e.g. "Mother", "her Brother"), built from `step.relationshipType` + `direction` (invert like `GraphPathFocusNotifier._invertForTarget`), and a `String _pathSentence(...)` for the
semantics label ("You -> Mother -> Brother -> Son, 3 steps"). Keep `GraphKinshipPathFocus` as-is unless Plan A added `side`.
UI rules from the Starter: Semantics label on every new element, >= 48x48 tap targets (the "Focus path" button and any chip that becomes tappable), no clipping at 200% text scale (use `Wrap`, not a fixed-height `Row`).
Plural handling: use ICU plural in the ARB, not the current `'step' : 'steps'` ternary.
ARB keys: `relationshipSheetPathTitle` ("How you're connected"), `relationshipSheetStepCount` (ICU plural: `{count, plural, =1{1 step} other{{count} steps}}`), `relationshipSheetPathHop` (with `{from}`, `{relation}`, `{to}`),
`relationshipSheetNoPath` ("No confirmed family relationship path found."), `relationshipSheetRelated` (replaces the hard-coded `'Related'` fallback), `relationshipSheetFocusPath` ("Focus path"), `relationshipSheetYou` ("You").
Generated l10n files cannot be regenerated in the sandbox: add ARB keys, say regeneration (`flutter gen-l10n`) is needed, do not hand-edit `app_localizations*.dart`.
Heads-up: `lib/l10n/app_en.arb` contains mojibake in existing strings (`ΓÇö` where an em dash was meant). Edit with a UTF-8-safe tool and do not "fix" those strings in a G1 task.

**Plan C (small, with A or B): "me".** No change needed to `viewerPersonIdProvider`. Optional: label step 0 of the path as "You" via the `relationshipSheetYou` key rather than the person's stored name, so the chip row reads "You -> Mother -> ...".
Decide whether a viewer with `viewerPersonId == null` should still be able to open the sheet from an edge (today the edge path works without it; the "View relationship" path shows a snackbar).

**Verification notes for G1b/G1c:** no Flutter SDK in the sandbox. Push the branch, read `Flutter Analyze` conclusion + annotations (no new warning/error in touched files). `Flutter Test (fast)` timing out at 25 min and Backend CI's
5 `predictions.scheduler.ts` type errors are the known baseline, not yours. Pure-Dart unit tests for Plan A are the only behaviour check CI can give.

---

## G1a log

- Task: G1a (read-only audit; this file is the only change).
- Files changed: `docs/graph-ux-progress.md` (new). No Dart, SQL or config changed.
- Files read: `docs/fix-progress.md` (grep only, 745 lines), `docs/visual-polish-progress.md` (head), `graph/widgets/relationship_info_sheet.dart`, `features/family/presentation/widgets/kinship_language_selector.dart`,
  `features/family/presentation/relationship_graph_picker.dart` (head + grep), plus what they call: `graph/interaction/graph_kinship_path_focus.dart`, `core/kinship/structural_kinship_classifier.dart` (labels/structure),
  `core/kinship/v4/vocabulary_{data,table,entry}.dart`, `core/kinship/language_code_map.dart`, `core/viewer/viewer_provider.dart` (provider), `graph/widgets/engine/{relationship_view,interaction_mixin}.dart` (call sites).
- `relationship_graph_picker.dart` (relationship category picker: All / Paternal / Maternal / Marital / Siblings from `allRelationshipsProvider`, `rel.lineage`, returns `rel.relationshipKey`) is a "pick a relationship type when adding a link" sheet,
  separate from the label computation; I only grepped it. It does have a Paternal/Maternal FILTER over relationship types, so it is the one place paternal/maternal is already user-visible (not audited further).
- CI: run 45162141546 on `fix/G1a` @ 76998ccc = **success**. Jobs: Detect Changes success, Secret Scan (gitleaks) success; Backend CI, Flutter Analyze, Flutter Test (fast), Flutter Test (native_maps), Android APK Build all **skipped** by the `detect-changes` path filter (only `docs/` changed), so no Dart or backend check actually ran for this task. Merged to `main` as 891d6eb9 (`--no-ff`).
- Process slip, recorded for honesty: the remote `fix/G1a` branch was deleted one step before the merge landed (a chained command did not stop when the first merge attempt failed on a missing git identity). No data was lost; the merge was redone from the local branch and the result verified before pushing.
- How a human verifies the audit's main claims on a phone (nothing to verify for the doc itself):
  1. Look for any control that changes the kinship TERM language (separate from the app language). Expect none: the picker widget is not mounted. If you find one, tell me where.
  2. Open a family graph where you have a paternal uncle and a maternal uncle. Long-press each -> "View relationship". Expect the sheet to show the English word "Uncle" for both
     (no "paternal"/"maternal", no "Chacha"/"Mama"), and the path chips to list names only.
  3. Change the APP language to Hindi in settings and repeat step 2. Expect the same English kinship label (the sheet reads the kinship-term preference, which stays `auto` = English).
  4. Long-press your own mother or father the same way and note what the sheet shows (the reverse-index collision guess in section 2 predicts a possible mix-up of Father/Mother terms only when a non-English language is active, which step 1 says you cannot select).

---

## G1c log

- Task: G1c - while the info sheet is open for person X, the path from "me" to X stays at full strength and everything else dims to 40%; closing the sheet restores the normal view. Branch `fix/G1c` (from `main`, NOT from `fix/G1b`, which is still unmerged).
- Reused mechanism (no second highlight system): the existing path focus. Selecting a person -> `canvas_mixin` resolves `graphPathFocusProvider` -> `EngineEdgePainter(pathFocusedEdgeIds, pathFocusActive)` + `node_builders` opacity via `computeEmphasisLevel`. `_onViewRelationship` already selected the target; G1c adds one bool provider that only tunes how that path focus is drawn.
- Changes: `pathEmphasisSheetOpenProvider` (StateProvider<bool>, end of `graph/interaction/graph_kinship_path_focus.dart`, exported via the existing `show` list in `family_graph_engine_view.dart`). `relationship_view.dart`: `_trackSheetForPathEmphasis` sets the flag when the sheet opens and, on close, clears it and clears the selection only if it is still the target. `canvas_mixin.dart` -> `edge_selection_wrapper.dart` -> `engine_edge_painter.dart`: new `pathEmphasis` (default false): off-path edges dim to 0.40 (all of them, not only `dimmedEdgeIds`), path edges 1.8x stroke, included in `shouldRepaint`. `node_builders.dart`: with the flag, path nodes/endpoints/target 1.0, every other node 0.40.
- Paint-only: the flag is not an input to layout, positions, edge list, `graphRevision` or `layoutRevision`; it changes painter props (repaint) and node opacity (widget rebuild, no relayout). (by reading; not profiled)
- Not colour alone: path edges are thicker (1.8x on top of the zoom-aware stroke floor), and off-path edges/nodes are dimmed.
- Reduced motion: no animation was added (no pulse, no fade). The change is an instant state switch, so nothing depends on `MediaQuery.disableAnimationsOf`.
- l10n: none. No new user-facing text, no new UI, so no ARB keys and no new Semantics/tap-target surface.
- Files: `lib/graph/interaction/graph_kinship_path_focus.dart`, `lib/graph/widgets/family_graph_engine_view.dart`, `lib/graph/widgets/engine/{relationship_view,canvas_mixin,edge_selection_wrapper,engine_edge_painter,node_builders}.dart`. No tests added (no pure-Dart seam; behaviour is paint).
- CI: run 45168135296 @ 228b5eed. Flutter Analyze success, no annotation on touched files (only the Node 20 / setup-java deprecation notices). Flutter Test (native_maps) success. Flutter Test (fast) still running when this was written (known 25-min baseline timeout). Backend CI skipped. First push dafb5494 failed Analyze: `pathEmphasisSheetOpenProvider` was not in the engine view's `show` list; fixed in 228b5eed. This docs commit is docs-only, so the tip run skips Flutter jobs; the code result is the run above.
- Merged to `main` as b7ea7c0f (`--no-ff`) on the owner's explicit instruction, although `Flutter Test (fast)` could not go green (baseline; the run was also cancelled by the docs push). G1b is still unmerged. Merge order matters: G1b also edits `relationship_view.dart` and `family_graph_engine_view.dart` (and `graph_kinship_path_focus.dart`); expect a small textual conflict at merge, resolved by keeping both.
- Limits / findings (not fixed): (1) Highlight applies to the "View relationship" flow (person X). The edge long-press sheet is about an edge, not "me" -> X, and is unchanged. (2) At far zoom the graph draws dots (`node_layer.dart`), which G1c does not dim; edges still do. (3) `_onViewRelationship` calls `_resolvePathFocus` before it sets the selection, so the PATH SHOWN IN THE SHEET is resolved for the previously selected node. The painter highlight is correct (the canvas resolves for the new selection), but the sheet's path text can differ if the previous selection was another person. Pre-existing; worth a separate task. (4) The sheet is modal, so the user cannot select another node while it is open.
- How a human verifies on a phone, on a tree of 50+ people (needs a build of this branch):
  1. Open a family graph with 50+ people where you have a linked person. Long-press someone 3+ hops away (e.g. a cousin's spouse) -> "View relationship".
  2. While the sheet is open, look at the graph above it: your node, the target and every person between stay at full strength; all other nodes are visibly faint (~40%); path lines are clearly thicker; all other lines are faint. Turn on a grayscale filter: the path must still stand out by thickness.
  3. Drag the sheet down / tap outside: the graph returns to normal (no dimming, no thick lines, nothing selected).
  4. Do it again on a different person, and then on your own mother: path of 1 hop, only that edge is thick.
  5. Settings > Accessibility > Remove animations (reduce motion) on: repeat; nothing pulses or animates (it never does).
  6. Pan/zoom with the sheet open: no stutter or re-layout jump; nodes do not move when the sheet opens or closes.
  7. Largest font size: sheet content scrolls; nothing is clipped (sheet UI itself is unchanged by G1c).
- Very long path (e.g. 15+ hops): every hop is on the path, so all of them stay full strength and thick; the faint remainder is what carries the contrast. Edge labels on path edges (existing `pathFocusLabels`) can crowd at low zoom. Path segments outside the viewport are not scrolled into view (G1c does not move the camera), and the bottom sheet covers the lower part of the screen, so part of a long path may be hidden; panning with the sheet closed shows it only while selected, so the user should re-open the sheet after panning. The sheet's own chip row wraps and scrolls. Nothing is truncated or capped by G1c; the BFS itself only sees persons that have a position (visible persons), so a path through a collapsed/hidden branch is not found and shows the "no path" state.

---

## G2 audit

Read-only (G2a): no code changed. Paths relative to `Daxelo-Kinrel-App/lib/`. Everything here was established by READING code; no Dart was run (no Flutter SDK), so runtime claims are marked **(by reading)**.
Scope note: the text of G2b/G2c (`graph-ux-implementation-prompts`) was not available to this session, so the plan in section 6 is a proposal built from the findings, not a re-mapping of the real prompts.
Beyond the six named files I only grepped or read small slices of `graph/interaction/wedge_view_state.dart`, `graph/engine/viewer_wedge_layout.dart`, `graph/interaction/proximity_graph_state.dart`, `graph/widgets/engine/{canvas_mixin,interaction_mixin,relationship_view}.dart` and `l10n/app_en.arb`, because the default cannot be stated correctly from the six files alone (see the key finding).

### 0. Key finding: there are two collapse systems and only one is live

`kUseViewerWedgeLayout = true` (`graph/engine/viewer_wedge_layout.dart:51`, "THE ONE BOOLEAN SWITCH"). With it on, `canvas_mixin.dart:~820` SKIPS `BranchCollapseNotifier.computeDensityCollapse`, with the comment that this keeps `branchCollapseProvider` empty "so the legacy chips never render alongside the wedge page chips".
- **Live today (wedge):** `WedgeViewNotifier` / `wedgeViewProvider` in `graph/interaction/wedge_view_state.dart`, laid out by `ViewerWedgeLayout`. What the user sees as "collapsed" is the wedge pager.
- **Legacy (radial, only if the constant is flipped):** `branch_collapse_state.dart` + the branch chips in `branch_affordance.dart`.
- `expand_collapse.dart` (`ExpandCollapseController`, bitmask per node + disclosure levels 0-4) is a THIRD, older system. Grep: nothing outside its own file instantiates or reads it; the engine view says "v5.132: no ExpandCollapseController here anymore (System B)" and `canvas_mixin.dart:458` repeats it. Treat as dead code. G2b/G2c must not touch it.

### 1. Initial camera position and zoom on first open, and where it is set

- `CameraController` (`graph/interaction/camera_controller.dart`) starts at `_panX = 0`, `_panY = 0`, `_zoomLevel = 1.0`; range `minZoom 0.2` / `maxZoom 5.0` (constructor defaults). Created in `_FamilyGraphEngineViewState.initState` (`family_graph_engine_view.dart:1160`) with a `PositionMemory`.
- First framing is `_maybeFrame(layout, flat, viewerPersonId)` (`family_graph_engine_view.dart:~2861`), called from the build at `:~2508`, guarded by `_framed` (one-time per family; reset to false when `familyId` changes, `:1361`). It needs a non-zero `_viewportSize` and non-empty `layout.positions`.
  - Anchor chosen as: viewer's position -> the person with `isAnchor == true` -> first position in the layout.
  - `_computeAnchorCenteredCamera(...)` (`:2765`) returns `{panX, panY, zoom}`: zoom = min over x/y of `(viewport - 160 padding) / (2 * maxDistFromAnchor + 1)`, clamped to **[0.35, 1.3]**, using the bounding distance of ALL positions (plus wedge "+N" chip slot centres) from the anchor; the anchor's avatar circle is put at the centre of the visible canvas (viewport height minus `widget.bottomChromeHeight`).
  - Applied with `_camera.animateTo(..., duration: 1ms, linear)`, i.e. an instant snap, never an animation.
- Re-centering while the user has not touched the camera: if the anchor's position changes because progressive loading re-laid-out the graph and `_userHasInteractedWithCamera == false`, the same helper runs again (`:~2514`, `:~3029`). After the first gesture it stops.
- The old whole-tree `initialFitOnce` / `fitToView` is no longer the first-load path (comment at `:~2840`: "fitToView-style whole-tree framing is NOT used on first load anymore"); `initialFitOnce` is only the fallback when there is no position at all.
- Saved camera is NOT restored on open: `CameraController.restorePosition` / `needsRepositioning` exist, and `_scheduleSave` writes the position, but grep finds no caller of the restore methods anywhere in `lib/` (**by reading**). So every open re-frames on the anchor.
- Consequence for big families: zoom is derived from the extent of what the layout placed, so it depends on layout size, not on family size; a wide pager/wedge can push it to the 0.35 floor.

### 2. Initial collapse state, and what the state is keyed by

- Live (wedge): `WedgeViewState` (`wedge_view_state.dart`): `expandedRoots: Set<String>` (PER PERSON; "the viewer is ALWAYS implicitly expanded, never stored here"), `pages: Map<String,int>` (per person, cumulative pages of 8: `WedgeLayoutConfig.pageSize = 8`), `expansionOrder` (LRU list), `filter`, `revealTarget`, `focusedPersonId`. Initial = everything empty: the viewer plus up to 8 first-ring relatives plus "+N more" chips for the rest. `ViewerWedgeLayout` enforces `kNodeBudget` (50) by collapsing the branch opened longest ago. Not keyed by generation, not by "branch" as an object: it is per person (an expanded person shows their children, paged).
- Persistence: wedge state is in-memory only (**by reading**: no persistence in `wedge_view_state.dart`). The legacy chip flow persists expansion per (user, family, branch root) via `LayoutOverridesService.saveBranchExpansionState`, wired in `initState` (`:1188`) and re-applied by `_applyPersistedBranchExpansion` (`:1539`); `canvas_mixin.dart:~847` still schedules that re-apply in wedge mode, but the notifier it seeds is the unused legacy one.
- Legacy: `BranchCollapseState` (`branch_collapse_state.dart:218`): `collapsedBranches: List<CollapsedBranch>` (each keyed by `rootPersonId`, id `'<root>_branch'`), `expandedBranchRoots`, `manuallyCollapsedRoots`, `revealedByBranchRoot: Map<root, Set<ids>>`. Per BRANCH ROOT PERSON, never per generation (generation depth is only a display field `hiddenGenerationDepth`). Initial = `BranchCollapseState.empty`; auto-collapse is the budget rule (`kNodeBudget = 50`, largest subtree first, recursive), `kMaxNodesPerExpansion = 15` per tap, `kMaxSimultaneouslyExpandedBranches = 0` (cap disabled). Separately, the default ego-centric proximity set caps visible nodes at `kProximityNodeBudget = 50`.
- There is no "collapse everything above N people" switch anywhere: the budget is node-count driven (50), independent of family size except that small graphs (<= 50 rendered) never collapse.

### 3. Is there a "focus on person" / recenter call, and its signature?

Several, with different jobs. None of them is "move the camera to person X at a readable zoom" as one public call.
- `CameraController.focusOnNode(String nodeId, Offset nodePosition, {int connectedNodeCount = 0, Size viewportSize = Size.zero, bool reducedMotion = false})` (`camera_controller.dart:423`): centres the node and picks zoom from `connectedNodeCount` (<=3 -> 1.5, <=10 -> 1.0, <=30 -> 0.7, else 0.5), spring-animated. **Zero callers** in `lib/` (grep). `family_graph_screen.dart:~721` has a comment saying the focus flow "calls _camera.focusOnNode()"; the code it points to (`_onFocusPerson`, `relationship_view.dart`) does not (it calls `graphFocusProvider.notifier.focus(...)`). Stale comment.
- `CameraController.animateToWithSpring(double targetPanX, double targetPanY, double targetZoom, {bool reducedMotion = false})` (`:640`) and `animateTo(...)`: the primitives everything else uses. Pan for "centre node P at zoom z" is `viewport/2 - P * z` (see `_maybeFocusCameraOnNode(String nodeId, GraphLayoutResult layout)` in `interaction_mixin.dart:~763`: keeps the current zoom, skips the move if the node is already inside the central 40% region, honours `MediaQuery.disableAnimationsOf`).
- Recenter on "me": `_centerOnRootUser()` in `family_graph_screen.dart:361` bumps `_recenterKey`; the engine view detects `recenterKey` (`:1416`) and sets `_pendingResetView`, executed by `_maybeRunPendingResetView(GraphLayoutResult layout, FlatGraphResult flat, String? viewerPersonId)` (`:~3060`), which clears rearrange overrides and uses the same `_computeAnchorCenteredCamera` as first open (animated unless reduced motion). Focus target order there: selected -> anchor -> viewer -> first node. UI: top-right `FloatingActionButton.small` "Center on You" (`my_location`, `:1370`) plus a bottom-toolbar button. Not parameterised by person: it cannot recenter on someone else.
- Provider-level focus: `graphFocusProvider.notifier.focus({personId, personName, edges, currentViewport})` = "isolate connections" (dims the rest to 18%, auto-clears after 15 s, `relationship_view.dart:~12`). It is NOT a camera call. Search-jump (`family_graph_screen.dart:~690-745`) uses it plus `wedgeViewProvider.notifier.revealPerson(memberId, viewerId:)`; the engine view then fits to the hub and person.
- Also: `CameraController.resetView({required Offset focusNodePosition, required double circleCenterYOffset, required Size viewportSize, bool reducedMotion = false})` (zoom 1.0, circle centred, v107.1) and `reset()` (origin, zoom 1.0). Both are older than the shared `_computeAnchorCenteredCamera`.

### 4. What a collapsed branch looks like today, and what says it can be opened

Wedge mode (live):
- A "+N" count badge on the node: `_WedgeCountBadge` (`branch_affordance.dart:~2557`), 48x48 hit target centred on the badge, Semantics `l10n.graphMorePeople(count)` = "Show {count} more people, double tap to reveal" (fallback English "$count more people, double tap to show"), tap -> `_handleWedgeNodeTap`.
- A page bubble `_WedgePageChipBubble` (`:~2341`), "+N" with two lines beneath: line 1 `graphMorePeopleShort` ("{count} more"), line 2 `graphTapToShowHint` ("Tap to show"); Semantics "Show N more family members. Double-tap to show the next page." Both strings are in `app_en.arb`, so they are localised.

Legacy radial mode (only if `kUseViewerWedgeLayout` is false): a compact chip attached to the bottom of the parent node: icon (tree glyph `account_tree_rounded` if sub-branches exist, chevron `expand_more_rounded` if flat, `hourglass_top` while loading) + text "<representative name> +<nextExpansionCount>" (12 px, one line, ellipsized). Colour = dominant kinship category. Semantics (hard-coded English): "Expand <name> branch: N members will appear on tap. Total hidden in this branch: M. ... Double-tap to expand. Long-press for branch details and the full names list." Long-press opens a detail sheet ("View all", names list). The chip's text and Semantics strings are NOT in ARB.

Gap relevant to G2: nothing on screen says the graph has been collapsed BY DEFAULT for a big family (e.g. "Showing 9 of 214 people"); the only cue is the per-node "+N". A first-time user cannot tell the default view is partial.

### 5. Measuring family size cheaply

- `flat.persons.length` (`FlatGraphResult`, a plain list, O(1)). Already read in the engine view (`graphRevision = edges.length * 100003 + flat.persons.length`, `interaction_mixin.dart:~730`) and available in `family_graph_screen.dart` as `graphData?.persons`. No new query, no loop.
- Caveats: (a) progressive loading means the count can grow after first paint; decide it once at `_framed` time and again only while `_userHasInteractedWithCamera == false` (the anchor-drift re-centre already uses that window). (b) It counts deceased and hidden people; that is right for "how big is the tree", wrong for "how many are on screen" (for that use `layout.positions.length`, also O(1)). (c) Do not use `computeCollapse(familyMemberCount:)`; it has no callers.

### 6. Plan for G2b and G2c (proposal; re-map when the real prompts are read)

Recommended threshold: **`kNodeBudget` (50), i.e. the default applies when `flat.persons.length > kNodeBudget`.** Reasons: it is the budget the layouts already enforce (`kProximityNodeBudget` is also 50), below it nothing is hidden so a "large family default" would change nothing, and reusing the constant avoids a second magic number. Import it from `branch_collapse_state.dart` (as `viewer_wedge_layout.dart` already does); do not hardcode 50. Keep the zoom floor/threshold decisions in one small pure helper so they can be unit-tested in CI.

**G2b (likely): first-open camera for large families.**
- Files: `graph/widgets/family_graph_engine_view.dart` (`_computeAnchorCenteredCamera`, `_maybeFrame`), nothing in `camera_controller.dart` unless a new public method is wanted.
- Change: when `flat.persons.length > kNodeBudget`, frame the viewer plus first ring (not the extent of every placed chip) with a readable zoom floor (proposal: 0.6 instead of 0.35; measure on device before fixing the number), leaving small families exactly as today. Keep the one-time `_framed` + `_userHasInteractedWithCamera` rules (Iron Rules in the camera header: no drift, no auto-zoom after user action).
- New pure function, e.g. `({double panX, double panY, double zoom}) frameForLargeFamily({required int memberCount, ...})` in a new file `graph/engine/initial_frame.dart`, unit test in `test/graph/engine/`. Do not change `CameraController`'s public API.
- Also decide (needs a product answer): whether to restore the saved camera (`restorePosition` has no callers) for a returning user instead of re-framing every open.

**G2c (likely): make "collapsed by default" legible + one public "focus on person".**
- Files: `family_graph_engine_view.dart` (add one `_focusCameraOnPerson(String personId, {double? zoom})` that wraps `_computeAnchorCenteredCamera`/`animateToWithSpring` and honours `MediaQuery.disableAnimationsOf`; reuse it from `_maybeRunPendingResetView` and `_maybeFocusCameraOnNode` only if asked), `graph/widgets/engine/branch_affordance.dart` (a small, non-modal "Showing N of M people" caption), `l10n/app_en.arb` (new keys, e.g. `graphShowingSubset` with `{shown}` and `{total}` ICU placeholders; say `flutter gen-l10n` is needed; do not hand-edit generated files).
- UI rules (rule 9): Semantics label, 48x48 target if tappable, wrap rather than clip at 200% text scale, no animation when reduced motion is on.
- Reuse, do not add: `wedgeViewProvider` for expansion state, `graphFocusProvider` stays the dim/isolate focus (do not overload it), and do not revive `ExpandCollapseController` or the legacy chips.
- Fix the stale comment at `family_graph_screen.dart:~721` only if G2c touches that block.

**Open questions for the owner before G2b/G2c:** (1) is "default" = camera framing only, or also fewer people shown at first open (today the wedge already shows viewer + 8)? (2) should the wedge state persist across opens (today it does not)? (3) restore the saved camera for returning users?

**Verification notes:** no Flutter SDK; push the branch and read Flutter Analyze annotations; the pure framing helper can be tested by CI, widget behaviour cannot. How a human checks the findings on a phone (no code changed): open a family with 50+ people and note the first view; open a family with <= 50 and compare; tap "Center on You"; tap a "+N more" bubble; check there is no on-screen hint that the view is partial.

### G2a log

- Task: G2a (read-only audit; this file is the only change). Files changed: `docs/graph-ux-progress.md`. No Dart, SQL or config changed.
- CI: run 45177608099 on `fix/G2a` @ d86cb948 = success. Detect Changes + Secret Scan (gitleaks) success; Flutter Analyze, Flutter Test (fast), Flutter Test (native_maps), Android APK Build and Backend CI all skipped by the path filter (docs-only), so no Dart check ran. Merged to `main` as db52ba67 (`--no-ff`).

## G1b log

- Task: G1b - top of the relationship info sheet is one plain sentence, e.g. "Rahul is your uncle (your mother's brother)." Branch `fix/G1b`.
- Builder: `buildRelationshipSentence(...)` in `graph/interaction/relationship_sentence.dart`. It reads the already-resolved `GraphKinshipPathFocus`
  (BFS path + `StructuralKinshipClassifier` label); it adds no relationship computation. Term = `resolvedRelationshipLabel`, translated with the existing
  `VocabularyTable.resolveByEnglishTerm` for the selected kinship language (`auto` = English), English lower-cased as fallback. Chain = the path hops read with
  `invertPathStepTypeForTarget` (the old `_invertForTarget` map, moved to a top-level function; the method now delegates, behaviour unchanged).
- Sentence forms: self "This is you."; term + chain; chain only (term unknown, or one hop where term == role word, e.g. "Asha is your mother."); term only (a hop that
  cannot be put in plain words); no path -> "We can't work out how you and {name} are related yet." Never a raw key, never empty.
- Files: `graph/interaction/relationship_sentence.dart` (new), `graph/interaction/relationship_sentence_l10n.dart` (new, binds to generated `S`),
  `graph/interaction/graph_kinship_path_focus.dart` (map extracted), `graph/widgets/relationship_info_sheet.dart` (sentence + Semantics; body wrapped in
  `SingleChildScrollView` so it cannot clip at 200% text scale), `graph/widgets/engine/relationship_view.dart` (passes `viewerPersonId` + genders; self snackbar now uses the ARB string),
  `graph/widgets/family_graph_engine_view.dart` (one import), `l10n/app_en.arb` (+26 keys: `relationshipSentence*` x8, `relationshipRole*` x18),
  `test/graph/interaction/relationship_sentence_test.dart` (new, 11 cases; reads wording from app_en.arb; lives in the fast set, no pumpWidget).
- **l10n regeneration is needed** (`flutter gen-l10n`): keys were added to `app_en.arb` only (other 21 locale ARBs untouched, they fall back to English) and the generated
  `app_localizations*.dart` files were NOT hand-edited. CI Flutter Analyze passed on the branch, so CI resolves the new getters, but the committed generated files are stale until regenerated.
- Known limits (not fixed, G1a findings still apply): (1) the sheet opens from "View relationship" / edge long-press, never from a plain tap (tap = select only, by design),
  and only the "View relationship" flow shows the sentence; the edge-tap flow does not (its two people are not "you" and the target). (2) The classifier emits plain `Uncle`; the vocab reverse index
  has no `Uncle` seed, so even with Hindi selected the term usually falls back to English "uncle", and the kinship-language picker is still not mounted. The sentence therefore reads
  "your uncle (your mother's brother)" today; "mama" appears only once Plan A (side-aware terms) lands. The chain keeps it understandable either way.
  (3) Intermediate persons with no gender in the map get neutral words ("your parent's sibling").
- CI: run 45165360692 @ 551e934f. Detect Changes, gitleaks success; Flutter Analyze **success** (first push af07ae18 failed on two `S?` nullability errors in my code, fixed in 551e934f);
  Backend CI skipped (no server changes); Flutter Test (fast) / (native_maps) were **cancelled** (not failed) when the docs-only push 3c6122af replaced the run through CI concurrency; the tip run 45165890326 is green only because the path filter skipped every Flutter job. So the new unit test has NOT been run by CI and the branch is NOT merged. To get a real signal: re-run via workflow_dispatch and read the `relationship_sentence_test.dart` result, or run `flutter test test/graph/interaction/relationship_sentence_test.dart` locally.
- How a human verifies on a phone (after `flutter gen-l10n` + build):
  1. Open a family graph, long-press your mother's brother, tap "View relationship". Top of the sheet: "<Name> is your uncle (your mother's brother)." Below it the avatars, two directional sentences and path section are unchanged.
  2. Same for your father's brother: "(your father's brother)". For your mother: "<Name> is your mother." (one hop, no brackets).
  3. Long-press your wife's father: "... is your father-in-law (your wife's father)."
  4. Long-press someone with no connection: "We can't work out how you and <Name> are related yet." (the existing snackbar also shows).
  5. Long-press your own node, "View relationship": snackbar "This is you."
  6. TalkBack/VoiceOver: focus the top sentence; it reads the full sentence once.
  7. Settings > Display size / font size to the largest: the sentence wraps and the sheet scrolls; nothing is cut off.

---

## G2b log

- Task: G2b - when the graph first opens and the tree is large, start with "me" centred, show me + 2 generations up + 1 down + siblings + spouse, collapse every other branch; collapsed branches carry a "+N relatives" label. Branch `fix/G2b` from `main`. Not merged.
- Threshold: a tree is large when it has MORE than `kLargeTreeThreshold` people = `kNodeBudget` (50). This is the audit's recommendation (G2a section 6); the task default of 40 was NOT used because the audit gives a value. People are counted as distinct ids in `flat.persons` plus both endpoints of every `allRelationships ?? relationships` row (so progressive loading does not under-count). Decided once per family load, after the viewer id and the saved-expansion provider have loaded; if either never loads, today's behaviour stays.
- Mechanism (existing wedge state, no new state class): `WedgeViewNotifier.seedDefault(expandedRoots, pages)` (new method, does not set `lastActionPersonId`, so no camera-fit cycle starts) and `clearLastAction()`. Default = expand the viewer's PARENTS (their parents = 2 generations up, and my siblings appear under them) and raise the viewer's page so spouse, parents, children and siblings are never behind a "+N" chip (wedge ranks the viewer's links spouse, parent, child, sibling first). Children are shown through the viewer's own ring (1 generation down); their branches stay collapsed. Pure helper + threshold: `lib/graph/engine/large_tree_default.dart`.
- Where saved state wins (in this order): (1) the wedge state already holds expansions/pages in this session: nothing is seeded. (2) `GraphLayoutState.expandedBranches` (via `branchExpansionStateProvider`) is not empty: the default is skipped and the saved expanded branches are applied; branches saved as collapsed stay collapsed. (3) otherwise the default applies. Only the viewer-page raise (never hide close family) is applied in cases 2 and 3. NOTE: in wedge mode nothing used to write that column (only the unused legacy chips did), so G2b now also saves the user's wedge expand/collapse via the existing `LayoutOverridesService.saveBranchExpansionState`, for large trees only, serialised, and never for the seeded default. No schema change, no migration.
- Label: every collapsed branch on a large tree shows "+N relatives" (N = people inside that branch, from the wedge tree's `parentOf`), 48x48 minimum tap target, wraps (max 3 lines, width 124) instead of clipping at 200% text scale, Semantics label "Collapsed branch, N more relatives. Double tap to expand." ARB keys added to `lib/l10n/app_en.arb` with ICU plurals: `graphCollapsedRelativesLabel`, `graphCollapsedRelativesSemantic`. Regeneration (`flutter gen-l10n`) is needed in the repo's tracked `lib/l10n/app_localizations*.dart`; they were NOT hand-edited. CI regenerates them on `flutter pub get` (Analyze compiled the new getters). Other 21 locales have no translation yet (fall back to English).
- Camera: tapping the label runs the normal expand flow (`_handleWedgeNodeTap`: accordion, lazy fetch) and then clears the action, so the fit-to-branch camera move does not run. The camera is therefore stable on expand. The wedge layout is still recomputed, so existing nodes can shift on screen (not prevented). On first open the existing anchor-drift re-centre (user has not touched the camera) may snap once after the default is seeded.
- Files: `lib/graph/engine/large_tree_default.dart` (new), `lib/graph/interaction/wedge_view_state.dart`, `lib/graph/widgets/family_graph_engine_view.dart`, `lib/graph/widgets/engine/{canvas_mixin,branch_affordance}.dart`, `lib/l10n/app_en.arb`, `test/graph/engine/large_tree_default_test.dart` (new, pure Dart, 3 tests; not seen to run).
- CI: run 45178822090 @ 3961baf1. Flutter Analyze success, annotations on the run are only the two Node 20 / setup-java deprecation notices (none on touched files). Flutter Test (native_maps) success. Flutter Test (fast) still running when recorded (known 25-minute baseline). Backend CI skipped. This docs commit is docs-only and cancels the running tip run; the code result is the run above.
- Known limits (not fixed): (1) The wedge engine has no per-child filter, so expanding a parent can also show that parent's siblings (uncles/aunts) within its first 8 children, after grandparents and my siblings. I did not change the engine's public API. (2) `kWedgeAccordionMode` is on: expanding another branch closes every branch that is not on its ancestor path, including the seeded parent branches (parents, spouse and children themselves stay). (3) Label position `_kWedgeLabelAnchor` (bottom of the node footprint) was not seen on a device: tune it if it covers the name. (4) No Dart was run; behaviour is verified only by Analyze compiling.
- How a human verifies this on a phone (needs a build of `fix/G2b`; run `flutter gen-l10n` first if building locally):
  1. 100-person tree, fresh account/cleared saved layout: open the graph. Expect you in the centre, your spouse, parents and all children visible, your parents expanded (their parents and your siblings visible), every other person collapsed with a "+N relatives" label, not just "+N".
  2. Same tree: tap a "+N relatives" label. Expect that branch to open and the camera NOT to pan or zoom. Check the label is tappable at the largest font size (it wraps, nothing clipped) and TalkBack/VoiceOver reads "Collapsed branch, N more relatives. Double tap to expand."
  3. Same tree: leave the graph and reopen. Expect the branches you opened to be open and the default NOT re-applied. Collapse everything you opened, reopen: expect everything collapsed (saved state wins, including collapsed).
  4. Same tree, user with 9+ children/siblings/spouse/parents combined: expect all of them visible on first open, none behind a "+N" bubble.
  5. 10-person tree: open the graph. Expect exactly today's view: no "relatives" labels, no extra expansion, same camera.
  6. A tree of exactly 50 people behaves like the 10-person tree; 51 behaves like the 100-person tree.
