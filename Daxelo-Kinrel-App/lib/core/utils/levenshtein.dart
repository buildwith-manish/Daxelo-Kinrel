/// Levenshtein distance utilities for fuzzy string matching.
///
/// Provides a reusable [levenshteinDistance] function extracted from
/// the inline implementations in `username_provider.dart` and
/// `search_repository.dart`.
///
/// Also provides [isFuzzyMatch] and [findClosestMatch] for common
/// fuzzy matching operations used throughout the app (username
/// suggestions, typo detection, search).

/// Compute the Levenshtein (edit) distance between two strings.
///
/// Returns the minimum number of single-character edits (insertions,
/// deletions, or substitutions) required to change [a] into [b].
///
/// Time complexity: O(a.length × b.length)
/// Space complexity: O(min(a.length, b.length)) — uses the optimized
/// two-row DP approach.
///
/// Example:
/// ```dart
/// levenshteinDistance('kitten', 'sitting'); // 3
/// levenshteinDistance('rahul', 'rahul');    // 0
/// ```
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Optimize: use the shorter string for the inner loop
  if (a.length > b.length) {
    return levenshteinDistance(b, a);
  }

  // Two-row DP: previous row and current row
  List<int> prevRow = List<int>.generate(a.length + 1, (i) => i);
  List<int> currRow = List<int>.filled(a.length + 1, 0);

  for (int j = 1; j <= b.length; j++) {
    currRow[0] = j;

    for (int i = 1; i <= a.length; i++) {
      final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
      currRow[i] = _min3(
        prevRow[i] + 1,       // deletion
        currRow[i - 1] + 1,   // insertion
        prevRow[i - 1] + cost, // substitution
      );
    }

    // Swap rows
    final temp = prevRow;
    prevRow = currRow;
    currRow = temp;
  }

  return prevRow[a.length];
}

/// Check if [query] fuzzy-matches [target] within [maxDistance].
///
/// Returns `true` if the Levenshtein distance between the lowercase
/// versions of [query] and [target] is ≤ [maxDistance].
///
/// This is useful for typo-tolerant matching in search, username
/// suggestions, and "did you mean?" features.
///
/// Example:
/// ```dart
/// isFuzzyMatch('rahul', 'rahul123'); // false (distance > 2)
/// isFuzzyMatch('rahul', 'rahul');    // true  (distance = 0)
/// isFuzzyMatch('rahul', 'rahil');    // true  (distance = 1)
/// ```
bool isFuzzyMatch(String query, String target, {int maxDistance = 2}) {
  final q = query.toLowerCase();
  final t = target.toLowerCase();

  // Quick length check: if lengths differ by more than maxDistance,
  // the distance must be at least that difference
  if ((q.length - t.length).abs() > maxDistance) return false;

  return levenshteinDistance(q, t) <= maxDistance;
}

/// Find the closest matching string from [candidates] to [query].
///
/// Returns the candidate with the smallest Levenshtein distance to
/// [query] that is within [maxDistance]. If no candidate is within
/// [maxDistance], returns `null`.
///
/// Ties are broken by the order of candidates (first match wins).
///
/// Example:
/// ```dart
/// findClosestMatch('rahil', ['rahul', 'rohit', 'raj']); // 'rahul'
/// findClosestMatch('xyz', ['abc', 'def']); // null
/// ```
String? findClosestMatch(
  String query,
  List<String> candidates, {
  int maxDistance = 2,
}) {
  if (candidates.isEmpty) return null;

  String? bestMatch;
  int bestDistance = maxDistance + 1;

  for (final candidate in candidates) {
    final distance = levenshteinDistance(
      query.toLowerCase(),
      candidate.toLowerCase(),
    );

    if (distance < bestDistance) {
      bestDistance = distance;
      bestMatch = candidate;
    }
  }

  return bestDistance <= maxDistance ? bestMatch : null;
}

// ── Private Helpers ─────────────────────────────────────────────────────

int _min3(int a, int b, int c) {
  if (a < b) return a < c ? a : c;
  return b < c ? b : c;
}
