# Kinrel Cameo v2 — Full Asset Catalog

Every variant in the modular system. Use this as the shopping list when
composing avatars or planning new asset generation.

---

## 1. Skin Tones (8)

Path: `skin-tones/skin_NN.png`

| File | Tone | Undertone |
|------|------|-----------|
| `skin_01.png` | Very fair porcelain | Subtle pink |
| `skin_02.png` | Fair warm wheat | Golden |
| `skin_03.png` | Light tan | Warm yellow |
| `skin_04.png` | Medium wheat | Neutral |
| `skin_05.png` | Medium olive | Warm yellow-green |
| `skin_06.png` | Tan brown | Rich warm |
| `skin_07.png` | Deep brown | Cool red |
| `skin_08.png` | Very deep dark brown | Rich warm |

**Usage**: Multiply-blend at the bottom of the layer stack (layer 0).

---

## 2. Face Shapes (6)

Path: `face-shapes/shape_<id>.png`

| File | Shape | Characteristics |
|------|-------|-----------------|
| `shape_oval.png` | Oval | Balanced proportions, forehead slightly wider than chin |
| `shape_round.png` | Round | Soft full curves, equal width and height |
| `shape_square.png` | Square | Strong jaw, forehead and jaw equal width |
| `shape_heart.png` | Heart | Wider forehead tapering to small pointed chin |
| `shape_diamond.png` | Diamond | Narrow forehead and chin, widest at cheekbones |
| `shape_long.png` | Long | Elongated vertical proportions, narrower than tall |

**Usage**: Layer 1, just above skin tone.

---

## 3. Base Faces (9 stages × variants A/B/C/D)

Path: `base-faces/<gender>/face_<age>_<variant>.png`

### Neutral gender (children)

| File | Age | Notes |
|------|-----|-------|
| `base-faces/neutral/face_baby_A.png` | Baby (0-2) | Soft rounded baby face |
| `base-faces/neutral/face_toddler_A.png` | Toddler (2-4) | Slightly slimmer than baby |
| `base-faces/neutral/face_child_A.png` | Child (5-8) | Balanced child proportions |
| `base-faces/neutral/face_preteen_A.png` | Preteen (9-12) | Developing features |

### Male

| File | Age | Variant | Distinguishing features |
|------|-----|---------|-------------------------|
| `base-faces/male/face_teen_male_A.png` | Teen Boy (13-17) | A | Narrower jaw, average eye spacing, slim nose |
| `base-faces/male/face_teen_male_B.png` | Teen Boy (13-17) | B | Wider jaw, wider eye spacing, broader nose |
| `base-faces/male/face_young_adult_male_A.png` | Young Adult Male (18-29) | A | Narrow jaw, close-set eyes, sharp nose, thin lips, medium ears |
| `base-faces/male/face_young_adult_male_B.png` | Young Adult Male (18-29) | B | Wide square jaw, wide-set eyes, broad nose, full lips, large ears |
| `base-faces/male/face_young_adult_male_C.png` | Young Adult Male (18-29) | C | Oval face, average eye spacing, button nose, average lips, small ears |
| `base-faces/male/face_young_adult_male_D.png` | Young Adult Male (18-29) | D | Round face, hooded eyes, roman nose, wide mouth, average ears |
| `base-faces/male/face_adult_male_A.png` | Adult Male (30-44) | A | Strong square jaw, average eye spacing, medium nose |
| `base-faces/male/face_adult_male_B.png` | Adult Male (30-44) | B | Rounded jaw, wide-set eyes, broad nose, full lips |
| `base-faces/male/face_adult_male_C.png` | Adult Male (30-44) | C | Narrow jaw, close-set eyes, sharp nose, thin lips |
| `base-faces/male/face_adult_male_D.png` | Adult Male (30-44) | D | Oval face, almond eyes, roman nose, wide mouth |
| `base-faces/male/face_middle_aged_male_A.png` | Middle Aged Male (45-59) | A | Mature features, subtle laugh lines |
| `base-faces/male/face_middle_aged_male_B.png` | Middle Aged Male (45-59) | B | Deeper wrinkles, wider jaw |
| `base-faces/male/face_senior_male_A.png` | Senior Male (60-74+) | A | Deep wrinkles, sagging skin, wise expression |
| `base-faces/male/face_senior_male_B.png` | Senior Male (60-74+) | B | Weathered skin, mature jaw |

### Female

