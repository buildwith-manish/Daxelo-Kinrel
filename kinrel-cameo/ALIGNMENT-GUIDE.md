# Kinrel Cameo v2 — Manual Alignment Guide (Step 6)

> AI generation does **not** produce pixel-perfect matching edges between
> separately-generated parts. This guide walks through the manual alignment
> pass that turns "AI-generated pieces" into a working modular avatar system.
>
> **This step is not optional.** No current AI tool holds pixel-perfect part
> alignment across separate generations.

---

## Tools you can use

| Tool | Cost | Best for |
|------|------|----------|
| **Figma** | Free tier OK | Teams, versioned layers, plugins |
| **Photopea** | Free, browser-based | Solo work, Photoshop-like workflow |
| **Adobe Photoshop** | Paid | Production-grade batch processing |
| **Affinity Photo** | One-time | Production-grade, no subscription |

---

## The Shared Anchor Grid (v2 — expanded)

Every part must be aligned to this grid before export. The grid assumes a
**1024×1024 canvas** for all head-and-shoulders parts.

| Landmark | X | Y | Notes |
|----------|---|---|-------|
| Canvas top-left | 0 | 0 | — |
| Canvas center | 512 | 512 | — |
| Hair top | **512** | **200** | Top of skull (hair-front layer) |
| Eyebrows | — | **360** | Both eyebrows sit at this Y |
| Eyes (both irises) | — | **400** | Eyes always sit at Y=400 |
| Left iris center | **400** | 400 | 112px left of canvas center |
| Right iris center | **624** | 400 | 112px right of canvas center |
| Cheeks (both) | — | **550** | Blush overlay sits here |
| Nose tip | **512** | **520** | Vertically centered |
| Mouth center | **512** | **620** | Vertically centered |
| Jaw bottom | **512** | **720** | Bottom of chin |
| Bindi (if worn) | **512** | **320** | Center of forehead |
| Nose ring (if worn) | **460** | **510** | Left nostril |
| Mangalsutra (if worn) | **512** | **750** | At the neck |

For **full-body clothing** on a 768×1344 canvas:

| Landmark | X | Y |
|----------|---|---|
| Canvas center | 384 | 672 |
| Top of head | 384 | 100 |
| Neck | 384 | 280 |
| Waist | 384 | 680 |
| Feet bottom | 384 | 1280 |

---

## Step-by-Step Alignment Workflow

### 1. Import all pieces

Create a new Figma file (or Photopea canvas). For each generated part:

1. Drag the PNG into the canvas
2. Rename the layer to match the filename (e.g. `face_adult_male_A`)
3. Place all parts in a single frame called `Kinrel Cameo Master v2`

### 2. Set up the anchor grid

1. Create a **guide frame** at exactly 1024×1024
2. Add horizontal guides at Y = 200, 320, 360, 400, 510, 520, 550, 620, 720, 750
3. Add vertical guides at X = 400, 460, 512, 624
4. Lock the guide frame so it doesn't move

### 3. Lay down the skin-tone layer (v2 — NEW)

1. Drop `skin-tones/skin_04.png` (or whichever tone) as the bottom layer
2. Set its blend mode to **Multiply** — it will tint everything above it
3. This is layer 0 of the stack

### 4. Add the face-shape layer (v2 — NEW)

1. Drop `face-shapes/shape_oval.png` (or whichever shape) above the skin tone
2. Scale uniformly until it fills the face area
3. This is the base geometry — everything else aligns to it

### 5. Align the base face

1. Drop `base-faces/male/face_adult_male_A.png` above the face-shape layer
2. Scale (uniformly) until the eyes sit exactly on Y=400
3. Move horizontally until the nose tip sits on X=512
4. The face is now your **anchor reference** — every other part aligns to it

### 6. Align each part to the same grid

For each part (eyebrows, eyes, nose, mouth, hair, accessories):

1. Drop the part PNG into the guide frame **above** the base face layer
2. Set the part layer's blend mode to **Multiply** (temporarily) so you can see through it
3. Scale (uniformly) until the part's natural landmark matches the grid:
   - **Eyebrows** → sit at Y=360
   - **Eyes** → iris centers at (400, 400) and (624, 400)
   - **Eyelids** → cover the eyes at Y=400
   - **Pupils** → centered in irises at Y=400
   - **Nose** → tip at (512, 520)
   - **Mouth** → center at (512, 620)
   - **Cheeks** → at Y=550, X=400 and X=624
   - **Hair-front** → top of skull at (512, 200)
   - **Hair-middle** → volume behind hair-front
   - **Hair-back** → length falling behind head
   - **Facial hair** → jaw/chin area Y=620–720
   - **Glasses** → eyes at Y=400
   - **Bindi** → forehead at (512, 320)
   - **Nose ring** → left nostril at (460, 510)
   - **Mangalsutra** → neck at (512, 750)
   - **Earrings** → earlobes (around X=380 and X=644, Y=520)
   - **Turban / Hijab / Cap / Hat** → top of head at (512, 200)
