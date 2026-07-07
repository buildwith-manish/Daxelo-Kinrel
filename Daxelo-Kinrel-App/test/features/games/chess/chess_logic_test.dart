// test/features/games/chess/chess_logic_test.dart
//
// Tests for Chess logic — verifies the chess.dart engine handles:
//   • Check detection (king in check, illegal moves that leave king in check)
//   • Checkmate detection (king in check + no legal moves)
//   • Stalemate detection (king not in check + no legal moves = draw)
//   • Castling eligibility (kingside/queenside, conditions)
//   • En passant (only available for one turn after qualifying pawn move)
//   • Pawn promotion (defaults to queen)
//
// Run with: flutter test test/features/games/chess/chess_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chess/chess.dart' as chess;

void main() {
  group('Initial position', () {
    test('starts with correct FEN', () {
      final game = chess.Chess();
      expect(
        game.fen,
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
    });

    test('white moves first', () {
      final game = chess.Chess();
      expect(game.turn, chess.Color.WHITE);
    });

    test('20 legal moves from starting position', () {
      final game = chess.Chess();
      final moves = game.generate_moves();
      expect(moves.length, 20);
    });
  });

  group('Check detection', () {
    test('king is in check when attacked', () {
      final game = chess.Chess.fromFEN(
        'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
      );
      expect(game.in_check, true);
    });

    test('cannot make a move that leaves own king in check', () {
      final game = chess.Chess.fromFEN('4r3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      final move = game.move({'from': 'e2', 'to': 'e4'});
      expect(move, isNull, reason: 'Should not allow move that exposes king');
    });

    test('king not in check in normal position', () {
      final game = chess.Chess();
      expect(game.in_check, false);
    });
  });

  group('Checkmate detection', () {
    test('fool\'s mate is detected as checkmate', () {
      final game = chess.Chess();
      game.move({'from': 'f2', 'to': 'f3'});
      game.move({'from': 'e7', 'to': 'e5'});
      game.move({'from': 'g2', 'to': 'g4'});
      game.move({'from': 'd8', 'to': 'h4'});

      expect(game.in_checkmate, true);
      expect(game.in_check, true);
    });

    test('checkmate means game is over', () {
      final game = chess.Chess();
      game.move({'from': 'f2', 'to': 'f3'});
      game.move({'from': 'e7', 'to': 'e5'});
      game.move({'from': 'g2', 'to': 'g4'});
      game.move({'from': 'd8', 'to': 'h4'});

      expect(game.game_over, true);
    });
  });

  group('Stalemate detection', () {
    test('stalemate is not checkmate', () {
      final game = chess.Chess.fromFEN('k7/2Q5/1K6/8/8/8/8/8 b - - 0 1');
      expect(game.in_stalemate, true);
      expect(game.in_checkmate, false);
      expect(game.in_check, false);
    });

    test('stalemate is a draw', () {
      final game = chess.Chess.fromFEN('k7/2Q5/1K6/8/8/8/8/8 b - - 0 1');
      expect(game.in_draw, true);
      expect(game.game_over, true);
    });
  });

  group('Castling', () {
    test('kingside castling is legal when conditions are met', () {
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
      final move = game.move({'from': 'e1', 'to': 'g1'});
      expect(move, isNotNull, reason: 'Kingside castling should be legal');
      expect(move!.flag, 'k'); // chess.dart uses string flag 'k' for kingside castle
    });

    test('queenside castling is legal when conditions are met', () {
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/R3K3 w Q - 0 1');
      final move = game.move({'from': 'e1', 'to': 'c1'});
      expect(move, isNotNull, reason: 'Queenside castling should be legal');
      expect(move!.flag, 'q');
    });

    test('cannot castle if king has moved', () {
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4K2R w - - 0 1');
      final move = game.move({'from': 'e1', 'to': 'g1'});
      expect(move, isNull, reason: 'Should not castle without castling rights');
    });

    test('cannot castle through check', () {
      final game = chess.Chess.fromFEN('4r3/8/8/8/8/8/8/4K2R w K - 0 1');
      final move = game.move({'from': 'e1', 'to': 'g1'});
      expect(move, isNull, reason: 'Should not castle through check');
    });
  });

  group('En passant', () {
    test('en passant capture is legal immediately after qualifying pawn move', () {
      final game = chess.Chess.fromFEN(
        '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
      );
      final move = game.move({'from': 'e5', 'to': 'd6'});
      expect(move, isNotNull, reason: 'En passant should be legal');
      expect(move!.flag, 'e'); // 'e' = en passant capture
    });

    test('en passant is not available after one turn', () {
      final game = chess.Chess.fromFEN('4k3/8/8/3pP3/8/8/8/4K3 b - - 0 1');
      game.move({'from': 'e8', 'to': 'd8'});
      final move = game.move({'from': 'e5', 'to': 'd6'});
      expect(move, isNull, reason: 'En passant should not be available after one turn');
    });
  });

  group('Pawn promotion', () {
    test('pawn promotes to queen by default', () {
      final game = chess.Chess.fromFEN('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      final move = game.move({'from': 'a7', 'to': 'a8'});
      expect(move, isNotNull, reason: 'Pawn promotion should work');
      expect(move!.promotion, chess.PieceType.QUEEN);
    });

    test('pawn can promote to knight', () {
      final game = chess.Chess.fromFEN('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      final move = game.move({'from': 'a7', 'to': 'a8', 'promotion': 'n'});
      expect(move, isNotNull);
      expect(move!.promotion, chess.PieceType.KNIGHT);
    });

    test('promoted piece appears on the board', () {
      final game = chess.Chess.fromFEN('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      game.move({'from': 'a7', 'to': 'a8'});
      final piece = game.get('a8');
      expect(piece, isNotNull);
      expect(piece!.type, chess.PieceType.QUEEN);
      expect(piece.color, chess.Color.WHITE);
    });
  });

  group('FEN serialization', () {
    test('FEN round-trips correctly', () {
      final fen1 = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final game = chess.Chess.fromFEN(fen1);
      expect(game.fen, fen1);
    });

    test('FEN updates after a move', () {
      final game = chess.Chess();
      game.move({'from': 'e2', 'to': 'e4'});
      expect(
        game.fen,
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      );
    });
  });

  group('Move notation (SAN)', () {
    test('generates correct SAN for pawn move', () {
      final game = chess.Chess();
      final move = game.move({'from': 'e2', 'to': 'e4'});
      expect(game.san(move!), 'e4');
    });

    test('generates correct SAN for knight move', () {
      final game = chess.Chess();
      final move = game.move({'from': 'g1', 'to': 'f3'});
      expect(game.san(move!), 'Nf3');
    });

    test('generates correct SAN for castling', () {
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
      final move = game.move({'from': 'e1', 'to': 'g1'});
      expect(game.san(move!), 'O-O');
    });
  });

  group('Draw detection', () {
    test('insufficient material (king vs king) is a draw', () {
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4K3 w - - 0 1');
      expect(game.insufficient_material, true);
      expect(game.in_draw, true);
    });

    test('king + queen vs king is not insufficient material', () {
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4KQ2 w - - 0 1');
      expect(game.insufficient_material, false);
    });
  });
}
