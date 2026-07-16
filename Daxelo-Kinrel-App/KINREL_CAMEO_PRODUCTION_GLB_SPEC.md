# KINREL CAMEO — Production Character GLB Specification

## Overview
This document specifies the production-ready 3D character asset that replaces
the synthetic `kinrel_cameo_b1_test.glb` (706 vertices, 4 placeholder morph targets).

## File: `assets/cameo/kinrel_cameo_production.glb`

### Triangle Budget
| LOD | Triangle Budget | Use Case |
|-----|----------------|----------|
| LOD0 | ~44,000 tris | Studio, Profile hero, Journey |
| LOD1 | ~26,500 tris | Low-tier devices |
| LOD2 | ~16,500 tris | Derived PNG source (Map/Graph/Chat) |
| LOD3 | ~9,500 tris | Thumbnails (notifications/search) |

The production GLB should be at LOD0 quality. Lower LODs are generated
automatically via mesh decimation during the build process.

### Morph Targets (36 total, REQUIRED)

#### Face Morphs (24)
| # | Name | Description | Weight Range |
|---|------|-------------|--------------|
| 1 | brow_inner_up | Inner brow raise (concern, surprise) | 0–1 |
| 2 | brow_outer_up | Outer brow raise (surprise, query) | 0–1 |
| 3 | brow_furrow | Brow pinch (concentration, worry) | 0–1 |
| 4 | eye_close | Full eye close (blink) | 0–1 |
| 5 | eye_widen | Eye widening (surprise) | 0–1 |
| 6 | eye_crinkle | Periocular crinkle (Duchenne smile) | 0–1 |
| 7 | upper_lid_lower | Upper eyelid droop (reverent, tired) | 0–1 |
| 8 | lower_lid_raise | Lower lid raise (squint, warmth) | 0–1 |
| 9 | nose_wrinkle | Nose wrinkle (disgust, playfulness) | 0–1 |
| 10 | mouth_relax | Neutral mouth posture | 0–1 |
| 11 | mouth_corner_up | Lip corner lift (smile base) | 0–1 |
| 12 | mouth_corner_down | Lip corner depression (sadness) | 0–1 |
| 13 | mouth_open | Jaw drop + lip part (speech, surprise) | 0–1 |
| 14 | mouth_pout | Lip protrusion (kiss, thought) | 0–1 |
| 15 | mouth_smile_full | Full smile (cheek + lip corner) | 0–1 |
| 16 | jaw_open | Jaw rotation open (speech, expression) | 0–1 |
| 17 | jaw_forward | Jaw thrust (determination) | 0–1 |
| 18 | cheek_raise | Cheek raise (smile, laugh) | 0–1 |
| 19 | cheek_puff | Cheek inflation (playful) | 0–1 |
| 20 | chin_raise | Chin raise (pride, defiance) | 0–1 |
| 21 | tongue_out | Tongue protrusion (playful) | 0–1 |
| 22 | lip_bite | Lip bite (concentration, nervous) | 0–1 |
| 23 | lip_funnel | Lip funnel (whistle, surprise) | 0–1 |
| 24 | lip_press | Lip compression (determination, disapproval) | 0–1 |

#### Age Morphs (8)
| # | Name | Description | Weight Range |
|---|------|-------------|--------------|
| 25 | age_brow_sag | Brow sag with age | 0–1 (0=young, 1=elder) |
| 26 | age_eyelid_drop | Eyelid droop with age | 0–1 |
| 27 | age_crow_feet | Crow's feet wrinkles | 0–1 |
| 28 | age_nasolabial | Nasolabial fold deepening | 0–1 |
| 29 | age_jowl | Jowl formation | 0–1 |
| 30 | age_neck_sag | Neck skin sagging | 0–1 |
| 31 | age_ear_lengthen | Ear lengthening with age | 0–1 |
| 32 | age_hair_recede | Hairline recession | 0–1 |

