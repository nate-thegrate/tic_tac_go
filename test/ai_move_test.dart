import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

void main() {
  test('easy blocks immediate win', () async {
    final board = BoardData([
      [PlayerMark.x, PlayerMark.x, null],
      [null, PlayerMark.o, null],
      [null, null, null],
    ]);
    final move = await aiMove(.easy, Ruleset.gomoku, board, .o);
    expect(move, (0, 2));
  });

  test('hard takes winning move', () async {
    final board = BoardData([
      [PlayerMark.x, PlayerMark.x, null],
      [PlayerMark.o, PlayerMark.o, null],
      [null, null, null],
    ]);
    final move = await aiMove(.hard, Ruleset.gomoku, board, .x);
    expect(move, (0, 2));
  });

  test('brutal takes winning move', () async {
    final board = BoardData([
      [PlayerMark.x, PlayerMark.x, null],
      [PlayerMark.o, PlayerMark.o, null],
      [null, null, null],
    ]);
    final move = await aiMove(.brutal, Ruleset.gomoku, board, .x);
    expect(move, (0, 2));
  });

  test('easy returns a cell on empty board', () async {
    final board = BoardData(List.generate(3, (_) => List<PlayerMark?>.filled(3, null)));
    final move = await aiMove(.easy, Ruleset.gomoku, board, .x);
    expect(move.$1, inInclusiveRange(0, 2));
    expect(move.$2, inInclusiveRange(0, 2));
  });

  test('connect6 uses explicit toMove when stone counts are equal', () async {
    // Five O and five X: equal counts would look like black to move under the
    // old inference, but mid-turn white may still be placing.
    final grid = List.generate(6, (_) => List<PlayerMark?>.filled(8, null));
    for (var col = 0; col < 5; col++) {
      grid[0][col] = PlayerMark.o; // O wins at (0, 5)
      grid[5][col] = PlayerMark.x; // X wins at (5, 5)
    }
    final board = BoardData(grid);
    expect(await aiMove(.easy, Ruleset.connect6, board, .o), (0, 5));
    expect(await aiMove(.easy, Ruleset.connect6, board, .x), (5, 5));
  });
}
