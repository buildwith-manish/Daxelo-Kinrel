// lib/services/kinship_sqlite_service.dart
//
// DAXELO KINREL — Kinship SQLite Query Service
//
// Queries the local kinship_matrix.db (downloaded from GitHub Releases)
// for O(1) kinship chain resolution.
//
// Schema:
//   CREATE TABLE kinship_matrix (
//     from_key TEXT NOT NULL,
//     via_key TEXT NOT NULL,
//     result_key TEXT NOT NULL,
//     result_female_key TEXT NOT NULL,
//     PRIMARY KEY (from_key, via_key)
//   );

import 'package:sqflite/sqflite.dart';
import 'package:logger/logger.dart';

/// Result of a kinship chain query.
class KinshipResult {
  final String resultKey;
  final String resultFemaleKey;

  const KinshipResult(this.resultKey, this.resultFemaleKey);

  @override
  String toString() =>
      'KinshipResult(resultKey: $resultKey, resultFemaleKey: $resultFemaleKey)';

  @override
  bool operator ==(Object other) =>
      other is KinshipResult &&
      other.resultKey == resultKey &&
      other.resultFemaleKey == resultFemaleKey;

  @override
  int get hashCode => Object.hash(resultKey, resultFemaleKey);
}

/// Queries the local SQLite kinship_matrix database.
class KinshipSqliteService {
  Database? _db;
  final _logger = Logger();

  /// Initialize with the path to the downloaded SQLite file.
  Future<void> initialize(String dbPath) async {
    try {
      _db = await openDatabase(
        dbPath,
        version: 1,
        readOnly: true,
        onConfigure: (db) async {
          // Performance pragmas for read-only access
          await db.execute('PRAGMA query_only = ON');
          await db.execute('PRAGMA cache_size = 10000');
        },
      );
      _logger.i('KinshipSqliteService initialized: $dbPath');
    } catch (e) {
      _logger.e('Failed to open kinship SQLite DB: $e');
      rethrow;
    }
  }

  /// Whether the database is ready for queries.
  bool get isReady => _db != null && _db!.isOpen;

  /// Query a single kinship chain: given (fromKey, viaKey), return the result.
  ///
  /// Returns null if the combination is not found in the database.
  Future<KinshipResult?> queryChain(String fromKey, String viaKey) async {
    if (!isReady) return null;

    try {
      final rows = await _db!.query(
        'kinship_matrix',
        columns: ['result_key', 'result_female_key'],
        where: 'from_key = ? AND via_key = ?',
        whereArgs: [fromKey, viaKey],
        limit: 1,
      );

      if (rows.isEmpty) return null;

      return KinshipResult(
        rows[0]['result_key'] as String,
        rows[0]['result_female_key'] as String,
      );
    } catch (e) {
      _logger.e('SQLite query failed ($fromKey + $viaKey): $e');
      return null;
    }
  }

  /// Batch query for graph rendering — resolve multiple (from, via) pairs at once.
  ///
  /// Returns a map keyed by "$fromKey:$viaKey" → KinshipResult.
  Future<Map<String, KinshipResult>> queryBatch(
    List<(String, String)> pairs,
  ) async {
    if (!isReady || pairs.isEmpty) return {};

    final results = <String, KinshipResult>{};

    // SQLite has a parameter limit (999), so batch in groups of 200 pairs (400 params)
    const batchSize = 200;

    for (var i = 0; i < pairs.length; i += batchSize) {
      final batch = pairs.skip(i).take(batchSize).toList();
      if (batch.isEmpty) continue;

      // Build IN clause with placeholders
      final whereParts = <String>[];
      final args = <String>[];
      for (final (fromKey, viaKey) in batch) {
        whereParts.add('(from_key = ? AND via_key = ?)');
        args.add(fromKey);
        args.add(viaKey);
      }

      final whereClause = whereParts.join(' OR ');
      final rows = await _db!.rawQuery(
        'SELECT from_key, via_key, result_key, result_female_key '
        'FROM kinship_matrix WHERE $whereClause',
        args,
      );

      for (final row in rows) {
        final key = '${row['from_key']}:${row['via_key']}';
        results[key] = KinshipResult(
          row['result_key'] as String,
          row['result_female_key'] as String,
        );
      }
    }

    return results;
  }

  /// Get total row count in the database (for verification).
  Future<int> getRowCount() async {
    if (!isReady) return 0;
    try {
      final rows = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM kinship_matrix');
      if (rows.isEmpty) return 0;
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      _logger.e('Row count query failed: $e');
      return 0;
    }
  }

  /// Close the database connection.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