#### Expression Morphs (4, B1 test compatibility)
| # | Name | Description | Weight Range |
|---|------|-------------|--------------|
| 33 | blink_left | Left eye blink | 0–1 |
| 34 | blink_right | Right eye blink | 0–1 |
| 35 | smile | Composite smile | 0–1 |
| 36 | jaw_open | Jaw open (duplicate for B1 compat) | 0–1 |

**Note**: Morph target names MUST exactly match `cameo_expression_catalog.dart`
naming. The `_collectMorphTargetNames()` method in `cameo_runtime_scene.dart`
collects all these names and passes them to the renderer.

### Skeleton
The skeleton MUST support all poses in `cameo_pose_catalog.dart`:

**Required Bones:**
- `spine_01`, `spine_02` — Torso rotation
- `neck` — Head turn/tilt
- `head` — Head nod/shake
- `thigh_l`, `thigh_r` — Leg rotation (Journey walk pose)
- `upper_arm_l`, `upper_arm_r` — Arm positioning (optional for bust framing)
- `shoulder_l`, `shoulder_r` — Shoulder positioning

**Pose Catalog Mapping:**
| Pose | Required Bones |
|------|---------------|
| centered | spine_01, neck, head |
| three_quarter | spine_01 (y=-8°), neck (y=4°), head (z=1°) |
| dignified | spine_01 (y=-6°), neck (-2,2,0), head (-1,0,0) |
| dignified_stooped | spine_01 (6,-6,0), spine_02 (4,0,0), neck (-3,2,0), head (-2,0,0) |
| journey_walk | spine_01 (0,-4,0), neck (0,2,0), thigh_l (-12,0,0), thigh_r (12,0,0) |

### Art Direction (per KINREL_CAMEO_STYLE_SYSTEM.md)
- **Proportions**: 7.5–8 head proportions (not chibi/SD)
- **Style**: Clean, warm, non-photorealistic but not cartoon-cel
- **NO black outlines** — no cel-shading outline meshes
- **NO toon shaders** — use PBR metallic-roughness workflow
- **Materials**: Skin, hair, eyes, clothing as separate PBR materials
- **Skin**: Warm ivory base (#F5E6D3) with ember rim accent
- **Hair**: Modular — separate mesh for each hairstyle
- **Clothing**: Modular — separate mesh for each outfit

### Modular Parts Structure
The GLB MUST use separate meshes for modularity:

```
Root
├── Body_Base          (base body mesh with skin material)
├── Head_Base          (head mesh with face morph targets)
├── Hair_Default       (default hairstyle — separate mesh)
├── Hair_Short         (alternate hairstyle — separate mesh)
├── Hair_Long          (alternate hairstyle — separate mesh)
├── Clothing_Default   (default outfit — separate mesh)
├── Clothing_Formal    (formal outfit — separate mesh)
├── Clothing_Casual    (casual outfit — separate mesh)
├── Glasses_None       (invisible/empty mesh when no glasses)
├── Headwear_None      (invisible/empty mesh when no headwear)
└── Skeleton           (shared armature for all meshes)
```

Each clothing/hair/accessory part is a separate mesh skinned to the
shared skeleton. `CameoDefinition.clothingId`, `hairStyleId`, etc.
map to these mesh names. The renderer shows/hides meshes based on
the definition.

### Validation
Run `python3 scripts/validate_cameo_glb.py assets/cameo/kinrel_cameo_production.glb`
to validate the asset. Zero errors required before integration.

Also validate with Khronos gltf-validator:
```
gltf_validator assets/cameo/kinrel_cameo_production.glb
```
Must produce 0 errors, 0 warnings. Non-negotiable.

### File Size Budget
| Asset | Max Size |
|-------|----------|
| Base GLB (body + head + skeleton) | 8 MB |
| Per hairstyle mesh | 500 KB |
| Per clothing item | 800 KB |
| Per accessory | 200 KB |
| Total (with all modular parts) | 25 MB |
