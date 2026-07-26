#!/usr/bin/env python3
"""
v5.0 Part 1 — Step 2 Immediate Mitigation

Reverts the bundled Kinrel dark style JSON's `openmaptiles` source from
`pmtiles://{{PMTILES_URL}}` (which breaks production on web because the
placeholder is never substituted, and on native because the build-time
default is `http://localhost:8080/mumbai.pmtiles`) to a plain OpenFreeMap
ZYX tile URL that works on ALL platforms with zero custom protocol code.

This is the minimum change required to unbreak production. PMTiles can be
re-enabled later via `--dart-define=PMTILES_URL=https://.../archive.pmtiles`
once a real archive is uploaded and verified — the runtime patch logic in
family_map_screen.dart now handles that opt-in path correctly.

Idempotent: re-running on an already-patched file is a no-op.
"""
import json
import os
import shutil
import sys
from datetime import datetime

STYLE_PATH = "/home/z/my-project/Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json"
BACKUP_PATH = f"/tmp/kinrel_dark_style.json.before-v5.0-part1-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

OPENFREEMAP_SOURCE = {
    "type": "vector",
    "tiles": ["https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf"],
    "maxzoom": 14,
    "minzoom": 0,
    "attribution": "© OpenStreetMap contributors, © OpenMapTiles, © Planetiler, © OpenFreeMap",
}

# Marker comment so future grep can find why this was changed
MARKER_COMMENT = (
    "// v5.0 Part 1 mitigation: was `pmtiles://{{PMTILES_URL}}` — broke "
    "production (placeholder never substituted on web; localhost default on "
    "native). Switched to OpenFreeMap ZYX tiles. PMTiles can be re-enabled "
    "via --dart-define=PMTILES_URL=https://.../archive.pmtiles — see "
    "family_map_screen.dart _applyPmtilesSource (opt-in patching)."
)


def main() -> int:
    if not os.path.exists(STYLE_PATH):
        print(f"ERROR: style file not found at {STYLE_PATH}", file=sys.stderr)
        return 1

    # Backup once
    if not os.path.exists(BACKUP_PATH):
        shutil.copy2(STYLE_PATH, BACKUP_PATH)
        print(f"Backup: {BACKUP_PATH}")

    with open(STYLE_PATH, "r", encoding="utf-8") as f:
        style = json.load(f)

    sources = style.get("sources", {})
    openmaptiles = sources.get("openmaptiles", {})

    # Idempotency check — if already OpenFreeMap ZYX, no-op
    current_url = openmaptiles.get("url") or ""
    current_tiles = openmaptiles.get("tiles") or []
    if "openfreemap.org" in current_url or (
        current_tiles and "openfreemap.org" in str(current_tiles[0])
    ):
        print("Already patched (OpenFreeMap source). No-op.")
        return 0

    print(f"Current openmaptiles source: {json.dumps(openmaptiles, indent=2)}")

    # Apply the fix: drop `url`, set `tiles` to OpenFreeMap ZYX template
    # (keep maxzoom/minzoom/attribution from the source dict, just override)
    new_source = dict(OPENFREEMAP_SOURCE)
    # Preserve any non-URL fields from original (none critical, but defensive)
    for k in ("maxzoom", "minzoom", "attribution"):
        if k in openmaptiles and k not in new_source:
            new_source[k] = openmaptiles[k]
    sources["openmaptiles"] = new_source
    style["sources"] = sources

    # Also inject a top-level _comment so future maintainers see why
    # (MapLibre ignores unknown top-level keys per the style spec)
    style["_v5_part1_mitigation"] = MARKER_COMMENT

    # Validate: ensure all source URLs in the file are HTTPS (no http://, no
    # pmtiles://{{...}} placeholders, no localhost)
    issues = []
    for name, src in style.get("sources", {}).items():
        for url_field in ("url", "tiles"):
            v = src.get(url_field)
            if v is None:
                continue
            urls = v if isinstance(v, list) else [v]
            for u in urls:
                if not isinstance(u, str):
                    continue
                if u.startswith("http://") and "localhost" not in u:
                    # Allow HTTP for now if explicitly non-localhost (rare);
                    # but warn
                    issues.append(f"  WARN: {name}.{url_field}={u} is HTTP")
                if "localhost" in u or "127.0.0.1" in u:
                    issues.append(f"  ERROR: {name}.{url_field}={u} points to localhost")
                if "{{" in u and "}}" in u:
                    issues.append(f"  ERROR: {name}.{url_field}={u} has unsubstituted placeholder")
                if u.startswith("pmtiles://"):
                    issues.append(f"  ERROR: {name}.{url_field}={u} still uses pmtiles:// protocol")

    if issues:
        print("Source URL validation found issues:")
        for i in issues:
            print(i)
        # Only fail on ERRORs, not WARNs
        if any("ERROR" in i for i in issues):
            print("Refusing to write file with ERROR issues.", file=sys.stderr)
            return 2

    with open(STYLE_PATH, "w", encoding="utf-8") as f:
        json.dump(style, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"\nPatched: {STYLE_PATH}")
    print(f"New openmaptiles source: {json.dumps(new_source, indent=2)}")
    print(f"\nFile size: {os.path.getsize(STYLE_PATH)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
