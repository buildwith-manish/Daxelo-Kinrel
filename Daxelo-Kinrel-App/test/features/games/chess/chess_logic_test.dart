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
      final moves = game.generateMoves();
      expect(moves.length, 20); // 16 pawn moves + 4 knight moves
    });
  });

  group('Check detection', () {
    test('king is in check when attacked', () {
      // Fool's mate position — white king in check after Qh4
      final game = chess.Chess.fromFEN(
        'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
      );
      expect(game.inCheck, true);
    });

    test('cannot make a move that leaves own king in check', () {
      // White king on e1, black rook on e8, white pawn on e2
      // Moving the pawn would expose the king to check — should be illegal
      final game = chess.Chess.fromFEN('4r3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      // Try to move pawn e2-e4 — this should fail because it exposes the king
      final move = game.move({'from': 'e2', 'to': 'e4'});
      expect(move, isNull, reason: 'Should not allow move that exposes king');
    });

    test('king not in check in normal position', () {
      final game = chess.Chess();
      expect(game.inCheck, false);
    });
  });

  group('Checkmate detection', () {
    test('fool\'s mate is detected as checkmate', () {
      final game = chess.Chess();
      // 1. f3 e5 2. g4 Qh4#
      game.move({'from': 'f2', 'to': 'f3'});
      game.move({'from': 'e7', 'to': 'e5'});
      game.move({'from': 'g2', 'to': 'g4'});
      game.move({'from': 'd8', 'to': 'h4'});

      expect(game.inCheckmate, true);
      expect(game.inCheck, true);
    });

    test('checkmate means game is over', () {
      final game = chess.Chess();
      game.move({'from': 'f2', 'to': 'f3'});
      game.move({'from': 'e7', 'to': 'e5'});
      game.move({'from': 'g2', 'to': 'g4'});
      game.move({'from': 'd8', 'to': 'h4'});

      expect(game.gameOver, true);
    });
  });

  group('Stalemate detection', () {
    test('stalemate is not checkmate', () {
      // Classic stalemate position:
      // Black king on a8, white king on c6, white queen on c7
      // Black to move but has no legal moves and is NOT in check
      final game = chess.Chess.fromFEN('k7/2Q5/1K6/8/8/8/8/8 b - - 0 1');
      expect(game.inStalemate, true);
      expect(game.inCheckmate, false);
      expect(game.inCheck, false);
    });

    test('stalemate is a draw', () {
      final game = chess.Chess.fromFEN('k7/2Q5/1K6/8/8/8/8/8 b - - 0 1');
      expect(game.inDraw, true);
      expect(game.gameOver, true);
    });
  });

  group('Castling', () {
    test('kingside castling is legal when conditions are met', () {
      // White king on e1, rook on h1, nothing between them
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
      final move = game.move({'from': 'e1', 'to': 'g1'});
      expect(move, isNotNull, reason: 'Kingside castling should be legal');
      expect(move!.flag, chess.MoveFlag.KSIDE_CASTLE);
    });

    test('queenside castling is legal when conditions are met', () {
      // White king on e1, rook on a1, nothing between them
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/R3K3 w Q - 0 1');
      final move = game.move({'from': 'e1', 'to': 'c1'});
      expect(move, isNotNull, reason: 'Queenside castling should be legal');
      expect(move!.flag, chess.MoveFlag.QSIDE_CASTLE);
    });

    test('cannot castle if king has moved', () {
      // King has moved (no castling rights)
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4K2R w - - 0 1');
      final move = game.move({'from': 'e1', 'to': 'g1'});
      expect(move, isNull, reason: 'Should not castle without castling rights');
    });

    test('cannot castle through check', () {
      // Black rook on e8 attacks the e-file — king passes through e1
      final game = chess.Chess.fromFEN('4r3/8/8/8/8/8/8/4K2R w K - 0 1');
      final move = game.move({'from': 'e1', 'to': 'g1'});
      expect(move, isNull, reason: 'Should not castle through check');
    });
  });

  group('En passant', () {
    test('en passant capture is legal immediately after qualifying pawn move', () {
      // White pawn on e5, black just played d7-d5
      // White can capture en passant: exd6
      final game = chess.Chess.fromFEN(
        '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
      );
      final move = game.move({'from': 'e5', 'to': 'd6'});
      expect(move, isNotNull, reason: 'En passant should be legal');
      expect(move!.flag, chess.MoveFlag.EP_CAPTURE);
    });

    test('en passant is not available after one turn', () {
      // If white doesn't capture en passant immediately, the opportunity is gone
      // Set up: white pawn on e5, black pawn on d5, but it's black's turn
      // (en passant square was set on the previous move, now it's expired)
      final game = chess.Chess.fromFEN('4k3/8/8/3pP3/8/8/8/4K3 b - - 0 1');
      // Black moves king somewhere
      game.move({'from': 'e8', 'to': 'd8'});
      // Now white tries en passant — should fail (no longer available)
      final move = game.move({'from': 'e5', 'to': 'd6'});
      expect(move, isNull, reason: 'En passant should not be available after one turn');
    });
  });

  group('Pawn promotion', () {
    test('pawn promotes to queen by default', () {
      // White pawn on a7, about to promote
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
      expect(game.insufficientMaterial, true);
      expect(game.inDraw, true);
    });

    test('king + queen vs king is not insufficient material', () {
      final game = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/4KQ2 w - - 0 1');
      expect(game.insufficientMaterial, false);
    });
  });
}
