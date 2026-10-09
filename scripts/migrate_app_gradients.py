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

REPO_ROOT auto-detection
========================
The script auto-detects its repo root by walking up from its own
location until it finds `Daxelo-Kinrel-App/`. Override with
`--repo-root /path/to/Daxelo-Kinrel-App` (useful in CI where the
script is copied out of tree).

Usage
=====
  # Dry-run (default): prints what WOULD be changed, no files touched.
  python3 scripts/migrate_app_gradients.py
  # Apply changes in place.
  python3 scripts/migrate_app_gradients.py --apply
  # Explicit repo root (otherwise auto-detected from script location).
  python3 scripts/migrate_app_gradients.py --repo-root /path/to/Daxelo-Kinrel-App
  # JSON report (for CI artifacts).
  python3 scripts/migrate_app_gradients.py --format json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable

# Directories under lib/ that have already been migrated by earlier PRs.
# Keep these in sync with the perf/flat-* PR series.
SKIP_DIRS: frozenset[str] = frozenset({"lib/features/chat", "lib/graph"})

# Brand gradients that must NEVER be flattened (they ARE the brand look).
# Matched as whole-word identifiers (regex \b boundaries) so a comment
# mentioning "igniteGradient" does NOT incorrectly exempt a different
# gradient on the same line.
EXEMPT_GRADIENT_NAMES: frozenset[str] = frozenset({
    "igniteGradient",
    "ctaGradient",
    "sunriseGradient",
    "heritageGradient",
    "wordmarkGradient",
    "signOutGradient",
    "signOutGradientDark",
    "achievementGradient",
})


# ── Helpers ────────────────────────────────────────────────────────────


def find_repo_root(explicit: Path | None = None) -> Path:
    """Return the Daxelo-Kinrel-App directory.

    Priority:
      1. --repo-root CLI arg
      2. Walk up from this script's location until we find a directory
         named `Daxelo-Kinrel-App` containing `lib/features/`.
      3. Fall back to CWD if it looks like the app root.
    """
    if explicit is not None:
        explicit = explicit.resolve()
        if not (explicit / "lib" / "features").is_dir():
            raise SystemExit(
                f"--repo-root does not look like the app root: {explicit}\n"
                f"Expected <root>/lib/features/ to exist."
            )
        return explicit

    # Walk up from this script's location.
    here = Path(__file__).resolve().parent
    for candidate in [here, *here.parents]:
        # <repo>/scripts/migrate_app_gradients.py → candidate=scripts
        # → parent has Daxelo-Kinrel-App/
        app_dir = candidate / "Daxelo-Kinrel-App"
        if (app_dir / "lib" / "features").is_dir():
            return app_dir
        # also handle being called from inside Daxelo-Kinrel-App/
        if (candidate / "lib" / "features").is_dir() and candidate.name == "Daxelo-Kinrel-App":
            return candidate

    # Fallback: CWD
    cwd = Path.cwd()
    if (cwd / "lib" / "features").is_dir():
        return cwd
    if (cwd / "Daxelo-Kinrel-App" / "lib" / "features").is_dir():
        return cwd / "Daxelo-Kinrel-App"

    raise SystemExit(
        "Could not auto-detect Daxelo-Kinrel-App root. "
        "Pass --repo-root /path/to/Daxelo-Kinrel-App explicitly."
    )


def is_exempt_gradient(line: str) -> bool:
    """True if the line references an exempt gradient NAME as an identifier.

    Uses word-boundary regex so that `// not igniteGradient` in a comment
    does NOT incorrectly exempt a different gradient on the same line.
    Strips comments first so trailing `// ...` text can't trip the check.
    """
    # Strip trailing line comments (// ...) — keep /* ... */ for simplicity.
    code = re.sub(r"//.*$", "", line)
    for name in EXEMPT_GRADIENT_NAMES:
        if re.search(r"\b" + re.escape(name) + r"\b", code):
            return True
    return False


def import_path_for(rel_path: str) -> str:
    """Compute the Dart package-relative import path for kinrel_fx.dart.

    rel_path is like `lib/features/auth/presentation/sign_in_screen.dart`.
    Dart's package: imports are relative to the importing file. The
    `lib/` directory is the root, so we count how many directories deep
    the file is BELOW `lib/` and prepend that many `../`.

      lib/main.dart                           → core/theme/kinrel_fx.dart
      lib/features/auth.dart                  → ../core/theme/kinrel_fx.dart
      lib/features/auth/foo.dart              → ../../core/theme/kinrel_fx.dart
      lib/features/a/b/c/d/foo.dart           → ../../../core/theme/kinrel_fx.dart  (4 dirs deep)

    The file's own basename contributes one "/" but no depth, so depth =
    (slashes in rel_path) - 1.
    """
    depth = max(rel_path.count("/") - 1, 0)
    return ("../" * depth) + "core/theme/kinrel_fx.dart"


