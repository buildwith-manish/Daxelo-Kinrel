# ADR-007: Safe Area & Overlay Policy — Graph Widgets

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-06-14 |
| **Decision Maker** | Agent-0 (Lead Architect) |
| **Affected Agents** | Agent-2 (Graph), Agent-6 (Flutter), Agent-8 (Testing) |
| **Supersedes** | None |
| **Related Bugs** | Notch/safe-area violations in graph widgets, `graph_legend` first-visit auto-open, `onboarding_flow.dart` canvas-blocking overlay |

---

## Context

A pattern of safe-area and overlay violations has been identified across the graph widgets in `lib/graph/widgets/`. These violations fall into three distinct categories: hardcoded safe-area offsets, double-stacked SafeArea padding, and unsolicited overlay panels that degrade first-run UX. Each category has caused real user-facing bugs on devices with notches, dynamic islands, or bottom gesture bars.

### Root Cause

Flutter's `Scaffold` does not automatically apply safe-area insets to its `body` — it is the widget author's responsibility to account for `MediaQuery.of(context).padding` (notch, status bar, bottom gesture area) when positioning elements inside a `Stack`. The project's graph widgets use `Stack` + `Positioned()` patterns extensively for overlays, legends, and control bars. When authors hardcode pixel offsets (e.g., `top: 16`, `bottom: 24`) instead of reading the device's actual safe-area insets, content is clipped behind notches or overlaps the home indicator on devices with gesture navigation.

Compounding the problem, some widgets apply `SafeArea()` as a wrapper **and** use `MediaQuery`-based offsets in a parent `Positioned()`, causing double padding — the overlay is pushed further from the edge than intended, wasting screen real estate and creating inconsistent spacing across the UI.

Finally, two overlay features — the `graph_legend` auto-open on first visit and the `onboarding_flow.dart` canvas-blocking overlay — introduced unsolicited UI that the user never requested. These overlays interrupted the first-run experience and were not specified in the product requirements. Agent-6 has already removed the `graph_legend` auto-open behavior.

### Bug Instances Found

| File | Issue | Severity |
|------|-------|----------|
| `lib/graph/widgets/family_graph.dart` | `Positioned(top: 16)` inside Scaffold body Stack — clipped behind notch on iPhone 14 Pro and similar devices | **HIGH** — content invisible under dynamic island |
| `lib/graph/widgets/family_graph.dart` | `Positioned(bottom: 24)` — overlaps bottom gesture bar on Android gesture navigation | **HIGH** — content hidden behind system gesture area |
| `lib/graph/widgets/graph_legend.dart` | `SafeArea()` wrapper inside a `Positioned()` that already offsets via `MediaQuery.padding.top` — double top padding | **MEDIUM** — legend panel pushed too far down, wastes ~48px |
| `lib/graph/widgets/control_bar.dart` | `Positioned(bottom: 16)` — safe-area not respected | **MEDIUM** — control bar partially obscured on devices with bottom inset |
| `lib/graph/widgets/graph_legend.dart` | Auto-open on first visit (now removed by Agent-6) | **HIGH** — unsolicited overlay, not in product spec |
| `lib/graph/widgets/onboarding_flow.dart` | Canvas-blocking onboarding overlay (deprecated) | **HIGH** — blocks graph canvas, negative user feedback |

**Verdict**: The hardcoded `Positioned()` offsets are the most widespread issue. The double-stacked SafeArea is a correctness bug that produces visible misalignment. The unsolicited overlays are a UX anti-pattern that must be prevented from recurring.

---

## Decision

### Rule 1: `Positioned()` offsets inside Scaffold body `Stack` MUST use `MediaQuery`

All `Positioned()` widgets inside a `Stack` that is a direct child of `Scaffold`'s `body` must derive their top and bottom offsets from `MediaQuery.of(context).padding`, never from hardcoded pixel values.

| Offset | Correct Pattern | Forbidden Pattern |
|--------|----------------|-------------------|
| Top | `top: MediaQuery.of(context).padding.top + 16` | `top: 16` |
| Bottom | `bottom: MediaQuery.of(context).padding.bottom + 24` | `bottom: 24` |

The additional constant (e.g., `+ 16`, `+ 24`) represents the desired visual spacing **after** the safe area is accounted for. The `MediaQuery.padding` portion ensures the content clears the notch, status bar, or gesture indicator.

```dart
// BEFORE (violation):
Positioned(
  top: 16,
  left: 0,
  right: 0,
  child: graphAppBar,
)

// AFTER (correct):
Positioned(
  top: MediaQuery.of(context).padding.top + 16,
  left: 0,
  right: 0,
  child: graphAppBar,
)
```

For bottom-positioned elements:

```dart
// BEFORE (violation):
Positioned(
  bottom: 24,
  left: 0,
  right: 0,
  child: controlBar,
)

// AFTER (correct):
Positioned(
  bottom: MediaQuery.of(context).padding.bottom + 24,
  left: 0,
  right: 0,
  child: controlBar,
)
```

**Important**: This rule applies specifically to `Positioned()` widgets inside a `Stack` that is a direct child of `Scaffold`'s `body`. Widgets that are not inside such a Stack (e.g., inline content in a `ListView`, or content inside a `SafeArea`-wrapped `Column`) are not subject to this rule because those containers handle safe-area insets differently.

### Rule 2: No double-stacked SafeArea — pick ONE approach per widget tree level

`SafeArea()` wrappers must NOT be combined with `MediaQuery`-based offsets on the same axis at the same widget tree level. This creates double padding: the `Positioned()` already accounts for the safe-area inset, and then `SafeArea()` adds it again.

