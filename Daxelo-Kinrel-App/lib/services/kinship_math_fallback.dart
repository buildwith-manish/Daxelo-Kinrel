// lib/services/kinship_math_fallback.dart
//
// DAXELO KINREL — Kinship Math Fallback Engine
//
// Pure-Dart kinship resolution that works without any downloaded files.
// Provides ~85% accuracy for common Indian family relationships.
// Used when SQLite DB is not yet downloaded (basic offline mode).

/// A resolved kinship result from the math fallback engine.
class KinshipMathResult {
  final String resultKey;
  final String resultFemaleKey;

  const KinshipMathResult(this.resultKey, this.resultFemaleKey);

  @override
  String toString() =>
      'KinshipMathResult(resultKey: $resultKey, resultFemaleKey: $resultFemaleKey)';
}

/// Pure-Dart math engine for kinship resolution.
///
/// Resolution algorithm:
/// 1. Check Indian-specific overrides (well-known kinship terms)
/// 2. Check self-referential pairs (e.g. son + father = self)
/// 3. Generation math: result_gen = from_gen + via_gen
/// 4. Map generation → kinship term using GENERATION_MAP
/// 5. Fallback to "distant-relative"
class KinshipMathFallback {
  /// Generation → (male_term, female_term) mapping.
  static const Map<int, Map<String, String>> generationMap = {
    -4: {
      'male': 'great-great-grandfather',
      'female': 'great-great-grandmother',
    },
    -3: {'male': 'great-grandfather', 'female': 'great-grandmother'},
    -2: {'male': 'grandfather', 'female': 'grandmother'},
    -1: {'male': 'father', 'female': 'mother'},
    0: {'male': 'brother', 'female': 'sister'},
    1: {'male': 'son', 'female': 'daughter'},
    2: {'male': 'grandson', 'female': 'granddaughter'},
    3: {'male': 'great-grandson', 'female': 'great-granddaughter'},
    4: {
      'male': 'great-great-grandson',
      'female': 'great-great-granddaughter',
    },
  };

  /// Indian-specific overrides for well-known kinship terms.
  /// Keyed by (from_key, via_key) → (male_result, female_result).
  static const Map<String, (String, String)> indianOverrides = {
    // Parent + sibling = uncle/aunt
    'father:brother': ('paternal-uncle', 'paternal-aunt'),
    'father:elder_brother': ('tau', 'tai'),
    'father:younger_brother': ('chacha', 'chachi'),
    'father:sister': ('paternal-aunt', 'paternal-aunt'),
    'mother:brother': ('maternal-uncle', 'maternal-aunt'),
    'mother:elder_brother': ('mama-elder', 'mama-elder'),
    'mother:younger_brother': ('mama-younger', 'mama-younger'),
    'mother:sister': ('maternal-aunt', 'maternal-aunt'),

    // Parent + parent = grandparent
    'father:father': ('paternal-grandfather', 'paternal-grandmother'),
    'father:mother': ('paternal-grandmother', 'paternal-grandmother'),
    'mother:father': ('maternal-grandfather', 'maternal-grandmother'),
    'mother:mother': ('maternal-grandmother', 'maternal-grandmother'),

    // Parent + child = self
    'father:son': ('self', 'self'),
    'father:daughter': ('self', 'self'),
    'mother:son': ('self', 'self'),
    'mother:daughter': ('self', 'self'),

    // Child + parent = self
    'son:father': ('self', 'self'),
    'son:mother': ('self', 'self'),
    'daughter:father': ('self', 'self'),
    'daughter:mother': ('self', 'self'),

    // Child + child = grandchild
    'son:son': ('grandson', 'granddaughter'),
    'son:daughter': ('granddaughter', 'granddaughter'),
    'daughter:son': ('grandson', 'granddaughter'),
    'daughter:daughter': ('granddaughter', 'granddaughter'),

    // Child + spouse = child-in-law
    'son:wife': ('daughter-in-law', 'daughter-in-law'),
    'son:husband': ('son-in-law', 'son-in-law'),
    'daughter:wife': ('daughter-in-law', 'daughter-in-law'),
    'daughter:husband': ('son-in-law', 'son-in-law'),

    // Sibling + spouse = sibling-in-law
    'brother:wife': ('sister-in-law', 'sister-in-law'),
    'brother:husband': ('brother-in-law', 'brother-in-law'),
    'sister:wife': ('sister-in-law', 'sister-in-law'),
    'sister:husband': ('brother-in-law', 'brother-in-law'),
    'elder_brother:wife': ('jethani', 'jethani'),
    'younger_brother:wife': ('devrani', 'devrani'),

    // Sibling + child = nephew/niece
    'brother:son': ('nephew', 'niece'),
    'brother:daughter': ('niece', 'niece'),
    'sister:son': ('nephew', 'niece'),
    'sister:daughter': ('niece', 'niece'),
    'elder_brother:son': ('nephew', 'niece'),
    'elder_brother:daughter': ('niece', 'niece'),
    'younger_brother:son': ('nephew', 'niece'),
    'younger_brother:daughter': ('niece', 'niece'),
    'elder_sister:son': ('nephew', 'niece'),
    'elder_sister:daughter': ('niece', 'niece'),
    'younger_sister:son': ('nephew', 'niece'),
    'younger_sister:daughter': ('niece', 'niece'),

    // Sibling + sibling = self
    'brother:brother': ('self', 'self'),
    'sister:sister': ('self', 'self'),
    'brother:sister': ('self', 'self'),
    'sister:brother': ('self', 'self'),
    'elder_brother:elder_brother': ('self', 'self'),
    'younger_brother:younger_brother': ('self', 'self'),
    'elder_sister:elder_sister': ('self', 'self'),
    'younger_sister:younger_sister': ('self', 'self'),

    // Spouse + parent = parent-in-law
    'husband:father': ('father-in-law', 'mother-in-law'),
    'husband:mother': ('mother-in-law', 'mother-in-law'),
    'wife:father': ('father-in-law', 'mother-in-law'),
    'wife:mother': ('mother-in-law', 'mother-in-law'),

    // Spouse + sibling = sibling-in-law (Indian-specific)
    'husband:elder_brother': ('jeth', 'jethani'),
    'husband:younger_brother': ('devar', 'devrani'),
    'husband:sister': ('nanad', 'nanad'),
    'wife:brother': ('sala', 'sali'),
    'wife:sister': ('sali', 'sali'),

    // Spouse + spouse = self
    'husband:wife': ('self', 'self'),
    'wife:husband': ('self', 'self'),

    // Grandparent + sibling = great-uncle/aunt
    'paternal_grandfather:brother': ('great-uncle', 'great-aunt'),
    'paternal_grandfather:sister': ('great-aunt', 'great-aunt'),
    'paternal_grandmother:brother': ('great-uncle', 'great-aunt'),
    'paternal_grandmother:sister': ('great-aunt', 'great-aunt'),
    'maternal_grandfather:brother': ('great-uncle', 'great-aunt'),
    'maternal_grandfather:sister': ('great-aunt', 'great-aunt'),
    'maternal_grandmother:brother': ('great-uncle', 'great-aunt'),
    'maternal_grandmother:sister': ('great-aunt', 'great-aunt'),

    // Grandparent + parent = great-grandparent
    'paternal_grandfather:father': ('great-grandfather', 'great-grandmother'),
    'paternal_grandfather:mother': ('great-grandmother', 'great-grandmother'),
    'paternal_grandmother:father': ('great-grandfather', 'great-grandmother'),
    'paternal_grandmother:mother': ('great-grandmother', 'great-grandmother'),
    'maternal_grandfather:father': ('great-grandfather', 'great-grandmother'),
    'maternal_grandfather:mother': ('great-grandmother', 'great-grandmother'),
    'maternal_grandmother:father': ('great-grandfather', 'great-grandmother'),
    'maternal_grandmother:mother': ('great-grandmother', 'great-grandmother'),

    // Uncle/aunt + child = cousin
    'fathers_elder_brother:son': ('cousin-elder', 'cousin-elder'),
    'fathers_elder_brother:daughter': ('cousin-elder', 'cousin-elder'),
    'fathers_younger_brother:son': ('cousin-younger', 'cousin-younger'),
    'fathers_younger_brother:daughter': ('cousin-younger', 'cousin-younger'),
    'fathers_sister:son': ('cousin-paternal', 'cousin-paternal'),
    'fathers_sister:daughter': ('cousin-paternal', 'cousin-paternal'),
    'mothers_brother:son': ('cousin-maternal', 'cousin-maternal'),
    'mothers_brother:daughter': ('cousin-maternal', 'cousin-maternal'),
    'mothers_sister:son': ('cousin-maternal', 'cousin-maternal'),
    'mothers_sister:daughter': ('cousin-maternal', 'cousin-maternal'),
  };

