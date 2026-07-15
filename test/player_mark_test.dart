import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/player_mark.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

import 'helpers/board_helpers.dart';

void main() {
  group('PlayerMark', () {
    test('opponent swaps x and o', () {
      expect(PlayerMark.x.opponent, PlayerMark.o);
      expect(PlayerMark.o.opponent, PlayerMark.x);
    });

    test('toString depends on goMode', () {
      expect(PlayerMark.x.toString(), 'X');
      expect(PlayerMark.o.toString(), 'O');
      expect(PlayerMark.x.toString(goMode: true), 'Black');
      expect(PlayerMark.o.toString(goMode: true), 'White');
    });

    test('colors are distinct', () {
      expect(PlayerMark.x.color, isNot(PlayerMark.o.color));
      expect(PlayerMark.x.winnerGlow, isNot(PlayerMark.o.winnerGlow));
    });
  });

  group('isWinningRunLength', () {
    test('gomoku uses >= winLength', () {
      expect(isWinningRunLength(4, .x, 5, .gomoku), isFalse);
      expect(isWinningRunLength(5, .x, 5, .gomoku), isTrue);
      expect(isWinningRunLength(6, .o, 5, .gomoku), isTrue);
    });

    test('connect6 uses >= 6', () {
      expect(isWinningRunLength(5, .x, 6, .connect6), isFalse);
      expect(isWinningRunLength(6, .x, 6, .connect6), isTrue);
    });

    test('renju black requires exact five', () {
      expect(isWinningRunLength(5, .x, 5, .renju), isTrue);
      expect(isWinningRunLength(6, .x, 5, .renju), isFalse);
      expect(isWinningRunLength(4, .x, 5, .renju), isFalse);
    });

    test('renju white uses >= winLength', () {
      expect(isWinningRunLength(5, .o, 5, .renju), isTrue);
      expect(isWinningRunLength(6, .o, 5, .renju), isTrue);
    });
  });

  group('BoardCell', () {
    test('inBounds / inBoardSize', () {
      final board = emptyBoard(3);
      expect((0, 0).inBounds(board), isTrue);
      expect((2, 2).inBounds(board), isTrue);
      expect((-1, 0).inBounds(board), isFalse);
      expect((0, 3).inBounds(board), isFalse);
      expect((1, 1).inBoardSize(3, 3), isTrue);
      expect((3, 0).inBoardSize(3, 3), isFalse);
    });

    test('markOn returns null out of bounds or empty', () {
      final board = emptyBoard(3);
      board[1][1] = .x;
      expect((1, 1).markOn(board), PlayerMark.x);
      expect((0, 0).markOn(board), isNull);
      expect((-1, 0).markOn(board), isNull);
    });

    test('withMark restores cell after body', () {
      final board = emptyBoard(3);
      final result = (1, 1).withMark(board, .x, () {
        expect(board[1][1], PlayerMark.x);
        return 42;
      });
      expect(result, 42);
      expect(board[1][1], isNull);
    });

    test('withMark restores even if body throws', () {
      final board = emptyBoard(3);
      expect(
        () => (0, 0).withMark(board, .o, () => throw StateError('boom')),
        throwsStateError,
      );
      expect(board[0][0], isNull);
    });

    test('isLegalOn rejects occupied and out-of-bounds', () {
      final board = emptyBoard(3);
      board[0][0] = .x;
      expect((0, 0).isLegalOn(board, .o, .gomoku), isFalse);
      expect((-1, 0).isLegalOn(board, .o, .gomoku), isFalse);
      expect((1, 1).isLegalOn(board, .o, .gomoku), isTrue);
    });

    test('runLengthThrough counts both directions', () {
      final board = emptyBoard(5);
      placeHorizontal(board, .x, row: 2, startCol: 1, length: 3);
      // Through middle of xxx
      expect((2, 2).runLengthThrough(board, .x, 0, 1), 3);
      expect((2, 1).runLengthThrough(board, .x, 0, 1), 3);
    });

    test('formsWin detects diagonal win', () {
      final board = emptyBoard(5);
      board[0][0] = .x;
      board[1][1] = .x;
      board[2][2] = .x;
      board[3][3] = .x;
      board[4][4] = .x;
      expect((2, 2).formsWin(board, .x, 5, ruleset: .gomoku), isTrue);
      expect((0, 1).formsWin(board, .x, 5, ruleset: .gomoku), isFalse);
    });
  });

  group('BoardGrid', () {
    test('countMark and stoneCount', () {
      final board = emptyBoard(3);
      place(board, .x, [(0, 0), (1, 1)]);
      place(board, .o, [(0, 1)]);
      expect(board.countMark(.x), 2);
      expect(board.countMark(.o), 1);
      expect(board.stoneCount, 3);
    });

    test('isBoardFull', () {
      final List<List<PlayerMark?>> full = [
        [PlayerMark.x, PlayerMark.o, PlayerMark.x],
        [PlayerMark.o, PlayerMark.x, PlayerMark.o],
        [PlayerMark.x, PlayerMark.o, PlayerMark.x],
      ];
      expect(full.isBoardFull, isTrue);
      expect(emptyBoard(3).isBoardFull, isFalse);
    });

    test('centerCell, emptyCells, occupiedCells', () {
      final board = emptyBoard(3);
      board[1][1] = .x;
      expect(board.centerCell, (1, 1));
      expect(board.occupiedCells, [(1, 1)]);
      expect(board.emptyCells, hasLength(8));
      expect(board.emptyCells, isNot(contains((1, 1))));
    });

    test('copyMutable is independent', () {
      final board = emptyBoard(2);
      board[0][0] = .x;
      final copy = board.copyMutable();
      copy[0][0] = .o;
      expect(board[0][0], PlayerMark.x);
    });
  });

  group('winnerOn / winningRunOn', () {
    test('finds horizontal winner', () {
      final board = emptyBoard(3);
      placeHorizontal(board, .o, row: 1, startCol: 0, length: 3);
      expect(winnerOn(board, Ruleset.gomoku), PlayerMark.o);
      expect(winningRunOn(board, Ruleset.gomoku), [(1, 0), (1, 1), (1, 2)]);
    });

    test('returns null when no winner', () {
      expect(winnerOn(emptyBoard(3), Ruleset.gomoku), isNull);
      expect(winningRunOn(emptyBoard(3), Ruleset.gomoku), isNull);
    });
  });
}
