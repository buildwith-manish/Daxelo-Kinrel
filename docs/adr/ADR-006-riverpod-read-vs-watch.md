# ADR-006: Riverpod `ref.read()` vs `ref.watch()` — Guardrail Rule

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-14 |
| **Decision Maker** | Agent-0 (Lead Architect) |
| **Affected Agents** | Agent-2 (Graph), Agent-6 (Flutter), Agent-8 (Testing) |
| **Supersedes** | None |
| **Related Bugs** | `family_graph.dart` ref.read() in build path, `onboarding_flow.dart` ref.read() in getter called from build() |

---

## Context

Three bugs were identified in `lib/graph/widgets/` where Riverpod's `ref.read()` was incorrectly used inside `build()` methods or methods called from `build()`, causing reactive state to not trigger UI rebuilds. This is a cross-cutting pattern issue that can recur across any Riverpod widget in the codebase.

### Root Cause

Riverpod provides two primary ways to access provider state:

- **`ref.watch(provider)`** — Subscribes the widget to the provider. When the provider state changes, the widget is rebuilt automatically. **Must** be used for any state that influences the rendered UI.
- **`ref.read(provider)`** — Reads the provider value once without subscribing. The widget will **not** rebuild when the provider state changes. Should only be used in event handlers or lifecycle methods where a one-time read is intentional.

When `ref.read()` is used inside `build()` (or a getter/method called during build), the widget reads the current value but never subscribes. If the provider later emits a new value, the widget remains stale — the UI does not update. This produces bugs that are difficult to reproduce because they only manifest when state changes after the initial build.

### Bug Instances Found

| File | Line | Context | Severity |
|------|------|---------|----------|
| `lib/graph/widgets/family_graph.dart` | L466 | `ref.read(analyticsTrackerProvider).trackGraphOpenTime(...)` inside `build()` → `graphAsync.when(data:)` callback | **HIGH** — fires once during build, but `analyticsTrackerProvider` could be a mutable service. If it changes, stale reference persists. |
| `lib/graph/widgets/onboarding_flow.dart` | L302-303 | `ref.watch(onboardingDismissedProvider)` correctly used in `_isDismissedForFamily` getter — **this was already fixed** in the bug PR | N/A (fixed) |
| `lib/graph/widgets/family_graph.dart` | L261, L286 | `ref.read(analyticsTrackerProvider)` in `_onNodeTap()` and `_focusOnNode()` event handlers | **OK** — event handlers are the correct place for `ref.read()` |
| `lib/graph/widgets/onboarding_flow.dart` | L239, L264, L286 | `ref.read(onboardingDismissedProvider.notifier).update(...)` in `_animateToStep()`, `_skipStep()`, `_completeStepAction()` | **OK** — writing to a notifier, not reading state for rendering |
| `lib/graph/widgets/onboarding_flow.dart` | L296 | `ref.read(analyticsTrackerProvider).trackOnboardingStepCompleted(...)` in `_trackStepCompleted()` | **OK** — one-time side effect, not rendering |
| `lib/graph/widgets/search_bar.dart` | L263 | `ref.read(analyticsTrackerProvider).trackSearchQuery(...)` inside async `_performSearch()` callback | **OK** — one-time side effect after async operation |

**Verdict**: The `family_graph.dart` L466 occurrence is the remaining **true violation** — `ref.read()` used inside the `build()` method's data callback path. The other occurrences are legitimate uses in event handlers or side-effect-only contexts.

---

## Decision

### Rule 1: `ref.read()` is ONLY permitted in these contexts

| Context | Example | Reason |
|---------|---------|--------|
| Event handlers | `onPressed: () { ref.read(provider).doThing(); }` | One-time action, no rebuild needed |
| `initState` / `didChangeDependencies` | Late init of controllers | Lifecycle setup, not rendering |
| `dispose` | Cleanup operations | Widget is being destroyed |
| Async callbacks (post-await) | `await api.call(); ref.read(provider).track();` | Side-effect after async gap |
| Notifier mutations | `ref.read(provider.notifier).update(...)` | Writing state, not reading for UI |

### Rule 2: `ref.watch()` MUST be used for ALL state consumed during rendering

Any provider value that influences what the widget renders (visible content, layout decisions, conditional branches, computed properties used in the widget tree) must be obtained via `ref.watch()`. This includes:

