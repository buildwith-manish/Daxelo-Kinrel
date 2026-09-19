// lib/features/games/sketch_telephone/sketch_telephone_engine.dart
//
// Sketch Telephone — pure Dart game engine.
//
// Gartic Phone-style drawing chain. 4–8 players. Each player writes a
// prompt, then everyone rotates: at step k, player j works on the chain
// owned by player (j + k) mod N. So step 0 = write your own prompt,
// step 1 = draw the prompt of the next player, step 2 = describe that
// drawing, step 3 = draw that description, and so on. After N steps
// (one per player), every chain has been touched by every player and
// the chains are revealed step by step — the "telephone" degradation
// is the comedy.
//
// Architecture mirrors mind_match:
//   • Supabase stores games + players + chains (each step is one row)
//   • Supabase Realtime broadcasts boardState changes + new chain rows
//   • RLS lets every family member read chains (the reveal needs this),
//     but the active UI only surfaces the player's currently-assigned
//     chain's previous step. Future steps simply don't exist yet.
//   • A 2s watchdog (invoked by every client) auto-advances when the
//     step timer expires.

import 'dart:convert';

const int kSketchTelephoneMinPlayers = 4;
const int kSketchTelephoneMaxPlayers = 8;
const int kSketchTelephoneDefaultDrawingSeconds = 90;
const int kSketchTelephoneMaxPromptLength = 200;
const int kSketchTelephoneMaxDescriptionLength = 200;

/// Step type — drives the input UI (text vs canvas).
enum SketchStepType { prompt, drawing, description }

extension SketchStepTypeX on SketchStepType {
  String get wire {
    switch (this) {
      case SketchStepType.prompt:
        return 'prompt';
      case SketchStepType.drawing:
        return 'drawing';
      case SketchStepType.description:
        return 'description';
    }
  }

  static SketchStepType fromString(String? s) {
    switch (s) {
      case 'drawing':
        return SketchStepType.drawing;
      case 'description':
        return SketchStepType.description;
      case 'prompt':
      default:
        return SketchStepType.prompt;
    }
  }

  /// True if this step takes text input (prompt or description).
  bool get isText => this != SketchStepType.drawing;

  /// Friendly label shown in the UI.
  String get label {
    switch (this) {
      case SketchStepType.prompt:
        return 'Write a prompt';
      case SketchStepType.drawing:
        return 'Draw it';
      case SketchStepType.description:
        return 'Describe it';
    }
  }

  String get verb {
    switch (this) {
      case SketchStepType.prompt:
        return 'writing a prompt';
      case SketchStepType.drawing:
        return 'drawing';
      case SketchStepType.description:
        return 'describing';
    }
  }
}

/// Phase — drives the high-level UI state machine.
enum SketchPhase { writing, drawing, revealing, finished }

extension SketchPhaseX on SketchPhase {
  String get wire {
    switch (this) {
      case SketchPhase.writing:
        return 'writing';
      case SketchPhase.drawing:
        return 'drawing';
      case SketchPhase.revealing:
        return 'revealing';
      case SketchPhase.finished:
        return 'finished';
    }
  }

  static SketchPhase fromString(String? s) {
    switch (s) {
      case 'drawing':
        return SketchPhase.drawing;
      case 'revealing':
        return SketchPhase.revealing;
      case 'finished':
        return SketchPhase.finished;
      case 'writing':
      default:
        return SketchPhase.writing;
    }
  }
}

/// Step-type lookup for a given 0-indexed step.
///   step 0         → prompt
///   step odd       → drawing
///   step even (>0) → description
SketchStepType stepTypeForIndex(int stepIndex) {
  if (stepIndex == 0) return SketchStepType.prompt;
  if (stepIndex.isEven) return SketchStepType.description;
  return SketchStepType.drawing;
}

/// Phase for a given 0-indexed step.
SketchPhase phaseForStep(int stepIndex) {
  final t = stepTypeForIndex(stepIndex);
  return t == SketchStepType.drawing
      ? SketchPhase.drawing
      : SketchPhase.writing;
}

