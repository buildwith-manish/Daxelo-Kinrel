# Kinrel Cameo v2 — Modular Genetics-Aware Avatar System

**A modular, swappable, genetics-aware 2D avatar system built for the
[Daxelo Kinrel](https://github.com/buildwith-manish/Daxelo-Kinrel) family-relationship platform.**

> *A Cameo is never a standalone avatar. Always a member of the family.*

---

## Why v2?

v1 generated one face per age stage, with skin tone, hair, and face shape baked in.
That works for a generic avatar builder — but **Kinrel is a family-relationship app**.
Every family has multiple people who look related. v2 was rebuilt around that insight.

The v2 upgrade delivers **13 improvements** that turn a generic avatar builder into
a production-ready modular avatar pipeline uniquely suited to a family-focused platform:

1. **Multiple face variants per age** (A/B/C/D) — no more "everyone looks like siblings"
2. **Skin tone layer** (8 tones spanning the Indian skin spectrum) — applied separately, not baked in
3. **Hair separated into Front / Middle / Back** — so buns, braids, ponytails have proper volume
4. **Accessories layer** — glasses, earrings, turban, hijab, cap, hat, bindi, mangalsutra, nose-ring, headband, hair-clip — each isolated, never merged into hair
5. **Clothing by category, not age-locked** — Casual / Formal / Traditional / Festival / Winter / Sports / Office / School / Baby / Wedding, resized to fit any age
6. **Face shape layer** — Oval / Round / Square / Heart / Diamond / Long — separated from facial features
7. **Nose variants** — Small / Medium / Broad / Roman / Button / Round / Sharp
8. **Eyes variants** — Round / Almond / Large / Small / Droopy / Deep-set / Monolid / Wide
9. **Mouth variants** — 11 expressions including Neutral, Soft smile, Big smile, Open smile, Laugh, Sad, Thinking, Surprised, Concerned, Angry, Sleepy
10. **Eyebrows variants** — Thin / Medium / Thick / Straight / Curved / Bushy / Soft / High-arch
11. **9 age stages** (not 13) — Baby / Toddler / Child / Preteen / Teen / Young Adult / Adult / Middle Age / Senior — facial features vary appearance instead of redundant age bands
12. **Additive expressions** — only eyebrows / eyelids / pupils / mouth / cheeks change; the rest of the face stays identical (Bitmoji-style consistency)
13. **Genetics system** — children inherit eye shape, nose, eyebrows, hair texture from father; skin tone (blended), mouth shape, face shape, hair color from mother; with grandparent contributions. **Family resemblance emerges naturally.**

---

## Repository Structure

```
kinrel-cameo/
├── README.md                    ← this file
├── STYLE-LOCK.md                ← the locked visual style spec
├── PROMPT-SPEC.md               ← full 6-step generation spec (v2)
├── ALIGNMENT-GUIDE.md           ← manual Step 6 alignment walkthrough
├── GENETICS-SYSTEM.md           ← family-resemblance inheritance system
├── ASSET-CATALOG.md             ← every variant in the full system
├── MANIFEST.json                ← machine-readable asset registry
│
├── reference/                   ← master reference sheets (v1 + v2)
├── skin-tones/                  ← 8 flat skin tone swatches
├── face-shapes/                 ← 6 face shape silhouettes
├── base-faces/
│   ├── male/                    ← male faces by age + variant (A/B/C/D)
│   ├── female/                  ← female faces by age + variant (A/B/C/D)
│   └── neutral/                 ← child/baby faces (gender-neutral)
├── age-stages/                  ← full-body characters per age stage
│
├── parts/
│   ├── eyebrows/                ← 8 eyebrow variants
│   ├── eyes/                    ← 8 eye shape variants
│   ├── eyelids/                 ← 4 eyelid states (for expressions)
│   ├── pupils/                  ← 4 pupil gaze directions
│   ├── nose/                    ← 7 nose variants
│   ├── mouth/                   ← 11 mouth/expression variants
│   ├── cheeks/                  ← 3 cheek states (neutral/blush/flushed)
│   ├── hair-front/              ← front hair layer (bangs/fringe)
│   ├── hair-middle/             ← middle hair layer (volume for buns/braids/ponytails)
│   ├── hair-back/               ← back hair layer (length falling behind)
│   └── facial-hair/             ← 5 facial hair variants (adult male)
│
├── accessories/
│   ├── glasses/                 ← round, square, reading, sunglasses
│   ├── earrings/                ← stud, hoop, jhumka
│   ├── turban/                  ← Sikh, Rajasthani
│   ├── hijab/                   ← beige, rust
│   ├── cap/                     ← baseball, knit
│   ├── hat/                     ← fedora, panama
│   ├── bindi/                   ← red, maroon
│   ├── mangalsutra/             ← traditional necklace
│   ├── nose-ring/               ← nath, stud
│   ├── headband/                ← red, floral (gajra)
│   └── hair-clip/               ← gold, bow
│
├── clothing/                    ← category-based, NOT age-locked
│   ├── casual/                  ← t-shirt/jeans, hoodie/jeans, kurta/jeans
│   ├── formal/                  ← suit, blouse/trouser, sherwani
│   ├── traditional/             ← sari, kurta/pajama, lehenga
│   ├── festival/                ← anarkali, pathani
│   ├── winter/                  ← jacket/jeans, sweater/pants
│   ├── sports/                  ← tracksuit, t-shirt/shorts
│   ├── office/                  ← shirt/trouser, pencil dress
│   ├── school/                  ← boy uniform, girl uniform
│   ├── baby/                    ← onesie, romper
│   └── wedding/                 ← bridal lehenga, groom sherwani
│
├── expressions/                 ← ADDITIVE overlays (only the part that changes)
│   ├── eyebrows/                ← 9 eyebrow positions for expressions
│   ├── eyelids/                 ← eyelid states for expressions
│   ├── mouth/                   ← 7 mouth shapes for expressions
│   └── cheeks/                  ← blush states for expressions
│
├── genetics/                    ← family-resemblance demos and inheritance maps
│
└── outfits/                     ← (legacy v1 full-body outfits — kept for reference)
```

---

## The Master Style Lock

Every asset — without exception — is generated with this locked style block:

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

See [`STYLE-LOCK.md`](./STYLE-LOCK.md).

---

## Layered Architecture (how a final character is composed)

A final character is a **stack of transparent PNG layers**, each from this system:

```
14. hair-back          (length falling behind head)
13. hair-middle        (volume for buns/braids/ponytails)
12. hair-front         (bangs/fringe)
11. accessories        (glasses, earrings, bindi, turban, hijab, etc.)
10. facial-hair        (stubble, beard, mustache — adult male only)
 9. cheeks             (blush overlay)
 8. mouth              (from 11 mouth variants)
 7. nose               (from 7 nose variants)
 6. pupils             (gaze direction — for expressions)
 5. eyelids            (open/half/squint — for expressions)
 4. eyes               (from 8 eye shape variants)
 3. eyebrows           (from 8 eyebrow variants)
 2. base-face          (variant A/B/C/D per age + gender)
 1. face-shape         (oval/round/square/heart/diamond/long)
 0. skin-tone          (8 tones — multiply blend)
```

For full-body compositions, the composed head sits on top of a `clothing/` asset
which is then resized to the character's age proportions.

---

## The Genetics System (Kinrel's unique feature)

Because Kinrel is a family-relationship app, the v2 system includes a
**genetics inheritance model**. When a child avatar is generated, features are
inherited from parents rather than picked at random:

| Feature | Inherited from |
|---------|---------------|
| Eye shape | One parent (50/50) |
| Nose type | One parent (50/50) |
| Eyebrows | One parent (50/50) |
| Hair texture | One parent (50/50) |
| Skin tone | **Blended** between both parents |
| Mouth shape | One parent (50/50) |
| Face shape | One parent (50/50) |
| Hair color | One parent or a grandparent (25% chance) |
| Smile | Often a grandparent |

This makes generated families actually **look related** — the core UX promise
of a family-relationship app. See [`GENETICS-SYSTEM.md`](./GENETICS-SYSTEM.md).

---

## Why this matters for Kinrel

A generic avatar builder gives you 13 nearly-identical age bands and one face
per stage. Everyone ends up looking like siblings — which is the **opposite**
of what a family-relationship app needs.

The v2 system gives you:

- **Variety** — 4+ face variants per adult age, with different jaw/eye/nose/lip/ear shapes
- **Inclusivity** — 8 skin tones spanning the full Indian skin spectrum
- **Cultural authenticity** — turbans, hijabs, bindis, mangalsutras, jhumkas, saris, sherwanis, lehengas
- **Family resemblance** — genetics system makes children visibly inherit from parents
- **Scalability** — clothing is category-based, so adding a new age doesn't require new outfits
- **Consistency** — additive expressions keep the same face across emotions (Bitmoji-style)

---

## Regenerating Assets

The full v2 spec script: [`/scripts/generate-kinrel-cameo-v2.js`](../scripts/generate-kinrel-cameo-v2.js)
The priority generation script: [`/scripts/generate-kinrel-cameo-v2-priority.js`](../scripts/generate-kinrel-cameo-v2-priority.js)

```bash
# Generate the priority subset (recommended)
node scripts/generate-kinrel-cameo-v2-priority.js

# Generate the full system (much longer)
node scripts/generate-kinrel-cameo-v2.js
```

Both scripts:
- Generate assets sequentially with 20-second delays (rate-limit aware)
- Skip any asset that already exists (>5 KB) — safely re-runnable
- Retry on 429 / 5xx with exponential backoff
- Write a `generation-log-v2.json` summary at the end

---

## License & Ownership

Generated for the **Daxelo Kinrel** project. All assets are exclusive to Kinrel
and may not be repurposed outside the Kinrel family platform.
