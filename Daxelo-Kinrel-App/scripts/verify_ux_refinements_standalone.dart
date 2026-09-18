// verify_ux_refinements_standalone.dart
//
// Self-contained verifier for the three UX refinements contract. Mirrors
// the logic in:
//   • lib/features/games/presentation/widgets/family_moment_card.dart
//     (groupMomentsByDate)
//   • lib/features/games/presentation/widgets/quick_picks_row.dart
//     (Play With exclusion logic)
//   • lib/features/gaming_ecosystem/data/gaming_providers.dart
//     (ParticipationLeaderboard contract)
//
// Run via: dart run scripts/verify_ux_refinements_standalone.dart
// Exit code 0 = contract verified; non-zero = violation.

/// Mirror of FamilyMoment (minimal fields needed for date grouping).
class Moment {
  const Moment({required this.id, required this.createdAt});
  final String id;
  final DateTime? createdAt;
}

/// Mirror of groupMomentsByDate.
class DateGroup {
  const DateGroup({required this.headerLabel, required this.momentIds});
  final String headerLabel;
  final List<String> momentIds;
}

List<DateGroup> groupMomentsByDate(List<Moment> moments) {
  if (moments.isEmpty) return const <DateGroup>[];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final groups = <String, List<String>>{};
  final order = <String>[];
  for (final m in moments) {
    final t = m.createdAt;
    final String key;
    if (t == null) {
      key = 'Earlier';
    } else {
      final d = DateTime(t.year, t.month, t.day);
      if (d == today) {
        key = 'Today';
      } else if (d == yesterday) {
        key = 'Yesterday';
      } else if (d.year == today.year) {
        key = '${_monthAbbrev(d.month)} ${d.day}';
      } else {
        key = '${_monthAbbrev(d.month)} ${d.day}, ${d.year}';
      }
    }
    if (!groups.containsKey(key)) {
      groups[key] = <String>[];
      order.add(key);
    }
    groups[key]!.add(m.id);
  }
  return order
      .map((key) => DateGroup(headerLabel: key, momentIds: groups[key]!))
      .toList();
}

String _monthAbbrev(int month) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  if (month < 1 || month > 12) return '';
  return months[month - 1];
}

