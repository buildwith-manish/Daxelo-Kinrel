// Daxelo-Kinrel — Flutter-side Relationship Engine (spec §18)
// ============================================================
// Mirror of the server-side GraphEngineService + PathCanonicalizer +
// Signature builder + Vocabulary Mapper. Used for OFFLINE resolution
// (spec §1 — Drift SQLite is the offline cache).
//
// When the device is online, the engine delegates to the server for
// authoritative answers; when offline, it uses the same algorithm
// locally to provide instant UI feedback and queues mutations for sync.
//
// File: lib/core/services/relationship_engine.dart

import 'dart:collection';
import 'package:drift/drift.dart';
import '../../data/drift/app_database.dart';

// ===========================================================================
// 1. KINSHIP SIGNATURE (mirror of kinship-signature.ts — spec §6)
// ===========================================================================

enum Side { paternal, maternal, none }
enum Consanguinity { blood, half, step, adoptive, inLaw, foster, spiritual }
enum GenderAnchor { male, female, neutral }
enum Seniority { elder, younger, twin, none }
enum Temporal { current, former, late }

/// Traversal primitives (spec §5). Forbidden: BROTHER, SISTER, UNCLE,
/// AUNT, COUSIN, GRANDFATHER — these must always be derived.
enum Primitive {
  upParent,
  downChild,
  spouse,
  upAdoptiveParent,
  downAdoptiveChild,
  upStepParent,
  downStepChild,
  upFosterParent,
  downFosterChild,
  upSpiritualParent,
  downSpiritualChild,
}

extension PrimitiveX on Primitive {
  String get name => toString().split('.').last;
}

class KinshipSignature {
  final int generationDelta;       // -8..+8
  final String pathPattern;        // primitives joined by _
  final Side side;
  final Consanguinity consanguinity;
  final GenderAnchor genderAnchor;
  final Seniority seniority;
  final int removal;               // 0..8
  final bool doubleKinship;
  final Temporal temporal;

  const KinshipSignature({
    required this.generationDelta,
    required this.pathPattern,
    required this.side,
    required this.consanguinity,
    required this.genderAnchor,
    required this.seniority,
    required this.removal,
    required this.doubleKinship,
    this.temporal = Temporal.current,
  });

  /// Deterministic composite lookup key. Same key = same term. Always.
  String get signatureKey => [
        'g=$generationDelta',
        'p=$pathPattern',
        's=${side.name}',
        'c=${consanguinity.name}',
        'x=${genderAnchor.name}',
        'r=$removal',
        'sn=${seniority.name}',
        'd=${doubleKinship ? 1 : 0}',
        't=${temporal.name}',
      ].join('|');

  @override
  String toString() => 'KinshipSignature($signatureKey)';

  Map<String, dynamic> toJson() => {
        'generationDelta': generationDelta,
        'pathPattern': pathPattern,
        'side': side.name,
        'consanguinity': consanguinity.name,
        'genderAnchor': genderAnchor.name,
        'seniority': seniority.name,
        'removal': removal,
        'doubleKinship': doubleKinship,
        'temporal': temporal.name,
        'signatureKey': signatureKey,
      };
}

// ===========================================================================
// 2. TRAVERSAL STEP + PATH CANONICALIZER (mirror of path-canonicalizer.ts)
// ===========================================================================

class TraversalStep {
  final Primitive primitive;
  final String nodeId;
  final String targetNodeId;
  final String edgeType;
  final Consanguinity consanguinity;
  const TraversalStep({
    required this.primitive,
    required this.nodeId,
    required this.targetNodeId,
    required this.edgeType,
    required this.consanguinity,
  });
}

class PathCanonicalizer {
  /// Spec §3.2.2 — remove UP_PARENT immediately followed by DOWN_CHILD
  /// on the same node (and vice versa).
  List<TraversalStep> removeBacktracking(List<TraversalStep> steps) {
    final result = <TraversalStep>[];
    int i = 0;
    while (i < steps.length) {
      if (i + 1 < steps.length) {
        final a = steps[i];
        final b = steps[i + 1];
        final isBacktrack = _isBacktrack(a, b) || _isBacktrack(b, a);
        if (isBacktrack && a.targetNodeId == b.nodeId) {
          i += 2;
          continue;
        }
      }
      result.add(steps[i]);
      i += 1;
    }
    return result;
  }

