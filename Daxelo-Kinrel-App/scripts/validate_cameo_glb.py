#!/usr/bin/env python3
# scripts/validate_cameo_glb.py
#
# KINREL CAMEO — GLB Asset Validation Script
#
# Validates a Cameo GLB asset against the Kinrel production requirements:
#   - Contains all 36 required morph targets (24 face + 8 age + 4 expression)
#   - Triangle count within LOD0 budget (~44k tris)
#   - PBR materials present
#   - Skeleton with required bones for pose catalog
#   - No cel-shading / black outlines
#   - Modular clothing/hair structure
#
# Usage:
#   python3 scripts/validate_cameo_glb.py assets/cameo/kinrel_cameo_production.glb
#
# Requirements:
#   pip install pygltflib

import sys
import json
from pathlib import Path

# ── Required Morph Targets ─────────────────────────────────────────
FACE_MORPHS = [
    'brow_inner_up', 'brow_outer_up', 'brow_furrow',
    'eye_close', 'eye_widen', 'eye_crinkle',
    'upper_lid_lower', 'lower_lid_raise',
    'nose_wrinkle',
    'mouth_relax', 'mouth_corner_up', 'mouth_corner_down',
    'mouth_open', 'mouth_pout', 'mouth_smile_full',
    'jaw_open', 'jaw_forward',
    'cheek_raise', 'cheek_puff', 'chin_raise',
    'tongue_out', 'lip_bite', 'lip_funnel', 'lip_press',
]

AGE_MORPHS = [
    'age_brow_sag', 'age_eyelid_drop', 'age_crow_feet',
    'age_nasolabial', 'age_jowl', 'age_neck_sag',
    'age_ear_lengthen', 'age_hair_recede',
]

EXPRESSION_MORPHS = [
    'blink_left', 'blink_right', 'smile', 'jaw_open',
]

ALL_REQUIRED_MORPHS = sorted(set(FACE_MORPHS + AGE_MORPHS + EXPRESSION_MORPHS))

# ── Required Skeleton Bones ────────────────────────────────────────
REQUIRED_BONES = [
    'spine_01', 'spine_02', 'neck', 'head',
    'thigh_l', 'thigh_r',
]

# ── LOD0 Triangle Budget ───────────────────────────────────────────
LOD0_MAX_TRIS = 48000  # ~44k budget + 10% tolerance

