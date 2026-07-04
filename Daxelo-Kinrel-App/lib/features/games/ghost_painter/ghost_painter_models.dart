// lib/features/games/ghost_painter/ghost_painter_models.dart

class GhostPainterRound {
  const GhostPainterRound({
    required this.id,
    required this.familyId,
    required this.drawerPersonId,
    required this.drawerPersonName,
    required this.promptWord,
    required this.status,
    required this.startedAt,
    this.endsAt,
  });
  final String id;
  final String familyId;
  final String drawerPersonId;
  final String drawerPersonName;
  final String promptWord;
  final String status; // drawing | guessing | completed
  final DateTime startedAt;
  final DateTime? endsAt;

  factory GhostPainterRound.fromJson(Map<String, dynamic> json) => GhostPainterRound(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    drawerPersonId: json['drawerPersonId'] ?? '',
    drawerPersonName: json['drawerPersonName'] ?? 'Member',
    promptWord: json['promptWord'] ?? '',
    status: json['status'] ?? 'drawing',
    startedAt: DateTime.tryParse(json['startedAt'] ?? '') ?? DateTime.now(),
    endsAt: json['endsAt'] != null ? DateTime.tryParse(json['endsAt']) : null,
  );

  bool get isActive => status == 'drawing' || status == 'guessing';
  bool get isCompleted => status == 'completed';
}

class GhostPainterStroke {
  const GhostPainterStroke({
    required this.id,
    required this.roundId,
    required this.points,
    required this.sequenceOrder,
  });
  final String id;
  final String roundId;
  final List<OffsetPoint> points;
  final int sequenceOrder;

  factory GhostPainterStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['strokeData'] as List? ?? [];
    return GhostPainterStroke(
      id: json['id'] ?? '',
      roundId: json['roundId'] ?? '',
      points: rawPoints.map((p) => OffsetPoint.fromJson(p as Map<String, dynamic>)).toList(),
      sequenceOrder: json['sequenceOrder'] ?? 0,
    );
  }
}

class OffsetPoint {
  const OffsetPoint({required this.x, required this.y});
  final double x;
  final double y;

  factory OffsetPoint.fromJson(Map<String, dynamic> json) =>
      OffsetPoint(x: (json['x'] as num?)?.toDouble() ?? 0, y: (json['y'] as num?)?.toDouble() ?? 0);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class GhostPainterGuess {
  const GhostPainterGuess({
    required this.id,
    required this.roundId,
    required this.userId,
    required this.userName,
    required this.guessText,
    required this.isCorrect,
    required this.guessedAt,
  });
  final String id;
  final String roundId;
  final String userId;
  final String userName;
  final String guessText;
  final bool isCorrect;
  final DateTime guessedAt;

  factory GhostPainterGuess.fromJson(Map<String, dynamic> json) => GhostPainterGuess(
    id: json['id'] ?? '',
    roundId: json['roundId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Member',
    guessText: json['guessText'] ?? '',
    isCorrect: json['isCorrect'] ?? false,
    guessedAt: DateTime.tryParse(json['guessedAt'] ?? '') ?? DateTime.now(),
  );
}

/// V1 hardcoded prompt words — family-friendly, drawable.
const ghostPainterPrompts = [
  'House', 'Tree', 'Sun', 'Moon', 'Star', 'Heart', 'Fish', 'Cat', 'Dog',
  'Bird', 'Flower', 'Car', 'Boat', 'Umbrella', 'Hat', 'Key', 'Clock',
  'Book', 'Cup', 'Banana', 'Apple', 'Eye', 'Hand', 'Door', 'Window',
  'Mountain', 'River', 'Cloud', 'Rainbow', 'Cake', 'Candle', 'Gift',
  'Camera', 'Phone', 'Guitar', 'Drum', 'Crown', 'Kite', 'Balloon',
  'Ladder', 'Bridge', 'Tent', 'Windmill', 'Lighthouse', 'Castle',
  'Rocket', 'Bicycle', 'Scooter', 'Elephant', 'Lion', 'Snake',
  'Butterfly', 'Spider', 'Rocket', 'Anchor', 'Compass', 'Map',
  'Piano', 'Headphones', 'Sunglasses', 'Backpack', 'Scissors',
];
