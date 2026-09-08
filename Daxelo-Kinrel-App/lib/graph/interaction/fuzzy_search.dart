// lib/graph/interaction/fuzzy_search.dart
//
// DAXELO KINREL — v5.175 Fuzzy/Phonetic Search
//
// Provides phonetic matching for Indian names using a simplified
// DoubleMetaphone algorithm. Handles transliteration variants:
//   "Srinivasan" ↔ "Sreenivasan" ↔ "Shrinivasan"
//   "Rajesh" ↔ "Rajesh" ↔ "Ragesh"
//   "Krishna" ↔ "Krisna" ↔ "Krishnan"
//
// Also provides Levenshtein distance for typo tolerance.

/// Computes a phonetic code for a name using a simplified DoubleMetaphone
/// algorithm optimized for Indian-language transliterations.
///
/// Returns a lowercase string code. Names that sound the same
/// (even if spelled differently) produce the same code.
String metaphone(String name) {
  if (name.isEmpty) return '';

  var s = name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

  // Common Indian transliteration normalization
  s = s
      .replaceAll('SH', 'S')   // Shrinivas → Srinivas
      .replaceAll('PH', 'F')   // Phani → Fani
      .replaceAll('TH', 'T')   // Krishnanthan → Krishnantan
      .replaceAll('DH', 'D')   // Dharma → Darma
      .replaceAll('GH', 'G')   // Ghosh → Gosh
      .replaceAll('KH', 'K')   // Akhtar → Aktar
      .replaceAll('BH', 'B')   // Bhat → Bat
      .replaceAll('CH', 'C')   // Chandra → Cand ra
      .replaceAll('JH', 'J')   // Jha → Ja
      .replaceAll('MH', 'M');  // Mukherjee → Mukerjee

  // Remove duplicate consecutive consonants
  final result = StringBuffer();
  String? prev;
  for (final ch in s.split('')) {
    if (ch != prev) {
      result.write(ch);
    }
    prev = ch;
  }

  // Remove trailing vowels for matching (Krishna ↔ Krishnan)
  return result.toString().replaceAll(RegExp(r'[AEIOU]$'), '').toLowerCase();
}

/// Computes the Levenshtein edit distance between two strings.
/// Used for typo-tolerant matching.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final matrix = List.generate(
    a.length + 1,
    (i) => List.generate(b.length + 1, (j) => 0),
  );
  for (var i = 0; i <= a.length; i++) matrix[i][0] = i;
  for (var j = 0; j <= b.length; j++) matrix[0][j] = j;

  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = (matrix[i - 1][j] + 1)
          .clamp(0, 999999)
          .clamp(0, (matrix[i][j - 1] + 1).clamp(0, 999999));
      if (matrix[i][j - 1] + 1 < matrix[i][j]) {
        matrix[i][j] = matrix[i][j - 1] + 1;
      }
      if (matrix[i - 1][j - 1] + cost < matrix[i][j]) {
        matrix[i][j] = matrix[i - 1][j - 1] + cost;
      }
    }
  }
  return matrix[a.length][b.length];
}

/// Returns true if [name] fuzzy-matches [query].
/// Checks: exact, startsWith, contains, phonetic (metaphone), and
/// Levenshtein distance (typo tolerance — distance <= 2 for names
/// longer than 5 chars).
bool fuzzyMatch(String name, String query) {
  final n = name.toLowerCase();
  final q = query.toLowerCase();

  // Exact / prefix / substring — already handled by the caller,
  // but check here too for completeness.
  if (n.startsWith(q) || n.contains(q)) return true;

  // Phonetic match — handles transliteration variants.
  if (metaphone(n) == metaphone(q)) return true;

  // Typo tolerance — Levenshtein distance <= 2 for names > 5 chars.
  if (n.length > 5 && q.length > 3) {
    final dist = levenshtein(n, q);
    if (dist <= 2) return true;
  }

  return false;
}