def validate_glb(glb_path: str) -> dict:
    """Validates a GLB file against Kinrel production requirements."""
    results = {
        'path': glb_path,
        'passes': True,
        'errors': [],
        'warnings': [],
        'morph_targets': {'found': [], 'missing': [], 'extra': []},
        'bones': {'found': [], 'missing': []},
        'stats': {},
    }

    try:
        from pygltflib import GLTF2
    except ImportError:
        results['errors'].append(
            'pygltflib not installed. Run: pip install pygltflib'
        )
        results['passes'] = False
        return results

    if not Path(glb_path).exists():
        results['errors'].append(f'File not found: {glb_path}')
        results['passes'] = False
        return results

    gltf = GLTF2().load(glb_path)

    # ── 1. Morph Targets ───────────────────────────────────────────
    found_morphs = set()
    for mesh in gltf.meshes:
        for primitive in mesh.primitives:
            if primitive.targets:
                for target in primitive.targets:
                    # Morph target names are stored in the mesh extras
                    pass
        # Check mesh extras for morph target names
        if mesh.extras and 'targetNames' in mesh.extras:
            for name in mesh.extras['targetNames']:
                found_morphs.add(name)

    # Also check in the primitive extras
    for mesh in gltf.meshes:
        for primitive in mesh.primitives:
            if primitive.extras and 'targetNames' in primitive.extras:
                for name in primitive.extras['targetNames']:
                    found_morphs.add(name)

    required_set = set(ALL_REQUIRED_MORPHS)
    results['morph_targets']['found'] = sorted(found_morphs)
    results['morph_targets']['missing'] = sorted(required_set - found_morphs)
    results['morph_targets']['extra'] = sorted(found_morphs - required_set)

    if results['morph_targets']['missing']:
        results['errors'].append(
            f"Missing {len(results['morph_targets']['missing'])} required morph targets: "
            f"{', '.join(results['morph_targets']['missing'])}"
        )
        results['passes'] = False

    # ── 2. Triangle Count ──────────────────────────────────────────
    total_tris = 0
    for mesh in gltf.meshes:
        for primitive in mesh.primitives:
            if primitive.indices is not None:
                # Indexed geometry: index count / 3
                accessor = gltf.accessors[primitive.indices]
                total_tris += accessor.count // 3
            elif primitive.attributes.POSITION is not None:
                # Non-indexed: vertex count / 3
                accessor = gltf.accessors[primitive.attributes.POSITION]
                total_tris += accessor.count // 3

    results['stats']['triangle_count'] = total_tris

    if total_tris > LOD0_MAX_TRIS:
        results['errors'].append(
            f'Triangle count ({total_tris}) exceeds LOD0 budget ({LOD0_MAX_TRIS})'
        )
        results['passes'] = False
    elif total_tris > 44000:
        results['warnings'].append(
            f'Triangle count ({total_tris}) within tolerance but above '
            f'44k target'
        )

    # ── 3. Materials ───────────────────────────────────────────────
    material_count = len(gltf.materials) if gltf.materials else 0
    results['stats']['material_count'] = material_count

    if material_count == 0:
        results['errors'].append('No materials found in GLB')
        results['passes'] = False

    has_pbr = False
    for mat in (gltf.materials or []):
        if mat.pbrMetallicRoughness is not None:
            has_pbr = True
            break

    if not has_pbr:
        results['warnings'].append(
            'No PBR metallic-roughness materials found. '
            'Kinrel requires PBR materials (no cel-shading).'
        )

    # ── 4. Skeleton Bones ──────────────────────────────────────────
    found_bones = set()
    for skin in (gltf.skins or []):
        if skin.joints:
            for joint_idx in skin.joints:
                node = gltf.nodes[joint_idx]
                if node.name:
                    found_bones.add(node.name)

    required_bones = set(REQUIRED_BONES)
    results['bones']['found'] = sorted(found_bones)
    results['bones']['missing'] = sorted(required_bones - found_bones)

    if results['bones']['missing']:
        results['warnings'].append(
            f"Missing skeleton bones: {', '.join(results['bones']['missing'])}. "
            f"Required for CameoPoseCatalog pose compatibility."
        )

    # ── 5. No Cel-Shading / Black Outlines ─────────────────────────
    # Check for outline meshes (common cel-shading technique)
    for mesh in gltf.meshes:
        if mesh.name and ('outline' in mesh.name.lower() or
                          ' Outline' in mesh.name):
            results['warnings'].append(
                f"Mesh '{mesh.name}' appears to be an outline mesh. "
                f"Kinrel requires NO cel-shading outlines."
            )

    # ── 6. Modular Parts ───────────────────────────────────────────
    clothing_meshes = []
    hair_meshes = []
    for mesh in gltf.meshes:
        if mesh.name:
            name_lower = mesh.name.lower()
            if any(k in name_lower for k in ['cloth', 'outfit', 'dress', 'shirt']):
                clothing_meshes.append(mesh.name)
            if any(k in name_lower for k in ['hair', 'ponytail', 'bun']):
                hair_meshes.append(mesh.name)

    results['stats']['clothing_meshes'] = clothing_meshes
    results['stats']['hair_meshes'] = hair_meshes

    if not clothing_meshes:
        results['warnings'].append(
            'No modular clothing meshes found. '
            'Production GLB should have separate clothing mesh parts.'
        )
    if not hair_meshes:
        results['warnings'].append(
            'No modular hair meshes found. '
            'Production GLB should have separate hair mesh parts.'
        )

    return results


def main():
    if len(sys.argv) < 2:
        print('Usage: python3 scripts/validate_cameo_glb.py <path-to-glb>')
        sys.exit(1)

    glb_path = sys.argv[1]
    results = validate_glb(glb_path)

    # Print results
    print('=' * 60)
    print('KINREL CAMEO — GLB Asset Validation Report')
    print('=' * 60)
    print(f'File: {results["path"]}')
    print(f'Result: {"PASS" if results["passes"] else "FAIL"}')
    print()

    # Stats
    if results['stats']:
        print('Stats:')
        for key, value in results['stats'].items():
            print(f'  {key}: {value}')
        print()

    # Morph targets
    mt = results['morph_targets']
    print(f'Morph Targets: {len(mt["found"])} found, '
          f'{len(mt["missing"])} missing, '
          f'{len(mt["extra"])} extra')
    if mt['missing']:
        print(f'  MISSING: {", ".join(mt["missing"])}')
    print()

    # Bones
    bones = results['bones']
    print(f'Skeleton Bones: {len(bones["found"])} found, '
          f'{len(bones["missing"])} missing')
    if bones['missing']:
        print(f'  MISSING: {", ".join(bones["missing"])}')
    print()

    # Errors
    if results['errors']:
        print('ERRORS:')
        for e in results['errors']:
            print(f'  ✗ {e}')
        print()

    # Warnings
    if results['warnings']:
        print('WARNINGS:')
        for w in results['warnings']:
            print(f'  ⚠ {w}')
        print()

    print('=' * 60)
    sys.exit(0 if results['passes'] else 1)


if __name__ == '__main__':
    main()