  bool _isBacktrack(TraversalStep a, TraversalStep b) {
    final upDown = {
      Primitive.upParent: Primitive.downChild,
      Primitive.upAdoptiveParent: Primitive.downAdoptiveChild,
      Primitive.upStepParent: Primitive.downStepChild,
      Primitive.upFosterParent: Primitive.downFosterChild,
      Primitive.upSpiritualParent: Primitive.downSpiritualChild,
    };
    return upDown[a.primitive] == b.primitive;
  }

  /// Spec §3.2.1 — remove cycles. If the same node appears twice,
  /// drop the segment between the two occurrences.
  List<TraversalStep> removeCycles(List<TraversalStep> steps) {
    final visited = <String, int>{};
    final result = <TraversalStep>[];
    for (final step in steps) {
      if (visited.containsKey(step.targetNodeId)) {
        final cutAt = visited[step.targetNodeId]!;
        result.removeRange(cutAt, result.length);
        visited.clear();
        for (var i = 0; i < result.length; i++) {
          visited[result[i].targetNodeId] = i;
        }
      } else {
        visited[step.targetNodeId] = result.length;
        result.add(step);
      }
    }
    return result;
  }

  /// Spec §3.2 — canonicalize: cycles → backtracking → final.
  List<TraversalStep> canonicalize(List<TraversalStep> steps) {
    var s = removeCycles(steps);
    int prevLen;
    do {
      prevLen = s.length;
      s = removeBacktracking(s);
    } while (s.isNotEmpty && s.length < prevLen);
    return s;
  }

  /// Spec §3.3 — deterministic selection when multiple shortest paths exist.
  /// Priority: blood > adoptive > step > inLaw > foster > spiritual.
  List<TraversalStep> selectDeterministic(List<List<TraversalStep>> candidates) {
    if (candidates.isEmpty) return const [];
    if (candidates.length == 1) return candidates.first;
    const rank = {
      Consanguinity.blood: 0,
      Consanguinity.adoptive: 1,
      Consanguinity.step: 2,
      Consanguinity.inLaw: 3,
      Consanguinity.foster: 4,
      Consanguinity.spiritual: 5,
    };
    final minLen = candidates.map((c) => c.length).reduce((a, b) => a < b ? a : b);
    final shortest = candidates.where((c) => c.length == minLen).toList();
    shortest.sort((a, b) {
      final aMax = a.map((s) => rank[s.consanguinity] ?? 99).reduce((x, y) => x > y ? x : y);
      final bMax = b.map((s) => rank[s.consanguinity] ?? 99).reduce((x, y) => x > y ? x : y);
      if (aMax != bMax) return aMax - bMax;
      final aPat = a.map((s) => s.primitive.name).join('_');
      final bPat = b.map((s) => s.primitive.name).join('_');
      return aPat.compareTo(bPat);
    });
    return shortest.first;
  }
}

// ===========================================================================
// 3. GRAPH ENGINE (mirror of graph-engine.service.ts — spec §3.1, §5)
// ===========================================================================

class FamilyNode {
  final String id;
  final String gender; // MALE | FEMALE | OTHER
  final DateTime? birthDate;
  final DateTime? deathDate;
  const FamilyNode(this.id, this.gender, this.birthDate, this.deathDate);
}

class StoredEdge {
  final String id;
  final String edgeType; // parent | spouse | adoptiveParent | stepParent
  final String temporal;
  final String personAId;
  final String personBId;
  final bool isInferred;
  const StoredEdge({
    required this.id,
    required this.edgeType,
    required this.temporal,
    required this.personAId,
    required this.personBId,
    required this.isInferred,
  });
}

const _maxDepth = 8;