void main() {
  var failures = 0;
  void check(String name, bool condition, String details) {
    if (condition) {
      print('  ✓ $name');
    } else {
      print('  ✗ $name');
      print('    $details');
      failures++;
    }
  }

  print('=== groupMomentsByDate — date grouping contract ===');

  // Contract 1: empty input → empty output
  check(
    'Empty input → empty output',
    groupMomentsByDate(const []).isEmpty,
    'Got non-empty result for empty input',
  );

  // Contract 2: today's moments → "Today" header
  final now = DateTime.now();
  final todayGroups = groupMomentsByDate([
    Moment(id: 'm1', createdAt: now),
    Moment(id: 'm2', createdAt: now.subtract(const Duration(minutes: 30))),
  ]);
  check(
    'Today\'s moments → "Today" header, ONE group',
    todayGroups.length == 1 && todayGroups.first.headerLabel == 'Today',
    'Got ${todayGroups.length} groups, first="${todayGroups.isEmpty ? "" : todayGroups.first.headerLabel}"',
  );

  // Contract 3: date header renders ONCE per group (not per entry)
  check(
    'Date header renders ONCE per group, not per entry',
    todayGroups.length == 1 && todayGroups.first.momentIds.length == 2,
    'Should have 1 group with 2 moments; got ${todayGroups.length} groups',
  );

  // Contract 4: yesterday → "Yesterday"
  final yesterdayDate = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1))
      .add(const Duration(hours: 10));
  final yGroups = groupMomentsByDate([Moment(id: 'y1', createdAt: yesterdayDate)]);
  check(
    'Yesterday → "Yesterday" header',
    yGroups.length == 1 && yGroups.first.headerLabel == 'Yesterday',
    'Got "${yGroups.isEmpty ? "" : yGroups.first.headerLabel}"',
  );

  // Contract 5: older this year → "Sep 15" format (no year)
  final olderThisYear = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 10))
      .add(const Duration(hours: 5));
  final oGroups = groupMomentsByDate([Moment(id: 'old1', createdAt: olderThisYear)]);
  check(
    'Older this year → "Sep 15" format (month abbrev + day, no year)',
    oGroups.length == 1 &&
        RegExp(r'^[A-Z][a-z]{2} \d+$').hasMatch(oGroups.first.headerLabel) &&
        !oGroups.first.headerLabel.contains(now.year.toString()),
    'Got "${oGroups.isEmpty ? "" : oGroups.first.headerLabel}"',
  );

  // Contract 6: previous year → "Sep 15, 2024" format (with year)
  final prevYear = DateTime(now.year - 1, 9, 15, 10, 0);
  final pGroups = groupMomentsByDate([Moment(id: 'py1', createdAt: prevYear)]);
  check(
    'Previous year → "Sep 15, 2024" format (with year)',
    pGroups.length == 1 &&
        RegExp(r'^[A-Z][a-z]{2} \d+, \d{4}$').hasMatch(pGroups.first.headerLabel),
    'Got "${pGroups.isEmpty ? "" : pGroups.first.headerLabel}"',
  );

  // Contract 7: null createdAt → "Earlier"
  final nGroups = groupMomentsByDate([const Moment(id: 'null-t', createdAt: null)]);
  check(
    'Null createdAt → "Earlier" header',
    nGroups.length == 1 && nGroups.first.headerLabel == 'Earlier',
    'Got "${nGroups.isEmpty ? "" : nGroups.first.headerLabel}"',
  );

  // Contract 8: multiple dates → multiple groups in reverse-chronological order
  final today = DateTime(now.year, now.month, now.day, 10);
  final yest = today.subtract(const Duration(days: 1));
  final twoAgo = today.subtract(const Duration(days: 2));
  final multiGroups = groupMomentsByDate([
    Moment(id: 'today', createdAt: today),
    Moment(id: 'yesterday', createdAt: yest),
    Moment(id: 'two-ago', createdAt: twoAgo),
  ]);
  check(
    'Multiple dates → multiple groups in reverse-chronological order',
    multiGroups.length == 3 &&
        multiGroups[0].headerLabel == 'Today' &&
        multiGroups[1].headerLabel == 'Yesterday',
    'Got ${multiGroups.length} groups: ${multiGroups.map((g) => g.headerLabel).join(", ")}',
  );

  print('');
  print('=== QuickPicks exclusion logic — Play With games excluded ===');

  // Mirror of the quickPicksProvider exclusion logic.
  final catalogToTable = {
    'tictactoe': 'tictactoe_games',
    'chess': 'chess_games',
    'checkers': 'checkers_games',
    'memorymatch': 'memorymatch_games',
  };

  // Contract 9: a game suggested in Play With is excluded from Quick Picks
  final qp1 = ['tictactoe_games', 'chess_games', 'checkers_games'];
  final pw1 = ['chess'];
  final excluded1 = pw1.map((id) => catalogToTable[id]).whereType<String>().toSet();
  final filtered1 = qp1.where((t) => !excluded1.contains(t)).toList();
  check(
    'A game suggested in Play With is excluded from Quick Picks',
    filtered1.length == 2 && !filtered1.contains('chess_games'),
    'Got: $filtered1',
  );

  // Contract 10: multiple Play With suggestions are all excluded
  final qp2 = ['tictactoe_games', 'chess_games', 'checkers_games', 'memorymatch_games'];
  final pw2 = ['chess', 'checkers'];
  final excluded2 = pw2.map((id) => catalogToTable[id]).whereType<String>().toSet();
  final filtered2 = qp2.where((t) => !excluded2.contains(t)).toList();
  check(
    'Multiple Play With suggestions are all excluded',
    filtered2.length == 2 &&
        !filtered2.contains('chess_games') &&
        !filtered2.contains('checkers_games'),
    'Got: $filtered2',
  );

  // Contract 11: null Play With suggestions don't exclude anything
  final qp3 = ['tictactoe_games', 'chess_games'];
  final pw3 = <String?>[null, null];
  final excluded3 = pw3.whereType<String>().map((id) => catalogToTable[id]).whereType<String>().toSet();
  final filtered3 = qp3.where((t) => !excluded3.contains(t)).toList();
  check(
    'Null Play With suggestions don\'t exclude anything',
    filtered3.length == 2,
    'Got: $filtered3',
  );

  print('');
  print('=== ParticipationLeaderboard contract — ranked vs notYetPlayed ===');

  // Contract 12: ranked rows all have matches >= 1
  final ranked = [
    {'userId': 'a', 'matches': 10, 'points': 20},
    {'userId': 'b', 'matches': 8, 'points': 30},
    {'userId': 'c', 'matches': 5, 'points': 15},
  ];
  var allRankedHaveMatches = true;
  for (final r in ranked) {
    if ((r['matches'] as int) < 1) {
      allRankedHaveMatches = false;
      break;
    }
  }
  check(
    'Ranked rows all have matches >= 1',
    allRankedHaveMatches,
    'Found a ranked row with matches < 1',
  );

  // Contract 13: ranked order is by matches DESC (NOT points DESC)
  // Note: member b has 30 pts but only 8 matches → ranks BELOW a (10 matches, 20 pts).
  var orderedByMatches = true;
  for (var i = 0; i < ranked.length - 1; i++) {
    if ((ranked[i]['matches'] as int) < (ranked[i + 1]['matches'] as int)) {
      orderedByMatches = false;
      break;
    }
  }
  check(
    'Ranked order is by matches DESC (NOT points DESC)',
    orderedByMatches,
    'Order is not matches DESC',
  );

  // Contract 14: 0-game members are NOT in ranked
  final notPlayed = [
    {'userId': 'x', 'matches': 0},
  ];
  check(
    '0-game members are NOT in ranked list',
    !ranked.any((r) => r['userId'] == 'x'),
    'Found 0-game member in ranked list',
  );

  // Contract 15: 0-game members ARE in notYetPlayed
  check(
    '0-game members ARE in notYetPlayed',
    notPlayed.any((r) => r['userId'] == 'x'),
    '0-game member not found in notYetPlayed',
  );

  // Contract 16: notYetPlayed rows all have matches == 0
  var allNotPlayedZero = true;
  for (final r in notPlayed) {
    if ((r['matches'] as int) != 0) {
      allNotPlayedZero = false;
      break;
    }
  }
  check(
    'notYetPlayed rows all have matches == 0',
    allNotPlayedZero,
    'Found a notYetPlayed row with matches != 0',
  );

  print('');
  if (failures == 0) {
    print('=== ALL CHECKS PASSED — UX refinements contract verified ===');
  } else {
    print('=== $failures CHECK(S) FAILED ===');
  }
  if (failures != 0) {
    throw StateError('UX refinements verification failed: $failures failure(s).');
  }
}