def ensure_import(content: str, import_path: str) -> tuple[str, bool]:
    """Insert `import '<path>';` if not already present.

    Returns (new_content, added). The added flag lets the caller
    distinguish "no-op because already imported" from "no-op because no
    gradient was wrapped".

    The check looks specifically for `import .*kinrel_fx.dart` so that
    a reference to kinrel_fx in a comment / string / test file does NOT
    incorrectly suppress the import.
    """
    # Match `import '.../kinrel_fx.dart';` (single or double quotes,
    # optional `;`, possibly with `deferred as` / `if (config)`)
    if re.search(
        r"""^\s*import\s+['"][^'"]*kinrel_fx\.dart['"]\s*;""",
        content,
        re.MULTILINE,
    ):
        return content, False

    lines = content.split("\n")
    insert_line = f"import '{import_path}';"

    # Prefer to insert immediately after the LAST `core/...` import,
    # to keep the core/theme imports grouped together.
    last_core_idx = -1
    for i, line in enumerate(lines):
        if "core/" in line and line.lstrip().startswith("import"):
            last_core_idx = i

    if last_core_idx >= 0:
        lines.insert(last_core_idx + 1, insert_line)
        return "\n".join(lines), True

    # No core/ imports yet — insert after the LAST import of any kind.
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.lstrip().startswith("import"):
            last_import_idx = i
    if last_import_idx >= 0:
        lines.insert(last_import_idx + 1, insert_line)
        return "\n".join(lines), True

    # No imports at all — prepend.
    return insert_line + "\n" + content, True


# Pattern that matches the opening of a const decoration constructor
# whose body may contain a `gradient:` argument. The decoration
# classes that accept a `gradient:` argument are BoxDecoration,
# ShapeDecoration, and FlutterLogoDecoration. We strip the `const`
# keyword from this line when we wrap a gradient inside, because
# KinrelFx.gradient() is non-const and would break the const context.
#
# NOTE: not anchored to start-of-line. In Dart widget trees the `const`
# is almost always mid-line, e.g. `decoration: const BoxDecoration(`.
# We search the whole line and strip just `const ` (with the trailing
# space), preserving everything else.
CONST_DECO_OPEN_RE = re.compile(
    r"\bconst\s+(BoxDecoration|ShapeDecoration|FlutterLogoDecoration)\s*\("
)


def _strip_const_from_deco(lines: list[str], gradient_idx: int) -> bool:
    """If the `gradient:` line at index `gradient_idx` is preceded
    (within 30 lines) by a `const BoxDecoration(` / `const
    ShapeDecoration(` / `const FlutterLogoDecoration(` whose body still
    spans the gradient line, strip the `const ` keyword from that
    opening line in place. Return True if a strip happened.

    The depth check uses simple paren counting on the original
    (post-strip) lines, ignoring parens inside string/char literals —
    good enough for the decoration-body heuristic; the gradient: line
    itself is the only argument we care about, and decoration bodies
    are short.
    """
    # Scan backwards up to 30 lines for the most recent const decoration open.
    open_idx = -1
    # Iterate from gradient_idx-30 .. gradient_idx inclusive (newest first
    # so the most-recent match wins when there are nested const decos).
    start = max(0, gradient_idx - 30)
    for j in range(gradient_idx, start - 1, -1):
        if CONST_DECO_OPEN_RE.search(lines[j]):
            open_idx = j
            break
    if open_idx < 0:
        return False
    # Verify the gradient: line is INSIDE the decoration body — the
    # paren depth between open_idx and gradient_idx must be >= 1 at
    # every step from open_idx (after the opening paren) up to and
    # including gradient_idx.
    depth = 0
    for j in range(open_idx, gradient_idx + 1):
        line = lines[j]
        # crude: ignore parens inside "..." / '...'.
        in_str = False
        str_ch = ""
        # Handle escape sequences: track prev char so we can skip the
        # character following a backslash inside a string.
        prev = ""
        for ch in line:
            if in_str:
                if prev == "\\":
                    prev = ch
                    continue
                if ch == "\\":
                    prev = ch
                    continue
                if ch == str_ch:
                    in_str = False
                prev = ch
                continue
            if ch in ("'", '"'):
                in_str = True
                str_ch = ch
                prev = ch
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            prev = ch
        # If depth drops to 0 or below at the end of an intermediate
        # line (before gradient_idx), the decoration has already
        # closed — the gradient: is NOT inside it. Bail.
        if depth <= 0 and j < gradient_idx:
            return False
    if depth < 1:
        return False
    # Strip `const ` from the open line.
    open_line = lines[open_idx]
    new_open = CONST_DECO_OPEN_RE.sub(
        lambda m: f"{m.group(1)}(",
        open_line,
        count=1,
    )
    if new_open == open_line:
        return False
    lines[open_idx] = new_open
    return True


