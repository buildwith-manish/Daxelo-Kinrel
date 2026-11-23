# Graph UX progress

Flutter app only (`Daxelo-Kinrel-App/lib/`). Engine = `lib/graph`. Branch model: `fix/<TASKID>` from `main`, merged `--no-ff` after CI is green.
Status values: `not started` | `in progress (<resume note>)` | `done (merged <sha>)`.

| ID | Status | Notes |
|---|---|---|
| G1a | done (see "G1a log" at the bottom; merge sha recorded there) | read-only audit + this file; no code changed |
| G1b | not started | plan below |
| G1c | not started | plan below |

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
- CI: see below.
- How a human verifies the audit's main claims on a phone (nothing to verify for the doc itself):
  1. Look for any control that changes the kinship TERM language (separate from the app language). Expect none: the picker widget is not mounted. If you find one, tell me where.
  2. Open a family graph where you have a paternal uncle and a maternal uncle. Long-press each -> "View relationship". Expect the sheet to show the English word "Uncle" for both
     (no "paternal"/"maternal", no "Chacha"/"Mama"), and the path chips to list names only.
  3. Change the APP language to Hindi in settings and repeat step 2. Expect the same English kinship label (the sheet reads the kinship-term preference, which stays `auto` = English).
  4. Long-press your own mother or father the same way and note what the sheet shows (the reverse-index collision guess in section 2 predicts a possible mix-up of Father/Mother terms only when a non-English language is active, which step 1 says you cannot select).
