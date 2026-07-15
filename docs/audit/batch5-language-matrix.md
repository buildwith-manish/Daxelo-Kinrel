# P12.6 Batch 5 — Language Capability Matrix

**Date:** 2026-07-15
**Method:** Per kinrel_final_audited_prompt_v2.md §7

## Matrix

| # | Language | Kinship terminology (`kinship_core.json`) | App UI localization (ARB file) | Human-reviewed | TTS/pronunciation |
|---|----------|-------------------------------------------|-------------------------------|----------------|-------------------|
| 1 | Hindi | ✅ | ✅ `hi.arb` | unknown | unknown (flutter_tts declared, runtime not verified) |
| 2 | Bengali | ✅ | ✅ `bn.arb` | unknown | unknown |
| 3 | Telugu | ✅ | ✅ `te.arb` | unknown | unknown |
| 4 | Marathi | ✅ | ✅ `mr.arb` | unknown | unknown |
| 5 | Tamil | ✅ | ✅ `ta.arb` | unknown | unknown |
| 6 | Urdu | ✅ | ✅ `ur.arb` | unknown | unknown |
| 7 | Gujarati | ✅ | ✅ `gu.arb` | unknown | unknown |
| 8 | Kannada | ✅ | ✅ `kn.arb` | unknown | unknown |
| 9 | Malayalam | ✅ | ✅ `ml.arb` | unknown | unknown |
| 10 | Odia | ✅ | ✅ `or.arb` | unknown | unknown |
| 11 | Punjabi | ✅ | ✅ `pa.arb` | unknown | unknown |
| 12 | Assamese | ✅ | ✅ `as.arb` | unknown | unknown |
| 13 | Sanskrit | ✅ | ✅ `sa.arb` | unknown | unknown |
| 14 | Sindhi | ✅ | ✅ `sd.arb` | unknown | unknown |
| 15 | English | ✅ | ✅ `en.arb` | yes (source language) | yes (flutter_tts en locale) |
| 16 | Chinese | ✅ | ❌ NO ARB | unknown | unknown |
| 17 | Japanese | ✅ | ❌ NO ARB | unknown | unknown |
| 18 | Korean | ✅ | ❌ NO ARB | unknown | unknown |
| 19 | Arabic | ✅ | ❌ NO ARB | unknown | unknown |
| 20 | Spanish | ✅ | ❌ NO ARB | unknown | unknown |
| 21 | French | ✅ | ❌ NO ARB | unknown | unknown |
| 22 | German | ✅ | ❌ NO ARB | unknown | unknown |

## Summary

| Capability | Count | Languages |
|-----------|-------|-----------|
| Kinship terminology | 22 | All 22 in `kinship_core.json` |
| App UI localization (ARB) | 15 | 14 Indian + English |
| Human-reviewed translations | 1 (English) | All others: unknown |
| TTS/pronunciation | unknown | flutter_tts declared but locale support not runtime-verified |

## Honest claims

- **"22 languages of kinship terminology"** — VERIFIED (kinship_core.json lists 22)
- **"22 languages of app UI"** — FALSE. Only 15 ARB files exist. The 7 international languages (Chinese, Japanese, Korean, Arabic, Spanish, French, German) have kinship terminology data but NO app UI translations.
- **"15 languages of app UI"** — VERIFIED (15 ARB files exist)

## Corrective action

Search product copy, code comments, and README for unsupported "22 languages" claims. Correct to either:
- "22 languages of kinship terminology + 15 languages of app UI"
- Or simply "15 languages" if referring to app UI

No "22 languages" claim should appear without qualifying which capability (terminology vs UI).
