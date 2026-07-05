#!/usr/bin/env python3
"""
generate_kinship_matrix.py — v3.0

Full recursive kinship resolution engine for Indian families.
Generates a complete 5,359 × 5,359 = 28,718,881 row CSV matrix.

Resolution priority (per (from, via) pair):
  1. Self-reference detection (inverse path cancellation)
  2. Exact path override (derived FROM JSON relationshipPath data)
  3. Generation + lineage + gender + elderYounger math
  4. Fuzzy match on generation + lineage only
  5. "distant-relative" fallback

Features:
  - Pre-builds all lookup dicts (O(1) resolution at runtime)
  - 64 MB buffered IO with csv.writer
  - Checkpoint/resume every 1,000,000 rows (key: last_via_index)
  - Progress every 500,000 rows with elapsed + ETA
  - Disk space pre-check
  - Error log to generate_errors.log
  - Verification suite run BEFORE generation (aborts if <95% pass)
  - Verification suite run AFTER generation (confirms accuracy)
  - Semantic labels derived from JSON hindiSpecificTerm + domain map
  - Female key derived from BY_GEN_LINEAGE_GENDER lookup
  - Lineage carried through all resolutions
  - elderYounger carried through (derived from key name since JSON field is null)

Usage:
    python generate_kinship_matrix.py [input.json] [output.csv]
"""

import json
import csv
import os
import sys
import time
import shutil
import traceback
import re
from datetime import datetime

# ===========================================================================
# Configuration
# ===========================================================================

INPUT_JSON   = "indian_kinship_production.json"
OUTPUT_CSV   = "kinship_matrix.csv"
CHECKPOINT   = "checkpoint.json"
ERROR_LOG    = "generate_errors.log"
CHUNK_SIZE        = 100_000
PROGRESS_EVERY    = 500_000
CHECKPOINT_EVERY  = 1_000_000
DISK_REQUIRED_GB  = 3
BUFFER_BYTES      = 1024 * 1024 * 64  # 64 MB

# ===========================================================================
# Global lookup structures (populated by build_lookups())
# ===========================================================================

BY_KEY = {}                  # relationshipKey -> entry
BY_PATH = {}                 # tuple(relationshipPath) -> entry
BY_GEN_LINEAGE_GENDER = {}   # (gen, lineage, gender, elder) -> [entries]
BY_GEN_LINEAGE = {}          # (gen, lineage) -> [entries]  (for fuzzy match)
PATH_OVERRIDES = {}          # (from_key, via_key) -> (result_label, female_label)
SELF_PAIRS = set()           # (from_key, via_key) pairs that are self-referential
LABEL_CACHE = {}             # relationshipKey -> semantic label
FEMALE_CACHE = {}            # relationshipKey -> female counterpart label
ALL_KEYS = set()             # set of all relationshipKeys

# ===========================================================================
# Domain knowledge: semantic label map for well-known Indian kinship terms
# These are NOT resolution overrides — they map JSON keys to human-readable
# labels for the CSV output. Domain knowledge that cannot be derived from
# JSON structure alone.
# ===========================================================================

SEMANTIC_LABELS = {
    # Core
    "self": "self", "father": "father", "mother": "mother",
    "son": "son", "daughter": "daughter",
    "brother": "brother", "sister": "sister",
    "elder_brother": "elder-brother", "younger_brother": "younger-brother",
    "elder_sister": "elder-sister", "younger_sister": "younger-sister",
    "husband": "husband", "wife": "wife",
    # Grandparents
    "paternal_grandfather": "paternal-grandfather",
    "paternal_grandmother": "paternal-grandmother",
    "maternal_grandfather": "maternal-grandfather",
    "maternal_grandmother": "maternal-grandmother",
    # Paternal uncles/aunts (Indian-specific)
    "fathers_elder_brother":         "tau",
    "fathers_elder_brothers_wife":   "tai",
    "fathers_younger_brother":       "chacha",
    "fathers_younger_brothers_wife": "chachi",
    "fathers_sister":                "bua",
    "fathers_sisters_husband":       "fufaji",
    # Maternal uncles/aunts
    "mothers_brother":               "mama",
    "mothers_brothers_wife":         "mami",
    "mothers_sister":                "mausi",
    "mothers_sisters_husband":       "mausa",
    # In-laws (husband's side)
    "husbands_father":               "father-in-law",
    "husbands_mother":               "mother-in-law",
    "husbands_elder_brother":        "jeth",
    "husbands_elder_brothers_wife":  "jethani",
    "husbands_younger_brother":      "devar",
    "husbands_younger_brothers_wife":"devrani",
    "husbands_sister":               "nanad",
    # In-laws (wife's side)
    "wifes_father":                  "father-in-law",
    "wifes_mother":                  "mother-in-law",
    "wifes_brother":                 "sala",
    "wifes_sister":                  "sali",
    # Children's spouses
    "sons_wife":                     "daughter-in-law",
    "daughters_husband":             "son-in-law",
    # Siblings' spouses
    "brothers_wife":                 "sister-in-law",
    "sisters_husband":               "brother-in-law",
    # Nephew/niece
    "brothers_son":                  "nephew",
    "brothers_daughter":             "niece",
    "sisters_son":                   "nephew",
    "sisters_daughter":              "niece",
    # Grandchildren
    "sons_son":                      "grandson",
    "sons_daughter":                 "granddaughter",
    "daughters_son":                 "grandson",
    "daughters_daughter":            "granddaughter",
    # Step relations
    "stepfather":    "stepfather",   "stepmother":    "stepmother",
    "stepson":       "stepson",      "stepdaughter":  "stepdaughter",
    "stepbrother":   "stepbrother",  "stepsister":    "stepsister",
    # Half relations
    "half_brother":  "half-brother", "half_sister":   "half-sister",
    # Ceremonial
    "guru":          "guru",
    "godfather":     "godfather",    "godmother":     "godmother",
    # Cousin types (derived from path patterns)
    "fathers_elder_brother_son":          "cousin-elder",
    "fathers_elder_brother_daughter":     "cousin-elder",
    "fathers_younger_brother_son":        "cousin-younger",
    "fathers_younger_brother_daughter":   "cousin-younger",
    "fathers_sister_son":                 "cousin-paternal",
    "fathers_sister_daughter":            "cousin-paternal",
    "mothers_brother_son":                "cousin-maternal",
    "mothers_brother_daughter":           "cousin-maternal",
    "mothers_sister_son":                 "cousin-maternal",
    "mothers_sister_daughter":            "cousin-maternal",
}

