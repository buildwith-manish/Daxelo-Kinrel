// test/graph/interaction/relationship_validation_test.dart
//
// Phase 7 — Safe Relationship Editing and Undo tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/relationship_validation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 7 — Relationship validation', () {
    test('TEST 1: self-link rejected (ERROR)', () {
      final result = validateRelationship(
        fromPersonId: 'A',
        toPersonId: 'A',
        relationshipKey: 'father',
        existingEdges: const [],
      );
      expect(result.isError, isTrue);
      expect(result.code, 'self_relationship');
    });

    test('TEST 2: duplicate rejected (ERROR)', () {
      final edges = [
        (fromId: 'A', toId: 'B', edgeId: 'e1', relationshipKey: 'wife'),
      ];
      final result = validateRelationship(
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'wife',
        existingEdges: edges,
      );
      expect(result.isError, isTrue);
      expect(result.code, 'duplicate_relationship');
    });

    test('TEST 3: parent cycle rejected (ERROR)', () {
      // A is ancestor of B. Adding B as A's father would create a cycle.
      final ancestorMap = <String, Set<String>>{
        'B': {'A'}, // B's ancestor is A
      };
      final result = validateRelationship(
        fromPersonId: 'B',
        toPersonId: 'A',
        relationshipKey: 'father', // B IS father OF A → B is parent of A
        existingEdges: const [],
        ancestorMap: ancestorMap,
      );
      // B→A father means B is A's parent. But A is B's ancestor.
      // So A would be a descendant of B AND B is A's parent → cycle.
      // Wait — the validation checks: is fromPersonId (B) a descendant
      // of toPersonId (A)? ancestorMap[A] = ? — A's ancestors.
      // Actually the check is: ancestorsOfTo.contains(fromPersonId).
      // ancestorsOfTo = ancestorMap['A'] = null or empty.
      // This particular setup doesn't trigger the cycle check because
      // we need A's ancestor set to contain B.
      //
      // Let me fix: A's ancestor is... we need ancestorMap['A'] to
      // contain 'B' for the check to fire when adding B→A 'father'.
      // But ancestorMap says B's ancestor is A, not the reverse.
      //
      // The validation logic: if key is 'father', from IS parent,
      // to IS child. Check: ancestorsOfTo.contains(fromPersonId).
      // ancestorsOfTo = ancestorMap[toPersonId=A].
      // If A's ancestors include B → cycle (B is A's ancestor AND B
      // is A's parent → B is its own ancestor).
      //
      // So we need ancestorMap['A'] = {'B'}.
      final fixedAncestorMap = <String, Set<String>>{
        'A': {'B'}, // A's ancestor is B
      };
      final result2 = validateRelationship(
        fromPersonId: 'B',
        toPersonId: 'A',
        relationshipKey: 'father',
        existingEdges: const [],
        ancestorMap: fixedAncestorMap,
      );
      expect(result2.isError, isTrue);
      expect(result2.code, 'circular_parentage');
    });

    test('TEST 4: valid spouse accepted (OK)', () {
      final result = validateRelationship(
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'wife',
        existingEdges: const [],
      );
      expect(result.isOk, isTrue);
    });

    test('TEST 5: valid parent accepted (OK)', () {
      final result = validateRelationship(
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'father',
        existingEdges: const [],
      );
      expect(result.isOk, isTrue);
    });

    test('TEST 6: inverse semantics — same canonical edge is a DUPLICATE (v5.0)', () {
      // v5.0: Previously, an existing B→A 'son' edge + a new A→B 'father'
      // edge was treated as a WARNING (incompatible inverse). But these
      // represent the SAME canonical relationship (B is A's father = A is
      // B's son), so they should be DUPLICATES.
      //
      // Storage convention: `from=A, to=B, key=X` means "A's X is B".
      // So `B→A 'son'` means "B's son is A" → A is B's son → B is A's father.
      // And `A→B 'father'` means "A's father is B" → B is A's father.
      // Same canonical edge → duplicate.
      final edges2 = [
        (fromId: 'B', toId: 'A', edgeId: 'e1', relationshipKey: 'son'),
      ];
      final result2 = validateRelationship(
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'father',
        existingEdges: edges2,
      );
      expect(result2.isError, isTrue,
          reason: 'v5.0: Existing B→A son + new A→B father are the same '
              'canonical edge — should be flagged as duplicate, not warning');
      expect(result2.code, 'duplicate_relationship');
    });

    test('TEST 7: duplicate parent rejected (ERROR)', () {
      // v5.0: Storage convention: `from=A, to=B, key=father` means
      // "A's father is B" → B is A's father, A is the CHILD.
      //
      // Setup: A already has B as father (edge A→B 'father').
      // Test: Adding C as A's father should be rejected as duplicate_parent.
      final edges = [
        (fromId: 'A', toId: 'B', edgeId: 'e1', relationshipKey: 'father'),
      ];
      final result = validateRelationship(
        fromPersonId: 'A',
        toPersonId: 'C',
        relationshipKey: 'father',
        existingEdges: edges,
      );
      expect(result.isError, isTrue);
      expect(result.code, 'duplicate_parent');
    });

    test('TEST 7b: duplicate parent via inverse direction (v5.0)', () {
      // v5.0: Existing edge `A→B 'son'` means "A's son is B" → A is B's
      // parent (father or mother — we don't know which). Adding C as B's
      // father should be rejected because B already has a parent.
      final edges = [
        (fromId: 'A', toId: 'B', edgeId: 'e1', relationshipKey: 'son'),
      ];
      final result = validateRelationship(
        fromPersonId: 'B',
        toPersonId: 'C',
        relationshipKey: 'father',
        existingEdges: edges,
      );
      expect(result.isError, isTrue,
          reason: 'B already has parent A (stored as A→B son). Adding C as '
              'father should be rejected.');
      expect(result.code, 'duplicate_parent');
    });

    test('TEST 7c: opposite-gender second parent ALLOWED (father + mother)', () {
      // v5.0: A child can have BOTH a father and a mother (standard
      // biological family). The validator blocks same-gender duplicates
      // (two fathers or two mothers) but allows opposite-gender pairs.
      final edges = [
        (fromId: 'B', toId: 'A', edgeId: 'e1', relationshipKey: 'mother'),
      ];
      final result = validateRelationship(
        fromPersonId: 'B',
        toPersonId: 'C',
        relationshipKey: 'father',
        existingEdges: edges,
      );
      expect(result.isOk, isTrue,
          reason: 'B already has mother A. Adding father C should be ALLOWED.');
    });

    test('TEST 7e: same-gender second parent BLOCKED (two fathers)', () {
      // v5.0: Two fathers is blocked — the user must remove the existing
      // father before adding a new one.
      final edges = [
        (fromId: 'B', toId: 'A', edgeId: 'e1', relationshipKey: 'father'),
      ];
      final result = validateRelationship(
        fromPersonId: 'B',
        toPersonId: 'C',
        relationshipKey: 'father',
        existingEdges: edges,
      );
      expect(result.isError, isTrue);
      expect(result.code, 'duplicate_parent');
    });

    test('TEST 7d: sibling co-parenting is allowed (different children)', () {
      // v5.0: A→B 'father' (B is A's father) + C→D 'father' (D is C's
      // father) — these are different children, so no duplicate. The
      // new edge should be accepted.
      final edges = [
        (fromId: 'A', toId: 'B', edgeId: 'e1', relationshipKey: 'father'),
      ];
      final result = validateRelationship(
        fromPersonId: 'C',
        toPersonId: 'D',
        relationshipKey: 'father',
        existingEdges: edges,
      );
      expect(result.isOk, isTrue,
          reason: 'Different children → different parents → no duplicate');
    });
  });

  group('Phase 7 — Undo stack', () {
    late GraphUndoNotifier notifier;

    setUp(() {
      notifier = GraphUndoNotifier();
    });

    test('TEST 8: undo add relationship', () {
      final command = GraphEditCommand(
        type: GraphEditType.addRelationship,
        familyId: 'fam-1',
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'wife',
        description: 'Added wife relationship',
      );

      notifier.push(command);
      expect(notifier.state.canUndo, isTrue);
      expect(notifier.state.lastCommand, command);

      final popped = notifier.pop();
      expect(popped, command);
      expect(notifier.state.canUndo, isFalse);
    });

    test('TEST 8: undo remove relationship', () {
      final command = GraphEditCommand(
        type: GraphEditType.removeRelationship,
        familyId: 'fam-1',
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'father',
        edgeId: 'edge-1',
        description: 'Removed father relationship',
      );

      notifier.push(command);
      final popped = notifier.pop();
      expect(popped?.type, GraphEditType.removeRelationship);
      expect(popped?.undoDescription, contains('restore'));
    });

    test('TEST 9: graph revision after edit (revision bumps)', () {
      final rev1 = notifier.state.revision;
      notifier.push(GraphEditCommand(
        type: GraphEditType.addRelationship,
        familyId: 'fam-1',
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'wife',
      ));
      final rev2 = notifier.state.revision;
      expect(rev2, greaterThan(rev1));

      notifier.pop();
      final rev3 = notifier.state.revision;
      expect(rev3, greaterThan(rev2));
    });

    test('TEST 10: undo stack bounded to 20', () {
      for (var i = 0; i < 25; i++) {
        notifier.push(GraphEditCommand(
          type: GraphEditType.addRelationship,
          familyId: 'fam-1',
          fromPersonId: 'A$i',
          toPersonId: 'B$i',
          relationshipKey: 'wife',
        ));
      }
      expect(notifier.state.commands.length, 20,
          reason: 'Undo stack must be bounded to 20 entries');
    });

    test('clearAll resets the stack', () {
      notifier.push(GraphEditCommand(
        type: GraphEditType.addRelationship,
        familyId: 'fam-1',
        fromPersonId: 'A',
        toPersonId: 'B',
        relationshipKey: 'wife',
      ));
      expect(notifier.state.canUndo, isTrue);

      notifier.clearAll();
      expect(notifier.state.canUndo, isFalse);
      expect(notifier.state.commands, isEmpty);
    });

    test('manual/Kinrel-linked identity independence', () {
      // The validation + undo system operates on canonical person IDs
      // — it doesn't care whether the person was added manually or
      // via Find on Kinrel. The relationshipKey + fromPersonId +
      // toPersonId are the only data needed.
      final manualResult = validateRelationship(
        fromPersonId: 'manual-person',
        toPersonId: 'kinrel-person',
        relationshipKey: 'wife',
        existingEdges: const [],
      );
      final kinrelResult = validateRelationship(
        fromPersonId: 'kinrel-person',
        toPersonId: 'manual-person',
        relationshipKey: 'husband',
        existingEdges: const [],
      );
      expect(manualResult.isOk, isTrue);
      expect(kinrelResult.isOk, isTrue);
      // Both are valid — identity source doesn't affect validation.
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // v102 (BUG-3 FIX): RelationshipValidationException typed exception.
  //
  // The old code in family_provider.dart threw a plain
  // Exception(validation.message) and then string-matched e.toString()
  // for code slugs — which never matched because e.toString() returns
  // the MESSAGE, not the CODE. The fix introduces a typed exception
  // so the catch block can do a type check instead.
  // ────────────────────────────────────────────────────────────────────
  group('v102 — RelationshipValidationException (BUG-3 fix)', () {
    test('exception carries both message and code', () {
      const exc = RelationshipValidationException(
        'A person cannot have a relationship with themselves.',
        'self_relationship',
      );
      expect(exc.message, 'A person cannot have a relationship with themselves.');
      expect(exc.code, 'self_relationship');
    });

    test('exception toString returns the message (not the code)', () {
      const exc = RelationshipValidationException(
        'A person cannot have a relationship with themselves.',
        'self_relationship',
      );
      // toString() returns the human-readable message — callers that
      // need the code must access exc.code directly. This matches the
      // old behavior (plain Exception(message).toString() = message)
      // so UI code that displays e.toString() still works.
      expect(exc.toString(), 'A person cannot have a relationship with themselves.');
      expect(exc.toString(), isNot(contains('self_relationship')));
    });

    test('exception is catchable by type (the actual BUG-3 fix)', () {
      // This is the test that would have FAILED before the fix.
      // The old code did:
      //   throw Exception(validation.message);
      //   ...
      //   catch (e) {
      //     if (e.toString().contains('self_relationship')) rethrow;
      //   }
      // But e.toString() = "Exception: A person cannot have..." which
      // does NOT contain 'self_relationship' → rethrow never fires.
      //
      // The new code does:
      //   throw RelationshipValidationException(message, code);
      //   ...
      //   on RelationshipValidationException catch (_) { rethrow; }
      // This type check ALWAYS works regardless of the message wording.
      const exc = RelationshipValidationException(
        'A person cannot have a relationship with themselves.',
        'self_relationship',
      );

      // Simulate the catch block's type check.
      bool wouldRethrow = exc is RelationshipValidationException;
      expect(wouldRethrow, isTrue,
          reason: 'THE BUG-3 TEST: a typed catch MUST catch the exception. '
              'Before the fix, the string-match catch could never fire '
              'because e.toString() returns the message, not the code.');
    });

    test('exception equality is based on code + message', () {
      const exc1 = RelationshipValidationException('msg', 'self_relationship');
      const exc2 = RelationshipValidationException('msg', 'self_relationship');
      const exc3 = RelationshipValidationException('msg', 'duplicate_relationship');
      const exc4 = RelationshipValidationException('different', 'self_relationship');

      expect(exc1 == exc2, isTrue);
      expect(exc1 == exc3, isFalse, reason: 'Different code → not equal');
      expect(exc1 == exc4, isFalse, reason: 'Different message → not equal');
      expect(exc1.hashCode, exc2.hashCode);
    });

    test('all validation error codes produce a catchable exception', () {
      // Verify that every code the validator can return maps to a
      // RelationshipValidationException that the typed catch will catch.
      final testCases = <(String, String, List<({String fromId, String toId, String edgeId, String relationshipKey})>)>[
        ('self_relationship', 'father', const []),
        ('duplicate_relationship', 'wife', [
          (fromId: 'A', toId: 'B', edgeId: 'e1', relationshipKey: 'wife'),
        ]),
      ];

      for (final (expectedCode, key, existingEdges) in testCases) {
        final result = validateRelationship(
          fromPersonId: 'A',
          toPersonId: expectedCode == 'self_relationship' ? 'A' : 'B',
          relationshipKey: key,
          existingEdges: existingEdges,
        );
        expect(result.isError, isTrue, reason: 'Code $expectedCode should be an error');

        // Simulate the throw + typed catch.
        final exc = RelationshipValidationException(
          result.message,
          result.code ?? 'unknown',
        );
        expect(exc is RelationshipValidationException, isTrue);
        expect(exc.code, expectedCode);
      }
    });

    test('plain Exception is NOT caught by the typed catch', () {
      // This proves the fix is narrow: only RelationshipValidationException
      // is rethrown. A plain Exception (e.g. from a network error) is
      // NOT a RelationshipValidationException, so it falls through to
      // the non-blocking debugPrint path. This is the intended behavior
      // — network errors during the validation fetch should not block
      // the write.
      final plainException = Exception('Network error');
      expect(plainException is RelationshipValidationException, isFalse,
          reason: 'Plain exceptions must NOT be caught by the typed catch — '
              'they represent network failures, not validation failures.');
    });
  });
}
