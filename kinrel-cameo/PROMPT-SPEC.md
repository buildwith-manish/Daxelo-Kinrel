# Kinrel Cameo v2 — Full 6-Step Generation Specification

This document is the canonical spec for generating modular Kinrel Cameo v2 assets.
Every asset in this repository was produced by following this 6-step process,
upgraded to incorporate all 13 user-requested improvements.

---

## Master Style Lock (use in every generation, unchanged)

```
Kinrel Cameo character style: soft rounded 3D-illustrated look, warm semi-
realistic proportions (7.5-8 heads tall for adults), large expressive eyes 
with a small sharp catchlight, soft matte skin shading with gentle subsurface 
warmth, rounded jaw, natural lips, no black outlines, no cel shading, no hard 
edges, no anime style, no Bitmoji/Memoji/Pixar/Disney resemblance. Lighting: 
soft frontal key light, warm neutral beige background, no cast shadows on 
background. Color palette: warm skin tones, cream/tan/rust clothing tones 
matching the Kinrel brand (F7EFE4, C9B79E, 2A2A2A accents).
```

Paste this block into every single prompt below, unchanged.

---

## Step 1 — Lock the canvas rules (do this once, before generating any parts)

Fixed for every asset:

- **Canvas:** 1024×1024 for all head/parts/accessories, 768×1344 for full-body clothing/age-stages, 1344×768 for master sheets
- **Character centered:** same head position and scale every time
- **Front-facing head-and-shoulders crop** for parts; full-body standing neutral for outfits
- **Anchor grid:** eyes at Y=400px, nose center at X=512px, mouth center at Y=620px, hair top at Y=200px
- **Plain warm beige background** (`#F7EFE4`)

---

## Step 2 — Generate SKIN TONES + FACE SHAPES + BASE FACES (v2 upgrade)

### 2a. Skin tones (8 — Indian spectrum)

```
[MASTER STYLE LOCK]
Generate: a flat skin tone swatch filling the entire 1024x1024 canvas, 
[TONE DESCRIPTION], smooth matte finish, no facial features, no eyes, 
no nose, no mouth, no hair. This is a skin tone layer for a modular 
avatar system — used as a multiply-blend layer under the face.
Tone: [skin_01 very fair porcelain / skin_02 fair warm wheat / 
skin_03 light tan / skin_04 medium wheat / skin_05 medium olive / 
skin_06 tan brown / skin_07 deep brown / skin_08 very deep dark brown]
```

**Why separate**: Critical for an Indian family app — skin tones span the full
spectrum, and the genetics system blends them between parents.

### 2b. Face shapes (6)

```
[MASTER STYLE LOCK]
Generate: [SHAPE] face shape outline, front view, no facial features, 
just the face silhouette as a soft matte cream/tan shape on warm beige 
background, 1024x1024 canvas. This is the face shape layer for a modular 
avatar system — silhouette only. Used as the base geometry layer.
Shape: [oval / round / square / heart / diamond / long]
```

**Why separate**: Face shape was previously baked into the face. Separating it
lets users mix face shapes with any features.

### 2c. Base faces (multiple variants per age)

```
[MASTER STYLE LOCK]
Generate: front-facing head-and-shoulders portrait, [AGE STAGE] [GENDER], 
variant [VARIANT], [DISTINGUISHING FEATURES], no hair rendered yet 
(bald cap / hair masked out, smooth scalp), [CANVAS RULES]. 
Skin tone should be NEUTRAL MEDIUM — the actual skin tone is added 
as a separate layer later. No accessories, no clothing above shoulders.
Age stage: [Baby / Toddler / Child / Preteen / Teen / Young Adult / 
Adult / Middle Age / Senior]
Variant: [A / B / C / D] with different jaw, eye spacing, nose, lips, ears
```

**Why multiple variants**: Without variants, every adult of the same age looks
like a sibling. Variants A/B/C/D give 4+ visually distinct faces per age.

---

## Step 3 — Generate SWAPPABLE PARTS (each isolated, transparent)

### 3a. Eyebrows (8 variants)

```
[MASTER STYLE LOCK]
Generate ONLY the eyebrows, isolated on plain warm beige background, 
positioned exactly as they sit on the base face canvas (1024x1024, 
eyebrows around Y=360px), no face, eyes, nose, mouth, or hair included.
Variant: [thin / medium / thick / straight / curved / bushy / soft / high_arch]
```