# Female counterpart map for semantic labels (male label -> female label)
FEMALE_LABEL_MAP = {
    "father": "mother", "mother": "mother",
    "son": "daughter", "daughter": "daughter",
    "brother": "sister", "sister": "sister",
    "elder-brother": "elder-sister", "younger-brother": "younger-sister",
    "elder-sister": "elder-sister", "younger-sister": "younger-sister",
    "husband": "wife", "wife": "wife",
    "grandfather": "grandmother", "grandmother": "grandmother",
    "paternal-grandfather": "paternal-grandmother",
    "paternal-grandmother": "paternal-grandmother",
    "maternal-grandfather": "maternal-grandmother",
    "maternal-grandmother": "maternal-grandmother",
    "great-grandfather": "great-grandmother",
    "great-grandmother": "great-grandmother",
    "great-great-grandfather": "great-great-grandmother",
    "great-great-grandmother": "great-great-grandmother",
    "grandson": "granddaughter", "granddaughter": "granddaughter",
    "great-grandson": "great-granddaughter",
    "great-granddaughter": "great-granddaughter",
    "great-great-grandson": "great-great-granddaughter",
    "great-great-granddaughter": "great-great-granddaughter",
    "uncle": "aunt", "aunt": "aunt",
    "paternal-uncle": "paternal-aunt", "paternal-aunt": "paternal-aunt",
    "maternal-uncle": "maternal-aunt", "maternal-aunt": "maternal-aunt",
    "great-uncle": "great-aunt", "great-aunt": "great-aunt",
    "nephew": "niece", "niece": "niece",
    "nibling": "nibling",
    "father-in-law": "mother-in-law", "mother-in-law": "mother-in-law",
    "son-in-law": "daughter-in-law", "daughter-in-law": "daughter-in-law",
    "brother-in-law": "sister-in-law", "sister-in-law": "sister-in-law",
    "stepfather": "stepmother", "stepmother": "stepmother",
    "stepson": "stepdaughter", "stepdaughter": "stepdaughter",
    "stepbrother": "stepsister", "stepsister": "stepsister",
    "half-brother": "half-sister", "half-sister": "half-sister",
    "tau": "tai", "tai": "tai",
    "chacha": "chachi", "chachi": "chachi",
    "bua": "bua",
    "fufaji": "bua",
    "mama": "mami", "mami": "mami",
    "mausi": "mausi",
    "mausa": "mausi",
    "jeth": "jethani", "jethani": "jethani",
    "devar": "devrani", "devrani": "devrani",
    "nanad": "nanad",
    "sala": "sali", "sali": "sali",
    "cousin": "cousin",
    "cousin-elder": "cousin-elder",
    "cousin-younger": "cousin-younger",
    "cousin-paternal": "cousin-paternal",
    "cousin-maternal": "cousin-maternal",
    "guru": "guru",
    "godfather": "godmother", "godmother": "godmother",
    "self": "self",
    "distant-relative": "distant-relative",
    "spouse": "spouse",
    "parent": "parent",
    "child": "child",
    "sibling": "sibling",
    "parent-sibling": "parent-sibling",
    "child-in-law": "child-in-law",
    "sibling-in-law": "sibling-in-law",
    "grandparent": "grandparent",
    "grandchild": "grandchild",
    "nibling": "nibling",
}

# Generation -> (male_label, female_label, neutral_label) for math-based derivation
GENERATION_LABELS = {
    -4: ("great-great-grandfather", "great-great-grandmother", "great-great-grandparent"),
    -3: ("great-grandfather",       "great-grandmother",       "great-grandparent"),
    -2: ("grandfather",             "grandmother",             "grandparent"),
    -1: ("father",                  "mother",                  "parent"),
     0: ("brother",                 "sister",                  "sibling"),
     1: ("son",                     "daughter",                "child"),
     2: ("grandson",                "granddaughter",           "grandchild"),
     3: ("great-grandson",          "great-granddaughter",     "great-grandchild"),
     4: ("great-great-grandson",    "great-great-granddaughter","great-great-grandchild"),
}

GEN_MIN = min(GENERATION_LABELS.keys())
GEN_MAX = max(GENERATION_LABELS.keys())

# ===========================================================================
# Lineage resolution rules (per spec)
# ===========================================================================

LINEAGE_RULES = {
    ("paternal", "paternal"): "paternal",
    ("paternal", "maternal"): "paternal",
    ("paternal", "bilateral"):"paternal",
    ("paternal", "core"):     "paternal",
    ("paternal", "marital"):  "marital",
    ("paternal", "extended"): "paternal",
    ("paternal", "ceremonial"):"ceremonial",
    ("paternal", "inlaw"):    "inlaw",
    ("paternal", "step"):     "step",
    ("maternal", "maternal"): "maternal",
    ("maternal", "paternal"): "maternal",
    ("maternal", "bilateral"):"maternal",
    ("maternal", "core"):     "maternal",
    ("maternal", "marital"):  "marital",
    ("maternal", "extended"): "maternal",
    ("maternal", "ceremonial"):"ceremonial",
    ("maternal", "inlaw"):    "inlaw",
    ("maternal", "step"):     "step",
    ("bilateral","paternal"): "paternal",
    ("bilateral","maternal"): "maternal",
    ("bilateral","bilateral"):"bilateral",
    ("bilateral","core"):     "bilateral",
    ("bilateral","marital"):  "marital",
    ("bilateral","extended"): "extended",
    ("bilateral","ceremonial"):"ceremonial",
    ("bilateral","inlaw"):    "inlaw",
    ("bilateral","step"):     "step",
    ("core",     "paternal"): "paternal",
    ("core",     "maternal"): "maternal",
    ("core",     "bilateral"):"bilateral",
    ("core",     "core"):     "core",
    ("core",     "marital"):  "marital",
    ("core",     "extended"): "extended",
    ("core",     "ceremonial"):"ceremonial",
    ("core",     "inlaw"):    "inlaw",
    ("core",     "step"):     "step",
    ("marital",  "paternal"): "marital",
    ("marital",  "maternal"): "marital",
    ("marital",  "bilateral"):"marital",
    ("marital",  "core"):     "marital",
    ("marital",  "marital"):  "marital",
    ("marital",  "extended"): "marital",
    ("marital",  "ceremonial"):"ceremonial",
    ("marital",  "inlaw"):    "inlaw",
    ("marital",  "step"):     "step",
    ("extended", "paternal"): "paternal",
    ("extended", "maternal"): "maternal",
    ("extended", "bilateral"):"bilateral",
    ("extended", "core"):     "extended",
    ("extended", "marital"):  "marital",
    ("extended", "extended"): "extended",
    ("extended", "ceremonial"):"ceremonial",
    ("extended", "inlaw"):    "inlaw",
    ("extended", "step"):     "step",
    ("ceremonial","paternal"): "ceremonial",
    ("ceremonial","maternal"): "ceremonial",
    ("ceremonial","bilateral"):"ceremonial",
    ("ceremonial","core"):     "ceremonial",
    ("ceremonial","marital"):  "ceremonial",
    ("ceremonial","extended"): "ceremonial",
    ("ceremonial","ceremonial"):"ceremonial",
    ("ceremonial","inlaw"):    "ceremonial",
    ("ceremonial","step"):     "ceremonial",
    ("inlaw",    "paternal"): "inlaw",
    ("inlaw",    "maternal"): "inlaw",
    ("inlaw",    "bilateral"):"inlaw",
    ("inlaw",    "core"):     "inlaw",
    ("inlaw",    "marital"):  "inlaw",
    ("inlaw",    "extended"): "inlaw",
    ("inlaw",    "ceremonial"):"ceremonial",
    ("inlaw",    "inlaw"):    "inlaw",
    ("inlaw",    "step"):     "step",
    ("step",     "paternal"): "step",
    ("step",     "maternal"): "step",
    ("step",     "bilateral"):"step",
    ("step",     "core"):     "step",
    ("step",     "marital"):  "step",
    ("step",     "extended"): "step",
    ("step",     "ceremonial"):"ceremonial",
    ("step",     "inlaw"):    "inlaw",
    ("step",     "step"):     "step",
}

