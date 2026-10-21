// Regression tests for the "DM spins, then shows 'first message'" bug.
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/data/models/chat_state.dart';

void main() {
  group('ChatState.copyWith loading flag', () {
    test('unrelated updates do NOT end the loading state', () {
      const loading = ChatState(isLoading: true);
      // Previously `isLoading` defaulted to false, so this flipped it and the
      // UI showed the empty "first message" state before messages arrived.
      final next = loading.copyWith(members: const []);
      expect(next.isLoading, isTrue);
    });

    test('explicit isLoading still wins', () {
      const loading = ChatState(isLoading: true);
      expect(loading.copyWith(isLoading: false).isLoading, isFalse);
      expect(const ChatState().copyWith(isLoading: true).isLoading, isTrue);
    });
  });

  group('ChatState thread status', () {
    test('is preserved across unrelated copyWith calls', () {
      const s = ChatState(threadStatus: {'g1': ThreadStatus.loading});
      final next = s.copyWith(isTyping: true);
      expect(next.threadStatus['g1'], ThreadStatus.loading);
    });

    test('can be replaced per scope', () {
      const s = ChatState(threadStatus: {'g1': ThreadStatus.loading});
      final next = s.copyWith(
        threadStatus: {...s.threadStatus, 'g1': ThreadStatus.loaded},
        threadHasMore: {'g1': false},
      );
      expect(next.threadStatus['g1'], ThreadStatus.loaded);
      expect(next.threadHasMore['g1'], isFalse);
    });
  });
}