| File | Age | Variant | Distinguishing features |
|------|-----|---------|-------------------------|
| `base-faces/female/face_teen_female_A.png` | Teen Girl (13-17) | A | Oval face, average features, slim nose |
| `base-faces/female/face_teen_female_B.png` | Teen Girl (13-17) | B | Rounder face, wider eyes, smaller nose, fuller lips |
| `base-faces/female/face_young_adult_female_A.png` | Young Adult Female (18-29) | A | Oval face, almond eyes, slim nose, full lips, small ears |
| `base-faces/female/face_young_adult_female_B.png` | Young Adult Female (18-29) | B | Round face, round eyes, button nose, thin lips |
| `base-faces/female/face_young_adult_female_C.png` | Young Adult Female (18-29) | C | Heart face, wide eyes, sharp nose, medium lips |
| `base-faces/female/face_young_adult_female_D.png` | Young Adult Female (18-29) | D | Diamond face, deep-set eyes, broad nose, wide mouth |
| `base-faces/female/face_adult_female_A.png` | Adult Female (30-44) | A | Oval face, almond eyes, slim nose, full lips |
| `base-faces/female/face_adult_female_B.png` | Adult Female (30-44) | B | Round face, round eyes, button nose, average lips |
| `base-faces/female/face_adult_female_C.png` | Adult Female (30-44) | C | Square face, hooded eyes, sharp nose, thin lips |
| `base-faces/female/face_adult_female_D.png` | Adult Female (30-44) | D | Heart face, wide eyes, broad nose, wide mouth |
| `base-faces/female/face_middle_aged_female_A.png` | Middle Aged Female (45-59) | A | Mature features, subtle laugh lines, oval face |
| `base-faces/female/face_middle_aged_female_B.png` | Middle Aged Female (45-59) | B | Graceful aging, rounder face |
| `base-faces/female/face_senior_female_A.png` | Senior Female (60-74+) | A | Graceful aged features, fine wrinkles, warm expression |
| `base-faces/female/face_senior_female_B.png` | Senior Female (60-74+) | B | Deeper wrinkles, oval face |

**Total**: 4 neutral + 14 male + 14 female = **32 base faces**

---

## 4. Eyebrows (8)

Path: `parts/eyebrows/eyebrow_<id>.png`

| File | Variant |
|------|---------|
| `eyebrow_thin.png` | Thin, sparse, lightly arched |
| `eyebrow_medium.png` | Medium thickness, natural shape |
| `eyebrow_thick.png` | Thick, full, dense |
| `eyebrow_straight.png` | Straight horizontal, no arch |
| `eyebrow_curved.png` | Curved, soft arch |
| `eyebrow_bushy.png` | Bushy, unruly, dense and full |
| `eyebrow_soft.png` | Soft rounded, gentle shape |
| `eyebrow_high_arch.png` | High arched, dramatic peak |

---

## 5. Eyes (8)

Path: `parts/eyes/eyes_<id>.png`

| File | Variant |
|------|---------|
| `eyes_round.png` | Round |
| `eyes_almond.png` | Almond-shaped |
| `eyes_large.png` | Large wide |
| `eyes_small.png` | Small narrow |
| `eyes_droopy.png` | Droopy eyelids, outer corners down |
| `eyes_deep_set.png` | Deep-set hooded, heavy brow bone |
| `eyes_monolid.png` | Monolid, no visible crease |
| `eyes_wide.png` | Wide-set, larger gap between |

---

## 6. Eyelids (4)

Path: `parts/eyelids/eyelids_<id>.png`

| File | Variant |
|------|---------|
| `eyelids_open.png` | Fully open |
| `eyelids_half.png` | Half-closed, sleepy |
| `eyelids_quarter.png` | Quarter-closed, drowsy |
| `eyelids_squint.png` | Squinting, narrowed |

---

## 7. Pupils (4)

Path: `parts/pupils/pupils_<id>.png`

| File | Variant |
|------|---------|
| `pupils_forward.png` | Looking forward |
| `pupils_up.png` | Looking up |
| `pupils_side.png` | Looking to the side |
| `pupils_down.png` | Looking down |

---

## 8. Nose (7)

Path: `parts/nose/nose_<id>.png`

| File | Variant |
|------|---------|
| `nose_small.png` | Small, delicate, narrow bridge |
| `nose_medium.png` | Medium, average, balanced |
| `nose_broad.png` | Broad, wide, flat bridge |
| `nose_roman.png` | Roman aquiline, prominent bridge |
| `nose_button.png` | Button, small and round, upturned |
| `nose_round.png` | Round bulbous, wide tip |
| `nose_sharp.png` | Sharp pointed, narrow tip, defined bridge |