  /// Generation values for well-known relationship keys.
  static const Map<String, int> keyGenerations = {
    'self': 0,
    'father': -1,
    'mother': -1,
    'son': 1,
    'daughter': 1,
    'brother': 0,
    'sister': 0,
    'elder_brother': 0,
    'younger_brother': 0,
    'elder_sister': 0,
    'younger_sister': 0,
    'husband': 0,
    'wife': 0,
    'paternal_grandfather': -2,
    'paternal_grandmother': -2,
    'maternal_grandfather': -2,
    'maternal_grandmother': -2,
    'stepfather': -1,
    'stepmother': -1,
    'stepson': 1,
    'stepdaughter': 1,
    'stepbrother': 0,
    'stepsister': 0,
  };

  /// Resolve a kinship chain using math + overrides.
  KinshipMathResult resolve(String fromKey, String viaKey) {
    // 1. Check Indian overrides
    final overrideKey = '$fromKey:$viaKey';
    final override = indianOverrides[overrideKey];
    if (override != null) {
      return KinshipMathResult(override.$1, override.$2);
    }

    // 2. Self-reference: from_key == 'self' returns via_key
    if (fromKey == 'self') {
      final gen = keyGenerations[viaKey] ?? 0;
      final terms = generationMap[gen];
      if (terms != null) {
        return KinshipMathResult(terms['male']!, terms['female']!);
      }
    }

    // 3. Generation math
    final fromGen = keyGenerations[fromKey];
    final viaGen = keyGenerations[viaKey];

    if (fromGen != null && viaGen != null) {
      final resultGen = fromGen + viaGen;

      // Check for self-referential (generation sums to 0 with inverse paths)
      if (resultGen == 0 && fromGen != 0) {
        // e.g. son + father = self, father + son = self
        if ((fromGen > 0 && viaGen < 0) || (fromGen < 0 && viaGen > 0)) {
          return const KinshipMathResult('self', 'self');
        }
      }

      final terms = generationMap[resultGen];
      if (terms != null) {
        return KinshipMathResult(terms['male']!, terms['female']!);
      }

      // Out of range → distant-relative
      if (resultGen < -4 || resultGen > 4) {
        return const KinshipMathResult('distant-relative', 'distant-relative');
      }
    }

    // 4. Fallback
    return const KinshipMathResult('distant-relative', 'distant-relative');
  }
}