/// One stroke = list of points + color + brush size.
class SketchStrokePoint {
  const SketchStrokePoint({required this.x, required this.y});
  final double x;
  final double y;

  factory SketchStrokePoint.fromJson(Map<String, dynamic> json) =>
      SketchStrokePoint(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class SketchStroke {
  const SketchStroke({
    required this.points,
    required this.color,
    required this.size,
  });
  final List<SketchStrokePoint> points;
  final int color; // ARGB int
  final double size; // brush width in px

  factory SketchStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List? ?? const [];
    return SketchStroke(
      points: rawPoints
          .map((p) => SketchStrokePoint.fromJson(
              Map<String, dynamic>.from(p as Map)))
          .toList(),
      color: (json['color'] as num?)?.toInt() ?? 0xFFEC4899,
      size: (json['size'] as num?)?.toDouble() ?? 4.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => p.toJson()).toList(),
        'color': color,
        'size': size,
      };
}

/// A single step inside a chain (one row in sketch_telephone_chains).
class SketchChainStep {
  const SketchChainStep({
    required this.stepIndex,
    required this.stepType,
    required this.content,
    required this.authorUserId,
    required this.authorName,
  });

  final int stepIndex;
  final SketchStepType stepType;
  final String content; // text (prompt/description) or JSON (drawing)
  final String authorUserId;
  final String authorName;

