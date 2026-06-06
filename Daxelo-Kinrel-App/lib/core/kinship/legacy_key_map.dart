/// Maps legacy short keys (bua, chacha, mama...) to canonical relationshipKey
const Map<String, String> legacyKeyMap = {
  // Paternal side
  'bua': 'fathers_sister',
  'chacha': 'fathers_younger_brother',
  'chachi': 'fathers_younger_brothers_wife',
  'tau': 'fathers_elder_brother',
  'tai': 'fathers_elder_brothers_wife',
  'dada': 'paternal_grandfather',
  'dadi': 'paternal_grandmother',
  'par_dada': 'paternal_great_grandfather',
  'par_dadi': 'paternal_great_grandmother',

  // Maternal side
  'mama': 'mothers_brother',
  'mami': 'mothers_brothers_wife',
  'mausi': 'mothers_sister',
  'mausa': 'mothers_sisters_husband',
  'nana': 'maternal_grandfather',
  'nani': 'maternal_grandmother',

  // In-laws (husband's side)
  'sasur': 'husbands_father',
  'sasu': 'husbands_mother',
  'jeth': 'husbands_elder_brother',
  'jethani': 'husbands_elder_brothers_wife',
  'devar': 'husbands_younger_brother',
  'devrani': 'husbands_younger_brothers_wife',
  'nanad': 'husbands_sister',
  'nanand': 'husbands_sister',

  // In-laws (wife's side)
  'sasar': 'wives_father',
  'sasu_maa': 'wives_mother',
  'sadhu': 'wives_brother',
  'sadhvi': 'wives_sister',

  // Siblings
  'bhai': 'brother',
  'bahan': 'sister',
  'bhaiya': 'elder_brother',
  'didi': 'elder_sister',

  // Spouse
  'patni': 'wife',
  'pati': 'husband',

  // Children
  'beta': 'son',
  'beti': 'daughter',
  'bhatija': 'brothers_son',
  'bhatiji': 'brothers_daughter',

  // Nephew/Niece (maternal)
  'bhanja': 'sisters_son',
  'bhanji': 'sisters_daughter',

  // Grandchildren
  'pota': 'sons_son',
  'poti': 'sons_daughter',
  'natin': 'daughters_son',
  'natini': 'daughters_daughter',

  // Cousins
  'chachera_bhai': 'fathers_younger_brothers_son',
  'chachera_bahan': 'fathers_younger_brothers_daughter',
  'tauji_ka_beta': 'fathers_elder_brothers_son',
  'tauji_ki_beti': 'fathers_elder_brothers_daughter',
  'mamera_bhai': 'mothers_brothers_son',
  'mamera_bahan': 'mothers_brothers_daughter',
  'mausera_bhai': 'mothers_sisters_son',
  'mausera_bahan': 'mothers_sisters_daughter',

  // Step family
  'sauteli_maa': 'step_mother',
  'sautela_baap': 'step_father',
  'sautela_bhai': 'step_brother',
  'sauteli_bahan': 'step_sister',
};

/// Normalize a potentially legacy key to canonical form
String normalizeRelationshipKey(String raw) {
  final lower = raw.toLowerCase().trim().replaceAll(' ', '_');
  return legacyKeyMap[lower] ?? lower;
}
