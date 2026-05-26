// lib/features/explore/presentation/explore_screen.dart
//
// DAXELO KINREL — Kinship Dictionary / Explore Screen
//
// Redesigned Kinship Dictionary with:
//   • Custom search bar (#202338 bg, orange search icon, voice button)
//   • Language filter chips (horizontal scroll, 15 languages)
//   • Category filter chips (Core, Parental, Sibling, Cousin, In-Law, etc.)
//   • Kinship cards with regional script, transliteration, definition
//   • Gender indicator, generation badge, speaker icon
//   • Bottom sheet detail on card tap
//   • Debounced search (300ms)
//   • Empty state with illustration
//
// Design spec colors:
//   Background: #131416, Cards: #191B2C, Elevated: #202338
//   Text primary: #F5F0EE, secondary: #C9B4A8, dim: #8A7A72
//   Orange accent: #E8612A throughout

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/kinship/kinship_models.dart';
import '../../../shared/widgets/dk_components.dart';

// ═══════════════════════════════════════════════════════════════════════
// DESIGN TOKENS
// ═══════════════════════════════════════════════════════════════════════

class _Tokens {
  _Tokens._();

  // Colors from design spec
  static const Color bg = Color(0xFF131416);
  static const Color card = Color(0xFF191B2C);
  static const Color elevated = Color(0xFF202338);
  static const Color orange = Color(0xFFE8612A);
  static const Color textPrimary = Color(0xFFF5F0EE);
  static const Color textSecondary = Color(0xFFC9B4A8);
  static const Color textDim = Color(0xFF8A7A72);
  static const Color border = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)

  // Gender colors
  static const Color maleBlue = Color(0xFF3B82F6);
  static const Color femalePink = Color(0xFFEC4899);

  // Chip colors
  static const Color chipActiveBg = Color(0xFFE8612A);
  static const Color chipInactiveBg = Color(0xFF202338);
  static const Color chipInactiveText = Color(0xFFC9B4A8);
}

// ═══════════════════════════════════════════════════════════════════════
// KINSHIP TERM DATA MODEL (for sample data)
// ═══════════════════════════════════════════════════════════════════════

enum _KinshipGender { male, female }

enum _GenerationLevel { ancestor, same, descendant }

class _KinshipTerm {
  const _KinshipTerm({
    required this.englishTerm,
    required this.nativeScript,
    required this.transliteration,
    required this.definition,
    required this.category,
    required this.gender,
    required this.generation,
    required this.relationshipKey,
    this.reciprocalTerm,
    this.culturalNote,
    this.availableLanguages = const ['hi'],
  });

  final String englishTerm;
  final String nativeScript;
  final String transliteration;
  final String definition;
  final String category;
  final _KinshipGender gender;
  final _GenerationLevel generation;
  final String relationshipKey;
  final String? reciprocalTerm;
  final String? culturalNote;
  final List<String> availableLanguages;
}

// ═══════════════════════════════════════════════════════════════════════
// 52 BASE TERMS — SAMPLE DATA
// ═══════════════════════════════════════════════════════════════════════

