// lib/core/kinship/v4/vocabulary_table.dart
//
// DAXELO-KINREL — v4.0 Vocabulary Table (Phase 6 + Phase 7)
//
// The full vocabulary database mapping KinshipSignature → kinship term
// across 11 languages (English, Hindi, Tamil, Telugu, Kannada, Malayalam,
// Bengali, Marathi, Gujarati, Punjabi, Urdu).
//
// This is a DATA file — no engine logic. Adding terms requires ONLY
// new VocabularyEntry objects here. The engine never changes.

import '../v3/kinship_signature.dart';
import 'vocabulary_entry.dart';

class VocabularyTable {
  VocabularyTable._();

  /// The full vocabulary database. Each entry maps a specific signature
  /// combination to a kinship term in a specific language.
  ///
  /// Organized by relationship category for maintainability.
  static const List<VocabularyEntry> entries = [
    // ════════════════════════════════════════════════════════════════════
    // 1. PARENTS (UP_PARENT, gen=-1)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Father', locale: 'en', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Mother', locale: 'en', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Pita', locale: 'hi', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male', aliases: ['Papa', 'Babu']),
    VocabularyEntry(term: 'Mata', locale: 'hi', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female', aliases: ['Maa', 'Mummy']),
    VocabularyEntry(term: 'Appa', locale: 'ta', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Amma', locale: 'ta', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Nanna', locale: 'te', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Amma', locale: 'te', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Appa', locale: 'kn', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Amma', locale: 'kn', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Achan', locale: 'ml', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Amma', locale: 'ml', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Baba', locale: 'bn', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Maa', locale: 'bn', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Baba', locale: 'mr', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Aai', locale: 'mr', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Pita', locale: 'gu', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Ba', locale: 'gu', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Pita', locale: 'pa', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male', aliases: ['Papaji']),
    VocabularyEntry(term: 'Mata', locale: 'pa', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female', aliases: ['Mataji']),
    VocabularyEntry(term: 'Abbu', locale: 'ur', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Ammi', locale: 'ur', pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female'),

    // ════════════════════════════════════════════════════════════════════
    // 2. CHILDREN (DOWN_CHILD, gen=+1)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Son', locale: 'en', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Daughter', locale: 'en', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Beta', locale: 'hi', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Beti', locale: 'hi', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Magan', locale: 'ta', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Magal', locale: 'ta', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Koduku', locale: 'te', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Kuthuru', locale: 'te', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Maga', locale: 'kn', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'MagaLu', locale: 'kn', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Makan', locale: 'ml', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Makal', locale: 'ml', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Chele', locale: 'bn', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Meye', locale: 'bn', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Mulga', locale: 'mr', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Mulggi', locale: 'mr', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Dikra', locale: 'gu', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Dikri', locale: 'gu', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Puttar', locale: 'pa', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Puttar', locale: 'pa', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Beta', locale: 'ur', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Beti', locale: 'ur', pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),

    // ════════════════════════════════════════════════════════════════════
    // 3. GRANDPARENTS (UP_PARENT_UP_PARENT, gen=-2)
    // ════════════════════════════════════════════════════════════════════
    // English
    VocabularyEntry(term: 'Grandfather', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal, aliases: ['Grandpa']),
    VocabularyEntry(term: 'Grandfather', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Grandmother', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.paternal, aliases: ['Grandma']),
    VocabularyEntry(term: 'Grandmother', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.maternal),
    // Hindi — Dada (paternal) vs Nana (maternal)
    VocabularyEntry(term: 'Dada', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Dadi', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Nana', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Nani', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.maternal),
    // Tamil — Thatha (both), Paatti (both)
    VocabularyEntry(term: 'Thatha', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Thatha', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Paatti', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Paatti', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.maternal),
    // Telugu
    VocabularyEntry(term: 'Thata', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Thata', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Ammaamma', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.maternal),
    VocabularyEntry(term: 'Naayana', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.paternal),
    // Bengali — Dadu (both), Didima (maternal), Thakurma (paternal)
    VocabularyEntry(term: 'Dadu', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male'),
    VocabularyEntry(term: 'Thakurma', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Didima', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.maternal),
    // Marathi — Ajoba (paternal), Aaji (paternal)
    VocabularyEntry(term: 'Ajoba', locale: 'mr', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Aaji', locale: 'mr', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.paternal),
    // Punjabi
    VocabularyEntry(term: 'Dada', locale: 'pa', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal, aliases: ['Dadaji']),
    VocabularyEntry(term: 'Nana', locale: 'pa', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.maternal, aliases: ['Nanaji']),
    // Urdu
    VocabularyEntry(term: 'Dada', locale: 'ur', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Nana', locale: 'ur', pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.maternal),

    // ════════════════════════════════════════════════════════════════════
    // 4. GRANDCHILDREN (DOWN_CHILD_DOWN_CHILD, gen=+2)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Grandson', locale: 'en', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'male'),
    VocabularyEntry(term: 'Granddaughter', locale: 'en', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'female'),
    VocabularyEntry(term: 'Pota', locale: 'hi', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Poti', locale: 'hi', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Nati', locale: 'hi', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Natin', locale: 'hi', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'female', side: FamilySide.maternal),
    VocabularyEntry(term: 'Peran', locale: 'ta', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'male'),
    VocabularyEntry(term: 'Pertti', locale: 'ta', pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'female'),

    // ════════════════════════════════════════════════════════════════════
    // 5. SIBLINGS (UP_PARENT_DOWN_CHILD, gen=0)
    // ════════════════════════════════════════════════════════════════════
    // English — blood siblings
    VocabularyEntry(term: 'Brother', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood),
    VocabularyEntry(term: 'Sister', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood),
    VocabularyEntry(term: 'Elder Brother', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Elder Sister', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Younger Brother', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger'),
    VocabularyEntry(term: 'Younger Sister', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'younger'),
    // English — half/step/adoptive
    VocabularyEntry(term: 'Half Brother', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.half),
    VocabularyEntry(term: 'Half Sister', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.half),
    VocabularyEntry(term: 'Step Brother', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.step),
    VocabularyEntry(term: 'Step Sister', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.step),

    // Hindi — Bhaiya/Bhai (elder/younger brother), Didi/Bahen (elder/younger sister)
    VocabularyEntry(term: 'Bhaiya', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder', aliases: ['Bade Bhai']),
    VocabularyEntry(term: 'Bhai', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger', aliases: ['Chhote Bhai']),
    VocabularyEntry(term: 'Didi', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'elder', aliases: ['Badi Bahen']),
    VocabularyEntry(term: 'Bahen', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'younger', aliases: ['Chhoti Bahen']),
    VocabularyEntry(term: 'Bhai', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood), // generic
    VocabularyEntry(term: 'Bahen', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood), // generic

    // Tamil — Anna/Thambi (elder/younger brother), Akka/Thangai (elder/younger sister)
    VocabularyEntry(term: 'Anna', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Thambi', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger'),
    VocabularyEntry(term: 'Akka', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Thangai', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'younger'),
    VocabularyEntry(term: 'Sagotharan', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood), // generic
    VocabularyEntry(term: 'Sagothari', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood), // generic

    // Telugu — Anna/Thammudu, Akka/Chelli
    VocabularyEntry(term: 'Anna', locale: 'te', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Thammudu', locale: 'te', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger'),
    VocabularyEntry(term: 'Akka', locale: 'te', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Chelli', locale: 'te', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'younger'),

    // Bengali — Dada/Chhoto bhai, Didi/Chhoto bon
    VocabularyEntry(term: 'Dada', locale: 'bn', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Chhoto Bhai', locale: 'bn', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger'),
    VocabularyEntry(term: 'Didi', locale: 'bn', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Chhoto Bon', locale: 'bn', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'younger'),

    // Marathi — Dada/Bahini, Tai/Bahin
    VocabularyEntry(term: 'Dada', locale: 'mr', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Bahina', locale: 'mr', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger'),
    VocabularyEntry(term: 'Tai', locale: 'mr', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Bahin', locale: 'mr', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'younger'),

    // Punjabi — Veer/Bhara, Bhua/Didi
    VocabularyEntry(term: 'Veer', locale: 'pa', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger', aliases: ['Veera']),
    VocabularyEntry(term: 'Bhara', locale: 'pa', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder'),
    VocabularyEntry(term: 'Bhain', locale: 'pa', pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood),

    // ════════════════════════════════════════════════════════════════════
    // 6. UNCLES & AUNTS (UP_PARENT_UP_PARENT_DOWN_CHILD, gen=-1)
    //    Key Indian distinction: paternal vs maternal, elder vs younger
    // ════════════════════════════════════════════════════════════════════
    // English
    VocabularyEntry(term: 'Uncle', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Uncle', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Aunt', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Aunt', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),

    // Hindi — CRITICAL DISTINCTIONS:
    // Paternal: Tau (father's elder brother), Chacha (father's younger brother),
    //           Bua (father's sister), Phupha (father's sister's husband — but stored as uncle)
    // Maternal: Mama (mother's brother), Mausi (mother's sister)
    VocabularyEntry(term: 'Tau', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder', aliases: ['Taufather']),
    VocabularyEntry(term: 'Chacha', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger', aliases: ['Chachaji']),
    VocabularyEntry(term: 'Bua', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal, aliases: ['Buaji', 'Phuphi']),
    VocabularyEntry(term: 'Mama', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal, aliases: ['Mamaji']),
    VocabularyEntry(term: 'Mausi', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal, aliases: ['Mausi']),
    // Generic Hindi uncle/aunt (no intermediateSeniority)
    VocabularyEntry(term: 'Chacha', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Mama', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),

    // Tamil — Periyappa (father's elder brother), Chitthappa (father's younger brother),
    //         Ammamma/Periyamma (father's elder sister), Chithi (father's younger sister),
    //         Mama (mother's brother), Athai (mother's sister)
    VocabularyEntry(term: 'Periyappa', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder'),
    VocabularyEntry(term: 'Chitthappa', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger'),
    VocabularyEntry(term: 'Periyamma', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal, intermediateSeniority: 'elder'),
    VocabularyEntry(term: 'Chithi', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal, intermediateSeniority: 'younger'),
    VocabularyEntry(term: 'Mama', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Athai', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),

    // Telugu
    VocabularyEntry(term: 'Pedda Baava', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder'),
    VocabularyEntry(term: 'Chinna Baava', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger'),
    VocabularyEntry(term: 'Menamama', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Menamma', locale: 'te', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),

    // Bengali
    VocabularyEntry(term: 'Jyethu', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder'),
    VocabularyEntry(term: 'Kaku', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger'),
    VocabularyEntry(term: 'Pishi', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Mama', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Mashi', locale: 'bn', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),

    // Marathi
    VocabularyEntry(term: 'Tatya', locale: 'mr', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder'),
    VocabularyEntry(term: 'Kaka', locale: 'mr', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger'),
    VocabularyEntry(term: 'Atya', locale: 'mr', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Mama', locale: 'mr', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Mavshi', locale: 'mr', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),

    // Gujarati
    VocabularyEntry(term: 'Dada', locale: 'gu', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder'),
    VocabularyEntry(term: 'Kaka', locale: 'gu', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger'),
    VocabularyEntry(term: 'Foi', locale: 'gu', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Mama', locale: 'gu', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Mami', locale: 'gu', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),

    // Punjabi
    VocabularyEntry(term: 'Taya', locale: 'pa', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder', aliases: ['Tayaji']),
    VocabularyEntry(term: 'Chacha', locale: 'pa', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger', aliases: ['Chachaji']),
    VocabularyEntry(term: 'Bhua', locale: 'pa', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal, aliases: ['Phuphi']),
    VocabularyEntry(term: 'Mama', locale: 'pa', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal, aliases: ['Mamaji']),
    VocabularyEntry(term: 'Masi', locale: 'pa', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),

    // Urdu
    VocabularyEntry(term: 'Chacha', locale: 'ur', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Khala', locale: 'ur', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal),
    VocabularyEntry(term: 'Khalu', locale: 'ur', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Phuphi', locale: 'ur', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal),

    // ════════════════════════════════════════════════════════════════════
    // 7. NEPHEWS & NIECES (UP_PARENT_DOWN_CHILD_DOWN_CHILD, gen=+1)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Nephew', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Niece', locale: 'en', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    // Hindi — Bhatija/Bhatiji (brother's child), Bhanja/Bhanji (sister's child)
    VocabularyEntry(term: 'Bhatija', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Bhatiji', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Bhanja', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Bhanji', locale: 'hi', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female', side: FamilySide.maternal),
    // Tamil — Marumagan/Marumagal
    VocabularyEntry(term: 'Marumagan', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Marumagal', locale: 'ta', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    // Bengali — Vagnya/Vagni (brother's), Bhanja/Bhnaji (sister's)
    VocabularyEntry(term: 'Vagnya', locale: 'bn', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Vagni', locale: 'bn', pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female', side: FamilySide.paternal),

    // ════════════════════════════════════════════════════════════════════
    // 8. COUSINS
    // ════════════════════════════════════════════════════════════════════
    // First cousin (UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD, gen=0)
    VocabularyEntry(term: 'Cousin', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0),
    VocabularyEntry(term: 'Cousin Bhai', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Cousin Bahen', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female'),
    VocabularyEntry(term: 'Chithappa Magan', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Chithappa Magal', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', side: FamilySide.paternal),
    VocabularyEntry(term: 'Mama Magan', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', side: FamilySide.maternal),
    VocabularyEntry(term: 'Mama Magal', locale: 'ta', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', side: FamilySide.maternal),

    // First cousin once removed
    VocabularyEntry(term: 'Cousin (Once Removed)', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, removal: 1),
    VocabularyEntry(term: 'Cousin (Once Removed)', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: -1, removal: 1),

    // Second cousin
    VocabularyEntry(term: 'Second Cousin', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 0),

    // Double first cousin
    VocabularyEntry(term: 'Double Cousin', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, doubleKinship: true),

    // ════════════════════════════════════════════════════════════════════
    // 9. SPOUSE (SPOUSE, gen=0)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Husband', locale: 'en', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Wife', locale: 'en', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'female'),
    VocabularyEntry(term: 'Pati', locale: 'hi', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Patni', locale: 'hi', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'female'),
    VocabularyEntry(term: 'Kanavan', locale: 'ta', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Manaivi', locale: 'ta', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'female'),
    VocabularyEntry(term: 'Bhartha', locale: 'te', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Bharya', locale: 'te', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'female'),
    VocabularyEntry(term: 'Shami', locale: 'bn', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Bou', locale: 'bn', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'female'),
    VocabularyEntry(term: 'Miya', locale: 'ur', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Biwi', locale: 'ur', pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'female'),

    // ════════════════════════════════════════════════════════════════════
    // 10. IN-LAWS (SPOUSE_*, patterns starting with SPOUSE)
    // ════════════════════════════════════════════════════════════════════
    // Father-in-law / Mother-in-law
    VocabularyEntry(term: 'Father-in-Law', locale: 'en', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Mother-in-Law', locale: 'en', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Sasur', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Saas', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Mamanar', locale: 'ta', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Mamiyar', locale: 'ta', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Shoshur', locale: 'bn', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Shashuri', locale: 'bn', pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'female'),

    // Brother-in-law / Sister-in-law
    VocabularyEntry(term: 'Brother-in-Law', locale: 'en', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male'),
    VocabularyEntry(term: 'Sister-in-Law', locale: 'en', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female'),
    // Hindi — Jeth (husband's elder brother), Devar (husband's younger brother),
    //         Nand (husband's sister), Sala (wife's brother), Saali (wife's sister)
    VocabularyEntry(term: 'Jeth', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', spouseSide: FamilySide.paternal, intermediateSeniority: 'elder'),
    VocabularyEntry(term: 'Devar', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', spouseSide: FamilySide.paternal, intermediateSeniority: 'younger'),
    VocabularyEntry(term: 'Nand', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', spouseSide: FamilySide.paternal'),
    VocabularyEntry(term: 'Sala', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', spouseSide: FamilySide.maternal),
    VocabularyEntry(term: 'Saali', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', spouseSide: FamilySide.maternal),
    // Generic Hindi
    VocabularyEntry(term: 'Bhabhi', locale: 'hi', pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', spouseSide: FamilySide.paternal, notes: 'Brother wife'),

    // Son-in-law / Daughter-in-law
    VocabularyEntry(term: 'Son-in-Law', locale: 'en', pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Daughter-in-Law', locale: 'en', pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Damad', locale: 'hi', pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Bahu', locale: 'hi', pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),
    VocabularyEntry(term: 'Marumagan', locale: 'ta', pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male'),
    VocabularyEntry(term: 'Marumagal', locale: 'ta', pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female'),

    // ════════════════════════════════════════════════════════════════════
    // 11. GREAT-GRANDPARENTS (depth=-3)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Great Grandfather', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -3, genderAnchor: 'male'),
    VocabularyEntry(term: 'Great Grandmother', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -3, genderAnchor: 'female'),
    VocabularyEntry(term: 'Par Dada', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -3, genderAnchor: 'male', side: FamilySide.paternal),
    VocabularyEntry(term: 'Par Nana', locale: 'hi', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -3, genderAnchor: 'male', side: FamilySide.maternal),

    // ════════════════════════════════════════════════════════════════════
    // 12. GREAT-GRANDCHILDREN (depth=+3)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Great Grandson', locale: 'en', pathPattern: 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 3, genderAnchor: 'male'),
    VocabularyEntry(term: 'Great Granddaughter', locale: 'en', pathPattern: 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 3, genderAnchor: 'female'),

    // ════════════════════════════════════════════════════════════════════
    // 13. GREAT-UNCLE/AUNT (depth=-2, through grandparent)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Great Uncle', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -2, genderAnchor: 'male'),
    VocabularyEntry(term: 'Great Aunt', locale: 'en', pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -2, genderAnchor: 'female'),

    // ════════════════════════════════════════════════════════════════════
    // 14. STEP PARENTS (UP_STEP_PARENT, gen=-1, consanguinity=step)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Step Father', locale: 'en', pathPattern: 'UP_STEP_PARENT', generationDelta: -1, genderAnchor: 'male', consanguinity: Consanguinity.step),
    VocabularyEntry(term: 'Step Mother', locale: 'en', pathPattern: 'UP_STEP_PARENT', generationDelta: -1, genderAnchor: 'female', consanguinity: Consanguinity.step),

    // ════════════════════════════════════════════════════════════════════
    // 15. ADOPTIVE PARENTS (UP_ADOPTIVE_PARENT, gen=-1, consanguinity=adoptive)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Adoptive Father', locale: 'en', pathPattern: 'UP_ADOPTIVE_PARENT', generationDelta: -1, genderAnchor: 'male', consanguinity: Consanguinity.adoptive),
    VocabularyEntry(term: 'Adoptive Mother', locale: 'en', pathPattern: 'UP_ADOPTIVE_PARENT', generationDelta: -1, genderAnchor: 'female', consanguinity: Consanguinity.adoptive),

    // ════════════════════════════════════════════════════════════════════
    // 16. GRANDPARENTS-IN-LAW (SPOUSE_UP_PARENT_UP_PARENT, gen=-2)
    // ════════════════════════════════════════════════════════════════════
    VocabularyEntry(term: 'Grandfather-in-Law', locale: 'en', pathPattern: 'SPOUSE_UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male'),
    VocabularyEntry(term: 'Grandmother-in-Law', locale: 'en', pathPattern: 'SPOUSE_UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female'),
  ];

  /// Resolves a signature to the best matching vocabulary entry.
  /// Returns the term string, or null if no match found.
  static String? resolve({
    required String pathPattern,
    required int generationDelta,
    required FamilySide side,
    required Consanguinity consanguinity,
    required String genderAnchor,
    required String seniority,
    required int removal,
    required bool doubleKinship,
    String? intermediateSeniority,
    FamilySide? spouseSide,
    String? intermediateGender,
    String locale = 'en',
  }) {
    // Try exact match first
    for (final entry in entries) {
      if (entry.locale != locale) continue;
      if (entry.matches(
        path: pathPattern,
        genDelta: generationDelta,
        famSide: side,
        consang: consanguinity,
        gender: genderAnchor,
        senior: seniority,
        remov: removal,
        isDouble: doubleKinship,
        intSenior: intermediateSeniority,
        sSide: spouseSide,
        intGender: intermediateGender,
      )) {
        return entry.term;
      }
    }

    // Fallback: try without seniority
    for (final entry in entries) {
      if (entry.locale != locale) continue;
      if (entry.matches(
        path: pathPattern,
        genDelta: generationDelta,
        famSide: side,
        consang: consanguinity,
        gender: genderAnchor,
        senior: 'none',
        remov: removal,
        isDouble: doubleKinship,
        intSenior: intermediateSeniority,
        sSide: spouseSide,
        intGender: intermediateGender,
      )) {
        return entry.term;
      }
    }

    // Fallback: try without intermediateSeniority
    for (final entry in entries) {
      if (entry.locale != locale) continue;
      if (entry.matches(
        path: pathPattern,
        genDelta: generationDelta,
        famSide: side,
        consang: consanguinity,
        gender: genderAnchor,
        senior: 'none',
        remov: removal,
        isDouble: doubleKinship,
        intSenior: null,
        sSide: spouseSide,
        intGender: intermediateGender,
      )) {
        return entry.term;
      }
    }

    // Fallback: English
    if (locale != 'en') {
      return resolve(
        pathPattern: pathPattern,
        generationDelta: generationDelta,
        side: side,
        consanguinity: consanguinity,
        genderAnchor: genderAnchor,
        seniority: seniority,
        removal: removal,
        doubleKinship: doubleKinship,
        intermediateSeniority: intermediateSeniority,
        spouseSide: spouseSide,
        intermediateGender: intermediateGender,
        locale: 'en',
      );
    }

    return null;
  }
}
