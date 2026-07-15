import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/player_mark.dart';

import '../helpers/board_helpers.dart';

void main() {
  group('Difficulty', () {
    test('toString capitalizes name', () {
      expect(Difficulty.easy.toString(), 'Easy');
      expect(Difficulty.hard.toString(), 'Hard');
      expect(Difficulty.brutal.toString(), 'Brutal');
    });
  });

  group('easy', () {
    test('blocks immediate win', () async {
      final board = BoardData([
        [PlayerMark.x, PlayerMark.x, null],
        [null, PlayerMark.o, null],
        [null, null, null],
      ]);
      final move = await aiMove(.easy, .gomoku, board, .o);
      expect(move, (0, 2));
    });

    test('takes winning move when available', () async {
      final board = BoardData([
        [PlayerMark.o, PlayerMark.o, null],
        [PlayerMark.x, PlayerMark.x, null],
        [null, null, null],
      ]);
      final move = await aiMove(.easy, .gomoku, board, .o);
      expect(move, (0, 2));
    });

    test('returns a cell on empty board', () async {
      final board = BoardData(emptyBoard(3));
      final move = await aiMove(.easy, .gomoku, board, .x);
      expect(move.$1, inInclusiveRange(0, 2));
      expect(move.$2, inInclusiveRange(0, 2));
    });

    test('prefers center-ish on empty larger board', () async {
      final board = BoardData(emptyBoard(15));
      final move = await aiMove(.easy, .gomoku, board, .x);
      // Candidate pool on empty board is only centerCell
      expect(move, (7, 7));
    });
  });

  group('hard', () {
    test('takes winning move', () async {
      final board = BoardData([
        [PlayerMark.x, PlayerMark.x, null],
        [PlayerMark.o, PlayerMark.o, null],
        [null, null, null],
      ]);
      final move = await aiMove(.hard, .gomoku, board, .x);
      expect(move, (0, 2));
    });

    test('blocks opponent win before random play', () async {
      final board = BoardData([
        [PlayerMark.x, PlayerMark.x, null],
        [null, PlayerMark.o, null],
        [null, null, null],
      ]);
      final move = await aiMove(.hard, .gomoku, board, .o);
      expect(move, (0, 2));
    });
  });

  group('brutal', () {
    test('takes winning move', () async {
      final board = BoardData([
        [PlayerMark.x, PlayerMark.x, null],
        [PlayerMark.o, PlayerMark.o, null],
        [null, null, null],
      ]);
      final move = await aiMove(.brutal, .gomoku, board, .x);
      expect(move, (0, 2));
    });
  });

  group('connect6', () {
    test('uses explicit toMove when stone counts are equal', () async {
      // Five O and five X: mid-turn white may still be placing.
      final grid = emptyBoard(6, 8);
      for (var col = 0; col < 5; col++) {
        grid[0][col] = .o; // O wins at (0, 5)
        grid[5][col] = .x; // X wins at (5, 5)
      }
      final board = BoardData(grid);
      expect(await aiMove(.easy, .connect6, board, .o), (0, 5));
      expect(await aiMove(.easy, .connect6, board, .x), (5, 5));
    });
  });

  group('renju', () {
    test('easy does not pick a black double-three foul', () async {
      final grid = emptyBoard(15);
      place(grid, .x, [(7, 5), (7, 6), (5, 7), (6, 7)]);
      // Fill nearby so the foul cell is attractive but illegal
      place(grid, .o, [(0, 0), (0, 1)]);
      final board = BoardData(grid);
      // Run several times — random among legal moves, never (7,7)
      for (var i = 0; i < 15; i++) {
        final move = await aiMove(.easy, .renju, board, .x);
        expect(move, isNot((7, 7)));
        expect(move.isLegalOn(grid, .x, .renju), isTrue);
      }
    });
  });
}