---

## 9. Mouth (11)

Path: `parts/mouth/mouth_<id>.png`

| File | Variant |
|------|---------|
| `mouth_neutral.png` | Closed neutral, relaxed |
| `mouth_soft_smile.png` | Soft gentle closed-lip smile |
| `mouth_big_smile.png` | Big wide closed-lip smile |
| `mouth_open_smile.png` | Open smile showing upper teeth |
| `mouth_laugh.png` | Open laughing, showing teeth |
| `mouth_sad.png` | Sad, corners downturned |
| `mouth_thinking.png` | Lips pursed to one side |
| `mouth_surprised.png` | Small open O shape |
| `mouth_concerned.png` | Slight frown, lips pressed |
| `mouth_angry.png` | Tight pressed lips, downward corners |
| `mouth_sleepy.png` | Slightly open, relaxed |

---

## 10. Cheeks (3)

Path: `parts/cheeks/cheeks_<id>.png`

| File | Variant |
|------|---------|
| `cheeks_neutral.png` | No blush |
| `cheeks_blush.png` | Soft pink blush |
| `cheeks_flushed.png` | Stronger flushed, rosier |

---

## 11. Hair — 3 Layers (Front / Middle / Back)

### Hair Front

Path: `parts/hair-front/hair_front_<id>.png`

| File | Variant |
|------|---------|
| `hair_front_short_textured_male.png` | Short dark brown textured, short sides, longer top |
| `hair_front_wavy_shoulder_female.png` | Long wavy, middle part, front bangs |
| `hair_front_curly_volume.png` | Voluminous curly, front curls framing face |
| `hair_front_straight_long.png` | Straight long, middle part, front pieces |
| `hair_front_bob_cut.png` | Short bob, jaw length, front fringe |
| `hair_front_buzz_cut_male.png` | Buzz cut, very short, front hairline |
| `hair_front_silver_gray_senior.png` | Silver gray short, senior, front hairline |
| `hair_front_bald.png` | Clean bald, smooth scalp |
| `hair_front_slick_back.png` | Slicked back, front pushed back |
| `hair_front_middle_part_long.png` | Long straight black, middle part, front pieces |

### Hair Middle

Path: `parts/hair-middle/hair_middle_<id>.png`

| File | Variant |
|------|---------|
| `hair_middle_long_straight.png` | Side strands past shoulders |
| `hair_middle_wavy_shoulder.png` | Side strands with wave texture |
| `hair_middle_curly_volume.png` | Side curls framing face |
| `hair_middle_bun.png` | Bun shape on top/back of head |
| `hair_middle_braid.png` | Braid resting against side of head |
| `hair_middle_ponytail.png` | Ponytail wrap at back of head |

### Hair Back

Path: `parts/hair-back/hair_back_<id>.png`

| File | Variant |
|------|---------|
| `hair_back_long_straight.png` | Length falling past shoulders |
| `hair_back_wavy_shoulder.png` | Back length with wave texture |
| `hair_back_curly_long.png` | Back length with curl texture |
| `hair_back_short_back.png` | Back of head coverage only |
| `hair_back_bun_back.png` | Back portion of bun |
| `hair_back_braid_back.png` | Braid falling down the back |
| `hair_back_ponytail_back.png` | Ponytail length down the back |

**Why 3 layers?** Long hair, buns, braids, and ponytails need **middle volume**
between the front bangs and the back length. Without a middle layer, these
hairstyles look flat and unrealistic.

---

## 12. Facial Hair (5 — adult male only)

Path: `parts/facial-hair/facialhair_<id>.png`

| File | Variant |
|------|---------|
| `facialhair_clean_shaven.png` | Clean shaven, smooth |
| `facialhair_stubble.png` | Short light stubble |
| `facialhair_goatee.png` | Goatee, chin only, no mustache |
| `facialhair_full_beard.png` | Full short beard, covers jaw |
| `facialhair_mustache.png` | Mustache, classic, no beard |

---

## 13. Accessories

Each accessory is **fully isolated** — never merged into hair.

### Glasses (4)

Path: `accessories/glasses/`

| File | Variant |
|------|---------|
| `round_glasses.png` | Round thin metal frame |
| `square_glasses.png` | Square dark frame |
| `reading_glasses.png` | Rectangular thin frame |
| `sunglasses.png` | Aviator dark |

