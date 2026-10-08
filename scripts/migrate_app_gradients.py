#!/usr/bin/env python3
"""
PR 2 — Migrate decorative gradients to KinrelFx.gradient() so flat
mode drops the gradient and falls back to a solid color.

Strategy
========
For each .dart file under lib/features/ (excluding chat which is
already done):
  1. Add the kinrel_fx.dart import.
  2. For every `gradient: <gradient-expr>,` inside a BoxDecoration
     (NOT inside a CustomPainter paint() — those are exempt), wrap
     as `gradient: KinrelFx.gradient(<gradient-expr>),` so flat mode
     returns null and the caller's `color:` (if present) takes over.

This script does NOT touch:
  - Primary orange CTA gradients (KinrelGradients.igniteGradient,
    ctaGradient, sunriseGradient, heritageGradient) — EXEMPT.
  - KINREL wordmark gradients (wordmarkGradient) — EXEMPT.
  - achievementGradient, signOutGradient — EXEMPT (brand).
  - ShaderMask usages — EXEMPT.
  - CustomPainter paint() methods (Paint()..shader = ...) — EXEMPT.

Skip lib/features/chat (already done in PR 95) and lib/graph
(done in PR 1 graph-glow-lite).

Usage: python3 scripts/migrate_app_gradients.py [--apply]
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path("/home/z/my-project/workspace/Daxelo-Kinrel/Daxelo-Kinrel-App")
SKIP_DIRS = {"lib/features/chat", "lib/graph"}

EXEMPT_GRADIENT_NAMES = {
    "igniteGradient",
    "ctaGradient",
    "sunriseGradient",
    "heritageGradient",
    "wordmarkGradient",
    "signOutGradient",
    "signOutGradientDark",
    "achievementGradient",
}


def is_exempt_gradient(expr: str) -> bool:
    """Check if a gradient expression references an exempt gradient name."""
    for name in EXEMPT_GRADIENT_NAMES:
        if name in expr:
            return True
    return False


def import_path_for(rel_path: str) -> str:
    depth = rel_path.count("/") - 1
    return "../" * depth + "core/theme/kinrel_fx.dart"


def ensure_import(content: str, import_line: str) -> str:
    if "kinrel_fx.dart" in content:
        return content
    lines = content.split("\n")
    last_core_idx = -1
    for i, line in enumerate(lines):
        if "core/" in line and line.lstrip().startswith("import"):
            last_core_idx = i
    if last_core_idx < 0:
        last_import_idx = -1
        for i, line in enumerate(lines):
            if line.lstrip().startswith("import"):
                last_import_idx = i
        if last_import_idx < 0:
            return f"import '{import_line}';\n" + content
        lines.insert(last_import_idx + 1, f"import '{import_line}';")
        return "\n".join(lines)
    lines.insert(last_core_idx + 1, f"import '{import_line}';")
    return "\n".join(lines)


def wrap_gradients(content: str) -> tuple[str, int]:
    """Find every `gradient: <expr>,` inside a BoxDecoration (widget
    context, NOT painter) and wrap with KinrelFx.gradient(<expr>).

    Conservative: only matches `gradient:` followed by a `const` keyword
    OR an identifier — skips `gradient: KinrelGradients.<exempt>` and
    `gradient: SomeGradient(...)` that contain exempt names.
    """
    count = 0
    # Pattern: gradient: <something that ends with ),
    # We need to match `gradient:` then capture the gradient expression
    # up to the matching close paren of the gradient constructor.
    # Conservative: match `gradient: const LinearGradient(` or
    # `gradient: LinearGradient(` or `gradient: const RadialGradient(`
    # or `gradient: RadialGradient(` or `gradient: KinrelGradients.X`
    # or `gradient: someVar`.
    #
    # Skip if the line contains an exempt gradient name.
    # Skip if already wrapped in KinrelFx.gradient(.
    # Skip if inside a Paint()..shader = context (heuristic: line
    # contains `..shader =`).

    out_lines = []
    for line in content.split("\n"):
        stripped = line.lstrip()
        # Skip if not a gradient: line
        if not re.match(r"^\s*gradient\s*:", line):
            out_lines.append(line)
            continue
        # Skip if already wrapped
        if "KinrelFx.gradient(" in line:
            out_lines.append(line)
            continue
        # Skip if contains an exempt gradient name
        if any(name in line for name in EXEMPT_GRADIENT_NAMES):
            out_lines.append(line)
            continue
        # Skip if this looks like a painter shader line
        if "..shader" in line or "createShader" in line:
            out_lines.append(line)
            continue
        # Skip ShaderMask usages (they use shaderCallback, not gradient:)
        if "shaderCallback" in line:
            out_lines.append(line)
            continue

        # This is a gradient: line that needs wrapping.
        # Extract the indentation and the gradient expression.
        # The expression starts after `gradient:` and ends at the
        # matching close paren (for constructor calls) OR at the
        # trailing comma (for simple references).
        #
        # Conservative approach: only wrap lines where the gradient
        # expression is on a SINGLE line ending with `),` (constructor
        # call) OR ends with a simple identifier + `,`.
        # Multi-line gradient expressions are skipped (would need
        # bracket matching across lines).
        indent_match = re.match(r"^(\s*)gradient\s*:\s*(.*)$", line)
        if not indent_match:
            out_lines.append(line)
            continue
        indent = indent_match.group(1)
        rest = indent_match.group(2)

        # Check if rest ends with `),` (single-line constructor call)
        # or `,` (simple reference like `someVar,`)
        if rest.endswith("),"):
            # Single-line constructor: wrap as KinrelFx.gradient(<expr>),
            # Remove the trailing `),` and re-add after wrapping.
            expr = rest[:-2]  # strip `),`
            # expr is like `const LinearGradient(...)` or `LinearGradient(...)`
            new_line = f"{indent}gradient: KinrelFx.gradient({expr}),"
            out_lines.append(new_line)
            count += 1
        elif rest.endswith(",") and "(" not in rest:
            # Simple reference: `someVar,` or `KinrelGradients.foo,`
            # (but KinrelGradients.foo is exempt — already skipped above)
            expr = rest[:-1].strip()  # strip `,`
            new_line = f"{indent}gradient: KinrelFx.gradient({expr}),"
            out_lines.append(new_line)
            count += 1
        else:
            # Multi-line or complex — skip
            out_lines.append(line)

    return "\n".join(out_lines), count


def main():
    apply = "--apply" in sys.argv
    total_files = 0
    total_wraps = 0
    files_changed = []

    for dart_file in REPO_ROOT.rglob("lib/features/**/*.dart"):
        rel = str(dart_file.relative_to(REPO_ROOT))
        if any(rel.startswith(skip) for skip in SKIP_DIRS):
            continue
        text = dart_file.read_text()
        if "gradient:" not in text:
            continue
        # Skip if file is a `part of`
        if re.search(r"^\s*part of\s+", text, re.MULTILINE):
            continue
        new_text = ensure_import(text, import_path_for(rel))
        new_text, count = wrap_gradients(new_text)
        if count > 0:
            files_changed.append((rel, count))
            total_wraps += count
            if apply:
                dart_file.write_text(new_text)

    print(f"{'Applied' if apply else 'DRY RUN'} — {len(files_changed)} files, {total_wraps} gradient sites wrapped.")
    if not apply:
        for rel, count in files_changed[:30]:
            print(f"  {rel}: {count}")
        if len(files_changed) > 30:
            print(f"  ... and {len(files_changed) - 30} more")


if __name__ == "__main__":
    main()