const _allTerms = <_KinshipTerm>[
  // ── Core (10) ──────────────────────────────────────────────────
  _KinshipTerm(
    englishTerm: 'Father',
    nativeScript: 'पिता',
    transliteration: 'Pita',
    definition: 'Father',
    category: 'Core',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'father',
    reciprocalTerm: 'Son / Daughter',
    culturalNote: 'Revered term; used with deep respect across all Indian cultures.',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'sd', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Mother',
    nativeScript: 'माता',
    transliteration: 'Mata',
    definition: 'Mother',
    category: 'Core',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mother',
    reciprocalTerm: 'Son / Daughter',
    culturalNote: 'One of the most sacred relationships in Indian culture. "Mata" is also used for goddesses.',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'sd', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Son',
    nativeScript: 'बेटा',
    transliteration: 'Beta',
    definition: 'Son',
    category: 'Core',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'son',
    reciprocalTerm: 'Father / Mother',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Daughter',
    nativeScript: 'बेटी',
    transliteration: 'Beti',
    definition: 'Daughter',
    category: 'Core',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'daughter',
    reciprocalTerm: 'Father / Mother',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Husband',
    nativeScript: 'पति',
    transliteration: 'Pati',
    definition: 'Husband',
    category: 'Core',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'husband',
    reciprocalTerm: 'Wife',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Wife',
    nativeScript: 'पत्नी',
    transliteration: 'Patni',
    definition: 'Wife',
    category: 'Core',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'wife',
    reciprocalTerm: 'Husband',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Elder Brother',
    nativeScript: 'बड़ा भाई',
    transliteration: 'Bhaiya',
    definition: "Father and mother's elder son",
    category: 'Core',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'elder_brother',
    reciprocalTerm: 'Younger Sibling',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Younger Brother',
    nativeScript: 'छोटा भाई',
    transliteration: 'Chhota Bhai',
    definition: "Father and mother's younger son",
    category: 'Core',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'younger_brother',
    reciprocalTerm: 'Elder Sibling',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Elder Sister',
    nativeScript: 'बड़ी बहन',
    transliteration: 'Didi',
    definition: "Father and mother's elder daughter",
    category: 'Core',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'elder_sister',
    reciprocalTerm: 'Younger Sibling',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Younger Sister',
    nativeScript: 'छोटी बहन',
    transliteration: 'Chhoti Bahen',
    definition: "Father and mother's younger daughter",
    category: 'Core',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'younger_sister',
    reciprocalTerm: 'Elder Sibling',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),

  // ── Parental — Paternal (8) ──────────────────────────────────────
  _KinshipTerm(
    englishTerm: "Father's father",
    nativeScript: 'दादा',
    transliteration: 'Dada',
    definition: "Father's father (paternal grandfather)",
    category: 'Parental',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_father',
    reciprocalTerm: 'Grandson / Granddaughter',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's mother",
    nativeScript: 'दादी',
    transliteration: 'Dadi',
    definition: "Father's mother (paternal grandmother)",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_mother',
    reciprocalTerm: 'Grandson / Granddaughter',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's elder brother",
    nativeScript: 'ताऊ',
    transliteration: 'Tau',
    definition: "Father's elder brother",
    category: 'Parental',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_elder_brother',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's elder brother's wife",
    nativeScript: 'ताई',
    transliteration: 'Tai',
    definition: "Father's elder brother's wife",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_elder_brothers_wife',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's younger brother",
    nativeScript: 'चाचा',
    transliteration: 'Chacha',
    definition: "Father's younger brother",
    category: 'Parental',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_younger_brother',
    reciprocalTerm: 'Nephew / Niece',
    culturalNote: 'One of the most commonly used kinship terms. "Chacha" carries warmth and affection.',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's younger brother's wife",
    nativeScript: 'चाची',
    transliteration: 'Chachi',
    definition: "Father's younger brother's wife",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_younger_brothers_wife',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's sister",
    nativeScript: 'बुआ',
    transliteration: 'Bua',
    definition: "Father's sister",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_sister',
    reciprocalTerm: 'Nephew / Niece',
    culturalNote: 'Bua holds a special place — she is both father\'s sister and a beloved figure in the family.',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's sister's husband",
    nativeScript: 'फूफा',
    transliteration: 'Fufa',
    definition: "Father's sister's husband",
    category: 'Parental',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'fathers_sisters_husband',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),

  // ── Parental — Maternal (8) ──────────────────────────────────────
  _KinshipTerm(
    englishTerm: "Mother's father",
    nativeScript: 'नाना',
    transliteration: 'Nana',
    definition: "Mother's father (maternal grandfather)",
    category: 'Parental',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_father',
    reciprocalTerm: 'Grandson / Granddaughter',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's mother",
    nativeScript: 'नानी',
    transliteration: 'Nani',
    definition: "Mother's mother (maternal grandmother)",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_mother',
    reciprocalTerm: 'Grandson / Granddaughter',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's brother",
    nativeScript: 'मामा',
    transliteration: 'Mama',
    definition: "Mother's brother",
    category: 'Parental',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_brother',
    reciprocalTerm: 'Nephew / Niece',
    culturalNote: '"Mama" is widely used across India. In many families, mama has a duty to sponsor the sister\'s daughter\'s wedding.',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's brother's wife",
    nativeScript: 'मामी',
    transliteration: 'Mami',
    definition: "Mother's brother's wife",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_brothers_wife',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's sister",
    nativeScript: 'मौसी',
    transliteration: 'Mausi',
    definition: "Mother's sister",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_sister',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's sister's husband",
    nativeScript: 'मौसा',
    transliteration: 'Mausa',
    definition: "Mother's sister's husband",
    category: 'Parental',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_sisters_husband',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's elder sister",
    nativeScript: 'बड़ी मौसी',
    transliteration: 'Badi Mausi',
    definition: "Mother's elder sister",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_elder_sister',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's younger sister",
    nativeScript: 'छोटी मौसी',
    transliteration: 'Chhoti Mausi',
    definition: "Mother's younger sister",
    category: 'Parental',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mothers_younger_sister',
    reciprocalTerm: 'Nephew / Niece',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),

  // ── In-Laws (12) ────────────────────────────────────────────────
  _KinshipTerm(
    englishTerm: 'Father-in-law',
    nativeScript: 'ससुर',
    transliteration: 'Sasur',
    definition: "Husband's father / Wife's father",
    category: 'In-Law',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'father_in_law',
    reciprocalTerm: 'Daughter-in-law / Son-in-law',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Mother-in-law',
    nativeScript: 'सास',
    transliteration: 'Saas',
    definition: "Husband's mother / Wife's mother",
    category: 'In-Law',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'mother_in_law',
    reciprocalTerm: 'Daughter-in-law / Son-in-law',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Husband's elder brother",
    nativeScript: 'जेठ',
    transliteration: 'Jeth',
    definition: "Husband's elder brother",
    category: 'In-Law',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'husbands_elder_brother',
    reciprocalTerm: 'Brother\'s wife (Devarani)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Husband's elder brother's wife",
    nativeScript: 'जेठानी',
    transliteration: 'Jethani',
    definition: "Husband's elder brother's wife",
    category: 'In-Law',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'husbands_elder_brothers_wife',
    reciprocalTerm: 'Husband\'s younger brother\'s wife (Devrani)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Husband's younger brother",
    nativeScript: 'देवर',
    transliteration: 'Devar',
    definition: "Husband's younger brother",
    category: 'In-Law',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'husbands_younger_brother',
    reciprocalTerm: 'Brother\'s wife (Jethani)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Husband's younger brother's wife",
    nativeScript: 'देवरानी',
    transliteration: 'Devrani',
    definition: "Husband's younger brother's wife",
    category: 'In-Law',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'husbands_younger_brothers_wife',
    reciprocalTerm: 'Husband\'s elder brother\'s wife (Jethani)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Husband's sister",
    nativeScript: 'नंद',
    transliteration: 'Nand',
    definition: "Husband's sister",
    category: 'In-Law',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'husbands_sister',
    reciprocalTerm: 'Brother\'s wife (Bhabhi)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Wife's brother",
    nativeScript: 'साला',
    transliteration: 'Sala',
    definition: "Wife's brother",
    category: 'In-Law',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'wifes_brother',
    reciprocalTerm: 'Sister\'s husband',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Wife's sister",
    nativeScript: 'साली',
    transliteration: 'Sali',
    definition: "Wife's sister",
    category: 'In-Law',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'wifes_sister',
    reciprocalTerm: 'Sister\'s husband',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Wife's sister's husband",
    nativeScript: 'सदुहु',
    transliteration: 'Sadhu',
    definition: "Wife's sister's husband",
    category: 'In-Law',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'wifes_sisters_husband',
    reciprocalTerm: 'Wife\'s sister\'s husband (mutual)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Son's wife",
    nativeScript: 'बहू',
    transliteration: 'Bahu',
    definition: "Son's wife (daughter-in-law)",
    category: 'In-Law',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'sons_wife',
    reciprocalTerm: 'Father-in-law / Mother-in-law',
    culturalNote: '"Bahu" also means "bride" — the term carries cultural weight as the bringer of new lineage.',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Daughter's husband",
    nativeScript: 'दामाद',
    transliteration: 'Damad',
    definition: "Daughter's husband (son-in-law)",
    category: 'In-Law',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'daughters_husband',
    reciprocalTerm: 'Father-in-law / Mother-in-law',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),

  // ── Cousins (6) ─────────────────────────────────────────────────
  _KinshipTerm(
    englishTerm: "Father's brother's son",
    nativeScript: 'चचेरा भाई',
    transliteration: 'Chachera Bhai',
    definition: "Father's brother's son (paternal parallel cousin)",
    category: 'Cousin',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'fathers_brothers_son',
    reciprocalTerm: 'Cousin (mutual)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's brother's daughter",
    nativeScript: 'चचेरी बहन',
    transliteration: 'Chacheri Bahen',
    definition: "Father's brother's daughter (paternal parallel cousin)",
    category: 'Cousin',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'fathers_brothers_daughter',
    reciprocalTerm: 'Cousin (mutual)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Father's sister's son",
    nativeScript: 'फुफेरा भाई',
    transliteration: 'Fufera Bhai',
    definition: "Father's sister's son (paternal cross-cousin)",
    category: 'Cousin',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'fathers_sisters_son',
    reciprocalTerm: 'Cousin (mutual)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's brother's son",
    nativeScript: 'मामेरा भाई',
    transliteration: 'Mamera Bhai',
    definition: "Mother's brother's son (maternal cross-cousin)",
    category: 'Cousin',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'mothers_brothers_son',
    reciprocalTerm: 'Cousin (mutual)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's sister's son",
    nativeScript: 'मौसेरा भाई',
    transliteration: 'Mausera Bhai',
    definition: "Mother's sister's son (maternal parallel cousin)",
    category: 'Cousin',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.same,
    relationshipKey: 'mothers_sisters_son',
    reciprocalTerm: 'Cousin (mutual)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Mother's sister's daughter",
    nativeScript: 'मौसेरी बहन',
    transliteration: 'Mauseri Bahen',
    definition: "Mother's sister's daughter (maternal parallel cousin)",
    category: 'Cousin',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.same,
    relationshipKey: 'mothers_sisters_daughter',
    reciprocalTerm: 'Cousin (mutual)',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),

  // ── Extended (8) ────────────────────────────────────────────────
  _KinshipTerm(
    englishTerm: 'Great-grandfather',
    nativeScript: 'परदादा',
    transliteration: 'Pardada',
    definition: "Father's father's father",
    category: 'Extended',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'great_grandfather',
    reciprocalTerm: 'Great-grandson / Great-granddaughter',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Great-grandmother',
    nativeScript: 'परदादी',
    transliteration: 'Pardadi',
    definition: "Father's father's mother",
    category: 'Extended',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.ancestor,
    relationshipKey: 'great_grandmother',
    reciprocalTerm: 'Great-grandson / Great-granddaughter',
    availableLanguages: ['hi', 'bn', 'mr', 'gu', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Grandson',
    nativeScript: 'पोता',
    transliteration: 'Pota',
    definition: "Son's son",
    category: 'Extended',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'grandson',
    reciprocalTerm: 'Grandfather / Grandmother',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: 'Granddaughter',
    nativeScript: 'पोती',
    transliteration: 'Poti',
    definition: "Son's daughter",
    category: 'Extended',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'granddaughter',
    reciprocalTerm: 'Grandfather / Grandmother',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Nephew (brother's son)",
    nativeScript: 'भतीजा',
    transliteration: 'Bhatija',
    definition: "Brother's son",
    category: 'Extended',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'brothers_son',
    reciprocalTerm: 'Uncle / Aunt',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Niece (brother's daughter)",
    nativeScript: 'भतीजी',
    transliteration: 'Bhatiji',
    definition: "Brother's daughter",
    category: 'Extended',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'brothers_daughter',
    reciprocalTerm: 'Uncle / Aunt',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Nephew (sister's son)",
    nativeScript: 'भानजा',
    transliteration: 'Bhanja',
    definition: "Sister's son",
    category: 'Extended',
    gender: _KinshipGender.male,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'sisters_son',
    reciprocalTerm: 'Uncle (Mama) / Aunt (Mausi)',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
  _KinshipTerm(
    englishTerm: "Niece (sister's daughter)",
    nativeScript: 'भानजी',
    transliteration: 'Bhanji',
    definition: "Sister's daughter",
    category: 'Extended',
    gender: _KinshipGender.female,
    generation: _GenerationLevel.descendant,
    relationshipKey: 'sisters_daughter',
    reciprocalTerm: 'Uncle (Mama) / Aunt (Mausi)',
    availableLanguages: ['hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'en'],
  ),
];

// ═══════════════════════════════════════════════════════════════════════
// LANGUAGE FILTER DATA
// ═══════════════════════════════════════════════════════════════════════

const _languageChips = [
  ('All', 'All'),
  ('हिन्दी', 'hi'),
  ('অসমীয়া', 'as'),
  ('বাংলা', 'bn'),
  ('मराठी', 'mr'),
  ('தமிழ்', 'ta'),
  ('తెలుగు', 'te'),
  ('ಕನ್ನಡ', 'kn'),
  ('മലയാളം', 'ml'),
  ('ଓଡ଼ିଆ', 'or'),
  ('ਪੰਜਾਬੀ', 'pa'),
  ('اردو', 'ur'),
  ('सिन्धी', 'sd'),
  ('ગુજરાતી', 'gu'),
  ('English', 'en'),
];

// ═══════════════════════════════════════════════════════════════════════
// CATEGORY FILTER DATA
// ═══════════════════════════════════════════════════════════════════════

const _categoryChips = ['All', 'Core', 'Parental', 'Sibling', 'Cousin', 'In-Law', 'Extended', 'Ceremonial'];

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Search query provider for the explore screen
final _exploreSearchProvider = StateProvider<String>((ref) => '');

/// Kinship search results from the loaded JSON data
final _exploreKinshipProvider = FutureProvider<List<KinshipSearchResult>>((ref) async {
  final query = ref.watch(_exploreSearchProvider);
  if (query.isEmpty) return [];
  await ref.watch(kinshipInitializedProvider.future);
  final service = ref.watch(kinshipServiceProvider);
  return service.search(query);
});

/// Search results provider — searches across all family members, families
final _exploreResultsProvider =
    FutureProvider<_ExploreResults>((ref) async {
  final query = ref.watch(_exploreSearchProvider);
  if (query.isEmpty) return _ExploreResults.empty();

  final families = await ref.watch(familyListProvider.future);
  final matchingMembers = <_SearchResultItem>[];
  final matchingFamilies = <_SearchResultItem>[];

  for (final family in families) {
    if (family.name.toLowerCase().contains(query.toLowerCase())) {
      matchingFamilies.add(_SearchResultItem(
        id: family.id,
        title: family.name,
        subtitle: 'Family',
        icon: Icons.family_restroom_rounded,
        type: _ResultType.family,
        familyId: family.id,
      ));
    }

    final slug = family.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.contains(query.toLowerCase())) {
      final alreadyListed = matchingFamilies.any((f) => f.id == family.id);
      if (!alreadyListed) {
        matchingFamilies.add(_SearchResultItem(
          id: family.id,
          title: family.name,
          subtitle: 'Family code match',
          icon: Icons.family_restroom_rounded,
          type: _ResultType.family,
          familyId: family.id,
        ));
      }
    }

    try {
      final members =
          await ref.watch(familyMembersProvider(family.id).future);
      for (final member in members) {
        if (member.name.toLowerCase().contains(query.toLowerCase())) {
          matchingMembers.add(_SearchResultItem(
            id: member.id,
            title: member.name,
            subtitle: family.name,
            icon: Icons.person_outline_rounded,
            type: _ResultType.member,
            familyId: family.id,
          ));
        }
      }
    } catch (_) {
      // Skip families we can't load members for
    }
  }

  return _ExploreResults(
    members: matchingMembers,
    families: matchingFamilies,
  );
});

class _ExploreResults {
  const _ExploreResults({required this.members, required this.families});

  factory _ExploreResults.empty() => const _ExploreResults(
        members: [],
        families: [],
      );

  final List<_SearchResultItem> members;
  final List<_SearchResultItem> families;

  bool get isEmpty => members.isEmpty && families.isEmpty;
}

enum _ResultType { member, family }

class _SearchResultItem {
  const _SearchResultItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.type,
    required this.familyId,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final _ResultType type;
  final String familyId;
}

// ═══════════════════════════════════════════════════════════════════════
// EXPLORE SCREEN
// ═══════════════════════════════════════════════════════════════════════

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;
  String _selectedLanguage = 'All';
  String _selectedCategory = 'All';
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(_exploreSearchProvider.notifier).state = query;
    });
    setState(() => _isSearching = query.isNotEmpty);
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    ref.read(_exploreSearchProvider.notifier).state = '';
    setState(() => _isSearching = false);
    _searchFocusNode.unfocus();
  }

  List<_KinshipTerm> get _filteredTerms {
    var terms = _allTerms;

    // Filter by category
    if (_selectedCategory != 'All') {
      terms = terms.where((t) => t.category == _selectedCategory).toList();
    }

    // Filter by search query against sample data
    if (_isSearching && _searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      terms = terms.where((t) {
        return t.englishTerm.toLowerCase().contains(q) ||
            t.nativeScript.contains(q) ||
            t.transliteration.toLowerCase().contains(q) ||
            t.definition.toLowerCase().contains(q);
      }).toList();
    }

    return terms;
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: _Tokens.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Title + Search Bar ───────────────────────────────────
          SliverToBoxAdapter(
            child: _SearchSection(
              controller: _searchController,
              focusNode: _searchFocusNode,
              isSearching: _isSearching,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
              onVoiceSearch: () => context.push('/voice-search'),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── Language Filter Chips ────────────────────────────────
          SliverToBoxAdapter(
            child: _LanguageFilterRow(
              selected: _selectedLanguage,
              onSelected: (lang) => setState(() => _selectedLanguage = lang),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Category Filter Chips ────────────────────────────────
          SliverToBoxAdapter(
            child: _CategoryFilterRow(
              selected: _selectedCategory,
              onSelected: (cat) => setState(() => _selectedCategory = cat),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── Content ──────────────────────────────────────────────
          if (_isSearching)
            _buildSearchResults()
          else
            _buildKinshipDictionary(),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildKinshipDictionary() {
    final terms = _filteredTerms;

    if (terms.isEmpty) {
      return SliverToBoxAdapter(
        child: _EmptyState(
          title: 'No terms found',
          subtitle: 'Try a different category or language filter',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final term = terms[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _KinshipCard(
                term: term,
                onTap: () => _showDetailSheet(context, term),
              ),
            )
                .animate(onPlay: (c) => c.forward())
                .fadeIn(
                  duration: 300.ms,
                  delay: Duration(milliseconds: index * 30),
                )
                .slideY(begin: 0.03, end: 0, duration: 300.ms);
          },
          childCount: terms.length,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final resultsAsync = ref.watch(_exploreResultsProvider);
    final kinshipAsync = ref.watch(_exploreKinshipProvider);

    // Combine sample data search + JSON search + family/member results
    final sampleResults = _filteredTerms;

    return resultsAsync.when(
      data: (results) {
        final kinshipResults =
            kinshipAsync.whenOrNull(data: (data) => data) ?? [];
        final hasNoResults =
            results.isEmpty && kinshipResults.isEmpty && sampleResults.isEmpty;

        if (hasNoResults) {
          return SliverToBoxAdapter(
            child: _EmptyState(
              title: 'No results found',
              subtitle: 'Try a different term or filter',
            ),
          );
        }

        return SliverList(
          delegate: SliverChildListDelegate([
            // Sample kinship term results (from local data)
            if (sampleResults.isNotEmpty) ...[
              _SectionLabel(label: 'Kinship Terms', count: sampleResults.length),
              const SizedBox(height: 8),
              ...sampleResults.map((term) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base, vertical: 5),
                    child: _KinshipCard(
                      term: term,
                      onTap: () => _showDetailSheet(context, term),
                    ),
                  )),
              const SizedBox(height: 16),
            ],

            // JSON kinship search results
            if (kinshipResults.isNotEmpty) ...[
              _SectionLabel(
                  label: 'More Terms', count: kinshipResults.length),
              const SizedBox(height: 8),
              ...kinshipResults.take(5).map((result) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base, vertical: 4),
                    child: _JsonKinshipResultCard(
                      result: result,
                      onTap: () => context.push(
                          '/kinship/${result.relationship.relationshipKey}'),
                    ),
                  )),
              if (kinshipResults.length > 5)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base, vertical: 8),
                  child: DKButton(
                    label:
                        'View all ${kinshipResults.length} kinship terms →',
                    variant: DKButtonVariant.secondary,
                    size: DKButtonSize.sm,
                    fullWidth: true,
                    onPressed: () => context.push('/kinship-search'),
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // Family member results
            if (results.members.isNotEmpty) ...[
              _SectionLabel(
                  label: 'Members', count: results.members.length),
              const SizedBox(height: 8),
              ...results.members.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base, vertical: 4),
                    child: _SearchResultCard(
                      item: item,
                      onTap: () =>
                          context.push('/family/${item.familyId}'),
                    ),
                  )),
              const SizedBox(height: 16),
            ],

            // Family results
            if (results.families.isNotEmpty) ...[
              _SectionLabel(
                  label: 'Families', count: results.families.length),
              const SizedBox(height: 8),
              ...results.families.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base, vertical: 4),
                    child: _SearchResultCard(
                      item: item,
                      onTap: () =>
                          context.push('/family/${item.familyId}'),
                    ),
                  )),
            ],
          ]),
        );
      },
      loading: () => SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: DKLoadingShimmer(width: 200, height: 16),
          ),
        ),
      ),
      error: (_, __) => SliverToBoxAdapter(
        child: DKErrorState(
          message: 'Error searching',
          onRetry: () => ref.invalidate(_exploreResultsProvider),
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context, _KinshipTerm term) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KinshipDetailSheet(term: term),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEARCH SECTION — custom search bar
// ═══════════════════════════════════════════════════════════════════════

class _SearchSection extends StatelessWidget {
  const _SearchSection({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.onChanged,
    required this.onClear,
    required this.onVoiceSearch,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onVoiceSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Title
          Text('Kinship Dictionary',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _Tokens.textPrimary,
              )),
          const SizedBox(height: 4),
          Text('Explore 52 base terms across 15 languages',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: _Tokens.textSecondary,
              )),
          const SizedBox(height: 14),
          // Search bar
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: _Tokens.elevated,
              borderRadius: BorderRadius.circular(KinrelRadius.full),
              border: Border.all(
                color: isSearching
                    ? _Tokens.orange.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.search_rounded,
                    size: 22, color: _Tokens.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 15,
                      color: _Tokens.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Search relationships (bua, chacha, mama...)',
                      hintStyle: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _Tokens.textDim,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                if (isSearching)
                  GestureDetector(
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.close_rounded,
                          size: 20, color: _Tokens.textDim),
                    ),
                  ),
                // Voice search button
                GestureDetector(
                  onTap: onVoiceSearch,
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: _Tokens.orange.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.mic_rounded,
                        size: 18, color: _Tokens.orange),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LANGUAGE FILTER ROW
// ═══════════════════════════════════════════════════════════════════════

class _LanguageFilterRow extends StatelessWidget {
  const _LanguageFilterRow({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: _languageChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = _languageChips[index];
          final label = chip.$1;
          final value = chip.$2;
          final isActive = selected == value;
          return _FilterChip(
            label: label,
            isActive: isActive,
            onTap: () => onSelected(value),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CATEGORY FILTER ROW
// ═══════════════════════════════════════════════════════════════════════

class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: _categoryChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = _categoryChips[index];
          final isActive = selected == label;
          return _FilterChip(
            label: label,
            isActive: isActive,
            onTap: () => onSelected(label),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FILTER CHIP
// ═══════════════════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _Tokens.chipActiveBg : _Tokens.chipInactiveBg,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: isActive
              ? null
              : Border.all(
                  color: _Tokens.textDim.withValues(alpha: 0.15),
                  width: 0.5,
                ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? Colors.white : _Tokens.chipInactiveText,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// KINSHIP CARD
// ═══════════════════════════════════════════════════════════════════════

class _KinshipCard extends StatelessWidget {
  const _KinshipCard({
    required this.term,
    required this.onTap,
  });

  final _KinshipTerm term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _Tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _Tokens.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Main content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Native script (orange, large) + gender + generation
                  Row(
                    children: [
                      // Native script
                      Text(
                        term.nativeScript,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _Tokens.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Gender indicator
                      _GenderIcon(gender: term.gender),
                      const SizedBox(width: 4),
                      // Generation badge
                      _GenerationBadge(generation: term.generation),
                      const SizedBox(width: 4),
                      // Speaker icon
                      Icon(Icons.volume_up_rounded,
                          size: 16, color: _Tokens.orange),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Row 2: Transliteration (white)
                  Text(
                    term.transliteration,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _Tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Row 3: English definition (secondary)
                  Text(
                    term.englishTerm,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _Tokens.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Language availability chips (tiny)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: term.availableLanguages.take(5).map((lang) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _Tokens.elevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          lang.toUpperCase(),
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: _Tokens.textDim,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            // Chevron
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: _Tokens.textDim),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GENDER ICON
// ═══════════════════════════════════════════════════════════════════════

class _GenderIcon extends StatelessWidget {
  const _GenderIcon({required this.gender});

  final _KinshipGender gender;

  @override
  Widget build(BuildContext context) {
    final isMale = gender == _KinshipGender.male;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: (isMale ? _Tokens.maleBlue : _Tokens.femalePink)
            .withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          isMale ? '♂' : '♀',
          style: TextStyle(
            fontSize: 11,
            color: isMale ? _Tokens.maleBlue : _Tokens.femalePink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GENERATION BADGE
// ═══════════════════════════════════════════════════════════════════════

class _GenerationBadge extends StatelessWidget {
  const _GenerationBadge({required this.generation});

  final _GenerationLevel generation;

  @override
  Widget build(BuildContext context) {
    final label = switch (generation) {
      _GenerationLevel.ancestor => '↑',
      _GenerationLevel.descendant => '↓',
      _GenerationLevel.same => '=',
    };

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: _Tokens.orange.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: _Tokens.orange,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION LABEL
// ═══════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _Tokens.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _Tokens.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _Tokens.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// JSON KINSHIP RESULT CARD (for loaded JSON data results)
// ═══════════════════════════════════════════════════════════════════════

class _JsonKinshipResultCard extends ConsumerWidget {
  const _JsonKinshipResultCard({
    required this.result,
    required this.onTap,
  });

  final KinshipSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rel = result.relationship;
    final termAsync = ref.watch(kinshipTermProvider(
      (key: rel.relationshipKey, language: 'hindi'),
    ));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _Tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _Tokens.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Category badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _Tokens.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rel.relationshipCategory
                        .replaceAll('_', ' ')
                        .toUpperCase(),
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _Tokens.orange,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                // Gender indicator
                _GenderIcon(
                    gender: rel.gender == 'male'
                        ? _KinshipGender.male
                        : _KinshipGender.female),
                const SizedBox(width: 4),
                Icon(Icons.volume_up_rounded,
                    size: 16, color: _Tokens.orange),
              ],
            ),
            const SizedBox(height: 8),
            // Native translation
            termAsync.when(
              data: (translation) {
                if (translation == null) return const SizedBox.shrink();
                return Text(
                  translation.native,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: _Tokens.orange,
                  ),
                );
              },
              loading: () => DKLoadingShimmer(
                  width: 120, height: 24, radius: 4),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 4),
            // English term
            Text(
              rel.englishTerm,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _Tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            // Relationship key
            Text(
              rel.relationshipKey.replaceAll('_', ' → '),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: _Tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEARCH RESULT CARD (for family members/families)
// ═══════════════════════════════════════════════════════════════════════

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.item,
    required this.onTap,
  });

  final _SearchResultItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _Tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _Tokens.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _Tokens.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon,
                  size: 18,
                  color: _Tokens.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _Tokens.textPrimary,
                    ),
                  ),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _Tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: _Tokens.textDim),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            // Search illustration
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _Tokens.elevated,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_rounded,
                size: 36,
                color: _Tokens.textDim,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _Tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: _Tokens.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Suggestion chips
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                'bua', 'chacha', 'mama', 'jethani', 'dada',
              ].map((term) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _Tokens.elevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: _Tokens.orange.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      term,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: _Tokens.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// KINSHIP DETAIL BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════

class _KinshipDetailSheet extends StatelessWidget {
  const _KinshipDetailSheet({required this.term});

  final _KinshipTerm term;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: _Tokens.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _Tokens.textDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero: Large kinship term ────────────────────────
                  Center(
                    child: Column(
                      children: [
                        // Orange gradient glow
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFE8612A),
                                Color(0xFFF59240),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _Tokens.orange.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              term.nativeScript.characters.first,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Large native script
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFFE8612A), Color(0xFFF59240)],
                          ).createShader(bounds),
                          child: Text(
                            term.nativeScript,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Transliteration
                        Text(
                          term.transliteration,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: _Tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Audio play button
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _Tokens.orange,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    _Tokens.orange.withValues(alpha: 0.3),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Definition Card ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _Tokens.elevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _Tokens.border,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.menu_book_rounded,
                                size: 16, color: _Tokens.orange),
                            const SizedBox(width: 6),
                            Text(
                              'Definition',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _Tokens.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          term.englishTerm,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _Tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          term.definition,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: _Tokens.textSecondary,
                          ),
                        ),
                        // Path description
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _GenderIcon(gender: term.gender),
                            const SizedBox(width: 6),
                            _GenerationBadge(generation: term.generation),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _Tokens.orange
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                term.category,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _Tokens.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Cultural Context Card ────────────────────────────
                  if (term.culturalNote != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _Tokens.elevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _Tokens.border,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_stories_rounded,
                                  size: 16, color: _Tokens.orange),
                              const SizedBox(width: 6),
                              Text(
                                'Cultural Context',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _Tokens.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            term.culturalNote!,
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                              color: _Tokens.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (term.culturalNote != null)
                    const SizedBox(height: 12),

                  // ── Translations Card ────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _Tokens.elevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _Tokens.border,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.translate_rounded,
                                size: 16, color: _Tokens.orange),
                            const SizedBox(width: 6),
                            Text(
                              'Translations',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _Tokens.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: term.availableLanguages.map((lang) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _Tokens.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _Tokens.border,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                lang.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: KinrelTypography.monoFont,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: _Tokens.textSecondary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Reciprocal Relationship ──────────────────────────
                  if (term.reciprocalTerm != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _Tokens.elevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _Tokens.orange.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded,
                              size: 18, color: _Tokens.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 13,
                                  color: _Tokens.textSecondary,
                                ),
                                children: [
                                  TextSpan(text: 'They call you: '),
                                  TextSpan(
                                    text: term.reciprocalTerm,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _Tokens.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── Related Terms ────────────────────────────────────
                  Builder(builder: (context) {
                    final related = _allTerms
                        .where((t) =>
                            t.category == term.category &&
                            t.relationshipKey != term.relationshipKey)
                        .take(4)
                        .toList();
                    if (related.isEmpty) return const SizedBox.shrink();

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _Tokens.elevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _Tokens.border,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.family_restroom_rounded,
                                  size: 16, color: _Tokens.orange),
                              const SizedBox(width: 6),
                              Text(
                                'Related Terms',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _Tokens.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: related.map((t) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _Tokens.card,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _Tokens.border,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t.nativeScript,
                                      style: TextStyle(
                                        fontFamily:
                                            KinrelTypography.bodyFont,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _Tokens.orange,
                                      ),
                                    ),
                                    Text(
                                      t.transliteration,
                                      style: TextStyle(
                                        fontFamily:
                                            KinrelTypography.bodyFont,
                                        fontSize: 11,
                                        color: _Tokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