### 3b. Eyes (8 variants)

```
[MASTER STYLE LOCK]
Generate ONLY the eyes (both left and right), isolated on plain warm 
beige background, positioned exactly as they sit on the base face canvas 
(1024x1024, eyes at Y=400px, iris centers at X=400 and X=624), no 
eyebrows, nose, mouth, face, or hair included.
Variant: [round / almond / large / small / droopy / deep_set / monolid / wide]
```

### 3c. Eyelids (4 variants — for additive expressions)

```
[MASTER STYLE LOCK]
Generate ONLY the eyelids (skin tone neutral medium), isolated on plain 
warm beige background, positioned exactly over the eyes on the base face 
canvas (1024x1024, eyes at Y=400px), no eyes, eyebrows, nose, mouth, 
face, or hair included.
Variant: [open / half / quarter / squint]
```

### 3d. Pupils (4 variants — gaze directions)

```
[MASTER STYLE LOCK]
Generate ONLY the pupils (both left and right), isolated on plain warm 
beige background, positioned exactly over the eyes on the base face 
canvas (1024x1024, at Y=400px, X=400 and X=624), no eyes, eyelids, 
eyebrows, nose, mouth, face, or hair included.
Variant: [forward / up / side / down]
```

### 3e. Nose (7 variants)

```
[MASTER STYLE LOCK]
Generate ONLY the nose, isolated on plain warm beige background, 
positioned exactly as it sits on the base face canvas (1024x1024, 
nose tip at Y=520px, nose center at X=512px), no eyes, eyebrows, 
mouth, face, or hair included.
Variant: [small / medium / broad / roman / button / round / sharp]
```

### 3f. Mouth (11 variants — including emotions)

```
[MASTER STYLE LOCK]
Generate ONLY the mouth, isolated on plain warm beige background, 
positioned exactly as it sits on the base face canvas (1024x1024, 
mouth center at Y=620px, X=512px), no eyes, eyebrows, nose, face, 
or hair included.
Variant: [neutral / soft_smile / big_smile / open_smile / laugh / 
sad / thinking / surprised / concerned / angry / sleepy]
```

### 3g. Cheeks (3 variants — for blush/flush expressions)

```
[MASTER STYLE LOCK]
Generate ONLY the cheek color overlay, isolated on plain warm beige 
background, positioned exactly as it sits on the base face canvas 
(1024x1024, cheeks at Y=550px, X=400 and X=624), no eyes, eyebrows, 
nose, mouth, face, or hair included.
Variant: [neutral / blush / flushed]
```

### 3h. Hair — 3 LAYERS (Front / Middle / Back)

**Front layer** (bangs, fringe, sideburns, front pieces):

```
[MASTER STYLE LOCK]
Generate ONLY the FRONT layer of the hair (the part that frames the 
face — bangs, fringe, sideburns, front pieces), isolated on plain 
warm beige background, positioned exactly as it sits on the base face 
canvas (1024x1024, hair top at Y=200px), no face, eyes, nose, mouth, 
or other hair layers included.
Variant: [short_textured_male / wavy_shoulder_female / curly_volume / 
straight_long / bob_cut / buzz_cut_male / silver_gray_senior / bald / 
slick_back / middle_part_long]
```

**Middle layer** (volume for buns/braids/ponytails):

```
[MASTER STYLE LOCK]
Generate ONLY the MIDDLE layer of the hair (the volume that gives 
long hair, buns, braids, ponytails their body — side strands, bun 
shape, braid body), isolated on plain warm beige background, 
positioned exactly as it sits on the head (1024x1024), no face, no 
front hair bangs, no back hair length included.
Variant: [long_straight / wavy_shoulder / curly_volume / bun / braid / ponytail]
```

**Back layer** (length falling behind head):

```
[MASTER STYLE LOCK]
Generate ONLY the BACK layer of the hair (the length that falls 
behind the head and down the back), isolated on plain warm beige 
background, positioned to fall behind the head on the base face 
canvas (1024x1024), no face, no front hair bangs, no middle hair 
volume included.
Variant: [long_straight / wavy_shoulder / curly_long / short_back / 
bun_back / braid_back / ponytail_back]
```

**Why 3 layers**: Long hair, buns, braids, and ponytails need middle volume
between front bangs and back length. Without it, hairstyles look flat.

### 3i. Facial hair (5 variants — adult male only)

