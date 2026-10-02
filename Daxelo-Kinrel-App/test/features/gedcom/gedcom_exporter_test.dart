// test/features/gedcom/gedcom_exporter_test.dart
//
// P12.6 Batch 3 — GEDCOM exporter tests with independent validation.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/family/family_provider.dart';
import 'package:kinrel/features/gedcom/data/gedcom_exporter.dart';

void main() {
  group('P12.6 GEDCOM exporter — default-deny allowlist', () {
    test('exports valid GEDCOM 5.5.1 structure', () {
      final persons = [
        const Person(
          id: 'p1',
          familyId: 'fam1',
          name: 'John Doe',
          gender: 'male',
          birthYear: 1950,
        ),
        const Person(
          id: 'p2',
          familyId: 'fam1',
          name: 'Jane Doe',
          gender: 'female',
          birthYear: 1955,
        ),
      ];
      final rels = [
        const GedcomRelationship(
          fromPersonId: 'p1',
          toPersonId: 'p2',
          relationshipKey: 'spouse',
        ),
      ];

      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: rels,
        viewerPersonId: 'p1',
      );

      expect(gedcom, startsWith('0 HEAD'));
      expect(gedcom, endsWith('0 TRLR\n'));
      expect(gedcom, contains('1 SOUR KINREL'));
      expect(gedcom, contains('2 VERS 5.5.1'));
      expect(gedcom, contains('0 @I1@ INDI'));
      expect(gedcom, contains('1 NAME John Doe'));
      expect(gedcom, contains('1 SEX M'));
      expect(gedcom, contains('0 @F1@ FAM'));
      expect(gedcom, contains('1 HUSB @I1@'));
      expect(gedcom, contains('1 WIFE @I2@'));
    });

    test('exports birth year only (not full date)', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'John', birthYear: 1950),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'p1',
      );
      expect(gedcom, contains('2 DATE 1950'));
      expect(gedcom, isNot(contains('2 DATE 1950-01-15')));
    });

    test('excludes private persons (privacy filter)', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'Public'),
        const Person(
          id: 'p2',
          familyId: 'fam1',
          name: 'Private',
          privacyLevel: 'private',
        ),
        const Person(
          id: 'p3',
          familyId: 'fam1',
          name: 'Hidden',
          privacyLevel: 'hidden',
        ),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'p1',
      );
      expect(gedcom, contains('Public'));
      expect(gedcom, isNot(contains('Private')));
      expect(gedcom, isNot(contains('Hidden')));
    });

    test('viewer can always export their own data', () {
      final persons = [
        const Person(id: 'me', familyId: 'fam1', name: 'Me', privacyLevel: 'private'),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'me',
      );
      expect(gedcom, contains('Me'));
    });

    test('excludes auth identifiers (linkedUserId, username)', () {
      final persons = [
        const Person(
          id: 'p1',
          familyId: 'fam1',
          name: 'John',
          linkedUserId: 'auth-user-uuid-12345',
          username: 'john@example.com',
        ),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'p1',
      );
      expect(gedcom, isNot(contains('auth-user-uuid-12345')));
      expect(gedcom, isNot(contains('john@example.com')));
    });

    test('excludes operational metadata', () {
      final persons = [
        const Person(
          id: 'p1',
          familyId: 'fam1',
          name: 'John',
          city: 'Mumbai',
          gotra: 'Bharadwaj',
          occupation: 'Engineer',
          notes: 'Secret notes',
          sideOfFamily: 'paternal',
        ),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'p1',
      );
      expect(gedcom, isNot(contains('Mumbai')));
      expect(gedcom, isNot(contains('Bharadwaj')));
      expect(gedcom, isNot(contains('Engineer')));
      expect(gedcom, isNot(contains('Secret notes')));
    });

    test('handles parent-child relationships', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'Father', gender: 'male'),
        const Person(id: 'p2', familyId: 'fam1', name: 'Mother', gender: 'female'),
        const Person(id: 'p3', familyId: 'fam1', name: 'Child', gender: 'male'),
      ];
      final rels = [
        const GedcomRelationship(
          fromPersonId: 'p1',
          toPersonId: 'p2',
          relationshipKey: 'spouse',
        ),
        const GedcomRelationship(
          fromPersonId: 'p1',
          toPersonId: 'p3',
          relationshipKey: 'father',
        ),
        const GedcomRelationship(
          fromPersonId: 'p2',
          toPersonId: 'p3',
          relationshipKey: 'mother',
        ),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: rels,
        viewerPersonId: 'p1',
      );
      expect(gedcom, contains('1 CHIL @I3@'));
    });

    test('handles deceased persons', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'John', isDeceased: true),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'p1',
      );
      expect(gedcom, contains('1 DEAT'));
    });

    test('excludes inactive relationships', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'A'),
        const Person(id: 'p2', familyId: 'fam1', name: 'B'),
      ];
      final rels = [
        const GedcomRelationship(
          fromPersonId: 'p1',
          toPersonId: 'p2',
          relationshipKey: 'spouse',
          isActive: false,
        ),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: rels,
        viewerPersonId: 'p1',
      );
      expect(gedcom, isNot(contains('0 @F1@ FAM')));
    });

    test('escapes @ in names', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'John@Example'),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'p1',
      );
      expect(gedcom, contains('1 NAME John@@Example'));
    });

    test('handles unknown gender', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'John', gender: null),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: [],
        viewerPersonId: 'p1',
      );
      expect(gedcom, contains('1 SEX U'));
    });

    test('empty family produces valid empty GEDCOM', () {
      final gedcom = GedcomExporter.export(
        persons: [],
        relationships: [],
        viewerPersonId: 'none',
      );
      expect(gedcom, startsWith('0 HEAD'));
      expect(gedcom, endsWith('0 TRLR\n'));
    });

    test('single parent with child', () {
      final persons = [
        const Person(id: 'p1', familyId: 'fam1', name: 'Mom', gender: 'female'),
        const Person(id: 'p2', familyId: 'fam1', name: 'Child', gender: 'male'),
      ];
      final rels = [
        const GedcomRelationship(
          fromPersonId: 'p1',
          toPersonId: 'p2',
          relationshipKey: 'mother',
        ),
      ];
      final gedcom = GedcomExporter.export(
        persons: persons,
        relationships: rels,
        viewerPersonId: 'p1',
      );
      expect(gedcom, contains('Mom'));
      expect(gedcom, contains('Child'));
    });
  });
}