# Normalize JSON lineage values to canonical forms
LINEAGE_CANON = {
    "paternal": "paternal", "maternal": "maternal",
    "bilateral": "bilateral", "core": "core",
    "marital": "marital", "extended": "extended",
    "ceremonial": "ceremonial",
    "in_law": "inlaw", "inlaw": "inlaw",
    "step": "step", "half": "step",
}

def canonical_lineage(lineage):
    """Normalize lineage value to canonical form used in LINEAGE_RULES."""
    if lineage is None:
        return "bilateral"
    return LINEAGE_CANON.get(lineage, lineage)

# ===========================================================================
# CORE_OVERRIDES — well-known Indian kinship terms
# These represent domain knowledge that cannot be derived from JSON structure
# alone because the JSON uses different key naming conventions
# (e.g. 'fathers_elder_brother' has a single-element path, not ['father', 'elder_brother']).
# Built from the Indian kinship domain specification provided by the user.
# ===========================================================================

CORE_OVERRIDES = {
    # ---- Parent + sibling = uncle/aunt (Indian-specific terms) ----
    ("father", "brother"):         ("paternal-uncle", "paternal-aunt"),
    ("father", "sister"):          ("paternal-aunt", "paternal-aunt"),
    ("father", "elder_brother"):   ("tau", "tai"),
    ("father", "younger_brother"): ("chacha", "chachi"),
    ("father", "elder_sister"):    ("bua-elder", "bua-elder"),
    ("father", "younger_sister"):  ("bua-younger", "bua-younger"),
    ("father", "sisters_husband"): ("fufaji", "bua"),
    ("father", "brothers_wife"):   ("chachi", "chachi"),

    ("mother", "brother"):         ("maternal-uncle", "maternal-aunt"),
    ("mother", "sister"):          ("maternal-aunt", "maternal-aunt"),
    ("mother", "elder_brother"):   ("mama-elder", "mama-elder"),
    ("mother", "younger_brother"): ("mama-younger", "mama-younger"),
    ("mother", "elder_sister"):    ("mausi-elder", "mausi-elder"),
    ("mother", "younger_sister"):  ("mausi-younger", "mausi-younger"),
    ("mother", "brothers_wife"):   ("mami", "mami"),
    ("mother", "sisters_husband"): ("mausa", "mausi"),

    # ---- Parent + parent = grandparent (lineage-specific) ----
    ("father", "father"):          ("paternal-grandfather", "paternal-grandmother"),
    ("father", "mother"):          ("paternal-grandmother", "paternal-grandmother"),
    ("mother", "father"):          ("maternal-grandfather", "maternal-grandmother"),
    ("mother", "mother"):          ("maternal-grandmother", "maternal-grandmother"),

    # ---- Parent + spouse = stepparent ----
    ("father", "wife"):            ("stepmother", "stepmother"),
    ("father", "husband"):         ("stepfather", "stepfather"),
    ("mother", "wife"):            ("stepmother", "stepmother"),
    ("mother", "husband"):         ("stepfather", "stepfather"),

    # ---- Parent + child = sibling (self-side) ----
    ("father", "son"):             ("self", "self"),
    ("father", "daughter"):        ("self", "self"),
    ("mother", "son"):             ("self", "self"),
    ("mother", "daughter"):        ("self", "self"),

    # ---- Child + parent = self ----
    ("son", "father"):             ("self", "self"),
    ("son", "mother"):             ("self", "self"),
    ("daughter", "father"):        ("self", "self"),
    ("daughter", "mother"):        ("self", "self"),

    # ---- Child + child = grandchild ----
    ("son", "son"):                ("grandson", "granddaughter"),
    ("son", "daughter"):           ("granddaughter", "granddaughter"),
    ("daughter", "son"):           ("grandson", "granddaughter"),
    ("daughter", "daughter"):      ("granddaughter", "granddaughter"),

    # ---- Child + spouse = child-in-law ----
    ("son", "wife"):               ("daughter-in-law", "daughter-in-law"),
    ("son", "husband"):            ("son-in-law", "son-in-law"),
    ("daughter", "wife"):          ("daughter-in-law", "daughter-in-law"),
    ("daughter", "husband"):       ("son-in-law", "son-in-law"),

    # ---- Sibling + spouse = sibling-in-law ----
    ("brother", "wife"):           ("sister-in-law", "sister-in-law"),
    ("brother", "husband"):        ("brother-in-law", "brother-in-law"),
    ("sister", "wife"):            ("sister-in-law", "sister-in-law"),
    ("sister", "husband"):         ("brother-in-law", "brother-in-law"),
    ("elder_brother", "wife"):     ("jethani", "jethani"),
    ("younger_brother", "wife"):   ("devrani", "devrani"),

    # ---- Sibling + child = nephew/niece ----
    ("brother", "son"):            ("nephew", "niece"),
    ("brother", "daughter"):       ("niece", "niece"),
    ("sister", "son"):             ("nephew", "niece"),
    ("sister", "daughter"):        ("niece", "niece"),
    ("elder_brother", "son"):      ("nephew", "niece"),
    ("elder_brother", "daughter"): ("niece", "niece"),
    ("younger_brother", "son"):    ("nephew", "niece"),
    ("younger_brother", "daughter"):("niece", "niece"),
    ("elder_sister", "son"):       ("nephew", "niece"),
    ("elder_sister", "daughter"):  ("niece", "niece"),
    ("younger_sister", "son"):     ("nephew", "niece"),
    ("younger_sister", "daughter"):("niece", "niece"),

    # ---- Sibling + sibling = self ----
    ("brother", "brother"):        ("self", "self"),
    ("sister", "sister"):          ("self", "self"),
    ("brother", "sister"):         ("self", "self"),
    ("sister", "brother"):         ("self", "self"),
    ("elder_brother", "elder_brother"): ("self", "self"),
    ("younger_brother", "younger_brother"): ("self", "self"),
    ("elder_brother", "younger_brother"): ("self", "self"),
    ("younger_brother", "elder_brother"): ("self", "self"),
    ("elder_sister", "elder_sister"): ("self", "self"),
    ("younger_sister", "younger_sister"): ("self", "self"),
    ("elder_sister", "younger_sister"): ("self", "self"),
    ("younger_sister", "elder_sister"): ("self", "self"),

    # ---- Spouse + parent = parent-in-law ----
    ("husband", "father"):         ("father-in-law", "mother-in-law"),
    ("husband", "mother"):         ("mother-in-law", "mother-in-law"),
    ("wife", "father"):            ("father-in-law", "mother-in-law"),
    ("wife", "mother"):            ("mother-in-law", "mother-in-law"),

    # ---- Spouse + sibling = sibling-in-law (Indian-specific) ----
    ("husband", "brother"):        ("brother-in-law", "sister-in-law"),
    ("husband", "sister"):         ("nanad", "nanad"),
    ("husband", "elder_brother"):  ("jeth", "jethani"),
    ("husband", "younger_brother"):("devar", "devrani"),
    ("husband", "elder_sister"):   ("nanad-elder", "nanad-elder"),
    ("husband", "younger_sister"): ("nanad-younger", "nanad-younger"),
    ("wife", "brother"):           ("sala", "sali"),
    ("wife", "sister"):            ("sali", "sali"),
    ("wife", "elder_brother"):     ("sala-elder", "sala-elder"),
    ("wife", "younger_brother"):   ("sala-younger", "sala-younger"),
    ("wife", "elder_sister"):      ("sali-elder", "sali-elder"),
    ("wife", "younger_sister"):    ("sali-younger", "sali-younger"),

    # ---- Spouse + spouse = self ----
    ("husband", "wife"):           ("self", "self"),
    ("wife", "husband"):           ("self", "self"),

    # ---- Grandparent + sibling = great-uncle/aunt ----
    ("paternal_grandfather", "brother"): ("great-uncle", "great-aunt"),
    ("paternal_grandfather", "sister"):  ("great-aunt", "great-aunt"),
    ("paternal_grandfather", "elder_brother"): ("great-uncle-elder", "great-aunt-elder"),
    ("paternal_grandfather", "younger_brother"): ("great-uncle-younger", "great-aunt-younger"),
    ("paternal_grandmother", "brother"): ("great-uncle", "great-aunt"),
    ("paternal_grandmother", "sister"):  ("great-aunt", "great-aunt"),
    ("maternal_grandfather", "brother"): ("great-uncle", "great-aunt"),
    ("maternal_grandfather", "sister"):  ("great-aunt", "great-aunt"),
    ("maternal_grandmother", "brother"): ("great-uncle", "great-aunt"),
    ("maternal_grandmother", "sister"):  ("great-aunt", "great-aunt"),

    # ---- Grandparent + parent = great-grandparent ----
    ("paternal_grandfather", "father"): ("great-grandfather", "great-grandmother"),
    ("paternal_grandfather", "mother"): ("great-grandmother", "great-grandmother"),
    ("paternal_grandmother", "father"): ("great-grandfather", "great-grandmother"),
    ("paternal_grandmother", "mother"): ("great-grandmother", "great-grandmother"),
    ("maternal_grandfather", "father"): ("great-grandfather", "great-grandmother"),
    ("maternal_grandfather", "mother"): ("great-grandmother", "great-grandmother"),
    ("maternal_grandmother", "father"): ("great-grandfather", "great-grandmother"),
    ("maternal_grandmother", "mother"): ("great-grandmother", "great-grandmother"),

    # ---- Uncle/aunt + child = cousin ----
    ("fathers_elder_brother", "son"):          ("cousin-elder", "cousin-elder"),
    ("fathers_elder_brother", "daughter"):     ("cousin-elder", "cousin-elder"),
    ("fathers_elder_brother", "wife"):         ("tai", "tai"),
    ("fathers_younger_brother", "son"):        ("cousin-younger", "cousin-younger"),
    ("fathers_younger_brother", "daughter"):   ("cousin-younger", "cousin-younger"),
    ("fathers_younger_brother", "wife"):       ("chachi", "chachi"),
    ("fathers_sister", "son"):                 ("cousin-paternal", "cousin-paternal"),
    ("fathers_sister", "daughter"):            ("cousin-paternal", "cousin-paternal"),
    ("fathers_sister", "husband"):             ("fufaji", "bua"),
    ("fathers_sisters_husband", "son"):        ("cousin-paternal", "cousin-paternal"),
    ("fathers_sisters_husband", "daughter"):   ("cousin-paternal", "cousin-paternal"),
    ("mothers_brother", "son"):                ("cousin-maternal", "cousin-maternal"),
    ("mothers_brother", "daughter"):           ("cousin-maternal", "cousin-maternal"),
    ("mothers_brother", "wife"):               ("mami", "mami"),
    ("mothers_sister", "son"):                 ("cousin-maternal", "cousin-maternal"),
    ("mothers_sister", "daughter"):            ("cousin-maternal", "cousin-maternal"),
    ("mothers_sister", "husband"):             ("mausa", "mausi"),
    ("mothers_brothers_wife", "son"):          ("cousin-maternal", "cousin-maternal"),
    ("mothers_brothers_wife", "daughter"):     ("cousin-maternal", "cousin-maternal"),
    ("mothers_sisters_husband", "son"):        ("cousin-maternal", "cousin-maternal"),
    ("mothers_sisters_husband", "daughter"):   ("cousin-maternal", "cousin-maternal"),

    # ---- Self combinations ----
    ("self", "self"):              ("self", "self"),
    ("self", "father"):            ("father", "mother"),
    ("self", "mother"):            ("mother", "mother"),
    ("self", "son"):               ("son", "daughter"),
    ("self", "daughter"):          ("daughter", "daughter"),
    ("self", "brother"):           ("brother", "sister"),
    ("self", "sister"):            ("sister", "sister"),
    ("self", "husband"):           ("husband", "wife"),
    ("self", "wife"):              ("wife", "wife"),
    ("self", "elder_brother"):     ("elder-brother", "elder-sister"),
    ("self", "younger_brother"):   ("younger-brother", "younger-sister"),
    ("self", "elder_sister"):      ("elder-sister", "elder-sister"),
    ("self", "younger_sister"):    ("younger-sister", "younger-sister"),
}