```
[MASTER STYLE LOCK]
Generate ONLY the facial hair, isolated on plain warm beige background, 
positioned exactly as it sits on the base face canvas (1024x1024, 
around Y=620-720px for jaw/chin area), no face, eyes, nose, mouth, 
or hair included.
Variant: [clean_shaven / stubble / goatee / full_beard / mustache]
```

---

## Step 4 — Generate ACCESSORIES (each fully isolated, NOT merged into hair)

```
[MASTER STYLE LOCK]
Generate ONLY the accessory, isolated on plain warm beige background, 
positioned exactly as it sits on the base face canvas (1024x1024), 
no face, no hair, no clothing included. This is a separate accessory 
layer for a modular avatar system — it should NOT include any hair 
or face.
Accessory: [glasses (round/square/reading/sunglasses) / 
earrings (stud/hoop/jhumka) / turban (sikh/rajasthani) / 
hijab (beige/rust) / cap (baseball/knit) / hat (fedora/panama) / 
bindi (red/maroon) / mangalsutra / nose-ring (nath/stud) / 
headband (red/floral) / hair-clip (gold/bow)]
```

**Why separate**: Accessories were previously baked into hair. A user wearing
glasses shouldn't have to pick a "glasses hairstyle". Separating accessories
makes them mixable with any hair.

---

## Step 5 — Generate CLOTHING (by category, NOT age-locked)

```
[MASTER STYLE LOCK]
Generate: [OUTFIT DESCRIPTION], full body, front view, plain warm 
beige background. Body positioned at the same scale and anchor point 
as reference turnaround sheet. 8 heads tall proportions for adult 
clothing, smaller for baby. Clothing should be on a featureless 
neutral body silhouette — no head, no hands, no facial features, 
just the clothing itself. The clothing is category-based (not 
age-locked) — it can be resized to fit any age.
Category: [casual / formal / traditional / festival / winter / 
sports / office / school / baby / wedding]
```

**Why category-based**: A user can wear casual clothes whether they're 8 or 80.
Age-locked outfits forced regenerating clothing for every age band. Category-based
clothing scales to any age.

---

## Step 6 — The critical manual step (don't skip)

AI generation will **NOT** produce pixel-perfect matching edges between
separately-generated parts. After generation:

1. Import all pieces into **Figma** or **Photopea**
2. Align every part to the shared anchor grid (see [`ALIGNMENT-GUIDE.md`](./ALIGNMENT-GUIDE.md))
3. Manually touch up edges, recolor for exact palette match, and fix any
   lighting/shading mismatches between pieces generated in separate batches
4. Export each aligned part as a clean transparent PNG or SVG layer

See [`ALIGNMENT-GUIDE.md`](./ALIGNMENT-GUIDE.md) for the full manual alignment walkthrough.

---

## Step 7 — Apply the GENETICS SYSTEM (Kinrel's unique feature)

When generating a **child** avatar, inherit features from parents rather than
picking randomly:

| Feature | Rule |
|---------|------|
| Eye shape | 50% father / 50% mother |
| Nose type | 50% father / 50% mother |
| Eyebrows | 50% father / 50% mother |
| Hair texture | 50% father / 50% mother |
| **Skin tone** | **Blended** between both parents |
| Mouth shape | 50% father / 50% mother |
| Face shape | 50% father / 50% mother |
| Hair color | 50% parent / 25% each grandparent |
| Smile | Often a grandparent |

See [`GENETICS-SYSTEM.md`](./GENETICS-SYSTEM.md) for the full inheritance model
and blending rules.

---

## Why this order matters

The v2 order — **skin → face shape → base face → parts → accessories → clothing
→ genetics** — is what makes the system actually work as a **family avatar
pipeline** rather than a generic avatar builder.

The key v2 insights:

1. **Layers, not whole characters** — every feature is its own transparent PNG
2. **Variants per age** — no more "everyone looks like siblings"
3. **Skin tone separated** — critical for Indian families
4. **Hair in 3 layers** — buns/braids/ponytails need middle volume
5. **Accessories isolated** — never merged into hair
6. **Clothing by category** — resize to any age, not regenerate
7. **Genetics** — children inherit from parents; family resemblance emerges

Step 6 (manual alignment) is still not optional — no current AI tool holds
pixel-perfect part alignment across separate generations.

Step 7 (genetics) is what makes Kinrel **unique** — random faces don't make a
family look related. Inherited features do.