class PathResult {
  final List<TraversalStep> steps;
  final KinshipSignature signature;
  final String fromPersonId;
  final String toPersonId;
  const PathResult(this.steps, this.signature, this.fromPersonId, this.toPersonId);
}

class RelationshipEngine {
  final PathCanonicalizer _canonicalizer = PathCanonicalizer();

  /// Build the KinshipSignature for the relationship A → B in the family.
  /// Deterministic per spec §14.
  Future<PathResult?> resolveSignature({
    required Map<String, FamilyNode> nodes,
    required List<StoredEdge> edges,
    required String personAId,
    required String personBId,
  }) async {
    // 1. BFS — find all shortest paths up to MAX_DEPTH
    final candidates = _bfsAllShortestPaths(nodes, edges, personAId, personBId);
    if (candidates.isEmpty) return null;

    // 2. Canonicalize each candidate
    final canonical = candidates
        .map((c) => _canonicalizer.canonicalize(c))
        .where((c) => c.isNotEmpty)
        .toList();
    if (canonical.isEmpty) return null;

    // 3. Deterministic selection
    final winner = _canonicalizer.selectDeterministic(canonical);

    // 4. Build signature
    final signature = _buildSignature(winner, nodes, personAId);
    return PathResult(winner, signature, personAId, personBId);
  }

  // ----- BFS ------------------------------------------------------------

  List<List<TraversalStep>> _bfsAllShortestPaths(
    Map<String, FamilyNode> nodes,
    List<StoredEdge> edges,
    String startId,
    String targetId,
  ) {
    final adjacency = _buildAdjacency(edges);
    if (startId == targetId) return const [];

    final visitedDepths = <String, int>{startId: 0};
    final queue = Queue<List<TraversalStep>>();
    final initialNeighbors = adjacency[startId] ?? const [];
    for (final n in initialNeighbors) {
      queue.add([TraversalStep(
        primitive: n.primitive,
        nodeId: startId,
        targetNodeId: n.targetId,
        edgeType: n.edge.edgeType,
        consanguinity: n.consanguinity,
      )]);
      visitedDepths[n.targetId] = 1;
    }

    final results = <List<TraversalStep>>[];
    int foundDepth = 1 << 30; // infinity

    while (queue.isNotEmpty) {
      final path = queue.removeFirst();
      final lastNode = path.last.targetNodeId;
      final depth = path.length;
      if (depth > _maxDepth) continue;
      if (depth > foundDepth) continue;

      if (lastNode == targetId) {
        if (depth < foundDepth) {
          foundDepth = depth;
          results.clear();
        }
        results.add(path);
        continue;
      }

      final neighbors = adjacency[lastNode] ?? const [];
      for (final n in neighbors) {
        final prevDepth = visitedDepths[n.targetId];
        if (prevDepth != null && prevDepth < depth + 1) continue;
        if (n.targetId == path.last.nodeId) continue; // trivial backtrack
        visitedDepths[n.targetId] = depth + 1;
        queue.add([...path, TraversalStep(
          primitive: n.primitive,
          nodeId: lastNode,
          targetNodeId: n.targetId,
          edgeType: n.edge.edgeType,
          consanguinity: n.consanguinity,
        )]);
      }
    }
    return results;
  }

  Map<String, List<_AdjEntry>> _buildAdjacency(List<StoredEdge> edges) {
    final adj = <String, List<_AdjEntry>>{};
    void add(String from, _AdjEntry entry) {
      adj.putIfAbsent(from, () => []).add(entry);
    }
    for (final e in edges) {
      switch (e.edgeType) {
        case 'parent':
          add(e.personAId, _AdjEntry(Primitive.upParent, e.personBId, e, Consanguinity.blood));
          add(e.personBId, _AdjEntry(Primitive.downChild, e.personAId, e, Consanguinity.blood));
          break;
        case 'spouse':
          add(e.personAId, _AdjEntry(Primitive.spouse, e.personBId, e, Consanguinity.inLaw));
          add(e.personBId, _AdjEntry(Primitive.spouse, e.personAId, e, Consanguinity.inLaw));
          break;
        case 'adoptiveParent':
          add(e.personAId, _AdjEntry(Primitive.upAdoptiveParent, e.personBId, e, Consanguinity.adoptive));
          add(e.personBId, _AdjEntry(Primitive.downAdoptiveChild, e.personAId, e, Consanguinity.adoptive));
          break;
        case 'stepParent':
          add(e.personAId, _AdjEntry(Primitive.upStepParent, e.personBId, e, Consanguinity.step));
          add(e.personBId, _AdjEntry(Primitive.downStepChild, e.personAId, e, Consanguinity.step));
          break;
      }
    }
    return adj;
  }