### Earrings (3)

Path: `accessories/earrings/`

| File | Variant |
|------|---------|
| `stud_earrings.png` | Small gold studs |
| `hoop_earrings.png` | Medium gold hoops |
| `jhumka_earrings.png` | Traditional Indian gold jhumka, bell-shaped |

### Turban (2)

Path: `accessories/turban/`

| File | Variant |
|------|---------|
| `sikh_turban.png` | Sikh pagri, saffron orange |
| `rajasthani_turban.png` | Rajasthani bandhani, red and orange patterned |

### Hijab (2)

Path: `accessories/hijab/`

| File | Variant |
|------|---------|
| `hijab_beige.png` | Soft beige |
| `hijab_rust.png` | Warm rust |

### Cap (2)

Path: `accessories/cap/`

| File | Variant |
|------|---------|
| `baseball_cap.png` | Navy blue |
| `knit_cap.png` | Cream knit beanie |

### Hat (2)

Path: `accessories/hat/`

| File | Variant |
|------|---------|
| `fedora_hat.png` | Brown fedora |
| `panama_hat.png` | Cream panama straw |

### Cultural / Religious Markers

Path: `accessories/bindi/`, `accessories/mangalsutra/`, `accessories/nose-ring/`

| File | Variant |
|------|---------|
| `bindi/red_bindi.png` | Small round red bindi |
| `bindi/maroon_bindi.png` | Small round maroon bindi |
| `mangalsutra/mangalsutra.png` | Black and gold beads with gold pendant |
| `nose-ring/nose_ring.png` | Small gold nath |
| `nose-ring/nose_stud.png` | Small gold nose stud |

### Hair Accessories

Path: `accessories/headband/`, `accessories/hair-clip/`

| File | Variant |
|------|---------|
| `headband/red_headband.png` | Red fabric |
| `headband/floral_headband.png` | White floral gajra |
| `hair-clip/gold_hair_clip.png` | Small gold clip |
| `hair-clip/bow_hair_clip.png` | Small cream bow |

---

## 14. Clothing (by category — NOT age-locked)

All clothing is full-body on a featureless neutral silhouette (no head, no hands).
Resize automatically to fit any age.

### Casual (3)

Path: `clothing/casual/`

| File | Outfit |
|------|--------|
| `casual_tshirt_jeans.png` | White t-shirt and blue jeans |
| `casual_hoodie_jeans.png` | Cream hoodie and blue jeans |
| `casual_kurta_jeans.png` | Short cotton kurta with jeans |

### Formal (3)

Path: `clothing/formal/`

| File | Outfit |
|------|--------|
| `formal_suit_beige.png` | Beige suit jacket, white shirt, brown trousers |
| `formal_blouse_trouser.png` | Cream silk blouse and navy trousers |
| `formal_sherwani.png` | Cream and gold sherwani |

### Traditional (3)

Path: `clothing/traditional/`

| File | Outfit |
|------|--------|
| `traditional_sari_beige_rust.png` | Beige and rust sari with blouse |
| `traditional_kurta_pajama.png` | White cotton kurta pajama |
| `traditional_lehenga.png` | Rust and gold lehenga choli |

### Festival (2)

Path: `clothing/festival/`

| File | Outfit |
|------|--------|
| `festival_anarkali.png` | Bright orange anarkali with gold embroidery |
| `festival_pathani.png` | Deep green pathani kurta with salwar |

### Winter (2)

Path: `clothing/winter/`

| File | Outfit |
|------|--------|
| `winter_jacket_jeans.png` | Brown padded jacket over cream sweater, blue jeans |
| `winter_sweater_pants.png` | Cream knit turtleneck and brown pants |

### Sports (2)

Path: `clothing/sports/`

| File | Outfit |
|------|--------|
| `sports_tracksuit.png` | Navy tracksuit |
| `sports_tshirt_shorts.png` | White t-shirt and blue sports shorts |

### Office (2)

Path: `clothing/office/`

| File | Outfit |
|------|--------|
| `office_shirt_trouser.png` | Light blue shirt and gray trousers |
| `office_pencil_dress.png` | Navy pencil dress with belt |

### School (2)

Path: `clothing/school/`

| File | Outfit |
|------|--------|
| `school_uniform_boy.png` | White shirt, navy tie, gray shorts |
| `school_uniform_girl.png` | White shirt, navy tie, gray pleated skirt |

