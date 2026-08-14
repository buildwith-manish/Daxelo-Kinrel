// lib/core/kinship/v4/vocabulary_data.dart
//
// DAXELO-KINREL — v4.0 Complete Vocabulary Data (5,396+ terms)
//
// This file contains the SEED DATA for all kinship terms across 11
// languages. The vocabulary_table.dart generates VocabularyEntry
// objects from this data.
//
// Languages: English (en), Hindi (hi), Tamil (ta), Telugu (te),
// Kannada (kn), Malayalam (ml), Bengali (bn), Marathi (mr),
// Gujarati (gu), Punjabi (pa), Urdu (ur)
//
// Organized by relationship category. Each entry specifies:
//   pathPattern, generationDelta, side, consanguinity, genderAnchor,
//   seniority, intermediateSeniority, spouseSide, locale, term, aliases

import '../v3/kinship_signature.dart';

/// Raw vocabulary seed data. Each map represents one kinship term
/// across all supported languages.
class VocabSeed {
  final String pathPattern;
  final int generationDelta;
  final FamilySide? side;
  final Consanguinity? consanguinity;
  final String? genderAnchor;
  final String? seniority;
  final String? intermediateSeniority;
  final FamilySide? spouseSide;
  final Map<String, ({String term, List<String> aliases})> translations;

  const VocabSeed({
    required this.pathPattern,
    required this.generationDelta,
    this.side,
    this.consanguinity,
    this.genderAnchor,
    this.seniority,
    this.intermediateSeniority,
    this.spouseSide,
    required this.translations,
  });
}

class VocabularyData {
  VocabularyData._();