  /// Parse the drawing content into a list of strokes.
  /// Returns an empty list if this step isn't a drawing or the JSON is
  /// malformed (we'd rather draw nothing than crash the reveal).
  List<SketchStroke> get strokes {
    if (stepType != SketchStepType.drawing) return const [];
    if (content.isEmpty) return const [];
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      return decoded
          .map((s) => SketchStroke.fromJson(
              Map<String, dynamic>.from(s as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toJson() => {
        'stepIndex': stepIndex,
        'stepType': stepType.wire,
        'content': content,
        'authorUserId': authorUserId,
        'authorName': authorName,
      };

  factory SketchChainStep.fromJson(Map<String, dynamic> json) =>
      SketchChainStep(
        stepIndex: (json['stepIndex'] as num?)?.toInt() ?? 0,
        stepType: SketchStepTypeX.fromString(json['stepType'] as String?),
        content: (json['content'] ?? '') as String,
        authorUserId: (json['authorUserId'] ?? '') as String,
        authorName: (json['authorName'] ?? 'Player') as String,
      );
}

/// One full chain (one per player).
class SketchChain {
  const SketchChain({
    required this.chainIndex,
    required this.ownerUserId,
    required this.ownerName,
    required this.steps,
  });

  final int chainIndex;
  final String ownerUserId;
  final String ownerName;
  final List<SketchChainStep> steps;

  /// Number of steps completed in this chain.
  int get completedSteps => steps.length;

  Map<String, dynamic> toJson() => {
        'chainIndex': chainIndex,
        'ownerUserId': ownerUserId,
        'ownerName': ownerName,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory SketchChain.fromJson(Map<String, dynamic> json) {
    final stepsList = <SketchChainStep>[];
    final raw = json['steps'];
    if (raw is List) {
      for (final s in raw) {
        if (s is Map) {
          stepsList.add(
              SketchChainStep.fromJson(Map<String, dynamic>.from(s)));
        }
      }
    }
    return SketchChain(
      chainIndex: (json['chainIndex'] as num?)?.toInt() ?? 0,
      ownerUserId: (json['ownerUserId'] ?? '') as String,
      ownerName: (json['ownerName'] ?? 'Player') as String,
      steps: stepsList,
    );
  }
}

/// Player info stored inside the boardState (just idx + identity).
class SketchPlayerInfo {
  const SketchPlayerInfo({
    required this.idx,
    required this.userId,
    required this.name,
  });
  final int idx;
  final String userId;
  final String name;

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'userId': userId,
        'name': name,
      };

  factory SketchPlayerInfo.fromJson(Map<String, dynamic> json) =>
      SketchPlayerInfo(
        idx: (json['idx'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] ?? '') as String,
        name: (json['name'] ?? 'Player') as String,
      );
}

/// The full boardState JSONB from the games row, parsed.
class SketchBoardState {
  const SketchBoardState({
    required this.playerCount,
    required this.drawingSeconds,
    required this.currentStep,
    required this.phase,
    required this.chains,
    required this.players,
    required this.status,
    required this.winnerIndex,
  });

  final int playerCount;
  final int drawingSeconds;
  final int currentStep;
  final SketchPhase phase;
  final List<SketchChain> chains;
  final List<SketchPlayerInfo> players;
  final String status;
  final int winnerIndex;

  bool get isFinished =>
      status == 'completed' || phase == SketchPhase.finished;
  bool get isRevealing => phase == SketchPhase.revealing;

  /// Type of the current active step.
  SketchStepType get currentStepType => stepTypeForIndex(currentStep);

  /// The chain index a given player is working on at the current step.
  /// Returns -1 if the player is not in the game.
  int chainIndexForPlayer(int playerIdx) {
    if (playerIdx < 0 || playerIdx >= playerCount) return -1;
    return (playerIdx + currentStep) % playerCount;
  }

  /// Total number of steps in each chain (= player count).
  int get totalSteps => playerCount;

  /// Whether the current step is the last step before reveal.
  bool get isLastStep => currentStep >= totalSteps - 1;

  Map<String, dynamic> toJson() => {
        'playerCount': playerCount,
        'drawingSeconds': drawingSeconds,
        'currentStep': currentStep,
        'phase': phase.wire,
        'chains': chains.map((c) => c.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'status': status,
        'winnerIndex': winnerIndex,
      };

  factory SketchBoardState.fromJson(Map<String, dynamic> json) {
    final chainsList = <SketchChain>[];
    final rawChains = json['chains'];
    if (rawChains is List) {
      for (final c in rawChains) {
        if (c is Map) {
          chainsList
              .add(SketchChain.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }
    final playersList = <SketchPlayerInfo>[];
    final rawPlayers = json['players'];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        if (p is Map) {
          playersList.add(
              SketchPlayerInfo.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    return SketchBoardState(
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 4,
      drawingSeconds: (json['drawingSeconds'] as num?)?.toInt() ??
          kSketchTelephoneDefaultDrawingSeconds,
      currentStep: (json['currentStep'] as num?)?.toInt() ?? 0,
      phase: SketchPhaseX.fromString(json['phase'] as String?),
      chains: chainsList,
      players: playersList,
      status: (json['status'] as String?) ?? 'in_progress',
      winnerIndex: (json['winnerIndex'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Pure-Dart engine — client-side validation + display helpers.
class SketchTelephoneEngine {
  SketchTelephoneEngine._();

  /// Validate a prompt / description. Returns null if valid.
  static String? validateText(String text, {bool isPrompt = true}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return isPrompt
          ? 'Prompt cannot be empty'
          : 'Description cannot be empty';
    }
    final max = isPrompt
        ? kSketchTelephoneMaxPromptLength
        : kSketchTelephoneMaxDescriptionLength;
    if (trimmed.length > max) {
      return 'Too long (max $max chars)';
    }
    return null;
  }

  /// Validate a drawing (list of strokes). Returns null if valid.
  static String? validateDrawing(List<SketchStroke> strokes) {
    if (strokes.isEmpty) return 'Draw something first!';
    return null;
  }

  /// Serialize a list of strokes to a JSON string for storage.
  static String encodeDrawing(List<SketchStroke> strokes) {
    final list = strokes.map((s) => s.toJson()).toList();
    return jsonEncode(list);
  }

  /// Available drawing-time presets (seconds).
  static const List<int> drawingSecondsPresets = [60, 90, 120];
}