4. Set the blend mode back to **Normal**
5. Hide the base face layer below to verify the part sits cleanly

### 7. Add the hair in 3 layers (v2 — NEW)

For hairstyles with length or volume (buns, braids, ponytails, long hair):

1. **Hair-back** (bottom of the 3 hair layers) — the length falling behind the head
2. **Hair-middle** (middle of the 3 hair layers) — the bun/braid/ponytail body
3. **Hair-front** (top of the 3 hair layers) — the bangs/fringe

The 3-layer system is what gives long hairstyles proper volume.

### 8. Add accessories last

Accessories (glasses, earrings, bindi, etc.) sit **above** the hair layers,
because some accessories (like earrings) need to be visible over the hair.

### 9. Touch up edges

AI generation will leave:

- Soft halo around the part edge (background beige bleeding into the part)
- Slight color mismatches between separately-generated pieces
- Lighting direction inconsistencies

Fix these with:

1. **Background removal** — use Figma's "Remove Background" or Photopea's magic wand
2. **Defringe** — Select → Modify → Contract by 1px to remove halo
3. **Color match** — use a Hue/Saturation adjustment layer pegged to the Kinrel palette
4. **Lighting match** — add a soft frontal dodge (5% opacity) to brighten any shadows

### 10. Export each part as a clean PNG

For each aligned part:

1. Hide all other layers
2. Right-click the part layer → Export → PNG
3. Set export size to 1024×1024 (or 768×1344 for full-body)
4. Enable transparency (alpha channel)
5. Save with a clear filename following the [naming convention](./ASSET-CATALOG.md)

---

## Quality Checklist

Before marking any part as "done", verify:

- [ ] Eyes sit exactly on Y=400 (within ±2px tolerance)
- [ ] Nose tip sits on X=512
- [ ] Mouth center at (512, 620)
- [ ] Hair-top at (512, 200)
- [ ] No background beige bleeding into the part edge
- [ ] Color palette matches Kinrel brand (F7EFE4 / C9B79E / 2A2A2A)
- [ ] No hard outlines or cel shading introduced during touch-up
- [ ] No anime / Bitmoji / Pixar resemblance
- [ ] Lighting is soft frontal key (no dramatic shadows)
- [ ] Filename matches the naming convention in ASSET-CATALOG.md
- [ ] Exported at exactly 1024×1024 (or 768×1344 for full-body)
- [ ] Skin tone layer is separate (not baked in) — v2
- [ ] Face shape layer is separate (not baked in) — v2
- [ ] Hair is in 3 layers (front/middle/back) for any style with length or volume — v2
- [ ] Accessories are isolated (not merged into hair) — v2

---

## Stacking Order (bottom to top — v2)

When composing a final character, stack layers in this order:

```
 0. skin-tone          (multiply blend)
 1. face-shape         (silhouette)
 2. base-face          (variant A/B/C/D)
 3. eyebrows
 4. eyes
 5. eyelids            (for expressions)
 6. pupils             (gaze direction)
 7. nose
 8. mouth
 9. cheeks             (blush overlay)
10. facial-hair        (adult male only)
11. accessories        (glasses, earrings, bindi, turban, hijab, etc.)
12. hair-front         (bangs/fringe)
13. hair-middle        (volume for buns/braids/ponytails)
14. hair-back          (length falling behind head)
```

For full-body compositions:

```
1. composed head (from above stack)
2. clothing (full-body, category-based — resized to age proportions)
3. accessories-below-neck (mangalsutra, etc.)
```

---

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| Eyes don't line up between faces | Different generation batches used different head sizes | Scale face uniformly until eyes hit Y=400 |
| Hair floats above head | Hair canvas was generated at different scale | Scale hair until top of skull hits Y=200 |
| Skin tone mismatch between face and hands | Outfit was generated with its own skin tone | Use the skin-tone layer as a multiply blend over the whole body |
| Mouth doesn't sit on face | Mouth was generated for a different face size | Scale mouth until center hits (512, 620) |
| Outfit doesn't match head scale | Outfit canvas is 768×1344, head is 1024×1024 | Scale head down to ~25% of outfit canvas height |
| Bun looks flat and lifeless | Only front and back hair layers used, missing middle | Add the `hair-middle_bun` layer between front and back |
| Glasses disappear under hair | Glasses placed below hair layers in stack | Move glasses layer ABOVE all hair layers |
| Bindi covers eyes | Bindi placed at wrong Y | Bindi goes at (512, 320) — between eyebrows and hairline |
| Expression breaks face identity | Whole new face generated for each expression | Use additive overlays — only swap eyebrows/eyelids/pupils/mouth/cheeks |
