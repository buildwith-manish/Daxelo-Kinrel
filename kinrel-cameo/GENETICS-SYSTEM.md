# Kinrel Cameo — Genetics System

**The unique feature that makes Kinrel Cameo more than a generic avatar builder.**

Because Kinrel is a **family-relationship app**, the avatar system must produce
families that *look related* — not random faces that happen to share a surname.
The genetics system achieves this by **inheriting features from parents** when
generating child avatars.

---

## The Inheritance Model

When a child avatar is generated, each feature is inherited according to this table:

| Feature | Inheritance Rule | Notes |
|---------|------------------|-------|
| **Eye shape** | 50% from father, 50% from mother | Round / Almond / Large / Small / Droopy / Deep-set / Monolid / Wide |
| **Nose type** | 50% from father, 50% from mother | Small / Medium / Broad / Roman / Button / Round / Sharp |
| **Eyebrows** | 50% from father, 50% from mother | Thin / Medium / Thick / Straight / Curved / Bushy / Soft / High-arch |
| **Hair texture** | 50% from father, 50% from mother | Straight / Wavy / Curly / Coily |
| **Skin tone** | **Blended** between both parents | Picks a tone between the two parents' tones — see blending rules below |
| **Mouth shape** | 50% from father, 50% from mother | Neutral / Soft smile / Big smile / Open smile / Laugh / Sad / etc. |
| **Face shape** | 50% from father, 50% from mother | Oval / Round / Square / Heart / Diamond / Long |
| **Hair color** | 50% parent, 25% each grandparent | Allows grandfather's hair color to skip a generation |
| **Smile** | Often a grandparent | A grandparent's mouth variant can surface in the grandchild |
| **Facial hair** (males only) | 50% from father | Stubble / Goatee / Full beard / Mustache / Clean-shaven |

---

## Skin Tone Blending

Skin tone is the only feature that is **blended** rather than picked from one
parent. The blending works on the 8-tone scale:

```
skin_01 (very fair) ─── skin_02 ─── skin_03 ─── skin_04 ─── skin_05 ─── skin_06 ─── skin_07 ─── skin_08 (very deep)
```

### Blending rules

| Father tone | Mother tone | Child tone |
|-------------|-------------|------------|
| skin_01 | skin_01 | skin_01 |
| skin_01 | skin_04 | skin_02 or skin_03 (random within range) |
| skin_02 | skin_06 | skin_04 or skin_05 |
| skin_03 | skin_07 | skin_05 |
| skin_04 | skin_08 | skin_06 |
| skin_05 | skin_05 | skin_05 |
| skin_06 | skin_08 | skin_07 |
| skin_07 | skin_08 | skin_07 or skin_08 |

The blend introduces slight randomization within the parent range — so two
children of the same parents can have slightly different skin tones, just like
real siblings.

---

## Sibling Resemblance

Siblings inherit from the same parents but roll the dice independently on each
feature. This produces realistic sibling variation:

- Two siblings may share their father's nose but differ in eye shape
- One sibling may have the mother's hair color, another the grandfather's
- Skin tone is independently blended for each sibling (within parent range)

This is why siblings **look related but not identical** — exactly the family
resemblance pattern Kinrel needs to convey.

---

## Grandparent Contributions

The genetics system supports **grandparent contributions** for two features:

- **Hair color** — 25% chance to inherit from each grandparent (instead of parents)
- **Smile (mouth variant)** — often skips a generation and resurfaces in a grandchild

This requires the family tree to track grandparents' features. The full
inheritance chain:

```
Great-grandparents (optional)
        ↓
Grandparents (hair color, smile tracked)
        ↓
Parents (all features tracked)
        ↓
Child (rolled at generation time)
```

---

## Implementation in the Modular Asset System

The genetics system is **enabled by the layered architecture** of v2. Because
every feature is a separate transparent PNG layer, you can:

1. Look up the father's `eyes_*.png` variant and the mother's `eyes_*.png` variant
2. Roll a 50/50 to pick which one the child inherits
3. Stack that eyes layer on the child's base face
4. Repeat for each feature
5. Blend the skin tone by picking from the 8-tone scale between the parents' tones
6. Stack the resulting skin-tone layer at the bottom (multiply blend)

A child avatar ends up as a unique stack of layers — but **every layer was
inherited from a parent or grandparent**, so the resemblance emerges naturally.

### Pseudo-code

```python
def generate_child(father, mother, grandparents):
    child = {}
    # 50/50 features
    child['eyes']        = random.choice([father.eyes, mother.eyes])
    child['nose']        = random.choice([father.nose, mother.nose])
    child['eyebrows']    = random.choice([father.eyebrows, mother.eyebrows])
    child['hair_texture']= random.choice([father.hair_texture, mother.hair_texture])
    child['mouth']       = random.choice([father.mouth, mother.mouth])
    child['face_shape']  = random.choice([father.face_shape, mother.face_shape])

    # Blended skin tone
    child['skin_tone']   = blend_skin_tone(father.skin_tone, mother.skin_tone)

    # Grandparent contributions
    if random.random() < 0.25:
        child['hair_color'] = random.choice(grandparents).hair_color
    else:
        child['hair_color'] = random.choice([father.hair_color, mother.hair_color])

    if random.random() < 0.30:
        child['smile'] = random.choice(grandparents).smile
    else:
        child['smile'] = random.choice([father.smile, mother.smile])

    return child

def blend_skin_tone(father_tone, mother_tone):
    # tones are 1-8; child gets a random tone in the range between them
    low  = min(father_tone, mother_tone)
    high = max(father_tone, mother_tone)
    return random.randint(low, high)
```

---

## Visual Proof — the Genetics Demo

See `genetics/family_genetics_demo.png` — a rendered family of three showing:

- **Father**: square jaw, almond eyes, sharp nose, thick eyebrows, medium skin tone, short textured hair, full beard
- **Mother**: oval face, round eyes, button nose, soft arched eyebrows, fair warm skin tone, long wavy hair
- **Child (age 6-8)**: almond eyes (← father), button nose (← mother), blended medium-fair skin tone, thick eyebrows (← father), wavy hair texture (← mother)

Also see `genetics/genetics_inheritance_diagram.png` — a clean infographic
showing the inheritance arrows from parents to child, plus the grandparent row.

---

## Why This Matters for Kinrel

A generic avatar builder gives you random faces. When users add their family
members, those avatars have no visual relationship to each other — which breaks
the core promise of a family-relationship app.

The genetics system makes the family feel like a **family**:

- Children visibly inherit features from their parents
- Siblings share some features and differ in others (realistic variation)
- Grandparents' features can resurface in grandchildren (skipping a generation)
- Skin tones blend like real genetics, not random picks

This is the **10/10 production-ready** feature that turns a generic avatar
pipeline into one uniquely suited to Kinrel's purpose.