Pick **one** approach per axis per widget tree level:

| Approach | When to Use | Example |
|----------|------------|---------|
| `Positioned(top: MediaQuery.of(context).padding.top + kSpacing)` | Inside a `Stack` where the widget is absolutely positioned | Overlay panels, floating toolbars, legends |
| `SafeArea(child: ...)` | Inside a `Stack` where the `Positioned()` does NOT apply a safe-area offset, or outside a `Stack` entirely | Full-screen content, scrollable views |

```dart
// WRONG (double padding):
Positioned(
  top: MediaQuery.of(context).padding.top + 16,
  child: SafeArea(              // ← SafeArea adds padding.top AGAIN
    child: LegendPanel(),
  ),
)

// CORRECT (approach A — MediaQuery in Positioned, no SafeArea):
Positioned(
  top: MediaQuery.of(context).padding.top + 16,
  child: LegendPanel(),
)

// CORRECT (approach B — Positioned at 0, SafeArea handles inset):
Positioned(
  top: 0,
  child: SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LegendPanel(),
    ),
  ),
)
```

**Recommendation**: For graph widget overlays in `Stack` layouts, prefer approach A (MediaQuery in `Positioned`) because it gives the author precise, explicit control over the total offset and makes the safe-area accounting visible at the positioning site.

### Rule 3: Auto-opening panels/overlays are PROHIBITED unless explicitly in product spec

No widget may automatically open, expand, or display an overlay panel on first visit, first load, or any unsolicited trigger unless the feature is:

1. **Explicitly documented in the product specification**, AND
2. **Signed off by the product owner** (with sign-off recorded in the relevant issue/PR)

This specifically addresses the `graph_legend` first-visit auto-open behavior, which was removed by Agent-6. That feature caused the legend panel to appear uninvited on a user's first graph view, obscuring graph content and creating confusion. No product requirement specified this behavior — it was a developer-added "convenience" that degraded UX.

**Enforcement**: Any PR that introduces an auto-opening overlay must include a link to the product spec issue where the feature is defined and approved. PRs without such a link will be rejected.

### Rule 4: Onboarding overlays inside the graph canvas are removed and deprecated

The `onboarding_flow.dart` widget that rendered a blocking overlay on top of the graph canvas is deprecated. No agent may re-introduce any overlay that blocks or obscures the graph canvas area.

User feedback consistently identified the canvas-blocking onboarding overlay as a negative first-run experience. Users expected to see and interact with their family graph immediately upon loading, not be forced through a multi-step tutorial overlay that prevented graph interaction.

**Deprecated file**: `lib/graph/widgets/onboarding_flow.dart` — do not delete (it may contain reusable animation logic for a future non-blocking approach), but do not import or render it in any widget tree.

**Future onboarding**: If onboarding guidance is needed for the graph view, it must be implemented as a **non-blocking** pattern — for example, a dismissible tooltip, a subtle hint chip, or a "Show me around" button that the user opts into. Any such implementation requires a product spec and sign-off per Rule 3.

---

## Consequences

### Positive

- Eliminates an entire class of notch/clipping bugs across all device form factors (notched phones, dynamic island, foldables, tablets with status bars)
- Makes safe-area intent explicit at each positioning site — no hidden `SafeArea` behavior in the widget tree
- Prevents double-padding misalignment that is difficult to debug visually
- Protects first-run UX from unsolicited overlays that were not requested by users or product
- Establishes a clear, enforceable boundary: overlays require product sign-off
- Prevents regression of the onboarding overlay issue — no agent can re-introduce it without a spec

### Negative

- Every `Positioned()` in a Scaffold-body Stack must call `MediaQuery.of(context).padding`, which adds verbosity. Mitigation: a helper extension or constant pattern can reduce boilerplate (e.g., `context.safeTop + kSpacing`).
- Developers must be conscious of which approach they pick (MediaQuery vs SafeArea) and not mix them. Mitigation: Rule 2 is binary and easy to lint for — if a `Positioned()` has a `MediaQuery`-derived offset, its child must not wrap in `SafeArea()` on the same axis.
- The auto-open prohibition means some "helpful" first-run features require a product decision before implementation. This is intentional — it forces UX choices through the proper channel.

### Enforcement

- **Code review**: Any PR touching a `Positioned()` inside a Scaffold-body Stack must be checked for hardcoded top/bottom offsets and double-stacked SafeArea.
- **Agent-8**: Add a lint rule or test that flags `Positioned(top: <int>)` or `Positioned(bottom: <int>)` with literal values inside `Stack` widgets that are children of `Scaffold` body.
- **Agent-8**: Add a lint rule or test that flags `SafeArea()` as a child of a `Positioned()` that already uses `MediaQuery.of(context).padding` on the same axis.
- **PR gate**: Any PR introducing an auto-opening overlay must reference a product spec issue. PRs without this reference will be blocked.
- **Deprecated file check**: `onboarding_flow.dart` must not be imported in any widget tree. Agent-8 should verify this in CI.
- This rule is binding on all agents per CONTRIBUTING.md.

---

## References

- [Flutter: MediaQuery.padding](https://api.flutter.dev/flutter/widgets/MediaQuery/padding.html)
- [Flutter: SafeArea widget](https://api.flutter.dev/flutter/widgets/SafeArea-class.html)
- Bug fix: `graph_legend` first-visit auto-open removed by Agent-6
- Deprecated: `lib/graph/widgets/onboarding_flow.dart`
- Related ADR: [ADR-006](./ADR-006-riverpod-read-vs-watch.md) — Riverpod `ref.read()` vs `ref.watch()` guardrail