  // ----- Signature builder (spec §6) ------------------------------------

  KinshipSignature _buildSignature(
    List<TraversalStep> steps,
    Map<String, FamilyNode> nodes,
    String startId,
  ) {
    final primitives = steps.map((s) => s.primitive).toList();
    final pathPattern = primitives.map((p) => p.name).join('_');

    int generationDelta = 0;
    for (final p in primitives) {
      if (p.name.startsWith('up_') || p.name.startsWith('up')) generationDelta -= 1;
      else if (p.name.startsWith('down_') || p.name.startsWith('down')) generationDelta += 1;
    }

    // WEAKEST consanguinity along the path wins
    const rank = {
      Consanguinity.blood: 0,
      Consanguinity.adoptive: 1,
      Consanguinity.step: 2,
      Consanguinity.inLaw: 3,
      Consanguinity.foster: 4,
      Consanguinity.spiritual: 5,
    };
    var consanguinity = Consanguinity.blood;
    var worstRank = -1;
    for (final s in steps) {
      final r = rank[s.consanguinity] ?? 99;
      if (r > worstRank) {
        worstRank = r;
        consanguinity = s.consanguinity;
      }
    }

    // side — set by the FIRST UP step (spec §6.3)
    var side = Side.none;
    for (final s in steps) {
      if (s.primitive == Primitive.upParent ||
          s.primitive == Primitive.upAdoptiveParent ||
          s.primitive == Primitive.upStepParent) {
        final parentNode = nodes[s.targetNodeId];
        if (parentNode?.gender == 'MALE') side = Side.paternal;
        else if (parentNode?.gender == 'FEMALE') side = Side.maternal;
        break;
      }
    }

    // genderAnchor — target person
    final targetId = steps.last.targetNodeId;
    final targetNode = nodes[targetId];
    var genderAnchor = GenderAnchor.neutral;
    if (targetNode?.gender == 'MALE') genderAnchor = GenderAnchor.male;
    else if (targetNode?.gender == 'FEMALE') genderAnchor = GenderAnchor.female;

    // removal — for cousins
    final upCount = primitives.where((p) => p.name.startsWith('up')).length;
    final downCount = primitives.where((p) => p.name.startsWith('down')).length;
    final removal = (upCount > 0 && downCount > 0) ? (upCount - downCount).abs() : 0;

    // temporal — read from edges; if any LATE → late; if any FORMER → former.
    // We don't carry edge temporal through TraversalStep in this lightweight
    // mirror; the caller (engine service) overrides this if needed.
    return KinshipSignature(
      generationDelta: generationDelta,
      pathPattern: pathPattern,
      side: side,
      consanguinity: consanguinity,
      genderAnchor: genderAnchor,
      seniority: Seniority.none,
      removal: removal,
      doubleKinship: false,
      temporal: Temporal.current,
    );
  }
}

class _AdjEntry {
  final Primitive primitive;
  final String targetId;
  final StoredEdge edge;
  final Consanguinity consanguinity;
  const _AdjEntry(this.primitive, this.targetId, this.edge, this.consanguinity);
}

// ===========================================================================
// 4. CANONICAL ID LAYER (mirror of canonical-id.service.ts — spec §4)
// ===========================================================================

enum CanonicalId { parent, spouse, adoptiveParent, stepParent, derived }