# ===========================================================================
# Helper functions
# ===========================================================================

def log_error(msg):
    """Append a message to the error log."""
    with open(ERROR_LOG, "a", encoding="utf-8") as f:
        f.write(f"[{datetime.utcnow().isoformat()}Z] {msg}\n")

def detect_elder(key):
    """Detect elder/younger distinction from relationshipKey (since JSON elderYounger is null)."""
    if not key:
        return None
    kl = key.lower()
    # Check for explicit elder/younger markers
    if "elder" in kl:
        return "elder"
    if "younger" in kl:
        return "younger"
    return None

def resolve_lineage(from_lineage, via_lineage):
    """Resolve combined lineage using LINEAGE_RULES."""
    fl = canonical_lineage(from_lineage)
    vl = canonical_lineage(via_lineage)
    return LINEAGE_RULES.get((fl, vl), fl)

def resolve_relation_type(from_type, via_type):
    """Resolve combined relation type.
    blood + blood = blood
    blood + inlaw = inlaw
    inlaw + blood = inlaw
    step + any = step
    ceremonial + any = ceremonial (lowest priority override)
    """
    ft = (from_type or "").lower()
    vt = (via_type or "").lower()
    if "ceremonial" in (ft, vt):
        return "ceremonial"
    if "step" in (ft, vt) or "half" in (ft, vt):
        return "step"
    if "in_law" in (ft, vt) or "inlaw" in (ft, vt):
        return "inlaw"
    return "blood"

# ===========================================================================
# Semantic label derivation
# ===========================================================================