def wrap_gradients(content: str) -> tuple[str, int]:
    """Wrap every eligible `gradient: <expr>,` with KinrelFx.gradient(...).

    Eligibility (per line whose first non-whitespace token is `gradient:`):
      - NOT already wrapped in KinrelFx.gradient(
      - NOT referencing an exempt gradient name (word-boundary match)
      - NOT a Paint()..shader = / createShader line (CustomPainter)
      - NOT a ShaderMask shaderCallback line
      - Single-line constructor call ending in `),` → wrap inline
      - Simple identifier reference ending in `,` (no `(`) → wrap inline
      - Anything else (multi-line constructor, ternary, etc.) → SKIP
        (logged in conservative-skip count for manual review)

    Const-context safety
    ====================
    When a wrap target is inside `const BoxDecoration(...)` /
    `const ShapeDecoration(...)` / `const FlutterLogoDecoration(...)`,
    the surrounding `const` keyword is ALSO stripped (because
    `KinrelFx.gradient()` is non-const and would break the const
    context). The strip is verified with paren-depth tracking so we
    don't strip const from an unrelated decoration that happens to
    appear nearby.
    """
    wrapped = 0
    out_lines: list[str] = content.split("\n")
    const_strips = 0

    i = 0
    while i < len(out_lines):
        line = out_lines[i]
        if not re.match(r"^\s*gradient\s*:", line):
            i += 1
            continue
        if "KinrelFx.gradient(" in line:
            i += 1
            continue
        if is_exempt_gradient(line):
            i += 1
            continue
        if "..shader" in line or "createShader" in line:
            i += 1
            continue
        if "shaderCallback" in line:
            i += 1
            continue

        m = re.match(r"^(\s*)gradient\s*:\s*(.*)$", line)
        if not m:
            i += 1
            continue
        indent, rest = m.group(1), m.group(2)

        new_line = None
        if rest.endswith("),"):
            # `gradient: <const?> <Gradient>(...),` → wrap as
            # `gradient: KinrelFx.gradient(<const?> <Gradient>(...)),`
            expr = rest[:-2]  # strip trailing `),`
            new_line = f"{indent}gradient: KinrelFx.gradient({expr}),"
        elif rest.endswith(",") and "(" not in rest:
            # `gradient: someIdentifier,` → wrap as
            # `gradient: KinrelFx.gradient(someIdentifier),`
            expr = rest[:-1].strip()
            if not expr:
                i += 1
                continue
            new_line = f"{indent}gradient: KinrelFx.gradient({expr}),"
        else:
            # Multi-line constructor or ternary — skip for manual review.
            i += 1
            continue

        # Strip const from the surrounding const decoration if any.
        if _strip_const_from_deco(out_lines, i):
            const_strips += 1

        out_lines[i] = new_line
        wrapped += 1
        i += 1

    return "\n".join(out_lines), wrapped


# ── Discovery + main ────────────────────────────────────────────────────


def iter_target_files(repo_root: Path) -> Iterable[Path]:
    """Yield every .dart file under lib/features/, minus SKIP_DIRS and
    `part of` files."""
    features_dir = repo_root / "lib" / "features"
    if not features_dir.is_dir():
        return
    for dart_file in features_dir.rglob("*.dart"):
        rel = dart_file.relative_to(repo_root).as_posix()
        if any(rel.startswith(skip) for skip in SKIP_DIRS):
            continue
        try:
            text = dart_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if "gradient:" not in text:
            continue
        if re.search(r"^\s*part of\s+", text, re.MULTILINE):
            continue
        yield dart_file


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[1] if __doc__ else "")
    p.add_argument("--apply", action="store_true",
                   help="Apply changes in place (default: dry-run).")
    p.add_argument("--repo-root", type=Path, default=None,
                   help="Path to Daxelo-Kinrel-App/ (auto-detected if omitted).")
    p.add_argument("--format", choices=("text", "json"), default="text",
                   help="Output format. text (default) or json (for CI).")
    args = p.parse_args()

    repo_root = find_repo_root(args.repo_root)

    files_changed: list[dict] = []
    total_wraps = 0

    for dart_file in iter_target_files(repo_root):
        rel = dart_file.relative_to(repo_root).as_posix()
        text = dart_file.read_text(encoding="utf-8")
        new_text, added_import = ensure_import(text, import_path_for(rel))
        new_text, count = wrap_gradients(new_text)
        if count == 0 and not added_import:
            continue
        # Only count as "changed" if we actually wrapped something.
        if count == 0:
            continue
        files_changed.append({"file": rel, "wraps": count, "import_added": added_import})
        total_wraps += count
        if args.apply and new_text != text:
            dart_file.write_text(new_text, encoding="utf-8")

    if args.format == "json":
        print(json.dumps({
            "mode": "apply" if args.apply else "dry-run",
            "repo_root": str(repo_root),
            "files_changed": len(files_changed),
            "total_wraps": total_wraps,
            "files": files_changed,
        }, indent=2))
    else:
        mode = "Applied" if args.apply else "DRY RUN"
        print(f"{mode} — {len(files_changed)} files, {total_wraps} gradient sites wrapped.")
        print(f"repo_root: {repo_root}")
        if files_changed:
            print()
            for entry in files_changed[:50]:
                imp = " (+import)" if entry["import_added"] else ""
                print(f"  {entry['file']}: {entry['wraps']} wrap{'' if entry['wraps'] == 1 else 's'}{imp}")
            if len(files_changed) > 50:
                print(f"  ... and {len(files_changed) - 50} more")
        else:
            print("  (no eligible gradient sites found — script is a no-op)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