- Data displayed in the UI (names, counts, lists)
- Boolean flags that control visibility or branching (`if (isOnline) ...`)
- State that determines which widget variant to show
- Values used to compute layout parameters

### Rule 3: Getters called from `build()` are part of the build path

A getter like `bool get _isDismissedForFamily => ref.watch(provider)...` is called during `build()` and therefore must use `ref.watch()`. A getter using `ref.read()` is a violation because it reads once without subscribing.

### Rule 4: Lint comment template

All ConsumerWidget and ConsumerStatefulWidget files must include the following comment at the top of the class definition:

```dart
/// Riverpod Usage (ADR-006):
///   - ref.watch(): used in build() for reactive state (UI rebuilds on change)
///   - ref.read(): used ONLY in event handlers, initState, dispose,
///     and notifier mutations (never in build path)
```

---

## Remaining Violations for Agent-6 to Fix

### CRITICAL — Must Fix

1. **`lib/graph/widgets/family_graph.dart` line 466**
   - **Current**: `ref.read(analyticsTrackerProvider).trackGraphOpenTime(...)` inside the `data:` callback of `graphAsync.when()` which is executed during `build()`.
   - **Fix**: Move the analytics tracking to `addPostFrameCallback` so it runs after the build frame:
     ```dart
     // BEFORE (violation):
     if (_openStopwatch.isRunning) {
       _openStopwatch.stop();
       ref.read(analyticsTrackerProvider).trackGraphOpenTime(...);
     }

     // AFTER (correct):
     if (_openStopwatch.isRunning) {
       _openStopwatch.stop();
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (!mounted) return;
         ref.read(analyticsTrackerProvider).trackGraphOpenTime(...);
       });
     }
     ```

### WATCH — Review but Likely OK

2. **`lib/graph/widgets/family_graph.dart` line 650** — `ref.watch(onboardingDismissedProvider)` — This is correctly using `ref.watch()`. No change needed.
3. **`lib/graph/widgets/onboarding_flow.dart` line 303** — `ref.watch(onboardingDismissedProvider)` in `_isDismissedForFamily` getter — Correctly using `ref.watch()`. No change needed.

### Already Correct — No Action Needed

4. **`lib/graph/widgets/family_graph.dart` lines 261, 286** — `ref.read(analyticsTrackerProvider)` in event handler methods `_onNodeTap()` and `_focusOnNode()`. Correct use.
5. **`lib/graph/widgets/onboarding_flow.dart` lines 239, 264, 286** — `ref.read(...notifier).update(...)` in mutation methods. Correct use.
6. **`lib/graph/widgets/onboarding_flow.dart` line 296** — `ref.read(analyticsTrackerProvider)` in `_trackStepCompleted()`. Correct use (side-effect only).
7. **`lib/graph/widgets/search_bar.dart` line 263** — `ref.read(analyticsTrackerProvider)` in async callback after await. Correct use.
8. **`lib/graph/widgets/control_bar.dart` line 80** — `ref.watch(isOnlineProvider)` in `build()`. Correct use.

---

## Consequences

### Positive

- Prevents an entire class of stale-state UI bugs
- Makes state dependencies explicit and traceable
- Aligns with Riverpod best practices and official documentation
- Easier code review: any `ref.read()` in a `build()` method is an automatic flag

### Negative

- `ref.watch()` triggers rebuilds on every provider change, which may cause unnecessary rebuilds if the watched provider emits frequently. Mitigation: use `ref.watch(provider.select(...))` to watch only specific derived values.
- Requires discipline and code review enforcement. Mitigation: the lint comment template and this ADR serve as enforceable references.

### Enforcement

- Code review: Any PR touching a Riverpod widget must be checked for `ref.read()` in `build()` paths
- Agent-8 should add a lint rule or test that flags `ref.read()` calls inside `build()` methods in ConsumerWidgets
- This rule is binding on all agents per CONTRIBUTING.md

---

## References

- [Riverpod: watch vs read](https://riverpod.dev/docs/essentials/combining_requests#using-refwatch-vs-refread)
- Bug PR: `fix/agent06/graph-overlay-visibility-fix` (PR #9)
- Bug PR: `fix/agent02/graph-onboarding-viewport-bugs` (PR #6)
