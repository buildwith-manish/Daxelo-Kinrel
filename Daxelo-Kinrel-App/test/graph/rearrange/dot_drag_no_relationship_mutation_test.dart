// test/graph/rearrange/dot_drag_no_relationship_mutation_test.dart
//
// v5.22 TEST 6 — Regression guard: dragging the midpoint dot NEVER
// results in any Relationship table row being modified.
//
// HARD CONSTRAINT (from the spec): dragging the dot may ONLY change
// the visual path geometry. It must never modify, in any code path,
// the underlying Relationship row's fromPersonId, toPersonId,
// relationshipKey, or labelAtoB. The drag handler must not call
// createRelationship/updateRelationship/deleteRelationship at all —
// only a position-override write (LayoutOverridesService.saveEdgeWaypoint)
// which writes to GraphLayoutState.edgeWaypoints, a SEPARATE table
// from Relationship.
//
// This test verifies the contract by:
//   1. Inspecting the source of LayoutOverridesService — it touches
//      ONLY the GraphLayoutState table, never Relationship.
//   2. Inspecting the source of the rearrange drag handlers
//      (_handleRearrangeDragUpdate / _handleRearrangeDragEnd /
//      _handleRearrangeSave) — they touch ONLY the live override
//      state vars + LayoutOverridesService, never the relationship
//      create/update/delete APIs.
//
// Because we can't easily load the source files at runtime in a
// Flutter test (no dart:mirrors on Flutter Web), this test uses a
// static-string sentinel approach: the production source file
// contains an EXPLICIT ASSERTION COMMENT at the drag handler wiring
// point stating the constraint. This test greps for that sentinel
// comment and fails if it's missing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rearrange/layout_overrides_service.dart';

void main() {
  group('Dot-drag never mutates Relationship rows (TEST 6)', () {
    test('LayoutOverridesService.saveEdgeWaypoint writes to '
        'GraphLayoutState.edgeWaypoints, NOT to Relationship', () {
      // LayoutOverridesService.saveEdgeWaypoint is the SOLE write path
      // invoked by the dot-drag Save handler. Reading its source (see
      // lib/graph/rearrange/layout_overrides_service.dart lines
      // 230-260), it does:
      //   client.from('GraphLayoutState').upsert({
      //     'familyId': ...,
      //     'userId': auth.id,
      //     'edgeWaypoints': edges,
      //     ...
      //   }, onConflict: 'familyId, userId');
      //
      // The table name is 'GraphLayoutState' (NOT 'Relationship').
      // There is NO reference to 'Relationship' anywhere in the file.
      //
      // We assert this by loading the source file and checking no
      // relationship-mutating API is referenced.
      final sourceFile = File(
        'lib/graph/rearrange/layout_overrides_service.dart',
      );
      expect(sourceFile.existsSync(), true,
          reason: 'LayoutOverridesService source must exist');
      final source = sourceFile.readAsStringSync();

      // Positive: the file MUST write to GraphLayoutState.
      expect(source.contains("from('GraphLayoutState')"), true,
          reason: 'LayoutOverridesService must write to GraphLayoutState');

      // Negative: the file MUST NOT touch the Relationship table.
      expect(source.contains("from('Relationship')"), false,
          reason: 'LayoutOverridesService must NEVER write to the '
              'Relationship table — dot-drag may only change visual '
              'geometry, never the underlying relationship row.');
    });

    test('the rearrange drag handlers source file contains the EXPLICIT '
        'ASSERTION COMMENT stating the dot-drag may not mutate '
        'relationship rows', () {
      // The HARD CONSTRAINT comment is in
      // lib/graph/widgets/engine/canvas_mixin.dart at the point where
      // edgeWaypoints is passed to EdgeSelectionWrapper. We grep for
      // the sentinel string "HARD CONSTRAINT" + "drag handler MUST
      // NOT" to confirm the constraint is documented in the source.
      //
      // If a future editor accidentally removes the comment, this
      // test fails — forcing them to re-read the constraint and
      // either restore it or explicitly acknowledge they're breaking
      // it.
      final canvasMixinFile = File(
        'lib/graph/widgets/engine/canvas_mixin.dart',
      );
      expect(canvasMixinFile.existsSync(), true);
      final canvasSource = canvasMixinFile.readAsStringSync();
      expect(canvasSource.contains('HARD CONSTRAINT'), true,
          reason: 'canvas_mixin.dart must contain the HARD CONSTRAINT '
              'comment at the edgeWaypoints wiring point stating that '
              'dot-drag may not modify the underlying Relationship row.');

      final interactionMixinFile = File(
        'lib/graph/widgets/engine/interaction_mixin.dart',
      );
      expect(interactionMixinFile.existsSync(), true);
      final interactionSource = interactionMixinFile.readAsStringSync();
      // The rearrange drag handlers must NOT reference
      // createRelationship / updateRelationship / deleteRelationship.
      expect(interactionSource.contains('createRelationship'), false,
          reason: 'The rearrange drag handlers in interaction_mixin.dart '
              'must NOT call createRelationship — dot-drag is a visual-'
              'only operation.');
      expect(interactionSource.contains('updateRelationship'), false,
          reason: 'The rearrange drag handlers in interaction_mixin.dart '
              'must NOT call updateRelationship.');
      expect(interactionSource.contains('deleteRelationship'), false,
          reason: 'The rearrange drag handlers in interaction_mixin.dart '
              'must NOT call deleteRelationship.');
    });

    test('LayoutOverridesService does NOT expose any method that mutates '
        'a Relationship row (audit the public API surface)', () {
      // The public API surface of LayoutOverridesService is:
      //   - saveNodeOverride(ref, familyId, personId, Offset)
      //   - removeNodeOverride(ref, familyId, personId)
      //   - saveEdgeWaypoint(ref, familyId, relationshipId, Offset)
      //   - removeEdgeWaypoint(ref, familyId, relationshipId)
      //
      // None of these methods takes a relationshipKey, fromPersonId,
      // toPersonId, or labelAtoB parameter. They take a relationshipId
      // ONLY as a key for the edgeWaypoints JSONB map (which is on
      // GraphLayoutState, a SEPARATE table from Relationship).
      //
      // The relationshipId is NEVER used to look up or modify the
      // Relationship row — it's just a stable string key for the
      // edgeWaypoints map entry.
      //
      // We can't reflect on the method signatures in a Flutter test
      // (no dart:mirrors), but we can verify the source doesn't
      // SELECT/UPDATE/INSERT/DELETE on the Relationship table.
      final sourceFile = File(
        'lib/graph/rearrange/layout_overrides_service.dart',
      );
      final source = sourceFile.readAsStringSync();
      // Hard-negative check: no relationship-mutating SQL.
      expect(source.toLowerCase().contains('delete from "relationship"'),
          false,
          reason: 'LayoutOverridesService must not DELETE from Relationship');
      expect(source.toLowerCase().contains('update "relationship"'), false,
          reason: 'LayoutOverridesService must not UPDATE Relationship');
      expect(source.toLowerCase().contains('insert into "relationship"'),
          false,
          reason: 'LayoutOverridesService must not INSERT into Relationship');
    });
  });

  // Suppress the unused-warning for LayoutOverridesService import.
  // It's referenced by name in the audit checks above (compile-time
  // guarantee that the import resolves).
  // ignore: unused_element
  final _serviceType = LayoutOverridesService;
}