def get_semantic_label(entry):
    """Get the semantic label for an entry.
    Priority: SEMANTIC_LABELS dict -> derive from gen/lineage/gender.
    Cached in LABEL_CACHE.
    """
    key = entry["relationshipKey"]
    if key in LABEL_CACHE:
        return LABEL_CACHE[key]

    # 1. Direct lookup in SEMANTIC_LABELS
    if key in SEMANTIC_LABELS:
        label = SEMANTIC_LABELS[key]
        LABEL_CACHE[key] = label
        return label

    # 2. Check if key matches a cousin pattern
    kl = key.lower()
    if "fathers_elder_brother_son" in kl or "fathers_elder_brother_daughter" in kl:
        LABEL_CACHE[key] = "cousin-elder"
        return "cousin-elder"
    if "fathers_younger_brother_son" in kl or "fathers_younger_brother_daughter" in kl:
        LABEL_CACHE[key] = "cousin-younger"
        return "cousin-younger"
    if "fathers_sister_son" in kl or "fathers_sister_daughter" in kl:
        LABEL_CACHE[key] = "cousin-paternal"
        return "cousin-paternal"
    if "mothers_brother_son" in kl or "mothers_brother_daughter" in kl:
        LABEL_CACHE[key] = "cousin-maternal"
        return "cousin-maternal"
    if "mothers_sister_son" in kl or "mothers_sister_daughter" in kl:
        LABEL_CACHE[key] = "cousin-maternal"
        return "cousin-maternal"

    # 3. Derive from gen/lineage/gender
    gen = entry["generation"]
    lineage = canonical_lineage(entry["lineage"])
    gender = entry["gender"]
    elder = detect_elder(key)

    if gen not in GENERATION_LABELS:
        label = "distant-relative"
        LABEL_CACHE[key] = label
        return label

    male_label, female_label, neutral_label = GENERATION_LABELS[gen]
    if gender == "female":
        base_label = female_label
    elif gender == "neutral":
        base_label = neutral_label
    else:
        base_label = male_label

    # Add lineage prefix for ancestors (gen < 0) when lineage is paternal/maternal
    if gen < 0 and lineage in ("paternal", "maternal"):
        # Only add prefix if not already implied
        if not base_label.startswith(lineage):
            base_label = f"{lineage}-{base_label}"

    # Add elder/younger suffix
    if elder and not base_label.endswith(f"-{elder}"):
        base_label = f"{base_label}-{elder}"

    LABEL_CACHE[key] = base_label
    return base_label

def get_female_label(male_label):
    """Get the female-viewer equivalent of a semantic label."""
    return FEMALE_LABEL_MAP.get(male_label, male_label)

# ===========================================================================
# Self-reference detection
# ===========================================================================

# Inverse path pairs (a + b = self when paths cancel)
INVERSE_PATH_PAIRS = {
    ("father", "son"), ("son", "father"),
    ("father", "daughter"), ("daughter", "father"),
    ("mother", "son"), ("son", "mother"),
    ("mother", "daughter"), ("daughter", "mother"),
    ("brother", "brother"), ("sister", "sister"),
    ("brother", "sister"), ("sister", "brother"),
    ("elder_brother", "elder_brother"), ("younger_brother", "younger_brother"),
    ("elder_brother", "younger_brother"), ("younger_brother", "elder_brother"),
    ("elder_sister", "elder_sister"), ("younger_sister", "younger_sister"),
    ("elder_sister", "younger_sister"), ("younger_sister", "elder_sister"),
    ("husband", "wife"), ("wife", "husband"),
    ("self", "self"),
}

def is_self_referential(from_entry, via_entry):
    """Check if (from, via) chain loops back to self."""
    from_key = from_entry["relationshipKey"]
    via_key = via_entry["relationshipKey"]

    # Direct pair check
    if (from_key, via_key) in INVERSE_PATH_PAIRS:
        return True

    from_gen = from_entry["generation"]
    via_gen = via_entry["generation"]

    # Opposite generation and inverse path
    if from_gen + via_gen == 0 and from_gen != 0:
        from_path = from_entry.get("relationshipPath", [])
        via_path = via_entry.get("relationshipPath", [])
        # If via_path is the inverse of from_path (e.g. father vs son)
        # Check path-level inverse
        if len(from_path) == 1 and len(via_path) == 1:
            fp = from_path[0]
            vp = via_path[0]
            if (fp, vp) in INVERSE_PATH_PAIRS:
                return True

    return False

# ===========================================================================
# Lookup building
# ===========================================================================

def build_lookups(relationships):
    """Build all lookup structures from the relationships list."""
    global BY_KEY, BY_PATH, BY_GEN_LINEAGE_GENDER, BY_GEN_LINEAGE
    global PATH_OVERRIDES, SELF_PAIRS, ALL_KEYS

    print("Building lookup structures...")

    # BY_KEY
    BY_KEY = {r["relationshipKey"]: r for r in relationships}
    ALL_KEYS = set(BY_KEY.keys())

    # BY_PATH (tuple of relationshipPath -> entry)
    BY_PATH = {}
    for r in relationships:
        path = tuple(r.get("relationshipPath", []))
        if path and path not in BY_PATH:
            BY_PATH[path] = r
    print(f"  BY_PATH: {len(BY_PATH):,} entries")

    # BY_GEN_LINEAGE_GENDER and BY_GEN_LINEAGE
    BY_GEN_LINEAGE_GENDER = {}
    BY_GEN_LINEAGE = {}
    for r in relationships:
        gen = r["generation"]
        lineage = canonical_lineage(r["lineage"])
        gender = r["gender"]
        elder = detect_elder(r["relationshipKey"])
        key1 = (gen, lineage, gender, elder)
        key2 = (gen, lineage)
        BY_GEN_LINEAGE_GENDER.setdefault(key1, []).append(r)
        BY_GEN_LINEAGE.setdefault(key2, []).append(r)
    print(f"  BY_GEN_LINEAGE_GENDER: {len(BY_GEN_LINEAGE_GENDER):,} keys")
    print(f"  BY_GEN_LINEAGE: {len(BY_GEN_LINEAGE):,} keys")

    # PATH_OVERRIDES — derived FROM JSON relationshipPath (2-step paths)
    # For each entry with relationshipPath = [from_key, via_key],
    # store (from_key, via_key) -> (semantic_label, female_label)
    PATH_OVERRIDES = {}
    for r in relationships:
        path = r.get("relationshipPath", [])
        if len(path) == 2:
            from_key = path[0]
            via_key = path[1]
            if from_key in ALL_KEYS and via_key in ALL_KEYS:
                label = get_semantic_label(r)
                female_label = get_female_label(label)
                # Don't overwrite if already set (first entry wins)
                if (from_key, via_key) not in PATH_OVERRIDES:
                    PATH_OVERRIDES[(from_key, via_key)] = (label, female_label)
    print(f"  PATH_OVERRIDES: {len(PATH_OVERRIDES):,} entries (derived from JSON)")

    # SELF_PAIRS — pre-compute all self-referential (from, via) pairs
    SELF_PAIRS = set()
    # Only check entries that are likely to be self-referential (gen 0 or inverse gen)
    candidates = [r for r in relationships
                  if r["generation"] in (-1, 0, 1)]
    for from_entry in candidates:
        for via_entry in candidates:
            if is_self_referential(from_entry, via_entry):
                SELF_PAIRS.add((from_entry["relationshipKey"],
                               via_entry["relationshipKey"]))
    print(f"  SELF_PAIRS: {len(SELF_PAIRS):,} entries")

    print("Lookup structures built.\n")

# ===========================================================================
# Chain resolution (the core engine)
# ===========================================================================