### Baby (2)

Path: `clothing/baby/`

| File | Outfit |
|------|--------|
| `baby_onesie_cream.png` | Soft cream onesie |
| `baby_romper_yellow.png` | Soft yellow romper |

### Wedding (2)

Path: `clothing/wedding/`

| File | Outfit |
|------|--------|
| `wedding_lehenga_red.png` | Red and gold bridal lehenga with heavy embroidery |
| `wedding_sherwani_cream.png` | Cream and gold groom sherwani with churidar |

**Total**: 23 clothing assets, all category-based.

---

## 15. Expressions (Additive Overlays)

Only the part that changes is replaced. Everything else stays identical.

### Eyebrow overlays (9)

Path: `expressions/eyebrows/`

| File | Expression |
|------|------------|
| `eyebrows_happy.png` | Slightly raised, soft arch |
| `eyebrows_excited.png` | Raised high, peaked |
| `eyebrows_thinking.png` | One raised, other lowered |
| `eyebrows_focused.png` | Slightly lowered and inward |
| `eyebrows_celebrating.png` | Raised very high |
| `eyebrows_loving.png` | Soft, slightly raised |
| `eyebrows_sad.png` | Inner corners raised |
| `eyebrows_surprised.png` | Raised high and rounded |
| `eyebrows_angry.png` | Lowered, sharp V shape |

### Eyelid overlays (3+)

Path: `expressions/eyelids/` — reuse from `parts/eyelids/`

### Mouth overlays (7)

Path: `expressions/mouth/`

| File | Expression |
|------|------------|
| `mouth_happy.png` | Soft closed-lip smile |
| `mouth_excited.png` | Wide open smile showing teeth |
| `mouth_thinking.png` | Lips pursed to one side |
| `mouth_focused.png` | Lips pressed together |
| `mouth_celebrating.png` | Big open laugh |
| `mouth_loving.png` | Soft gentle smile, slightly parted |
| `mouth_sleepy.png` | Slightly open, relaxed |

### Cheek overlays

Path: `expressions/cheeks/` — reuse from `parts/cheeks/`

---

## 16. Age Stages (9 stages × 2 genders)

Path: `age-stages/stage_<id>.png`

| File | Stage |
|------|-------|
| `stage_baby.png` | Baby (0-2) |
| `stage_toddler.png` | Toddler (2-4) |
| `stage_child.png` | Child (5-8) |
| `stage_preteen.png` | Preteen (9-12) |
| `stage_teen_male.png` | Teen Boy (13-17) |
| `stage_teen_female.png` | Teen Girl (13-17) |
| `stage_young_adult_male.png` | Young Adult Male (18-29) |
| `stage_young_adult_female.png` | Young Adult Female (18-29) |
| `stage_adult_male.png` | Adult Male (30-44) |
| `stage_adult_female.png` | Adult Female (30-44) |
| `stage_middle_aged_male.png` | Middle Aged Male (45-59) |
| `stage_middle_aged_female.png` | Middle Aged Female (45-59) |
| `stage_senior_male.png` | Senior Male (60-74+) |
| `stage_senior_female.png` | Senior Female (60-74+) |

---

## 17. Genetics (2 reference images)

Path: `genetics/`

| File | Purpose |
|------|---------|
| `family_genetics_demo.png` | Visual proof — father, mother, child showing inherited features |
| `genetics_inheritance_diagram.png` | Infographic showing the inheritance arrows |

---

## 18. Reference Sheets (2)

Path: `reference/`

| File | Purpose |
|------|---------|
| `kinrel-cameo-master-sheet.png` | v1 master sheet (legacy) |
| `kinrel-cameo-master-sheet-v2.png` | v2 master sheet showing layered architecture + genetics |

---

## Total Asset Count (Full v2 System)

| Category | Count |
|----------|-------|
| Skin tones | 8 |
| Face shapes | 6 |
| Base faces | 32 |
| Eyebrows | 8 |
| Eyes | 8 |
| Eyelids | 4 |
| Pupils | 4 |
| Nose | 7 |
| Mouth | 11 |
| Cheeks | 3 |
| Hair front | 10 |
| Hair middle | 6 |
| Hair back | 7 |
| Facial hair | 5 |
| Accessories | 23 |
| Clothing | 23 |
| Expressions (overlays) | 19 |
| Age stages | 14 |
| Genetics demos | 2 |
| Reference sheets | 2 |
| **TOTAL** | **202** |
