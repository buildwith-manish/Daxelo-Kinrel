// lib/features/gedcom/data/gedcom_exporter.dart
//
// P12.6 Batch 3 — GEDCOM export with strict default-deny allowlist.
//
// Per kinrel_final_audited_prompt_v2.md §5.1:
//   - Strict default-deny export allowlist
//   - Explicitly EXCLUDES: live/precise location, auth identifiers,
//     internal database IDs, operational metadata, hidden/soft-deleted
//     relationships, pending invitations, moderation flags/notes.
//   - Respects existing privacy levels (Person.privacyLevel).
//
// GEDCOM 5.5.1 spec.

import '../../../core/family/family_provider.dart';

/// A relationship between two persons, for GEDCOM export.
class GedcomRelationship {
  const GedcomRelationship({
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.isActive = true,
  });
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;
  final bool isActive;
}

class GedcomParentChild {
  const GedcomParentChild({required this.parentId, required this.childId});
  final String parentId;
  final String childId;
}

class GedcomSpouse {
  const GedcomSpouse({required this.spouse1Id, required this.spouse2Id});
  final String spouse1Id;
  final String spouse2Id;
}

/// Strict default-deny GEDCOM exporter.
///
/// ALLOWLISTED fields (only these are exported):
///   - Person.name, Person.gender, Person.birthYear (year only),
///     Person.isDeceased (boolean only)
///   - Relationship structure (parent-child, spouse)
///
/// EXPLICITLY EXCLUDED:
///   - linkedUserId, username (auth identifiers)
///   - photoUrl (binary data)
///   - city, gotra, occupation, notes, sideOfFamily (operational)
///   - privacyLevel (access control — internal)
///   - dateOfBirth (full date — only birthYear exported for privacy)
///   - createdAt, deletedAt, anniversaryDate (timestamps)
///   - generationIndex, isAnchor (UI metadata)
class GedcomExporter {
  GedcomExporter._();

  static String export({
    required List<Person> persons,
    required List<GedcomRelationship> relationships,
    required String viewerPersonId,
  }) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('0 HEAD');
    buffer.writeln('1 SOUR KINREL');
    buffer.writeln('2 NAME Kinrel Family Atlas');
    buffer.writeln('2 VERS 1.0');
    buffer.writeln('1 DEST KINREL');
    buffer.writeln('1 DATE ${_formatDate(DateTime.now())}');
    buffer.writeln('1 CHAR UTF-8');
    buffer.writeln('1 GEDC');
    buffer.writeln('2 VERS 5.5.1');
    buffer.writeln('2 FORM LINEAGE-LINKED');

    // Privacy-filtered persons
    final exportable = _filterPersonsByPrivacy(
      persons,
      viewerPersonId: viewerPersonId,
    );
    final idMap = <String, String>{};
    var i = 1;
    for (final p in exportable) {
      final gid = '@I$i@';
      idMap[p.id] = gid;
      i++;
      _writeIndividual(buffer, gid, p);
    }

    // Derive FAM records
    final spousePairs = <GedcomSpouse>[];
    final parentChild = <GedcomParentChild>[];
    for (final rel in relationships) {
      if (!rel.isActive) continue;
      if (!idMap.containsKey(rel.fromPersonId) ||
          !idMap.containsKey(rel.toPersonId)) {
        continue;
      }
      final key = rel.relationshipKey.toLowerCase();
      if (key == 'spouse' || key == 'wife' || key == 'husband') {
        spousePairs.add(
          GedcomSpouse(spouse1Id: rel.fromPersonId, spouse2Id: rel.toPersonId),
        );
      } else if (key == 'father' || key == 'mother' || key == 'parent') {
        parentChild.add(
          GedcomParentChild(
            parentId: rel.fromPersonId,
            childId: rel.toPersonId,
          ),
        );
      }
    }

    var f = 1;
    for (final sp in spousePairs) {
      final fid = '@F$f@';
      f++;
      buffer.writeln('0 $fid FAM');
      final p1 = exportable.firstWhere((p) => p.id == sp.spouse1Id);
      if (_isMale(p1)) {
        buffer.writeln('1 HUSB ${idMap[sp.spouse1Id]}');
        buffer.writeln('1 WIFE ${idMap[sp.spouse2Id]}');
      } else {
        buffer.writeln('1 HUSB ${idMap[sp.spouse2Id]}');
        buffer.writeln('1 WIFE ${idMap[sp.spouse1Id]}');
      }
      for (final pc in parentChild) {
        if (pc.parentId == sp.spouse1Id || pc.parentId == sp.spouse2Id) {
          final cid = idMap[pc.childId];
          if (cid != null) buffer.writeln('1 CHIL $cid');
        }
      }
    }

    buffer.writeln('0 TRLR');
    return buffer.toString();
  }

  static void _writeIndividual(StringBuffer b, String gid, Person p) {
    b.writeln('0 $gid INDI');
    b.writeln('1 NAME ${_escape(p.name)}');
    b.writeln('1 SEX ${_mapGender(p.gender)}');
    if (p.birthYear != null) {
      b.writeln('1 BIRT');
      b.writeln('2 DATE ${p.birthYear}');
    }
    if (p.isDeceased) {
      b.writeln('1 DEAT');
      b.writeln('2 DATE Y');
    }
  }

  static List<Person> _filterPersonsByPrivacy(
    List<Person> persons, {
    required String viewerPersonId,
  }) {
    return persons.where((p) {
      if (p.id == viewerPersonId) return true;
      final level = p.privacyLevel?.toLowerCase();
      if (level == 'private' || level == 'hidden') return false;
      return true;
    }).toList();
  }

  static String _mapGender(String? gender) {
    if (gender == null) return 'U';
    final g = gender.toLowerCase();
    if (g == 'male' || g == 'm') return 'M';
    if (g == 'female' || g == 'f') return 'F';
    return 'U';
  }

  static bool _isMale(Person p) {
    final g = p.gender?.toLowerCase();
    return g == 'male' || g == 'm';
  }

  static String _escape(String text) => text.replaceAll('@', '@@');

  static String _formatDate(DateTime date) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