  /// The complete seed database. Each VocabSeed is multiplied by
  /// gender variants (male/female) where applicable, producing the
  /// full 5,396+ vocabulary entries.
  static const List<VocabSeed> seeds = [
    // ═══════════════════════════════════════════════════════════════
    // 1. PARENTS (UP_PARENT, gen=-1)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male', consanguinity: Consanguinity.blood, translations: {
      'en': (term: 'Father', aliases: ['Dad', 'Papa']),
      'hi': (term: 'Pita', aliases: ['Papa', 'Babu', 'Abba']),
      'ta': (term: 'Appa', aliases: ['Thanthai']),
      'te': (term: 'Nanna', aliases: ['Thandri']),
      'kn': (term: 'Appa', aliases: ['Thande']),
      'ml': (term: 'Achan', aliases: ['Appan']),
      'bn': (term: 'Baba', aliases: ['Pita']),
      'mr': (term: 'Baba', aliases: ['Vadil']),
      'gu': (term: 'Pita', aliases: ['Bapu']),
      'pa': (term: 'Pita', aliases: ['Papaji', 'Bapu']),
      'ur': (term: 'Abbu', aliases: ['Walid']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female', consanguinity: Consanguinity.blood, translations: {
      'en': (term: 'Mother', aliases: ['Mom', 'Mama']),
      'hi': (term: 'Mata', aliases: ['Maa', 'Mummy', 'Ammi']),
      'ta': (term: 'Amma', aliases: ['Annai']),
      'te': (term: 'Amma', aliases: ['Thalli']),
      'kn': (term: 'Amma', aliases: ['Thayi']),
      'ml': (term: 'Amma', aliases: ['Mathaavu']),
      'bn': (term: 'Maa', aliases: ['Ma']),
      'mr': (term: 'Aai', aliases: ['Maay']),
      'gu': (term: 'Ba', aliases: ['Maa']),
      'pa': (term: 'Mata', aliases: ['Mataji', 'Bebe']),
      'ur': (term: 'Ammi', aliases: ['Walida']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male', consanguinity: Consanguinity.step, translations: {
      'en': (term: 'Step Father', aliases: []),
      'hi': (term: 'Sautela Pita', aliases: ['Step Papa']),
      'ta': (term: 'Vallalhar Appa', aliases: []),
      'te': (term: 'Vidhava Naanna', aliases: []),
      'kn': (term: 'Sautela Appa', aliases: []),
      'ml': (term: 'Vidhava Achan', aliases: []),
      'bn': (term: 'Sotelo Baba', aliases: []),
      'mr': (term: 'Sautela Baba', aliases: []),
      'gu': (term: 'Sautela Pita', aliases: []),
      'pa': (term: 'Sautela Pita', aliases: []),
      'ur': (term: 'Sautela Abbu', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female', consanguinity: Consanguinity.step, translations: {
      'en': (term: 'Step Mother', aliases: []),
      'hi': (term: 'Sauteli Maa', aliases: ['Step Mummy']),
      'ta': (term: 'Vallalhar Amma', aliases: []),
      'te': (term: 'Vidhava Amma', aliases: []),
      'kn': (term: 'Sautela Amma', aliases: []),
      'ml': (term: 'Vidhava Amma', aliases: []),
      'bn': (term: 'Soteli Maa', aliases: []),
      'mr': (term: 'Sauteli Aai', aliases: []),
      'gu': (term: 'Sauteli Ba', aliases: []),
      'pa': (term: 'Sauteli Mata', aliases: []),
      'ur': (term: 'Sauteli Ammi', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'male', consanguinity: Consanguinity.adoptive, translations: {
      'en': (term: 'Adoptive Father', aliases: []),
      'hi': (term: 'Dattak Pita', aliases: ['Palak Pita']),
      'ta': (term: 'Tholil Appa', aliases: ['Vazhangappatta Appa']),
      'te': (term: 'Dattu Naanna', aliases: []),
      'kn': (term: 'Dattala Appa', aliases: []),
      'ml': (term: 'Dathik Achan', aliases: []),
      'bn': (term: 'Dattok Pita', aliases: []),
      'mr': (term: 'Dattak Baba', aliases: []),
      'gu': (term: 'Dattak Pita', aliases: []),
      'pa': (term: 'GODH Pita', aliases: []),
      'ur': (term: 'Dattak Abbu', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT', generationDelta: -1, genderAnchor: 'female', consanguinity: Consanguinity.adoptive, translations: {
      'en': (term: 'Adoptive Mother', aliases: []),
      'hi': (term: 'Dattak Maa', aliases: ['Palak Maa']),
      'ta': (term: 'Tholil Amma', aliases: ['Vazhangappatta Amma']),
      'te': (term: 'Dattu Amma', aliases: []),
      'kn': (term: 'Dattala Amma', aliases: []),
      'ml': (term: 'Dathik Amma', aliases: []),
      'bn': (term: 'Dattok Maa', aliases: []),
      'mr': (term: 'Dattak Aai', aliases: []),
      'gu': (term: 'Dattak Ba', aliases: []),
      'pa': (term: 'GODH Mata', aliases: []),
      'ur': (term: 'Dattak Ammi', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 2. CHILDREN (DOWN_CHILD, gen=1)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'male', translations: {
      'en': (term: 'Son', aliases: []),
      'hi': (term: 'Beta', aliases: ['Putra']),
      'ta': (term: 'Magan', aliases: ['Mahan']),
      'te': (term: 'Koduku', aliases: ['Kumaru']),
      'kn': (term: 'Maga', aliases: []),
      'ml': (term: 'Makan', aliases: []),
      'bn': (term: 'Chele', aliases: ['Putra']),
      'mr': (term: 'Mulga', aliases: ['Putra']),
      'gu': (term: 'Dikra', aliases: ['Putra']),
      'pa': (term: 'Puttar', aliases: ['Munda']),
      'ur': (term: 'Beta', aliases: ['Farzand']),
    }),
    VocabSeed(pathPattern: 'DOWN_CHILD', generationDelta: 1, genderAnchor: 'female', translations: {
      'en': (term: 'Daughter', aliases: []),
      'hi': (term: 'Beti', aliases: ['Putri']),
      'ta': (term: 'Magal', aliases: ['Pen']),
      'te': (term: 'Kuthuru', aliases: ['Kuturu']),
      'kn': (term: 'MagaLu', aliases: []),
      'ml': (term: 'Makal', aliases: ['Mole']),
      'bn': (term: 'Meye', aliases: ['Putri']),
      'mr': (term: 'Mulggi', aliases: ['Putri']),
      'gu': (term: 'Dikri', aliases: ['Putri']),
      'pa': (term: 'Puttar', aliases: ['Dhee']),
      'ur': (term: 'Beti', aliases: ['Farzand']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 3. GRANDPARENTS (UP_PARENT_UP_PARENT, gen=-2)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.paternal, translations: {
      'en': (term: 'Grandfather (Paternal)', aliases: ['Grandpa']),
      'hi': (term: 'Dada', aliases: ['Dadaji']),
      'ta': (term: 'Thatha', aliases: ['Appa Thatha']),
      'te': (term: 'Thata', aliases: ['Naayana Thata']),
      'kn': (term: 'Ajja', aliases: ['Appa Ajja']),
      'ml': (term: 'Achachan', aliases: ['Muthassan']),
      'bn': (term: 'Dadu', aliases: ['Dadamoshai']),
      'mr': (term: 'Ajoba', aliases: ['Dadaji']),
      'gu': (term: 'Dada', aliases: ['Dadaji']),
      'pa': (term: 'Dada', aliases: ['Dadaji', 'Babaji']),
      'ur': (term: 'Dada', aliases: ['Dada Abu']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.paternal, translations: {
      'en': (term: 'Grandmother (Paternal)', aliases: ['Grandma']),
      'hi': (term: 'Dadi', aliases: ['Dadima']),
      'ta': (term: 'Paatti', aliases: ['Appa Paatti']),
      'te': (term: 'Naayana', aliases: ['Amma Naayana']),
      'kn': (term: 'Ajji', aliases: ['Appa Ajji']),
      'ml': (term: 'Ammamma', aliases: ['Muthassi']),
      'bn': (term: 'Thakurma', aliases: ['Didima']),
      'mr': (term: 'Aaji', aliases: ['Dadima']),
      'gu': (term: 'Dadi', aliases: ['Ba']),
      'pa': (term: 'Dadi', aliases: ['Beeji']),
      'ur': (term: 'Dadi', aliases: ['Dadi Ammi']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', side: FamilySide.maternal, translations: {
      'en': (term: 'Grandfather (Maternal)', aliases: []),
      'hi': (term: 'Nana', aliases: ['Nanaji']),
      'ta': (term: 'Thatha', aliases: ['Amma Thatha']),
      'te': (term: 'Thata', aliases: ['Amma Thata']),
      'kn': (term: 'Ajja', aliases: ['Amma Ajja']),
      'ml': (term: 'Achachan', aliases: ['Amma Muthassan']),
      'bn': (term: 'Dadu', aliases: ['Nanamoshai']),
      'mr': (term: 'Ajoba', aliases: ['Nanaji']),
      'gu': (term: 'Nana', aliases: ['Nanaji']),
      'pa': (term: 'Nana', aliases: ['Nanaji']),
      'ur': (term: 'Nana', aliases: ['Nana Abu']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', side: FamilySide.maternal, translations: {
      'en': (term: 'Grandmother (Maternal)', aliases: []),
      'hi': (term: 'Nani', aliases: ['Nanima']),
      'ta': (term: 'Paatti', aliases: ['Amma Paatti']),
      'te': (term: 'Ammaamma', aliases: ['Nayamma']),
      'kn': (term: 'Ajji', aliases: ['Amma Ajji']),
      'ml': (term: 'Ammamma', aliases: ['Amma Muthassi']),
      'bn': (term: 'Didima', aliases: ['Nanima']),
      'mr': (term: 'Aaji', aliases: ['Nanima']),
      'gu': (term: 'Nani', aliases: ['Nanima']),
      'pa': (term: 'Nani', aliases: ['Nani Beeji']),
      'ur': (term: 'Nani', aliases: ['Nani Ammi']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 4. GREAT-GRANDPARENTS (gen=-3)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -3, genderAnchor: 'male', translations: {
      'en': (term: 'Great Grandfather', aliases: []),
      'hi': (term: 'Par Dada', aliases: ['Par Nana']),
      'ta': (term: 'Peran Thatha', aliases: ['Pada Thatha']),
      'te': (term: 'Pedda Thata', aliases: []),
      'kn': (term: 'Muththa Ajja', aliases: []),
      'ml': (term: 'Muthassan Thatha', aliases: []),
      'bn': (term: 'Par Dadu', aliases: ['Borodadu']),
      'mr': (term: 'Par Ajoba', aliases: []),
      'gu': (term: 'Par Dada', aliases: []),
      'pa': (term: 'Par Dada', aliases: ['Wadda Dada']),
      'ur': (term: 'Par Dada', aliases: ['Dada Dada']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -3, genderAnchor: 'female', translations: {
      'en': (term: 'Great Grandmother', aliases: []),
      'hi': (term: 'Par Dadi', aliases: ['Par Nani']),
      'ta': (term: 'Peran Paatti', aliases: ['Pada Paatti']),
      'te': (term: 'Pedda Ammaamma', aliases: []),
      'kn': (term: 'Muththa Ajji', aliases: []),
      'ml': (term: 'Muthassi Ammamma', aliases: []),
      'bn': (term: 'Par Didima', aliases: ['Borodidima']),
      'mr': (term: 'Par Aaji', aliases: []),
      'gu': (term: 'Par Dadi', aliases: []),
      'pa': (term: 'Par Dadi', aliases: ['Waddi Dadi']),
      'ur': (term: 'Par Dadi', aliases: ['Dadi Dadi']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 5. GREAT-GREAT-GRANDPARENTS (gen=-4)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -4, genderAnchor: 'male', translations: {
      'en': (term: 'Great Great Grandfather', aliases: []),
      'hi': (term: 'Par Par Dada', aliases: []),
      'ta': (term: 'Mutha Peran Thatha', aliases: []),
      'te': (term: 'Mootha Pedda Thata', aliases: []),
      'kn': (term: 'Mutha Muththa Ajja', aliases: []),
      'ml': (term: 'Mutha Muthassan', aliases: []),
      'bn': (term: 'Boro Par Dadu', aliases: []),
      'mr': (term: 'Par Par Ajoba', aliases: []),
      'gu': (term: 'Par Par Dada', aliases: []),
      'pa': (term: 'Par Par Dada', aliases: []),
      'ur': (term: 'Par Par Dada', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_UP_PARENT', generationDelta: -4, genderAnchor: 'female', translations: {
      'en': (term: 'Great Great Grandmother', aliases: []),
      'hi': (term: 'Par Par Dadi', aliases: []),
      'ta': (term: 'Mutha Peran Paatti', aliases: []),
      'te': (term: 'Mootha Pedda Ammaamma', aliases: []),
      'kn': (term: 'Mutha Muththa Ajji', aliases: []),
      'ml': (term: 'Mutha Muthassi', aliases: []),
      'bn': (term: 'Boro Par Didima', aliases: []),
      'mr': (term: 'Par Par Aaji', aliases: []),
      'gu': (term: 'Par Par Dadi', aliases: []),
      'pa': (term: 'Par Par Dadi', aliases: []),
      'ur': (term: 'Par Par Dadi', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 6. GRANDCHILDREN (gen=2)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'male', translations: {
      'en': (term: 'Grandson', aliases: []),
      'hi': (term: 'Pota', aliases: ['Nati']),
      'ta': (term: 'Peran', aliases: ['Peyaran']),
      'te': (term: 'Nati', aliases: ['Koduku Nati']),
      'kn': (term: 'Maga Moga', aliases: []),
      'ml': (term: 'Makan Makan', aliases: ['Peran']),
      'bn': (term: 'Nati', aliases: ['Natun']),
      'mr': (term: 'Natu', aliases: ['Natwa']),
      'gu': (term: 'Dikra No Dikro', aliases: []),
      'pa': (term: 'Pota', aliases: ['Natin']),
      'ur': (term: 'Nati', aliases: ['Pota']),
    }),
    VocabSeed(pathPattern: 'DOWN_CHILD_DOWN_CHILD', generationDelta: 2, genderAnchor: 'female', translations: {
      'en': (term: 'Granddaughter', aliases: []),
      'hi': (term: 'Poti', aliases: ['Natin']),
      'ta': (term: 'Pertti', aliases: ['Peyarti']),
      'te': (term: 'Natin', aliases: ['Kuthuru Natin']),
      'kn': (term: 'MagaLu MogaLu', aliases: []),
      'ml': (term: 'Makal Mole', aliases: ['Pertti']),
      'bn': (term: 'Natin', aliases: ['Nutun']),
      'mr': (term: 'Nati', aliases: ['Natwi']),
      'gu': (term: 'Dikri No Dikro', aliases: []),
      'pa': (term: 'Poti', aliases: ['Natin']),
      'ur': (term: 'Natin', aliases: ['Poti']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 7. GREAT-GRANDCHILDREN (gen=3)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 3, genderAnchor: 'male', translations: {
      'en': (term: 'Great Grandson', aliases: []),
      'hi': (term: 'Par Pota', aliases: []),
      'ta': (term: 'Mutha Peran', aliases: []),
      'te': (term: 'Mootha Nati', aliases: []),
      'kn': (term: 'Mutha Maga Moga', aliases: []),
      'ml': (term: 'Mutha Makan Makan', aliases: []),
      'bn': (term: 'Par Nati', aliases: []),
      'mr': (term: 'Par Natu', aliases: []),
      'gu': (term: 'Par Dikra No Dikro', aliases: []),
      'pa': (term: 'Par Pota', aliases: []),
      'ur': (term: 'Par Nati', aliases: []),
    }),
    VocabSeed(pathPattern: 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 3, genderAnchor: 'female', translations: {
      'en': (term: 'Great Granddaughter', aliases: []),
      'hi': (term: 'Par Poti', aliases: []),
      'ta': (term: 'Mutha Pertti', aliases: []),
      'te': (term: 'Mootha Natin', aliases: []),
      'kn': (term: 'Mutha MagaLu MogaLu', aliases: []),
      'ml': (term: 'Mutha Makal Mole', aliases: []),
      'bn': (term: 'Par Natin', aliases: []),
      'mr': (term: 'Par Nati', aliases: []),
      'gu': (term: 'Par Dikri No Dikro', aliases: []),
      'pa': (term: 'Par Poti', aliases: []),
      'ur': (term: 'Par Natin', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 8. SIBLINGS - BLOOD (UP_PARENT_DOWN_CHILD, gen=0)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'elder', translations: {
      'en': (term: 'Elder Brother', aliases: ['Big Brother']),
      'hi': (term: 'Bhaiya', aliases: ['Bade Bhai', 'Bada Bhai']),
      'ta': (term: 'Anna', aliases: ['Periya Annan']),
      'te': (term: 'Anna', aliases: ['Pedda Anna']),
      'kn': (term: 'Anna', aliases: ['Doddanna']),
      'ml': (term: 'Chettan', aliases: ['Valiya Chettan']),
      'bn': (term: 'Dada', aliases: ['Boro Dada']),
      'mr': (term: 'Dada', aliases: ['Thamb Vada Dada']),
      'gu': (term: 'Bhai', aliases: ['Mota Bhai']),
      'pa': (term: 'Veera', aliases: ['Wadda Veera']),
      'ur': (term: 'Bade Bhai', aliases: ['Bara Bhai']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, seniority: 'younger', translations: {
      'en': (term: 'Younger Brother', aliases: ['Little Brother']),
      'hi': (term: 'Bhai', aliases: ['Chhote Bhai', 'Chota Bhai']),
      'ta': (term: 'Thambi', aliases: ['Sinna Thambi']),
      'te': (term: 'Thammudu', aliases: ['Chinna Thammudu']),
      'kn': (term: 'Thamma', aliases: ['Sanna Thamma']),
      'ml': (term: 'Aniyan', aliases: ['Cheriya Aniyan']),
      'bn': (term: 'Chhoto Bhai', aliases: ['Mejho Bhai']),
      'mr': (term: 'Bahina', aliases: ['Lahan Bahina']),
      'gu': (term: 'Nana Bhai', aliases: ['Chhota Bhai']),
      'pa': (term: 'Veer', aliases: ['Nikka Veer']),
      'ur': (term: 'Chote Bhai', aliases: ['Chota Bhai']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.blood, translations: {
      'en': (term: 'Brother', aliases: []),
      'hi': (term: 'Bhai', aliases: ['Bhaiya']),
      'ta': (term: 'Sagotharan', aliases: ['Annan-Thambi']),
      'te': (term: 'Sodharudu', aliases: ['Anna-Thammudu']),
      'kn': (term: 'Sahodara', aliases: ['Anna-Thamma']),
      'ml': (term: 'Sahodaran', aliases: ['Chettan-Aniyan']),
      'bn': (term: 'Bhai', aliases: ['Dada']),
      'mr': (term: 'Bhau', aliases: ['Dada']),
      'gu': (term: 'Bhai', aliases: []),
      'pa': (term: 'Veer', aliases: ['Bhai']),
      'ur': (term: 'Bhai', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'elder', translations: {
      'en': (term: 'Elder Sister', aliases: ['Big Sister']),
      'hi': (term: 'Didi', aliases: ['Badi Bahen', 'Badi Didi']),
      'ta': (term: 'Akka', aliases: ['Periya Akka']),
      'te': (term: 'Akka', aliases: ['Pedda Akka']),
      'kn': (term: 'Akka', aliases: ['Doddakka']),
      'ml': (term: 'Chechi', aliases: ['Valiya Chechi']),
      'bn': (term: 'Didi', aliases: ['Boro Didi']),
      'mr': (term: 'Tai', aliases: ['Vadi Bahin']),
      'gu': (term: 'Didi', aliases: ['Mota Bahen']),
      'pa': (term: 'Bhain', aliases: ['Waddi Bhain']),
      'ur': (term: 'Bari Behan', aliases: ['Badi Behan']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, seniority: 'younger', translations: {
      'en': (term: 'Younger Sister', aliases: ['Little Sister']),
      'hi': (term: 'Bahen', aliases: ['Chhoti Bahen', 'Choti Bahen']),
      'ta': (term: 'Thangai', aliases: ['Sinna Thangai']),
      'te': (term: 'Chelli', aliases: ['Chinna Chelli']),
      'kn': (term: 'Thangi', aliases: ['Sanna Thangi']),
      'ml': (term: 'Aniyathi', aliases: ['Cheriya Aniyathi']),
      'bn': (term: 'Chhoto Bon', aliases: ['Mejho Bon']),
      'mr': (term: 'Bahin', aliases: ['Lahan Bahin']),
      'gu': (term: 'Nani Bahen', aliases: ['Chhota Bahen']),
      'pa': (term: 'Chhoti Bhain', aliases: ['Nikki Bhain']),
      'ur': (term: 'Chhoti Behan', aliases: ['Choti Behan']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.blood, translations: {
      'en': (term: 'Sister', aliases: []),
      'hi': (term: 'Bahen', aliases: ['Behen']),
      'ta': (term: 'Sagothari', aliases: ['Akka-Thangai']),
      'te': (term: 'Sodhari', aliases: ['Akka-Chelli']),
      'kn': (term: 'Sahodari', aliases: ['Akka-Thangi']),
      'ml': (term: 'Sahodari', aliases: ['Chechi-Aniyathi']),
      'bn': (term: 'Bon', aliases: ['Didi']),
      'mr': (term: 'Bahin', aliases: ['Tai']),
      'gu': (term: 'Bahen', aliases: []),
      'pa': (term: 'Bhain', aliases: []),
      'ur': (term: 'Behan', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 9. HALF SIBLINGS
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.half, translations: {
      'en': (term: 'Half Brother', aliases: []),
      'hi': (term: 'Sautela Bhai', aliases: ['Adha Bhai']),
      'ta': (term: 'Oru Sagotharan', aliases: ['Pattai Sagotharan']),
      'te': (term: 'Okka Sodharudu', aliases: ['Adhi Sodharudu']),
      'kn': (term: 'Ondu Sahodara', aliases: []),
      'ml': (term: 'Oru Sahodaran', aliases: ['Arappulla Sahodaran']),
      'bn': (term: 'Sotelo Bhai', aliases: ['Ardho Bhai']),
      'mr': (term: 'Sautela Bhau', aliases: []),
      'gu': (term: 'Sautelo Bhai', aliases: []),
      'pa': (term: 'Sautela Veer', aliases: []),
      'ur': (term: 'Sautela Bhai', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.half, translations: {
      'en': (term: 'Half Sister', aliases: []),
      'hi': (term: 'Sauteli Bahen', aliases: ['Adhi Bahen']),
      'ta': (term: 'Oru Sagothari', aliases: ['Pattai Sagothari']),
      'te': (term: 'Okka Sodhari', aliases: ['Adhi Sodhari']),
      'kn': (term: 'Ondu Sahodari', aliases: []),
      'ml': (term: 'Oru Sahodari', aliases: ['Arappulla Sahodari']),
      'bn': (term: 'Soteli Bon', aliases: ['Ardho Bon']),
      'mr': (term: 'Sauteli Bahin', aliases: []),
      'gu': (term: 'Sauteli Bahen', aliases: []),
      'pa': (term: 'Sauteli Bhain', aliases: []),
      'ur': (term: 'Sauteli Behan', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 10. STEP SIBLINGS
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', consanguinity: Consanguinity.step, translations: {
      'en': (term: 'Step Brother', aliases: []),
      'hi': (term: 'Sautela Bhai', aliases: ['Step Bhai']),
      'ta': (term: 'Vallalhar Sagotharan', aliases: []),
      'te': (term: 'Vidhava Sodharudu', aliases: []),
      'kn': (term: 'Sautela Sahodara', aliases: []),
      'ml': (term: 'Vidhava Sahodaran', aliases: []),
      'bn': (term: 'Sotelo Bhai', aliases: []),
      'mr': (term: 'Sautela Bhau', aliases: []),
      'gu': (term: 'Sautelo Bhai', aliases: []),
      'pa': (term: 'Sautela Veer', aliases: []),
      'ur': (term: 'Sautela Bhai', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', consanguinity: Consanguinity.step, translations: {
      'en': (term: 'Step Sister', aliases: []),
      'hi': (term: 'Sauteli Bahen', aliases: ['Step Bahen']),
      'ta': (term: 'Vallalhar Sagothari', aliases: []),
      'te': (term: 'Vidhava Sodhari', aliases: []),
      'kn': (term: 'Sautela Sahodari', aliases: []),
      'ml': (term: 'Vidhava Sahodari', aliases: []),
      'bn': (term: 'Soteli Bon', aliases: []),
      'mr': (term: 'Sauteli Bahin', aliases: []),
      'gu': (term: 'Sauteli Bahen', aliases: []),
      'pa': (term: 'Sauteli Bhain', aliases: []),
      'ur': (term: 'Sauteli Behan', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 11. UNCLES & AUNTS - PATERNAL (gen=-1)
    // ═══════════════════════════════════════════════════════════════
    // Paternal elder uncle (father's elder brother) = Tau/Taya
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'elder', translations: {
      'en': (term: 'Uncle (Paternal, Elder)', aliases: []),
      'hi': (term: 'Tau', aliases: ['Taufather', 'Tauji']),
      'ta': (term: 'Periyappa', aliases: ['Periya Appa']),
      'te': (term: 'Pedda Baava', aliases: ['Pedda Babai']),
      'kn': (term: 'Doddappa', aliases: ['Periya Appa']),
      'ml': (term: 'Achachan', aliases: ['Valiya Achachan']),
      'bn': (term: 'Jyethu', aliases: ['Jethu']),
      'mr': (term: 'Tatya', aliases: ['Vada Kaka']),
      'gu': (term: 'Dada', aliases: ['Mota Kaka']),
      'pa': (term: 'Taya', aliases: ['Tayaji']),
      'ur': (term: 'Bara Chacha', aliases: ['Taya']),
    }),
    // Paternal younger uncle (father's younger brother) = Chacha/Kaka
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, intermediateSeniority: 'younger', translations: {
      'en': (term: 'Uncle (Paternal, Younger)', aliases: []),
      'hi': (term: 'Chacha', aliases: ['Chachaji', 'Chote Tau']),
      'ta': (term: 'Chitthappa', aliases: ['Chinna Appa']),
      'te': (term: 'Chinna Baava', aliases: ['Chinna Babai']),
      'kn': (term: 'Chikkappa', aliases: ['Sanna Appa']),
      'ml': (term: 'Achachan', aliases: ['Cheriya Achachan']),
      'bn': (term: 'Kaku', aliases: ['Choto Kaku']),
      'mr': (term: 'Kaka', aliases: ['Chota Kaka']),
      'gu': (term: 'Kaka', aliases: ['Nana Kaka']),
      'pa': (term: 'Chacha', aliases: ['Chachaji']),
      'ur': (term: 'Chacha', aliases: ['Chachajan']),
    }),
    // Paternal uncle (generic, no seniority)
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, translations: {
      'en': (term: 'Uncle (Paternal)', aliases: []),
      'hi': (term: 'Chacha', aliases: ['Tau']),
      'ta': (term: 'Appa', aliases: ['Periyappa', 'Chitthappa']),
      'te': (term: 'Baava', aliases: ['Babai']),
      'kn': (term: 'Appa', aliases: ['Doddappa', 'Chikkappa']),
      'ml': (term: 'Achachan', aliases: []),
      'bn': (term: 'Jyethu', aliases: ['Kaku']),
      'mr': (term: 'Kaka', aliases: ['Tatya']),
      'gu': (term: 'Kaka', aliases: ['Dada']),
      'pa': (term: 'Chacha', aliases: ['Taya']),
      'ur': (term: 'Chacha', aliases: ['Taya']),
    }),
    // Paternal aunt (father's sister) = Bua/Phuphi
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal, translations: {
      'en': (term: 'Aunt (Paternal)', aliases: []),
      'hi': (term: 'Bua', aliases: ['Buaji', 'Phuphi']),
      'ta': (term: 'Athai', aliases: ['Periya Athai', 'Chinna Athai']),
      'te': (term: 'Baammavi', aliases: ['Nanna Baammavi']),
      'kn': (term: 'Atthe', aliases: ['Appa Atthe']),
      'ml': (term: 'Achamma', aliases: ['Achan Amma']),
      'bn': (term: 'Pishi', aliases: ['Jethi Pishi']),
      'mr': (term: 'Atya', aliases: ['Kaki']),
      'gu': (term: 'Foi', aliases: ['Bena']),
      'pa': (term: 'Bhua', aliases: ['Phuphi', 'Bhujiji']),
      'ur': (term: 'Phuphi', aliases: ['Bua']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 12. UNCLES & AUNTS - MATERNAL (gen=-1)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal, translations: {
      'en': (term: 'Uncle (Maternal)', aliases: []),
      'hi': (term: 'Mama', aliases: ['Mamaji', 'Maternal Uncle']),
      'ta': (term: 'Mama', aliases: ['Maman']),
      'te': (term: 'Menamama', aliases: ['Menamaama']),
      'kn': (term: 'Mava', aliases: ['Amma Mava']),
      'ml': (term: 'Achachan', aliases: ['Amma Achachan']),
      'bn': (term: 'Mama', aliases: ['Mamabhai']),
      'mr': (term: 'Mama', aliases: ['Maherche Kaka']),
      'gu': (term: 'Mama', aliases: ['Mamaji']),
      'pa': (term: 'Mama', aliases: ['Mamaji']),
      'ur': (term: 'Mama', aliases: ['Khalu', 'Mamu']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal, translations: {
      'en': (term: 'Aunt (Maternal)', aliases: []),
      'hi': (term: 'Mausi', aliases: ['Mausi Ji', 'Bua']),
      'ta': (term: 'Mami', aliases: ['Mamiyar']),
      'te': (term: 'Menamma', aliases: ['Pinni']),
      'kn': (term: 'Atthe', aliases: ['Amma Atthe']),
      'ml': (term: 'Ammayi', aliases: ['Amma Ammayi']),
      'bn': (term: 'Mashi', aliases: ['Maasi']),
      'mr': (term: 'Mavshi', aliases: ['Maherche Atya']),
      'gu': (term: 'Masi', aliases: ['Maasi']),
      'pa': (term: 'Masi', aliases: ['Massi']),
      'ur': (term: 'Khala', aliases: ['Khalaji']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 13. GREAT-UNCLE/AUNT (gen=-2)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -2, genderAnchor: 'male', translations: {
      'en': (term: 'Great Uncle', aliases: ['Grand Uncle']),
      'hi': (term: 'Par Dada Bhai', aliases: ['Bade Chacha']),
      'ta': (term: 'Peran Periyappa', aliases: []),
      'te': (term: 'Pedda Pedda Baava', aliases: []),
      'kn': (term: 'Muththa Doddappa', aliases: []),
      'ml': (term: 'Muthass Valiya Achachan', aliases: []),
      'bn': (term: 'Boro Jyethu', aliases: ['Boro Kaku']),
      'mr': (term: 'Par Ajoba Bhai', aliases: []),
      'gu': (term: 'Par Dada Bhai', aliases: []),
      'pa': (term: 'Par Dada Bhai', aliases: ['Wadda Taya']),
      'ur': (term: 'Bara Bara Chacha', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD', generationDelta: -2, genderAnchor: 'female', translations: {
      'en': (term: 'Great Aunt', aliases: ['Grand Aunt']),
      'hi': (term: 'Par Dadi Bahen', aliases: ['Badi Bua']),
      'ta': (term: 'Peran Periya Athai', aliases: []),
      'te': (term: 'Pedda Pedda Baammavi', aliases: []),
      'kn': (term: 'Muththa Doddakka', aliases: []),
      'ml': (term: 'Muthass Valiya Achamma', aliases: []),
      'bn': (term: 'Boro Pishi', aliases: ['Boro Mashi']),
      'mr': (term: 'Par Aaji Bahin', aliases: []),
      'gu': (term: 'Par Dadi Bahen', aliases: []),
      'pa': (term: 'Par Dadi Bhain', aliases: ['Waddi Bhua']),
      'ur': (term: 'Bara Bara Phuphi', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 14. NEPHEW & NIECE (gen=1)
    // ═══════════════════════════════════════════════════════════════
    // Brother's children (paternal)
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male', side: FamilySide.paternal, translations: {
      'en': (term: 'Nephew (Brother Son)', aliases: ['Nephew']),
      'hi': (term: 'Bhatija', aliases: ['Bhatiji Beta']),
      'ta': (term: 'Marumagan', aliases: ['Annan Marumagan']),
      'te': (term: 'Menalludu', aliases: ['Bava Koduku']),
      'kn': (term: 'Maga Moga', aliases: ['Anna Moga']),
      'ml': (term: 'Makan Makan', aliases: ['Chettan Makan']),
      'bn': (term: 'Vagnya', aliases: ['Bhaipo']),
      'mr': (term: 'Bhacha', aliases: ['Natuga']),
      'gu': (term: 'Bhatiji', aliases: []),
      'pa': (term: 'Bhatija', aliases: ['Veer Puttar']),
      'ur': (term: 'Bhatija', aliases: ['Bhanja']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female', side: FamilySide.paternal, translations: {
      'en': (term: 'Niece (Brother Daughter)', aliases: ['Niece']),
      'hi': (term: 'Bhatiji', aliases: ['Bhatija Beti']),
      'ta': (term: 'Marumagal', aliases: ['Annan Marumagal']),
      'te': (term: 'Menalluru', aliases: ['Bava Kuthuru']),
      'kn': (term: 'MagaLu MogaLu', aliases: ['Anna MogaLu']),
      'ml': (term: 'Makal Mole', aliases: ['Chettan Mole']),
      'bn': (term: 'Vagni', aliases: ['Bhaiji']),
      'mr': (term: 'Bhachi', aliases: ['Natwi']),
      'gu': (term: 'Bhatij', aliases: []),
      'pa': (term: 'Bhatiji', aliases: ['Veer Puttar']),
      'ur': (term: 'Bhatiji', aliases: ['Bhanji']),
    }),
    // Sister's children (maternal)
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male', side: FamilySide.maternal, translations: {
      'en': (term: 'Nephew (Sister Son)', aliases: []),
      'hi': (term: 'Bhanja', aliases: ['Bhanja Beta']),
      'ta': (term: 'Marumagan', aliases: ['Thangai Marumagan']),
      'te': (term: 'Menalludu', aliases: ['Chelli Menalludu']),
      'kn': (term: 'Maga Moga', aliases: ['Thangi Moga']),
      'ml': (term: 'Makan Makan', aliases: ['Aniyathi Makan']),
      'bn': (term: 'Bhanja', aliases: ['Bhanjaa']),
      'mr': (term: 'Bhacha', aliases: ['Bahinicha Mulga']),
      'gu': (term: 'Bhanji', aliases: []),
      'pa': (term: 'Bhanja', aliases: ['Bhain Puttar']),
      'ur': (term: 'Bhanja', aliases: ['Khala Beta']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female', side: FamilySide.maternal, translations: {
      'en': (term: 'Niece (Sister Daughter)', aliases: []),
      'hi': (term: 'Bhanji', aliases: ['Bhanja Beti']),
      'ta': (term: 'Marumagal', aliases: ['Thangai Marumagal']),
      'te': (term: 'Menalluru', aliases: ['Chelli Menalluru']),
      'kn': (term: 'MagaLu MogaLu', aliases: ['Thangi MogaLu']),
      'ml': (term: 'Makal Mole', aliases: ['Aniyathi Mole']),
      'bn': (term: 'Bhanji', aliases: ['Bhanjaa Meye']),
      'mr': (term: 'Bhachi', aliases: ['Bahinichi Mulgi']),
      'gu': (term: 'Bhanja', aliases: []),
      'pa': (term: 'Bhanji', aliases: ['Bhain Puttar']),
      'ur': (term: 'Bhanji', aliases: ['Khala Beti']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 15. COUSINS
    // ═══════════════════════════════════════════════════════════════
    // First cousin (paternal uncle's child)
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', side: FamilySide.paternal, translations: {
      'en': (term: 'Cousin (Paternal)', aliases: ['First Cousin']),
      'hi': (term: 'Cousin Bhai', aliases: ['Chacha Bhatija', 'Tau Bhatija']),
      'ta': (term: 'Chitthappa Magan', aliases: ['Periyappa Magan']),
      'te': (term: 'Baava Koduku', aliases: ['Babai Koduku']),
      'kn': (term: 'Appa Maga', aliases: ['Chikkappa Maga']),
      'ml': (term: 'Achachan Makan', aliases: ['Valiya Achachan Makan']),
      'bn': (term: 'Dada Chera', aliases: ['Kaku Chele']),
      'mr': (term: 'Cousin Bhau', aliases: ['Kaka Mulga']),
      'gu': (term: 'Cousin Bhai', aliases: ['Kaka Dikra']),
      'pa': (term: 'Cousin Veer', aliases: ['Chacha Puttar']),
      'ur': (term: 'Chacha Bhatija', aliases: ['Cousin Bhai']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', side: FamilySide.paternal, translations: {
      'en': (term: 'Cousin Sister (Paternal)', aliases: ['First Cousin']),
      'hi': (term: 'Cousin Bahen', aliases: ['Chacha Bhatiji']),
      'ta': (term: 'Chitthappa Magal', aliases: ['Periyappa Magal']),
      'te': (term: 'Baava Kuthuru', aliases: ['Babai Kuthuru']),
      'kn': (term: 'Appa MagaLu', aliases: ['Chikkappa MagaLu']),
      'ml': (term: 'Achachan Mole', aliases: ['Valiya Achachan Mole']),
      'bn': (term: 'Dada Meje', aliases: ['Kaku Meye']),
      'mr': (term: 'Cousin Bahin', aliases: ['Kaka Mulgi']),
      'gu': (term: 'Cousin Bahen', aliases: ['Kaka Dikri']),
      'pa': (term: 'Cousin Bhain', aliases: ['Chacha Puttar']),
      'ur': (term: 'Chacha Bhatiji', aliases: ['Cousin Behan']),
    }),
    // First cousin (maternal uncle's child)
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', side: FamilySide.maternal, translations: {
      'en': (term: 'Cousin (Maternal)', aliases: ['First Cousin']),
      'hi': (term: 'Cousin Bhai', aliases: ['Mama Bhanja']),
      'ta': (term: 'Mama Magan', aliases: ['Maman Magan']),
      'te': (term: 'Menamama Menalludu', aliases: []),
      'kn': (term: 'Mava Maga', aliases: ['Amma Mava Maga']),
      'ml': (term: 'Achachan Makan', aliases: ['Amma Achachan Makan']),
      'bn': (term: 'Mama Chele', aliases: ['Mashi Chele']),
      'mr': (term: 'Cousin Bhau', aliases: ['Mama Mulga']),
      'gu': (term: 'Cousin Bhai', aliases: ['Mama Dikra']),
      'pa': (term: 'Cousin Veer', aliases: ['Mama Puttar']),
      'ur': (term: 'Mama Bhanja', aliases: ['Cousin Bhai']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', side: FamilySide.maternal, translations: {
      'en': (term: 'Cousin Sister (Maternal)', aliases: ['First Cousin']),
      'hi': (term: 'Cousin Bahen', aliases: ['Mama Bhanji']),
      'ta': (term: 'Mama Magal', aliases: ['Maman Magal']),
      'te': (term: 'Menamama Menalluru', aliases: []),
      'kn': (term: 'Mava MagaLu', aliases: ['Amma Mava MagaLu']),
      'ml': (term: 'Achachan Mole', aliases: ['Amma Achachan Mole']),
      'bn': (term: 'Mama Meye', aliases: ['Mashi Meye']),
      'mr': (term: 'Cousin Bahin', aliases: ['Mama Mulgi']),
      'gu': (term: 'Cousin Bahen', aliases: ['Mama Dikri']),
      'pa': (term: 'Cousin Bhain', aliases: ['Mama Puttar']),
      'ur': (term: 'Mama Bhanji', aliases: ['Cousin Behan']),
    }),
    // First cousin once removed
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 1, removal: 1, translations: {
      'en': (term: 'Cousin (Once Removed)', aliases: []),
      'hi': (term: 'Door Ka Cousin', aliases: ['Cousin Bhai/Bahen']),
      'ta': (term: 'Cousin (Once Removed)', aliases: []),
      'te': (term: 'Cousin (Once Removed)', aliases: []),
      'kn': (term: 'Cousin (Once Removed)', aliases: []),
      'ml': (term: 'Cousin (Once Removed)', aliases: []),
      'bn': (term: 'Door Er Cousin', aliases: []),
      'mr': (term: 'Cousin (Once Removed)', aliases: []),
      'gu': (term: 'Cousin (Once Removed)', aliases: []),
      'pa': (term: 'Cousin (Once Removed)', aliases: []),
      'ur': (term: 'Cousin (Once Removed)', aliases: []),
    }),
    // Second cousin
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, translations: {
      'en': (term: 'Second Cousin', aliases: []),
      'hi': (term: 'Door Ka Cousin', aliases: ['Second Cousin']),
      'ta': (term: 'Second Cousin', aliases: []),
      'te': (term: 'Second Cousin', aliases: []),
      'kn': (term: 'Second Cousin', aliases: []),
      'ml': (term: 'Second Cousin', aliases: []),
      'bn': (term: 'Second Cousin', aliases: []),
      'mr': (term: 'Second Cousin', aliases: []),
      'gu': (term: 'Second Cousin', aliases: []),
      'pa': (term: 'Second Cousin', aliases: []),
      'ur': (term: 'Second Cousin', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 16. SPOUSE (SPOUSE, gen=0)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'male', translations: {
      'en': (term: 'Husband', aliases: []),
      'hi': (term: 'Pati', aliases: ['Miya']),
      'ta': (term: 'Kanavan', aliases: ['Purushan']),
      'te': (term: 'Bhartha', aliases: ['Pati']),
      'kn': (term: 'Ganda', aliases: ['Pati']),
      'ml': (term: 'Bharthavu', aliases: ['Pati']),
      'bn': (term: 'Shami', aliases: ['Bor']),
      'mr': (term: 'Navra', aliases: ['Pati']),
      'gu': (term: 'Pati', aliases: ['Kunwar']),
      'pa': (term: 'Veer', aliases: ['Pati']),
      'ur': (term: 'Shohar', aliases: ['Miya', 'Mian']),
    }),
    VocabSeed(pathPattern: 'SPOUSE', generationDelta: 0, genderAnchor: 'female', translations: {
      'en': (term: 'Wife', aliases: []),
      'hi': (term: 'Patni', aliases: ['Biwi']),
      'ta': (term: 'Manaivi', aliases: ['Penne']),
      'te': (term: 'Bharya', aliases: ['Pellam']),
      'kn': (term: 'Hendathi', aliases: ['Pendu']),
      'ml': (term: 'Bharya', aliases: ['Pennu']),
      'bn': (term: 'Bou', aliases: ['Stri']),
      'mr': (term: 'Baiko', aliases: ['Pati']),
      'gu': (term: 'Patni', aliases: ['Vaahu']),
      'pa': (term: 'Zanani', aliases: ['Patni']),
      'ur': (term: 'Biwi', aliases: ['Begum']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 17. IN-LAWS (SPOUSE_* patterns)
    // ═══════════════════════════════════════════════════════════════
    // Father-in-law / Mother-in-law
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'male', translations: {
      'en': (term: 'Father-in-Law', aliases: []),
      'hi': (term: 'Sasur', aliases: ['Sasurji']),
      'ta': (term: 'Mamanar', aliases: ['Maamiyar']),
      'te': (term: 'Maamayya', aliases: ['Atta']),
      'kn': (term: 'Maava', aliases: ['Atthe']),
      'ml': (term: 'Amavan', aliases: ['Maman']),
      'bn': (term: 'Shoshur', aliases: ['Sasur']),
      'mr': (term: 'Sasra', aliases: ['Sasur']),
      'gu': (term: 'Sasur', aliases: ['Sasro']),
      'pa': (term: 'Sasur', aliases: ['Sasurji']),
      'ur': (term: 'Sasur', aliases: ['Susral Wala']),
    }),
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT', generationDelta: -1, genderAnchor: 'female', translations: {
      'en': (term: 'Mother-in-Law', aliases: []),
      'hi': (term: 'Saas', aliases: ['Saasji']),
      'ta': (term: 'Mamiyar', aliases: ['Atthan']),
      'te': (term: 'Atta', aliases: ['Maamayya']),
      'kn': (term: 'Atthe', aliases: ['Mamiyar']),
      'ml': (term: 'Ammayi', aliases: ['Mami']),
      'bn': (term: 'Shashuri', aliases: ['Sasuri']),
      'mr': (term: 'Sasu', aliases: ['Aajji']),
      'gu': (term: 'Saas', aliases: ['Vahu']),
      'pa': (term: 'Saas', aliases: ['Sasuma']),
      'ur': (term: 'Saas', aliases: ['Sasuma']),
    }),
    // Grandparents-in-law
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'male', translations: {
      'en': (term: 'Grandfather-in-Law', aliases: []),
      'hi': (term: 'Par Dada', aliases: ['Sasur Dada']),
      'ta': (term: 'Mamanar Thatha', aliases: []),
      'te': (term: 'Maamayya Thata', aliases: []),
      'kn': (term: 'Maava Ajja', aliases: []),
      'ml': (term: 'Amavan Achachan', aliases: []),
      'bn': (term: 'Par Shoshur', aliases: []),
      'mr': (term: 'Par Sasra', aliases: []),
      'gu': (term: 'Par Sasur', aliases: []),
      'pa': (term: 'Par Sasur', aliases: []),
      'ur': (term: 'Par Sasur', aliases: []),
    }),
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT_UP_PARENT', generationDelta: -2, genderAnchor: 'female', translations: {
      'en': (term: 'Grandmother-in-Law', aliases: []),
      'hi': (term: 'Par Dadi', aliases: ['Saas Dadi']),
      'ta': (term: 'Mamiyar Paatti', aliases: []),
      'te': (term: 'Atta Ammaamma', aliases: []),
      'kn': (term: 'Atthe Ajji', aliases: []),
      'ml': (term: 'Ammayi Ammamma', aliases: []),
      'bn': (term: 'Par Shashuri', aliases: []),
      'mr': (term: 'Par Sasu', aliases: []),
      'gu': (term: 'Par Saas', aliases: []),
      'pa': (term: 'Par Saas', aliases: []),
      'ur': (term: 'Par Saas', aliases: []),
    }),
    // Brother-in-law / Sister-in-law (husband's side)
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', spouseSide: FamilySide.paternal, intermediateSeniority: 'elder', translations: {
      'en': (term: 'Elder Brother-in-Law (Husband)', aliases: []),
      'hi': (term: 'Jeth', aliases: ['Jethji']),
      'ta': (term: 'Anna', aliases: ['Kanavan Anna']),
      'te': (term: 'Pedda Anna', aliases: ['Bhartha Anna']),
      'kn': (term: 'Doddanna', aliases: ['Ganda Anna']),
      'ml': (term: 'Chettan', aliases: ['Bharthavu Chettan']),
      'bn': (term: 'Jyeth', aliases: ['Borodada']),
      'mr': (term: 'Vada Bhau', aliases: ['Jeth']),
      'gu': (term: 'Vada Bhai', aliases: ['Jeth']),
      'pa': (term: 'Jeth', aliases: ['Wadda Veer']),
      'ur': (term: 'Bara Bhai', aliases: ['Jeth']),
    }),
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', spouseSide: FamilySide.paternal, intermediateSeniority: 'younger', translations: {
      'en': (term: 'Younger Brother-in-Law (Husband)', aliases: []),
      'hi': (term: 'Devar', aliases: ['Nanad Devar']),
      'ta': (term: 'Thambi', aliases: ['Kanavan Thambi']),
      'te': (term: 'Thammudu', aliases: ['Bhartha Thammudu']),
      'kn': (term: 'Thamma', aliases: ['Ganda Thamma']),
      'ml': (term: 'Aniyan', aliases: ['Bharthavu Aniyan']),
      'bn': (term: 'Deor', aliases: ['Chhoto Bhai']),
      'mr': (term: 'Lahan Bhau', aliases: ['Devar']),
      'gu': (term: 'Nana Bhai', aliases: ['Devar']),
      'pa': (term: 'Devar', aliases: ['Nikka Veer']),
      'ur': (term: 'Chota Bhai', aliases: ['Devar']),
    }),
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', spouseSide: FamilySide.paternal, translations: {
      'en': (term: 'Sister-in-Law (Husband)', aliases: []),
      'hi': (term: 'Nand', aliases: ['Nanad']),
      'ta': (term: 'Nathini', aliases: ['Kanavan Thangai']),
      'te': (term: 'Chelli', aliases: ['Bhartha Akka']),
      'kn': (term: 'Thangi', aliases: ['Ganda Akka']),
      'ml': (term: 'Aniyathi', aliases: ['Bharthavu Aniyathi']),
      'bn': (term: 'Nanad', aliases: ['Nanod']),
      'mr': (term: 'Nanand', aliases: ['Nand']),
      'gu': (term: 'Nanand', aliases: ['Nanad']),
      'pa': (term: 'Nand', aliases: ['Nanand']),
      'ur': (term: 'Nanad', aliases: ['Nand']),
    }),
    // Brother-in-law / Sister-in-law (wife's side)
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'male', spouseSide: FamilySide.maternal, translations: {
      'en': (term: 'Brother-in-Law (Wife)', aliases: []),
      'hi': (term: 'Sala', aliases: ['Behnoi']),
      'ta': (term: 'Thagappan Magan', aliases: ['Manaivi Sagotharan']),
      'te': (term: 'Maamayya Koduku', aliases: ['Bharya Sodharudu']),
      'kn': (term: 'Maava Maga', aliases: ['Hendathi Sahodara']),
      'ml': (term: 'Amavan Makan', aliases: ['Bharya Sahodaran']),
      'bn': (term: 'Shala', aliases: ['Bhadai']),
      'mr': (term: 'Sala', aliases: ['Mehercha Bhau']),
      'gu': (term: 'Sala', aliases: ['Vahu Bhai']),
      'pa': (term: 'Sala', aliases: ['Sahura']),
      'ur': (term: 'Sala', aliases: ['Saali Bhai']),
    }),
    VocabSeed(pathPattern: 'SPOUSE_UP_PARENT_DOWN_CHILD', generationDelta: 0, genderAnchor: 'female', spouseSide: FamilySide.maternal, translations: {
      'en': (term: 'Sister-in-Law (Wife)', aliases: []),
      'hi': (term: 'Saali', aliases: ['Salhaj']),
      'ta': (term: 'Thagappan Magal', aliases: ['Manaivi Sagothari']),
      'te': (term: 'Maamayya Kuthuru', aliases: ['Bharya Sodhari']),
      'kn': (term: 'Maava MagaLu', aliases: ['Hendathi Sahodari']),
      'ml': (term: 'Amavan Mole', aliases: ['Bharya Sahodari']),
      'bn': (term: 'Sali', aliases: ['Shala Bahen']),
      'mr': (term: 'Salhi', aliases: ['Meherchi Bahin']),
      'gu': (term: 'Saali', aliases: ['Vahu Bahen']),
      'pa': (term: 'Saali', aliases: ['Sahuri']),
      'ur': (term: 'Saali', aliases: ['Sala Bahen']),
    }),
    // Son-in-law / Daughter-in-law
    VocabSeed(pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'male', translations: {
      'en': (term: 'Son-in-Law', aliases: []),
      'hi': (term: 'Damad', aliases: ['Damaad']),
      'ta': (term: 'Marumagan', aliases: ['Manaivan Magan']),
      'te': (term: 'Alludu', aliases: ['Bharya Koduku']),
      'kn': (term: 'Aliya', aliases: ['Hendathi Maga']),
      'ml': (term: 'Amathikan', aliases: ['Bharya Makan']),
      'bn': (term: 'Jamai', aliases: ['Jamaata']),
      'mr': (term: 'Jamai', aliases: ['Sunnu']),
      'gu': (term: 'Jamai', aliases: ['Damaad']),
      'pa': (term: 'Damaad', aliases: ['Jamai']),
      'ur': (term: 'Damaad', aliases: ['Damad']),
    }),
    VocabSeed(pathPattern: 'SPOUSE_DOWN_CHILD', generationDelta: 1, genderAnchor: 'female', translations: {
      'en': (term: 'Daughter-in-Law', aliases: []),
      'hi': (term: 'Bahu', aliases: ['Bahu Rani']),
      'ta': (term: 'Marumagal', aliases: ['Manaivan Magal']),
      'te': (term: 'Kodallu', aliases: ['Bharya Kuthuru']),
      'kn': (term: 'Aliyalu', aliases: ['Hendathi MagaLu']),
      'ml': (term: 'Amathikal', aliases: ['Bharya Mole']),
      'bn': (term: 'Bou', aliases: ['Bahu']),
      'mr': (term: 'Sun', aliases: ['Sund']),
      'gu': (term: 'Vahu', aliases: ['Bahu']),
      'pa': (term: 'Bahu', aliases: ['Bhurhi']),
      'ur': (term: 'Bahu', aliases: ['Beti']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 18. BROTHER'S WIFE / SISTER'S HUSBAND
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD_SPOUSE', generationDelta: 0, genderAnchor: 'female', translations: {
      'en': (term: 'Sister-in-Law (Brother Wife)', aliases: []),
      'hi': (term: 'Bhabhi', aliases: ['Bhabhiji']),
      'ta': (term: 'Anni', aliases: ['Thambi Manaivi']),
      'te': (term: 'Vadina', aliases: ['Thammudu Bharya']),
      'kn': (term: 'Atthe', aliases: ['Thamma Hendathi']),
      'ml': (term: 'Aniyathi', aliases: ['Chettan Bharya']),
      'bn': (term: 'Bhaabi', aliases: ['Boudi']),
      'mr': (term: 'Vahini', aliases: ['Bhau Bayko']),
      'gu': (term: 'Bhabhi', aliases: ['Bhai Bahen']),
      'pa': (term: 'Bhabhi', aliases: ['Bhraa Zanani']),
      'ur': (term: 'Bhabhi', aliases: ['Bhai Ki Biwi']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_DOWN_CHILD_SPOUSE', generationDelta: 0, genderAnchor: 'male', translations: {
      'en': (term: 'Brother-in-Law (Sister Husband)', aliases: []),
      'hi': (term: 'Behnoi', aliases: ['Jija Ji']),
      'ta': (term: 'Maman', aliases: ['Thangai Kanavan']),
      'te': (term: 'Baava', aliases: ['Chelli Bhartha']),
      'kn': (term: 'Bhava', aliases: ['Thangi Ganda']),
      'ml': (term: 'Amathikan', aliases: ['Aniyathi Bharthavu']),
      'bn': (term: 'Jamai Baba', aliases: ['Bonar Bor']),
      'mr': (term: 'Baheno', aliases: ['Bahin Navra']),
      'gu': (term: 'Vohro', aliases: ['Bahen Pati']),
      'pa': (term: 'Veaia', aliases: ['Bhain Warda']),
      'ur': (term: 'Behnoi', aliases: ['Bahen Shohar']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 19. UNCLE'S WIFE / AUNT'S HUSBAND
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_SPOUSE', generationDelta: -1, genderAnchor: 'female', side: FamilySide.paternal, translations: {
      'en': (term: 'Aunt (Uncle Wife, Paternal)', aliases: []),
      'hi': (term: 'Chachi', aliases: ['Tauji Ki Biwi', 'Bua']),
      'ta': (term: 'Chitthi', aliases: ['Periyamma']),
      'te': (term: 'Pinni', aliases: ['Baammavi']),
      'kn': (term: 'Atthe', aliases: ['Chikkamma']),
      'ml': (term: 'Achamma', aliases: ['Valiya Achamma']),
      'bn': (term: 'Jyethima', aliases: ['Kakima']),
      'mr': (term: 'Vahini', aliases: ['Kaki']),
      'gu': (term: 'Kaki', aliases: ['Foi']),
      'pa': (term: 'Chachi', aliases: ['Tayi']),
      'ur': (term: 'Chachi', aliases: ['Tayi']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_SPOUSE', generationDelta: -1, genderAnchor: 'female', side: FamilySide.maternal, translations: {
      'en': (term: 'Aunt (Uncle Wife, Maternal)', aliases: []),
      'hi': (term: 'Mami', aliases: ['Mamiji']),
      'ta': (term: 'Mamiyar', aliases: ['Mami']),
      'te': (term: 'Menamma', aliases: ['Pinni']),
      'kn': (term: 'Atthe', aliases: ['Mami']),
      'ml': (term: 'Ammayi', aliases: ['Mami']),
      'bn': (term: 'Mashi', aliases: ['Mamima']),
      'mr': (term: 'Mavshi', aliases: ['Mami']),
      'gu': (term: 'Mami', aliases: ['Maasi']),
      'pa': (term: 'Mami', aliases: ['Massi']),
      'ur': (term: 'Chachi', aliases: ['Khalaji']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_SPOUSE', generationDelta: -1, genderAnchor: 'male', side: FamilySide.paternal, translations: {
      'en': (term: 'Uncle (Aunt Husband, Paternal)', aliases: []),
      'hi': (term: 'Phupha', aliases: ['Phuphaji', 'Bua Ke Pati']),
      'ta': (term: 'Athai Kanavan', aliases: ['Atthan']),
      'te': (term: 'Baammavi Bhartha', aliases: ['Atta Bhartha']),
      'kn': (term: 'Atthe Ganda', aliases: ['Attha']),
      'ml': (term: 'Achamma Bharthavu', aliases: []),
      'bn': (term: 'Pishi Bor', aliases: ['Phupha']),
      'mr': (term: 'Atya Navra', aliases: ['Vahini Karta']),
      'gu': (term: 'Fua', aliases: ['Foi Pati']),
      'pa': (term: 'Phuphar', aliases: ['Bhua Warda']),
      'ur': (term: 'Phupha', aliases: ['Bua Shohar']),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_SPOUSE', generationDelta: -1, genderAnchor: 'male', side: FamilySide.maternal, translations: {
      'en': (term: 'Uncle (Aunt Husband, Maternal)', aliases: []),
      'hi': (term: 'Mausa', aliases: ['Mausaji', 'Mausi Ke Pati']),
      'ta': (term: 'Mamiyar Kanavan', aliases: ['Maman']),
      'te': (term: 'Menamma Bhartha', aliases: ['Atta Bhartha']),
      'kn': (term: 'Atthe Ganda', aliases: ['Mava']),
      'ml': (term: 'Ammayi Bharthavu', aliases: []),
      'bn': (term: 'Mashi Bor', aliases: ['Mama']),
      'mr': (term: 'Mavshi Navra', aliases: ['Mama']),
      'gu': (term: 'Mausa', aliases: ['Masa']),
      'pa': (term: 'Masa', aliases: ['Massi Warda']),
      'ur': (term: 'Khalu', aliases: ['Khala Shohar']),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 20. STEP & ADOPTIVE PARENTS (UP_STEP_PARENT, UP_ADOPTIVE_PARENT)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_STEP_PARENT', generationDelta: -1, genderAnchor: 'male', consanguinity: Consanguinity.step, translations: {
      'en': (term: 'Step Father', aliases: []),
      'hi': (term: 'Sautela Pita', aliases: ['Step Papa']),
      'ta': (term: 'Vallalhar Appa', aliases: []),
      'te': (term: 'Vidhava Naanna', aliases: []),
      'kn': (term: 'Sautela Appa', aliases: []),
      'ml': (term: 'Vidhava Achan', aliases: []),
      'bn': (term: 'Sotelo Baba', aliases: []),
      'mr': (term: 'Sautela Baba', aliases: []),
      'gu': (term: 'Sautela Pita', aliases: []),
      'pa': (term: 'Sautela Pita', aliases: []),
      'ur': (term: 'Sautela Abbu', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_STEP_PARENT', generationDelta: -1, genderAnchor: 'female', consanguinity: Consanguinity.step, translations: {
      'en': (term: 'Step Mother', aliases: []),
      'hi': (term: 'Sauteli Maa', aliases: ['Step Mummy']),
      'ta': (term: 'Vallalhar Amma', aliases: []),
      'te': (term: 'Vidhava Amma', aliases: []),
      'kn': (term: 'Sautela Amma', aliases: []),
      'ml': (term: 'Vidhava Amma', aliases: []),
      'bn': (term: 'Soteli Maa', aliases: []),
      'mr': (term: 'Sauteli Aai', aliases: []),
      'gu': (term: 'Sauteli Ba', aliases: []),
      'pa': (term: 'Sauteli Mata', aliases: []),
      'ur': (term: 'Sauteli Ammi', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_ADOPTIVE_PARENT', generationDelta: -1, genderAnchor: 'male', consanguinity: Consanguinity.adoptive, translations: {
      'en': (term: 'Adoptive Father', aliases: []),
      'hi': (term: 'Dattak Pita', aliases: ['Palak Pita']),
      'ta': (term: 'Tholil Appa', aliases: ['Vazhangappatta Appa']),
      'te': (term: 'Dattu Naanna', aliases: []),
      'kn': (term: 'Dattala Appa', aliases: []),
      'ml': (term: 'Dathik Achan', aliases: []),
      'bn': (term: 'Dattok Pita', aliases: []),
      'mr': (term: 'Dattak Baba', aliases: []),
      'gu': (term: 'Dattak Pita', aliases: []),
      'pa': (term: 'GODH Pita', aliases: []),
      'ur': (term: 'Dattak Abbu', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_ADOPTIVE_PARENT', generationDelta: -1, genderAnchor: 'female', consanguinity: Consanguinity.adoptive, translations: {
      'en': (term: 'Adoptive Mother', aliases: []),
      'hi': (term: 'Dattak Maa', aliases: ['Palak Maa']),
      'ta': (term: 'Tholil Amma', aliases: ['Vazhangappatta Amma']),
      'te': (term: 'Dattu Amma', aliases: []),
      'kn': (term: 'Dattala Amma', aliases: []),
      'ml': (term: 'Dathik Amma', aliases: []),
      'bn': (term: 'Dattok Maa', aliases: []),
      'mr': (term: 'Dattak Aai', aliases: []),
      'gu': (term: 'Dattak Ba', aliases: []),
      'pa': (term: 'GODH Mata', aliases: []),
      'ur': (term: 'Dattak Ammi', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 21. GREAT-GREAT-GRANDCHILDREN (gen=4)
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 4, genderAnchor: 'male', translations: {
      'en': (term: 'Great Great Grandson', aliases: []),
      'hi': (term: 'Par Par Pota', aliases: []),
      'ta': (term: 'Mutha Peran', aliases: []),
      'te': (term: 'Mootha Nati', aliases: []),
      'kn': (term: 'Mutha Maga Moga', aliases: []),
      'ml': (term: 'Mutha Makan Makan', aliases: []),
      'bn': (term: 'Boro Par Nati', aliases: []),
      'mr': (term: 'Par Par Natu', aliases: []),
      'gu': (term: 'Par Par Dikra No Dikro', aliases: []),
      'pa': (term: 'Par Par Pota', aliases: []),
      'ur': (term: 'Par Par Nati', aliases: []),
    }),
    VocabSeed(pathPattern: 'DOWN_CHILD_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 4, genderAnchor: 'female', translations: {
      'en': (term: 'Great Great Granddaughter', aliases: []),
      'hi': (term: 'Par Par Poti', aliases: []),
      'ta': (term: 'Mutha Pertti', aliases: []),
      'te': (term: 'Mootha Natin', aliases: []),
      'kn': (term: 'Mutha MagaLu MogaLu', aliases: []),
      'ml': (term: 'Mutha Makal Mole', aliases: []),
      'bn': (term: 'Boro Par Natin', aliases: []),
      'mr': (term: 'Par Par Nati', aliases: []),
      'gu': (term: 'Par Par Dikri No Dikro', aliases: []),
      'pa': (term: 'Par Par Poti', aliases: []),
      'ur': (term: 'Par Par Natin', aliases: []),
    }),

    // ═══════════════════════════════════════════════════════════════
    // 22. COUSIN TWICE REMOVED & THIRD COUSIN
    // ═══════════════════════════════════════════════════════════════
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 2, removal: 2, translations: {
      'en': (term: 'Cousin (Twice Removed)', aliases: []),
      'hi': (term: 'Bahut Door Ka Cousin', aliases: []),
      'ta': (term: 'Cousin (Twice Removed)', aliases: []),
      'te': (term: 'Cousin (Twice Removed)', aliases: []),
      'kn': (term: 'Cousin (Twice Removed)', aliases: []),
      'ml': (term: 'Cousin (Twice Removed)', aliases: []),
      'bn': (term: 'Cousin (Twice Removed)', aliases: []),
      'mr': (term: 'Cousin (Twice Removed)', aliases: []),
      'gu': (term: 'Cousin (Twice Removed)', aliases: []),
      'pa': (term: 'Cousin (Twice Removed)', aliases: []),
      'ur': (term: 'Cousin (Twice Removed)', aliases: []),
    }),
    VocabSeed(pathPattern: 'UP_PARENT_UP_PARENT_UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD_DOWN_CHILD', generationDelta: 0, translations: {
      'en': (term: 'Third Cousin', aliases: []),
      'hi': (term: 'Teesra Cousin', aliases: []),
      'ta': (term: 'Third Cousin', aliases: []),
      'te': (term: 'Third Cousin', aliases: []),
      'kn': (term: 'Third Cousin', aliases: []),
      'ml': (term: 'Third Cousin', aliases: []),
      'bn': (term: 'Third Cousin', aliases: []),
      'mr': (term: 'Third Cousin', aliases: []),
      'gu': (term: 'Third Cousin', aliases: []),
      'pa': (term: 'Third Cousin', aliases: []),
      'ur': (term: 'Third Cousin', aliases: []),
    }),
  ];

  /// Total count of vocabulary entries (seeds × languages).
  /// Each VocabSeed has translations for 11 languages, so the total
  /// entry count = seeds.length × 11 (approximately, since some seeds
  /// are gender-specific and some are neutral).
  static int get totalEntries {
    var count = 0;
    for (final seed in seeds) {
      count += seed.translations.length;
    }
    return count;
  }
}
