// Daxelo-Kinrel — Flutter-side Drift schema (spec §18)
// =====================================================
// Offline SQLite schema mirroring the server's fundamental-edge model.
// Only the 4 canonical edge types are stored (spec §2). No derived rows.
//
// File: lib/data/drift/app_database.dart

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// Enum mirrors server's EdgeType (spec §2).
enum EdgeType {
  parent,
  spouse,
  adoptiveParent,
  stepParent,
}

/// Enum mirrors server's EdgeTemporal (spec §6, v3.1).
enum EdgeTemporal {
  current,
  former,
  late,
}

/// Persons table — nodes in the family graph.
class Persons extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get familyId => text()();
  TextColumn get fullName => text()();
  TextColumn get gender => text()(); // MALE | FEMALE | OTHER
  DateTimeColumn get birthDate => dateTime().nullable()();
  DateTimeColumn get deathDate => dateTime().nullable()();
  BoolColumn get isAdopted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(CurrentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(CurrentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Relationships table — fundamental edges ONLY (spec §2).
/// Four edge types. Direction depends on edgeType:
///   parent          : personA (child)  → personB (parent)
///   spouse          : personA ↔ personB (bidirectional)
///   adoptiveParent  : personA (child)  → personB (adoptive parent)
///   stepParent      : personA (child)  → personB (step-parent)
class Relationships extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get familyId => text()();
  TextColumn get personAId => text().references(Persons, #id)();
  TextColumn get personBId => text().references(Persons, #id)();
  TextColumn get edgeType => text()(); // EdgeType.name
  TextColumn get temporal => text().withDefault(const Constant('current'))();
  BoolColumn get isInferred => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(CurrentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(CurrentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        // No duplicate fundamental edge (spec §12 rule 2)
        {familyId, personAId, personBId, edgeType, temporal},
      ];
}

@DriftDatabase(tables: [Persons, Relationships])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ----- Persons --------------------------------------------------------

  Future<Person> addPerson({
    required String familyId,
    required String fullName,
    required String gender, // MALE | FEMALE | OTHER
    DateTime? birthDate,
    DateTime? deathDate,
    bool isAdopted = false,
  }) async {
    return into(persons).returning().insert(PersonsCompanion.insert(
          familyId: familyId,
          fullName: fullName,
          gender: gender,
          birthDate: Value(birthDate),
          deathDate: Value(deathDate),
          isAdopted: Value(isAdopted),
        ));
  }

  Future<List<Person>> personsInFamily(String familyId) {
    return (select(persons)..where((p) => p.familyId.equals(familyId))).get();
  }

  // ----- Relationships (fundamental edges ONLY — spec §2) ---------------

  Future<Relationship> addRelationship({
    required String familyId,
    required String personAId,
    required String personBId,
    required EdgeType edgeType,
    EdgeTemporal temporal = EdgeTemporal.current,
    bool isInferred = false,
  }) async {
    return into(relationships).returning().insert(RelationshipsCompanion.insert(
          familyId: familyId,
          personAId: personAId,
          personBId: personBId,
          edgeType: edgeType.name,
          temporal: Value(temporal.name),
          isInferred: Value(isInferred),
        ));
  }

  Future<List<Relationship>> edgesInFamily(String familyId) {
    return (select(relationships)..where((r) => r.familyId.equals(familyId))).get();
  }

  Future<int> removeRelationship(String id) {
    return (delete(relationships)..where((r) => r.id.equals(id))).go();
  }
}

String _uuid() {
  // Simple RFC-4122-ish v4 generator without external deps.
  // For production use, replace with the `uuid` package.
  final rng = DateTime.now().microsecondsSinceEpoch;
  final hex = (int x) => x.toRadixString(16).padLeft(2, '0');
  final b = List<int>.generate(16, (i) => (rng >> (i % 8)) & 0xff);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final parts = [
    b.sublist(0, 4).map(hex).join(),
    b.sublist(4, 6).map(hex).join(),
    b.sublist(6, 8).map(hex).join(),
    b.sublist(8, 10).map(hex).join(),
    b.sublist(10, 16).map(hex).join(),
  ];
  return parts.join('-');
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // For production, swap NativeDatabase for one backed by path_provider.
    return NativeDatabase.memory();
  });
}