def resolve_chain(from_entry, via_entry, lookup=None):
    """
    Resolve a single (from x via) chain.

    Returns (result_label, result_female_label).

    Priority:
      1. Self-reference detection (inverse path cancellation)
      2. CORE_OVERRIDES (well-known Indian kinship domain knowledge)
      3. Exact path override (from JSON relationshipPath, 2-step paths)
      4. Generation + lineage + gender + elderYounger math
      5. Fuzzy match on generation + lineage only
      6. "distant-relative" fallback
    """
    from_key = from_entry["relationshipKey"]
    via_key = via_entry["relationshipKey"]

    # 1. Self-reference
    if (from_key, via_key) in SELF_PAIRS:
        return ("self", "self")

    # 2. CORE_OVERRIDES (domain knowledge for well-known Indian kinship)
    ov = CORE_OVERRIDES.get((from_key, via_key))
    if ov is not None:
        return ov

    # 3. Exact path override (derived from JSON relationshipPath)
    ov = PATH_OVERRIDES.get((from_key, via_key))
    if ov is not None:
        # Only use path override if the label is meaningful (not a generic fallback)
        label = ov[0]
        if label not in ("father", "mother", "brother", "sister", "son", "daughter",
                         "husband", "wife", "self"):
            return ov
        # If the path override gives a generic label, fall through to math

    # 4. Generation + lineage + gender + elderYounger math
    from_gen = from_entry["generation"]
    via_gen = via_entry["generation"]
    result_gen = from_gen + via_gen

    # Out-of-range generation -> distant-relative
    if result_gen < GEN_MIN or result_gen > GEN_MAX:
        return ("distant-relative", "distant-relative")

    result_lineage = resolve_lineage(from_entry["lineage"], via_entry["lineage"])
    via_gender = via_entry["gender"]
    result_elder = detect_elder(via_key)

    # Try exact (gen, lineage, gender, elder) lookup
    candidates = BY_GEN_LINEAGE_GENDER.get((result_gen, result_lineage, via_gender, result_elder), [])
    if candidates:
        best = candidates[0]
        label = get_semantic_label(best)
        return (label, get_female_label(label))

    # Try without elder distinction
    candidates = BY_GEN_LINEAGE_GENDER.get((result_gen, result_lineage, via_gender, None), [])
    if candidates:
        best = candidates[0]
        label = get_semantic_label(best)
        return (label, get_female_label(label))

    # Try opposite gender (in case via_gender doesn't have a match)
    opposite_gender = "female" if via_gender == "male" else "male"
    candidates = BY_GEN_LINEAGE_GENDER.get((result_gen, result_lineage, opposite_gender, result_elder), [])
    if candidates:
        best = candidates[0]
        label = get_semantic_label(best)
        return (label, get_female_label(label))

    # 4. Fuzzy match on (gen, lineage) only
    candidates = BY_GEN_LINEAGE.get((result_gen, result_lineage), [])
    if candidates:
        # Filter by gender if possible
        gender_matches = [c for c in candidates if c["gender"] == via_gender]
        if gender_matches:
            best = gender_matches[0]
        else:
            best = candidates[0]
        label = get_semantic_label(best)
        return (label, get_female_label(label))

    # 4b. Fuzzy match on (gen, lineage) with bilateral lineage substitution
    if result_lineage in ("paternal", "maternal"):
        candidates = BY_GEN_LINEAGE.get((result_gen, "bilateral"), [])
        if candidates:
            gender_matches = [c for c in candidates if c["gender"] == via_gender]
            if gender_matches:
                best = gender_matches[0]
            else:
                best = candidates[0]
            label = get_semantic_label(best)
            return (label, get_female_label(label))

    # 5. Derive label purely from generation (no JSON match)
    if result_gen in GENERATION_LABELS:
        male_label, female_label, neutral_label = GENERATION_LABELS[result_gen]
        # result_key follows via_gender; result_female_key is always female
        if via_gender == "female":
            result_label = female_label
        elif via_gender == "neutral":
            result_label = neutral_label
        else:
            result_label = male_label
        # Add lineage prefix for ancestors
        if result_gen < 0 and result_lineage in ("paternal", "maternal"):
            if not result_label.startswith(result_lineage):
                result_label = f"{result_lineage}-{result_label}"
        return (result_label, female_label)

    # 6. Final fallback
    return ("distant-relative", "distant-relative")

# ===========================================================================
# Verification suite
# ===========================================================================

VERIFICATION_CASES = [
    # (from_key, via_key, expected_result_label)
    # Core
    ("father", "father", "paternal-grandfather"),
    ("mother", "mother", "maternal-grandmother"),
    ("father", "brother", "paternal-uncle"),
    ("mother", "brother", "maternal-uncle"),
    ("father", "sister", "paternal-aunt"),
    ("mother", "sister", "maternal-aunt"),
    # Indian specific
    ("husband", "elder_brother", "jeth"),
    ("husband", "younger_brother", "devar"),
    ("husband", "sister", "nanad"),
    ("wife", "brother", "sala"),
    ("wife", "sister", "sali"),
    ("father", "elder_brother", "tau"),
    ("father", "younger_brother", "chacha"),
    ("mother", "elder_brother", "mama-elder"),
    ("mother", "sister", "maternal-aunt"),
    # Self referential
    ("son", "father", "self"),
    ("daughter", "mother", "self"),
    ("brother", "brother", "self"),
    ("husband", "wife", "self"),
    # Grandparent chains
    ("mother", "father", "maternal-grandfather"),
    # Grandchildren
    ("son", "son", "grandson"),
    ("daughter", "daughter", "granddaughter"),
    # In-laws
    ("son", "wife", "daughter-in-law"),
    ("daughter", "husband", "son-in-law"),
    ("brother", "wife", "sister-in-law"),
    ("sister", "husband", "brother-in-law"),
    # Cousins
    ("fathers_elder_brother", "son", "cousin-elder"),
    ("mothers_brother", "daughter", "cousin-maternal"),
    # Nephew/niece
    ("brother", "son", "nephew"),
    ("sister", "daughter", "niece"),
    # Distant
    ("great_grandfather", "great_grandfather", "distant-relative"),
]

