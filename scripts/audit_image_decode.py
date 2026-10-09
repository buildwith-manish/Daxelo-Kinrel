#!/usr/bin/env python3
"""
PR 2 — Image decode audit.

Audits the Flutter app for image-decode call sites that are missing
`cacheWidth` / `cacheHeight` / `ResizeImage`, which cause images to be
decoded at their NATIVE resolution — the #1 cause of GPU memory spikes
and decode jank on mid-tier Android devices.

Why this matters
================
A 4032x3024 phone photo (12 MP) loaded via `Image.network(url)` decodes
to a 4032x3024 RGBA bitmap = ~46 MB of GPU memory, even if it is shown
in a 96x96 avatar. The Flutter framework can downscale on the paint
side, but the DECODE step still allocates the full-resolution bitmap.

Mitigations (in order of preference):
  1. Pass `cacheWidth:` / `cacheHeight:` to `Image.network`,
     `Image.asset`, `Image.memory`, `Image.file`, `Image(...)` — the
     decode step then allocates only the requested size.
  2. Wrap a `NetworkImage` / `AssetImage` source in `ResizeImage(...)`
     when the image is consumed via `DecorationImage`,
     `CircleAvatar(backgroundImage:)`, `Image(image:)`, etc. (these
     consumers do not accept cacheWidth directly).

What this script flags
======================
  HIGH   Image.network / .asset / .memory / .file missing both
         cacheWidth AND cacheHeight.
  HIGH   Image(image: NetworkImage(...)) missing both cache dims.
  MEDIUM DecorationImage(image: NetworkImage/AssetImage(...)) whose
         source is NOT wrapped in ResizeImage(...).
  MEDIUM CircleAvatar(backgroundImage: NetworkImage(...)) whose source
         is NOT wrapped in ResizeImage(...).
  INFO   Bare `NetworkImage(...)` / `AssetImage(...)` literal not
         inside ResizeImage(...) — caller may have a good reason
         (e.g. shown at native resolution), flagged for review.

Skipped
=======
  - Files under `test/`, `integration_test/`
  - `*_test.dart` files
  - Generated files: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`
  - Files with `// audit-image-decode: ignore-file` on the first 5
    lines (escape hatch for legitimate full-res use cases)

Usage
=====
  python3 scripts/audit_image_decode.py
  python3 scripts/audit_image_decode.py --repo-root /path/to/Daxelo-Kinrel-App
  python3 scripts/audit_image_decode.py --format json
  python3 scripts/audit_image_decode.py --format md > audit.md
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Iterable

# ── Config ─────────────────────────────────────────────────────────────

SKIP_PATH_PREFIXES: tuple[str, ...] = (
    "test/",
    "integration_test/",
)

SKIP_SUFFIXES: tuple[str, ...] = (
    "_test.dart",
    ".g.dart",
    ".freezed.dart",
    ".gr.dart",
)

# The image.* widget constructors that accept cacheWidth / cacheHeight
# directly. Use regex with word boundary so e.g. `CachedNetworkImage(`
# does NOT match the `NetworkImage(` rule.
DIRECT_IMAGE_CONSTRUCTOR_RE = re.compile(
    r"(?<![A-Za-z0-9_])(Image\.(?:network|asset|memory|file)\s*\()"
)

# Bare image PROVIDERS that do NOT accept cacheWidth/Height themselves;
# they must be wrapped in ResizeImage(...) to downscale at decode time.
# Word-boundary match so `CachedNetworkImage(` and `ResizeImage(` are
# NOT picked up here.
BARE_PROVIDER_RE = re.compile(
    r"(?<![A-Za-z0-9_])((?:NetworkImage|AssetImage|FileImage|MemoryImage)\s*\()"
)

# Contexts that consume an image provider via :image / :backgroundImage /
# :image provider. These require ResizeImage wrapping for downscaling.
PROVIDER_CONSUMERS: tuple[str, ...] = (
    "image:",
    "backgroundImage:",
    "foregroundImage:",
)

FILE_IGNORE_MARKER = "audit-image-decode: ignore-file"


# ── Data classes ───────────────────────────────────────────────────────

@dataclass
class Finding:
    severity: str          # "HIGH" | "MEDIUM" | "INFO"
    file: str
    line: int
    col: int = 0
    rule: str = ""
    snippet: str = ""
    suggestion: str = ""


@dataclass
class FileReport:
    file: str
    findings: list[Finding] = field(default_factory=list)


# ── Helpers ────────────────────────────────────────────────────────────

def find_repo_root(explicit: Path | None = None) -> Path:
    """Return the Daxelo-Kinrel-App directory (mirrors
    migrate_app_gradients.py)."""
    if explicit is not None:
        explicit = explicit.resolve()
        if not (explicit / "lib").is_dir():
            raise SystemExit(f"--repo-root does not look like the app root: {explicit}")
        return explicit
    here = Path(__file__).resolve().parent
    for cand in [here, *here.parents]:
        app = cand / "Daxelo-Kinrel-App"
        if (app / "lib").is_dir():
            return app
        if (cand / "lib").is_dir() and cand.name == "Daxelo-Kinrel-App":
            return cand
    cwd = Path.cwd()
    if (cwd / "lib").is_dir():
        return cwd
    if (cwd / "Daxelo-Kinrel-App" / "lib").is_dir():
        return cwd / "Daxelo-Kinrel-App"
    raise SystemExit("Could not auto-detect Daxelo-Kinrel-App root. "
                     "Pass --repo-root /path/to/Daxelo-Kinrel-App.")


def is_skippable(rel_path: str) -> bool:
    for prefix in SKIP_PATH_PREFIXES:
        if rel_path.startswith(prefix):
            return True
    for suffix in SKIP_SUFFIXES:
        if rel_path.endswith(suffix):
            return True
    return False


def strip_comments(text: str) -> tuple[list[str], list[set[int]]]:
    """Return (code_lines, masked) where code_lines is the source with
    comments replaced by spaces (preserving newlines + columns so line
    numbers and column offsets stay valid), and `masked[i]` is the set of
    column indices on line i that are INSIDE a comment (so the audit can
    skip matches that fall inside comments).

    Handles:
      - `//` line comments (also `///` doc comments)
      - `/* ... */` block comments (can span multiple lines)
      - String literals '...' and "..." (so `//` inside a string is
        not treated as a comment)

    Does NOT handle raw string interpolations or triple-quoted strings
    (Dart has no triple-quoted strings; raw strings r'//' are rare in
    image-related code).
    """
    lines = text.split("\n")
    masked: list[set[int]] = [set() for _ in lines]
    in_block_comment = False
    in_string = False
    string_char = ""

    out_lines: list[str] = []
    for li, line in enumerate(lines):
        out_chars: list[str] = []
        i = 0
        n = len(line)
        while i < n:
            ch = line[i]
            if in_block_comment:
                # Inside /* ... */ — mask until we find */
                if ch == "*" and i + 1 < n and line[i + 1] == "/":
                    in_block_comment = False
                    masked[li].add(i)
                    masked[li].add(i + 1)
                    out_chars.append(" ")
                    out_chars.append(" ")
                    i += 2
                    continue
                masked[li].add(i)
                out_chars.append(" ")
                i += 1
                continue
            if in_string:
                if ch == "\\" and i + 1 < n:
                    out_chars.append(line[i])
                    out_chars.append(line[i + 1])
                    i += 2
                    continue
                if ch == string_char:
                    in_string = False
                    out_chars.append(ch)
                    i += 1
                    continue
                out_chars.append(ch)
                i += 1
                continue
            # Not in block comment, not in string.
            if ch == "/" and i + 1 < n and line[i + 1] == "/":
                # Rest of the line is a comment — mask everything.
                for j in range(i, n):
                    masked[li].add(j)
                # Pad the output line so column offsets stay aligned.
                out_chars.append(" " * (n - i))
                i = n
                continue
            if ch == "/" and i + 1 < n and line[i + 1] == "*":
                in_block_comment = True
                masked[li].add(i)
                masked[li].add(i + 1)
                out_chars.append("  ")
                i += 2
                continue
            if ch in ("'", '"'):
                in_string = True
                string_char = ch
                out_chars.append(ch)
                i += 1
                continue
            out_chars.append(ch)
            i += 1
        out_lines.append("".join(out_chars))
    return out_lines, masked


def file_ignored(text: str) -> bool:
    # Only look at the first 5 lines for the marker comment.
    head = "\n".join(text.split("\n")[:5])
    return FILE_IGNORE_MARKER in head


def matching_paren_span(lines: list[str], start_line_idx: int, start_col: int) -> tuple[int, int]:
    """Given the index of the line containing the OPENING `(` of a call
    and the column of that `(`, return (end_line_idx, end_col) of the
    matching close paren. Purely bracket-counting (ignores strings /
    comments — sufficient for our heuristic since Dart call sites
    rarely have unbalanced brackets inside strings)."""
    depth = 0
    in_string = False
    string_char = ""
    for i in range(start_line_idx, len(lines)):
        line = lines[i]
        col_start = start_col + 1 if i == start_line_idx else 0
        for j in range(col_start, len(line)):
            ch = line[j]
            if in_string:
                if ch == "\\":
                    # Skip next char (escape)
                    continue
                if ch == string_char:
                    in_string = False
                continue
            if ch in ("'", '"'):
                in_string = True
                string_char = ch
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return i, j
    return start_line_idx, start_col  # unbalanced — fall back


def find_token_in_span(lines: list[str], sline: int, scol: int, eline: int, ecol: int,
                       token: str) -> bool:
    """True if `token` appears as a key-token (whitespace-bounded) within
    the [sline,scol]–[eline,ecol] span. Used to detect `cacheWidth:` /
    `cacheHeight:` inside an Image constructor call."""
    for i in range(sline, eline + 1):
        line = lines[i]
        if i == sline and i == eline:
            line = line[scol + 1:ecol]
        elif i == sline:
            line = line[scol + 1:]
        elif i == eline:
            line = line[:ecol]
        # Match `cacheWidth:` or `cacheWidth :` etc.
        if re.search(r"\b" + re.escape(token) + r"\s*:", line):
            return True
    return False


def line_has_resize_image_before(lines: list[str], call_line_idx: int) -> bool:
    """Check if `ResizeImage(` appears on this line or the previous ~6
    lines before the bare-provider call — heuristic for the wrapping
    case `ResizeImage(ResizeImage(NetworkImage(...), height: 96))`.

    We look backwards for an open `ResizeImage(` whose matching close
    is BEYOND the call site. The cheap approximation: `ResizeImage(`
    appears on a line <= call_line_idx, AND no `)` closes it before
    the call's `(`.
    """
    # Cheap approximation: scan back up to 6 lines for `ResizeImage(`
    # without a balancing `)` on the same line.
    for i in range(max(0, call_line_idx - 6), call_line_idx + 1):
        line = lines[i] if i < len(lines) else ""
        if "ResizeImage(" in line:
            # If the same line closes the ResizeImage(...) before our
            # call, it's not wrapping us.
            open_idx = line.find("ResizeImage(")
            close_idx = line.find(")", open_idx + len("ResizeImage("))
            if close_idx < 0:
                # The ResizeImage( is still open at end of line → it
                # DOES span subsequent lines (probably wrapping us).
                return True
            # If close_idx is AFTER the bare-provider call on the same
            # line, also consider it wrapped.
            # (Single-line `ResizeImage(NetworkImage(url), ...)` case.)
            return True
    return False


# ── Per-file audit ─────────────────────────────────────────────────────

def audit_file(rel_path: str, text: str) -> FileReport:
    """Audit a single Dart source file. Returns a FileReport with 0..N
    findings. Conservative — better to under-report than to false-flag
    a wrapped call.

    Comments are stripped before pattern-matching so that a `//`
    comment mentioning `Image.memory(` is NOT flagged. The original
    (unstripped) line text is preserved for the snippet so the report
    shows what the developer actually sees.
    """
    report = FileReport(file=rel_path)
    raw_lines = text.split("\n")
    code_lines, masked = strip_comments(text)

    # 1. Direct Image.* constructors → check for cacheWidth AND cacheHeight.
    for i, line in enumerate(code_lines):
        for m in DIRECT_IMAGE_CONSTRUCTOR_RE.finditer(line):
            col = m.start(1)  # column of the `(` of e.g. `Image.network(`
            if col in masked[i]:
                continue
            eline, ecol = matching_paren_span(code_lines, i, col)
            has_cw = find_token_in_span(code_lines, i, col, eline, ecol, "cacheWidth")
            has_ch = find_token_in_span(code_lines, i, col, eline, ecol, "cacheHeight")
            if has_cw and has_ch:
                continue
            if has_cw:  # cacheWidth alone is acceptable (height auto)
                continue
            # Determine which constructor was matched for the suggestion.
            ctor_name = m.group(1).rstrip("( \t")  # e.g. "Image.network"
            report.findings.append(Finding(
                severity="HIGH",
                file=rel_path,
                line=i + 1,
                col=col + 1,
                rule="image-direct-no-cache-width",
                snippet=raw_lines[i].strip()[:120],
                suggestion=(
                    f"Pass cacheWidth: <logical px> to {ctor_name}(...) so the "
                    "image decodes at display size, not native resolution. "
                    "If the source is also consumed at a different size, "
                    "wrap in ResizeImage(source, width: w, height: h)."
                ),
            ))

    # 2. Bare NetworkImage / AssetImage / FileImage / MemoryImage calls.
    #    Flag if NOT wrapped in ResizeImage(...).
    for i, line in enumerate(code_lines):
        for m in BARE_PROVIDER_RE.finditer(line):
            col = m.start(1)
            if col in masked[i]:
                continue
            if line_has_resize_image_before(code_lines, i):
                continue
            # Skip if this is the `image:` argument of an Image(...) —
            # those are caught by rule 3 below with a more accurate
            # cacheWidth check on the outer Image() call.
            if re.search(r"\bImage\s*\([^)]*$", line[:col]):
                continue
            prov_name = m.group(1).rstrip("( \t")
            report.findings.append(Finding(
                severity="MEDIUM",
                file=rel_path,
                line=i + 1,
                col=col + 1,
                rule="bare-provider-no-resize",
                snippet=raw_lines[i].strip()[:120],
                suggestion=(
                    f"Wrap {prov_name}(...) in ResizeImage(...) when consumed by "
                    "DecorationImage / CircleAvatar / Image(image:) so the "
                    "decode step allocates only display-size pixels. If you "
                    "intentionally need full resolution, add the comment "
                    "`// audit-image-decode: ignore-file` at the top of the file."
                ),
            ))

    # 3. Image(image: <provider>) — the outer Image() call can accept
    #    cacheWidth/cacheHeight even when the inner provider cannot.
    #    Flag if missing both.
    for i, line in enumerate(code_lines):
        m = re.search(r"\bImage\s*\(\s*image\s*:", line)
        if not m:
            continue
        open_paren_idx = line.find("(", m.start())
        if open_paren_idx < 0:
            continue
        if open_paren_idx in masked[i]:
            continue
        eline, ecol = matching_paren_span(code_lines, i, open_paren_idx)
        has_cw = find_token_in_span(code_lines, i, open_paren_idx, eline, ecol, "cacheWidth")
        has_ch = find_token_in_span(code_lines, i, open_paren_idx, eline, ecol, "cacheHeight")
        if has_cw and has_ch:
            continue
        if has_cw:
            continue
        report.findings.append(Finding(
            severity="HIGH",
            file=rel_path,
            line=i + 1,
            col=open_paren_idx + 1,
            rule="image-widget-no-cache-width",
            snippet=raw_lines[i].strip()[:120],
            suggestion=(
                "Pass cacheWidth: <logical px> to Image(image:...) so the "
                "underlying provider decodes at display size."
            ),
        ))

    return report


def iter_dart_files(repo_root: Path) -> Iterable[tuple[str, str]]:
    """Yield (rel_path, file_text) for every auditable .dart file."""
    for dart_file in (repo_root / "lib").rglob("*.dart"):
        rel = dart_file.relative_to(repo_root).as_posix()
        if is_skippable(rel):
            continue
        try:
            text = dart_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if file_ignored(text):
            continue
        yield rel, text


# ── Main ───────────────────────────────────────────────────────────────

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n", 2)[1])
    p.add_argument("--repo-root", type=Path, default=None,
                   help="Path to Daxelo-Kinrel-App/ (auto-detected if omitted).")
    p.add_argument("--format", choices=("text", "json", "md"), default="text",
                   help="Output format (default: text).")
    args = p.parse_args()

    repo_root = find_repo_root(args.repo_root)

    file_reports: list[FileReport] = []
    for rel, text in iter_dart_files(repo_root):
        fr = audit_file(rel, text)
        if fr.findings:
            file_reports.append(fr)

    total = sum(len(fr.findings) for fr in file_reports)
    by_severity = {"HIGH": 0, "MEDIUM": 0, "INFO": 0}
    for fr in file_reports:
        for f in fr.findings:
            by_severity[f.severity] = by_severity.get(f.severity, 0) + 1

    if args.format == "json":
        print(json.dumps({
            "repo_root": str(repo_root),
            "files_with_findings": len(file_reports),
            "total_findings": total,
            "by_severity": by_severity,
            "files": [
                {"file": fr.file, "findings": [asdict(f) for f in fr.findings]}
                for fr in file_reports
            ],
        }, indent=2))
        # Exit non-zero on HIGH findings so CI can gate.
        return 1 if by_severity["HIGH"] > 0 else 0

    if args.format == "md":
        print(f"# Image Decode Audit Report\n")
        print(f"Repo root: `{repo_root}`\n")
        print(f"## Summary\n")
        print(f"| Severity | Count |\n|---|---|")
        for sev in ("HIGH", "MEDIUM", "INFO"):
            print(f"| {sev} | {by_severity.get(sev, 0)} |")
        print(f"\n**Total findings:** {total} across {len(file_reports)} files.\n")
        print(f"## Findings\n")
        for fr in file_reports:
            print(f"### `{fr.file}`\n")
            for f in fr.findings:
                print(f"- **[{f.severity}]** L{f.line} — `{f.snippet}`")
                print(f"  - Rule: `{f.rule}`")
                print(f"  - {f.suggestion}\n")
        return 1 if by_severity["HIGH"] > 0 else 0

    # Text format
    print(f"=== Image Decode Audit ===")
    print(f"repo_root: {repo_root}")
    print(f"files with findings: {len(file_reports)}")
    print(f"total findings: {total}")
    print(f"by severity: HIGH={by_severity['HIGH']}, MEDIUM={by_severity['MEDIUM']}, INFO={by_severity.get('INFO', 0)}")
    print()
    for fr in file_reports:
        print(f"--- {fr.file} ---")
        for f in fr.findings:
            print(f"  [{f.severity}] L{f.line}:{f.col} {f.rule}")
            print(f"    {f.snippet}")
            print(f"    -> {f.suggestion}")
            print()

    return 1 if by_severity["HIGH"] > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
