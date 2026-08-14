// lib/core/kinship/v4/kinship_signature_v4.dart
//
// DAXELO-KINREL — v4.0 KinshipSignature
//
// Extended signature with fields required for full 5,396+ term coverage.

import '../v3/kinship_signature.dart' show TraversePrimitive, Consanguinity, FamilySide;

enum ResolutionStatus { confirmed, derived, inferred, ambiguous, incomplete }

class KinshipSignatureV4 {
  const KinshipSignatureV4({
    required this.generationDelta,
    required this.pathPattern,
    required this.side,
    required this.consanguinity,
    required this.genderAnchor,
    required this.seniority,
    required this.removal,
    required this.doubleKinship,
    required this.resolutionStatus,
    required this.intermediateSeniority,
    required this.spouseSide,
    required this.intermediateGender,
  });

  final int generationDelta;
  final String pathPattern;
  final FamilySide side;
  final Consanguinity consanguinity;
  final String genderAnchor;
  final String seniority;
  final int removal;
  final bool doubleKinship;
  final ResolutionStatus resolutionStatus;
  final String intermediateSeniority;
  final FamilySide spouseSide;
  final String intermediateGender;

  KinshipSignature toV3() => KinshipSignature(
    generationDelta: generationDelta, pathPattern: pathPattern, side: side,
    consanguinity: consanguinity, genderAnchor: genderAnchor, seniority: seniority,
    removal: removal, doubleKinship: doubleKinship,
  );

  @override
  String toString() => 'KinshipSignatureV4(gen=$generationDelta, pattern=$pathPattern, '
      'side=$side, consang=$consanguinity, gender=$genderAnchor, senior=$seniority, '
      'removal=$removal, double=$doubleKinship, status=$resolutionStatus, '
      'intSenior=$intermediateSeniority, spouseSide=$spouseSide, intGender=$intermediateGender)';
}