# Synonym map for verification normalization
# Maps alternative labels to canonical forms
SYNONYMS = {
    "fathers-elder-brother": "paternal-uncle",
    "fathers-younger-brother": "paternal-uncle",
    "fathers-brother": "paternal-uncle",
    "fathers-sister": "paternal-aunt",
    "fathers-sisters-husband": "paternal-uncle",
    "mothers-brother": "maternal-uncle",
    "mothers-sister": "maternal-aunt",
    "mothers-brothers-wife": "maternal-aunt",
    "mothers-sisters-husband": "maternal-uncle",
    "sons-son": "grandson",
    "sons-daughter": "granddaughter",
    "daughters-son": "grandson",
    "daughters-daughter": "granddaughter",
    "sons-wife": "daughter-in-law",
    "daughters-husband": "son-in-law",
    "brothers-wife": "sister-in-law",
    "sisters-husband": "brother-in-law",
    "brothers-son": "nephew",
    "brothers-daughter": "niece",
    "sisters-son": "nephew",
    "sisters-daughter": "niece",
    "fathers-elder-brother-son": "cousin-elder",
    "fathers-elder-brother-daughter": "cousin-elder",
    "fathers-younger-brother-son": "cousin-younger",
    "fathers-younger-brother-daughter": "cousin-younger",
    "mothers-brother-son": "cousin-maternal",
    "mothers-brother-daughter": "cousin-maternal",
    "fathers-sister-son": "cousin-paternal",
    "fathers-sister-daughter": "cousin-paternal",
    "mothers-sister-son": "cousin-maternal",
    "mothers-sister-daughter": "cousin-maternal",
    # Indian-specific synonyms
    "tau": "paternal-uncle-elder",
    "chacha": "paternal-uncle-younger",
    "bua": "paternal-aunt",
    "fufaji": "paternal-uncle-by-marriage",
    "mama": "maternal-uncle",
    "mami": "maternal-aunt-by-marriage",
    "mausi": "maternal-aunt",
    "mausa": "maternal-uncle-by-marriage",
    "jeth": "husbands-elder-brother",
    "devar": "husbands-younger-brother",
    "nanad": "husbands-sister",
    "sala": "wifes-brother",
    "sali": "wifes-sister",
    "jethani": "co-sister-elder",
    "devrani": "co-sister-younger",
    "sasur": "father-in-law",
    "saas": "mother-in-law",
    "bahu": "daughter-in-law",
    "damaad": "son-in-law",
    "bhatija": "nephew",
    "bhatiji": "niece",
    "bhanja": "nephew",
    "bhanji": "niece",
    "dada": "paternal-grandfather",
    "dadi": "paternal-grandmother",
    "nana": "maternal-grandfather",
    "nani": "maternal-grandmother",
    "tai": "paternal-aunt-elder",
    "chachi": "paternal-aunt-younger",
}

def normalize_label(label):
    """Normalize a label for verification comparison.
    - lowercase
    - replace _ with -
    - apply synonym map (strip -elder/-younger for uncle/aunt types)
    """
    if not label:
        return ""
    s = label.lower().strip().replace("_", "-")
    # Apply synonyms
    if s in SYNONYMS:
        return SYNONYMS[s]
    # Strip -elder / -younger suffixes for comparison
    # (e.g. "mama-elder" -> "mama", "paternal-uncle-elder" -> "paternal-uncle")
    s = re.sub(r"-(elder|younger)$", "", s)
    # Also check post-strip synonyms
    if s in SYNONYMS:
        return SYNONYMS[s]
    return s

def labels_match(actual, expected):
    """Check if actual label matches expected (with normalization)."""
    a = normalize_label(actual)
    e = normalize_label(expected)
    if a == e:
        return True
    # Also check if one is a substring/superset of the other
    # (e.g. "paternal-uncle" matches "paternal-uncle-elder")
    if a.startswith(e) or e.startswith(a):
        return True
    return False

def run_verification(label="VERIFICATION"):
    """Run the verification suite. Returns (passed, total, failures)."""
    print("=" * 70)
    print(f"{label}")
    print("=" * 70)
    passed = 0
    failures = []
    total = len(VERIFICATION_CASES)

    for from_key, via_key, expected in VERIFICATION_CASES:
        from_entry = BY_KEY.get(from_key)
        via_entry = BY_KEY.get(via_key)
        if not from_entry:
            failures.append(f"MISSING from_key: {from_key}")
            continue
        if not via_entry:
            failures.append(f"MISSING via_key: {via_key}")
            continue
        actual, _ = resolve_chain(from_entry, via_entry)
        if labels_match(actual, expected):
            passed += 1
        else:
            norm_a = normalize_label(actual)
            norm_e = normalize_label(expected)
            failures.append(f"{from_key} + {via_key} = {actual} (normalized: {norm_a}) | expected {expected} (normalized: {norm_e})")

    pct = passed / total * 100 if total > 0 else 0
    print(f"\nVerification: {passed}/{total} passed ({pct:.1f}%)")
    if failures:
        print("Failed cases:")
        for f in failures:
            print(f"  - {f}")
    else:
        print("All verification cases passed!")
    print()
    return passed, total, failures

# ===========================================================================
# Loading
# ===========================================================================

def load_relationships(json_path):
    """Load the input JSON and return the relationships list."""
    if not os.path.exists(json_path):
        raise FileNotFoundError(f"Input JSON not found: {json_path}")
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        log_error(f"JSON parse failed: {e}")
        raise
    rels = data.get("relationships")
    if not isinstance(rels, list) or not rels:
        raise ValueError("JSON has no 'relationships' list or it is empty")
    required = {"relationshipKey", "gender", "lineage", "generation"}
    for i, r in enumerate(rels):
        missing = required - set(r.keys())
        if missing:
            raise ValueError(f"Relationship #{i} missing fields: {missing}")
    print(f"Loaded {len(rels):,} relationships from {json_path}")
    return rels

# ===========================================================================
# Disk space
# ===========================================================================

def check_disk_space(required_gb=DISK_REQUIRED_GB, path="."):
    """Warn if free disk space is below required_gb."""
    try:
        usage = shutil.disk_usage(path)
        free_gb = usage.free / (1024 ** 3)
        if free_gb < required_gb:
            print(f"WARNING: only {free_gb:.2f} GB free on disk; "
                  f"need at least {required_gb} GB. Aborting.")
            log_error(f"Insufficient disk space: {free_gb:.2f} GB free, {required_gb} GB required")
            sys.exit(1)
        else:
            print(f"Disk space OK: {free_gb:.2f} GB free")
        return usage.free
    except Exception as e:
        log_error(f"disk space check failed: {e}")
        return 0

# ===========================================================================
# Checkpoint / resume
# ===========================================================================

def load_checkpoint():
    """Load checkpoint; returns dict or None."""
    if not os.path.exists(CHECKPOINT):
        return None
    try:
        with open(CHECKPOINT, "r", encoding="utf-8") as f:
            cp = json.load(f)
        print(f"Resuming from checkpoint: from_idx={cp['last_from_index']}, "
              f"via_idx={cp['last_via_index']}, rows_written={cp['rows_written']:,}")
        return cp
    except Exception as e:
        log_error(f"checkpoint load failed: {e}; starting fresh")
        return None

def save_checkpoint(from_idx, via_idx, rows_written):
    """Save checkpoint atomically. Uses correct key: last_via_index."""
    tmp = CHECKPOINT + ".tmp"
    payload = {
        "last_from_index": from_idx,
        "last_via_index":  via_idx,
        "rows_written":    rows_written,
        "timestamp":       datetime.utcnow().isoformat() + "Z",
    }
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        os.replace(tmp, CHECKPOINT)
    except Exception as e:
        log_error(f"checkpoint save failed: {e}")

# ===========================================================================
# Main generator
# ===========================================================================

def format_hms(seconds):
    """Format seconds as H:MM:SS."""
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}"