class CanonicalIdService {
  static const _en = {
    'father': CanonicalId.parent, 'dad': CanonicalId.parent, 'papa': CanonicalId.parent,
    'mother': CanonicalId.parent, 'mom': CanonicalId.parent, 'mama': CanonicalId.parent,
    'parent': CanonicalId.parent,
    'son': CanonicalId.parent, 'daughter': CanonicalId.parent, 'child': CanonicalId.parent,
    'husband': CanonicalId.spouse, 'wife': CanonicalId.spouse, 'spouse': CanonicalId.spouse,
    'adoptive father': CanonicalId.adoptiveParent,
    'adoptive mother': CanonicalId.adoptiveParent,
    'adoptive parent': CanonicalId.adoptiveParent,
    'stepfather': CanonicalId.stepParent, 'step mother': CanonicalId.stepParent,
    'step parent': CanonicalId.stepParent,
    // Derived — engine must NOT store
    'grandfather': CanonicalId.derived, 'grandmother': CanonicalId.derived,
    'uncle': CanonicalId.derived, 'aunt': CanonicalId.derived,
    'cousin': CanonicalId.derived, 'nephew': CanonicalId.derived, 'niece': CanonicalId.derived,
    'brother': CanonicalId.derived, 'sister': CanonicalId.derived,
  };

  /// Map a user-facing term to its CanonicalId.
  CanonicalId normalizeToCanonical(String input, {String locale = 'en'}) {
    if (input.isEmpty) return CanonicalId.derived;
    final term = input.trim().toLowerCase();
    return _en[term] ?? CanonicalId.derived;
  }

  bool isStorable(CanonicalId id) => id != CanonicalId.derived;
}

// ===========================================================================
// 5. OFFLINE VOCABULARY LOOKUP (mirror of kinship.service.ts — spec §7)
// ===========================================================================

/// Lightweight in-memory vocabulary entry for offline lookup.
/// The full 9,552-row table is bundled as an asset JSON file and loaded
/// on app startup. See README.md for asset-bundling instructions.
class VocabEntry {
  final String signatureKey;
  final String languageCode;
  final String localizedTerm;
  final String englishTerm;
  final String canonicalId;
  final String category;
  final int variantRank;
  const VocabEntry({
    required this.signatureKey,
    required this.languageCode,
    required this.localizedTerm,
    required this.englishTerm,
    required this.canonicalId,
    required this.category,
    required this.variantRank,
  });

  factory VocabEntry.fromJson(Map<String, dynamic> j) => VocabEntry(
        signatureKey: j['signature_key'] as String,
        languageCode: j['language_code'] as String,
        localizedTerm: j['localized_term'] as String,
        englishTerm: j['english_term'] as String,
        canonicalId: j['canonical_id'] as String,
        category: j['category'] as String,
        variantRank: (j['variant_rank'] as num).toInt(),
      );
}

class VocabularyMapper {
  final Map<String, VocabEntry> _primary = {}; // key = "$signatureKey|$lang"
  final Map<String, List<VocabEntry>> _variants = {};

  /// Load vocabulary entries from a JSON list (typically from the asset bundle).
  void loadAll(List<Map<String, dynamic>> rows) {
    for (final j in rows) {
      final e = VocabEntry.fromJson(j);
      final k = '${e.signatureKey}|${e.languageCode}';
      _variants.putIfAbsent(k, () => []).add(e);
      if (e.variantRank == 0) _primary[k] = e;
    }
  }

  /// Deterministic primary lookup (spec §14).
  /// Returns null if no entry — caller falls back to composed term.
  VocabEntry? resolve(KinshipSignature sig, String languageCode) {
    return _primary['${sig.signatureKey}|$languageCode'];
  }

  /// Resolve all regional/dialectal variants (for "Also known as: ...").
  List<VocabEntry> resolveVariants(KinshipSignature sig, String languageCode) {
    return _variants['${sig.signatureKey}|$languageCode'] ?? const [];
  }

  int get loadedCount => _primary.length;
}
