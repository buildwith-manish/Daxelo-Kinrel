# Kinrel Cameo — Master Style Lock

This is the **single source of truth** for the visual style of every Kinrel Cameo asset.
Paste this block into every image generation prompt, **unchanged**. It is what keeps every
generated piece combinable — same lighting, same rendering rules, same proportions.

---

## The Style Lock (copy verbatim)

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

---

## Why this block matters

Generating whole combined characters repeatedly gives you inconsistent,
non-swappable art — that's the mistake this style lock exists to prevent.

Locking the style block first, then generating parts in isolated batches with
fixed canvas rules, is what makes pieces actually stack together correctly later.

The style lock enforces:

- **Rendering style** — soft rounded 3D-illustrated look (not anime, not cel-shaded, not Bitmoji/Pixar/Disney)
- **Proportions** — adults 7.5–8 heads tall, children proportionally smaller
- **Eyes** — large, expressive, with a small sharp catchlight
- **Skin** — soft matte shading with gentle subsurface warmth
- **Jaw** — rounded, not angular
- **Lighting** — soft frontal key light, no cast shadows on background
- **Background** — warm neutral beige
- **Palette** — Kinrel brand: `#F7EFE4`, `#C9B79E`, `#2A2A2A` accents

---

## Kinrel Brand Palette

| Swatch | Hex | Usage |
|--------|-----|-------|
| 🟤 Cream | `#F7EFE4` | Backgrounds, base clothing, light tones |
| 🟫 Tan | `#C9B79E` | Accents, mid-tones, secondary clothing |
| ⚫ Charcoal | `#2A2A2A` | Text, outlines (where needed), dark accents |
| 🟧 Rust | `#A85C32` | Warm accent (saris, jackets, vests) |
| 🟦 Denim Blue | `#3A4F6B` | Jeans, casual pants |
| ⚪ Soft White | `#FCFAF5` | Highlights, sneakers, shirts |

---

## Canvas Rules (apply to every part)

- **Canvas size:** 1024×1024 (heads/parts/accessories), 768×1344 (full-body clothing/age stages), 1344×768 (master sheets)
- **Character centered:** same head position and scale every time
- **View:** front-facing head-and-shoulders crop (parts) / full-body standing neutral (clothing)
- **Anchor grid:** eyes at Y=400px, nose center at X=512px, mouth center at Y=620px, hair top at Y=200px
- **Background:** plain warm beige (`#F7EFE4`), no cast shadows

---

## Forbidden Styles

The style lock explicitly forbids the following. Any asset that visually
resembles any of these is a defect and must be regenerated:

- Anime / manga style
- Cel shading
- Black outlines
- Hard edges
- Bitmoji
- Memoji
- Pixar style
- Disney style
- Photorealistic rendering
- Toon shading

---

## Skin Tone Spectrum (v2)

The v2 system uses 8 skin tones spanning the full Indian skin spectrum. These
are applied as a separate multiply-blend layer, **not** baked into the face:

| Tone ID | Description | Undertone |
|---------|-------------|-----------|
| `skin_01` | Very fair porcelain | Subtle pink |
| `skin_02` | Fair warm wheat | Golden |
| `skin_03` | Light tan | Warm yellow |
| `skin_04` | Medium wheat | Neutral |
| `skin_05` | Medium olive | Warm yellow-green |
| `skin_06` | Tan brown | Rich warm |
| `skin_07` | Deep brown | Cool red |
| `skin_08` | Very deep dark brown | Rich warm |

This separation is **critical** for an Indian family-relationship app — the
genetics system blends these tones between parents to produce realistic
family resemblance.