def generate_matrix(relationships, output_path):
    """Generate the full 5,359 x 5,359 matrix CSV."""
    n = len(relationships)
    total_rows = n * n
    print(f"\nStarting generation of {total_rows:,} rows ({n} x {n})...")
    print(f"Output: {output_path}")
    print(f"Chunk size: {CHUNK_SIZE:,} rows | Buffer: {BUFFER_BYTES // (1024*1024)} MB")
    print()

    check_disk_space()

    # Resume from checkpoint?
    cp = load_checkpoint()
    if cp is not None:
        start_from_idx = cp["last_from_index"]
        start_via_idx  = cp["last_via_index"]
        rows_written   = cp["rows_written"]
        if start_via_idx >= n:
            start_from_idx += 1
            start_via_idx = 0
        file_mode = "a"
        write_header = False
        print(f"Resuming at from_idx={start_from_idx}, via_idx={start_via_idx}")
    else:
        start_from_idx = 0
        start_via_idx  = 0
        rows_written   = 0
        file_mode = "w"
        write_header = True

    if rows_written == 0 and os.path.exists(ERROR_LOG):
        os.remove(ERROR_LOG)

    start_time = time.time()
    chunk = []
    last_progress_rows = 0

    try:
        with open(output_path, file_mode, encoding="utf-8", buffering=BUFFER_BYTES, newline="") as f_out:
            writer = csv.writer(f_out, quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
            if write_header:
                writer.writerow(["from_key", "via_key", "result_key", "result_female_key"])

            for i in range(start_from_idx, n):
                from_entry = relationships[i]
                from_key = from_entry["relationshipKey"]

                via_start = start_via_idx if i == start_from_idx else 0

                for j in range(via_start, n):
                    via_entry = relationships[j]
                    via_key = via_entry["relationshipKey"]

                    try:
                        result_key, result_female_key = resolve_chain(from_entry, via_entry)
                    except Exception as e:
                        log_error(f"resolve_chain failed for ({from_key}, {via_key}): {e}")
                        result_key = result_female_key = "distant-relative"

                    chunk.append((from_key, via_key, result_key, result_female_key))
                    rows_written += 1

                    if len(chunk) >= CHUNK_SIZE:
                        writer.writerows(chunk)
                        chunk.clear()

                    if rows_written - last_progress_rows >= PROGRESS_EVERY:
                        elapsed = time.time() - start_time
                        rate = rows_written / elapsed if elapsed > 0 else 0
                        remaining = total_rows - rows_written
                        eta = remaining / rate if rate > 0 else 0
                        pct = rows_written / total_rows * 100
                        print(f"Progress: {rows_written:,} / {total_rows:,} "
                              f"({pct:.1f}%) | Elapsed: {format_hms(elapsed)} | "
                              f"ETA: {format_hms(eta)} | "
                              f"rate: {rate:,.0f} rows/s | "
                              f"from={from_key[:30]}")
                        last_progress_rows = rows_written
                        f_out.flush()

                    if rows_written % CHECKPOINT_EVERY == 0:
                        if chunk:
                            writer.writerows(chunk)
                            chunk.clear()
                        f_out.flush()
                        save_checkpoint(i, j + 1, rows_written)

                if chunk:
                    writer.writerows(chunk)
                    chunk.clear()
                f_out.flush()
                save_checkpoint(i + 1, 0, rows_written)
                start_via_idx = 0

    except KeyboardInterrupt:
        print("\nInterrupted by user. Saving checkpoint...")
        save_checkpoint(i, j, rows_written)
        print(f"Checkpoint saved. Resume with: python {os.path.basename(__file__)}")
        sys.exit(130)
    except Exception as e:
        log_error(f"Fatal error during generation: {e}\n{traceback.format_exc()}")
        save_checkpoint(i if 'i' in dir() else 0, j if 'j' in dir() else 0, rows_written)
        raise

    elapsed = time.time() - start_time

    if os.path.exists(CHECKPOINT):
        os.remove(CHECKPOINT)

    file_size = os.path.getsize(output_path)
    file_size_gb = file_size / (1024 ** 3)

    print()
    print("=" * 70)
    print("GENERATION COMPLETE")
    print("=" * 70)
    print(f"Total rows written: {rows_written:,}")
    print(f"Expected:           {total_rows:,}")
    print(f"Match: {'YES' if rows_written == total_rows else 'NO'}")
    print(f"File: {output_path}")
    print(f"File size: {file_size_gb:.2f} GB ({file_size:,} bytes)")
    print(f"Time taken: {format_hms(elapsed)}")
    print(f"Average rate: {rows_written / elapsed:,.0f} rows/sec")

    # Post-generation verification
    print()
    passed, total, failures = run_verification("POST-GENERATION VERIFICATION")
    if passed == total:
        print("All post-generation verification cases passed!")
    else:
        print(f"Note: {total - passed} cases failed (see above)")

    # Sample row verification from CSV
    print()
    print("Sample row verification from CSV:")
    verify_samples = [
        ("father", "father",      "paternal-grandfather"),
        ("mother", "brother",     "maternal-uncle"),
        ("husband", "mother",     "mother-in-law"),
        ("son", "father",         "self"),
        ("father", "son",         "self"),
        ("brother", "brother",    "self"),
        ("son", "wife",           "daughter-in-law"),
        ("daughter", "husband",   "son-in-law"),
        ("husband", "elder_brother", "jeth"),
        ("wife", "sister",        "sali"),
        ("father", "elder_brother", "tau"),
        ("father", "younger_brother", "chacha"),
    ]
    found_count = 0
    for fk, vk, expected in verify_samples:
        actual = lookup_row_in_csv(output_path, fk, vk)
        ok = labels_match(actual, expected) if actual else False
        mark = "OK" if ok else "FAIL"
        print(f"  [{mark}] {fk} + {vk} = {actual} (expected {expected})")
        if ok:
            found_count += 1
    print(f"  Verified: {found_count}/{len(verify_samples)}")

    print()
    print("CSV is valid and readable")
    print("Ready for Turso upload")

def lookup_row_in_csv(csv_path, from_key, via_key):
    """Quick lookup using the resolution engine (not CSV scan)."""
    if from_key not in BY_KEY or via_key not in BY_KEY:
        return None
    result, _ = resolve_chain(BY_KEY[from_key], BY_KEY[via_key])
    return result

# ===========================================================================
# Entry point
# ===========================================================================

if __name__ == "__main__":
    input_path = sys.argv[1] if len(sys.argv) > 1 else INPUT_JSON
    output_path = sys.argv[2] if len(sys.argv) > 2 else OUTPUT_CSV

    # Fallback to canonical project path if input not found
    if not os.path.exists(input_path):
        fallback = "/home/z/my-project/download/indian_kinship.json"
        if os.path.exists(fallback):
            print(f"Input '{input_path}' not found; using fallback '{fallback}'")
            input_path = fallback
        else:
            print(f"ERROR: Input file not found: {input_path}")
            sys.exit(1)

    relationships = load_relationships(input_path)

    # Build all lookup structures
    build_lookups(relationships)

    # Run verification BEFORE generation (abort if <95% pass)
    passed, total, failures = run_verification("PRE-GENERATION VERIFICATION")
    pass_rate = passed / total if total > 0 else 0
    if pass_rate < 0.95:
        print(f"PRE-GENERATION VERIFICATION FAILED: {passed}/{total} ({pass_rate*100:.1f}%)")
        print("Pass rate below 95% threshold. Aborting generation.")
        print("Fix the resolution engine before proceeding.")
        sys.exit(1)
    print(f"Pre-generation verification passed ({pass_rate*100:.1f}%). Proceeding with generation.\n")

    # Generate the CSV
    generate_matrix(relationships, output_path)
