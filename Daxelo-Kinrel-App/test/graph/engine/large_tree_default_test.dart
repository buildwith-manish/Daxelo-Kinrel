// test/graph/engine/large_tree_default_test.dart
//
// G2b: pure-Dart checks for the large-tree first-open default.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/large_tree_default.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';

WedgeLink _link(String from, String to, String key) => WedgeLink(
      fromId: from,
      toId: to,
      relationshipKey: key,
      keyAtoB: key,
    );

void main() {
  test('threshold is strictly greater than the node budget', () {
    expect(isLargeTree(kLargeTreeThreshold), isFalse);
    expect(isLargeTree(kLargeTreeThreshold + 1), isTrue);
  });

  test('expands only the viewer parents', () {
    final result = computeLargeTreeDefault(
      viewerId: 'me',
      links: [
        _link('me', 'dad', 'father'),
        _link('me', 'mom', 'mother'),
        _link('me', 'wife', 'wife'),
        _link('me', 'kid', 'son'),
        _link('dad', 'uncle', 'brother'),
      ],
    );
    expect(result.expandedRoots, {'dad', 'mom'});
    expect(result.viewerPages, isEmpty);
  });

  test('raises the viewer page when close family exceeds one page', () {
    final links = <WedgeLink>[
      _link('me', 'dad', 'father'),
      _link('me', 'mom', 'mother'),
      for (var i = 0; i < 9; i++) _link('me', 'kid$i', 'son'),
    ];
    final result = computeLargeTreeDefault(viewerId: 'me', links: links);
    expect(result.viewerPages['me'], 1);
  });
}
