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
    final move = await aiMove(.easy, Ruleset.gomoku, board);
    expect(move, (0, 2));
  });

  test('hard takes winning move', () async {
    final board = BoardData([
      [PlayerMark.x, PlayerMark.x, null],
      [PlayerMark.o, PlayerMark.o, null],
      [null, null, null],
    ]);
    final move = await aiMove(.hard, Ruleset.gomoku, board);
    expect(move, (0, 2));
  });

  test('brutal takes winning move', () async {
    final board = BoardData([
      [PlayerMark.x, PlayerMark.x, null],
      [PlayerMark.o, PlayerMark.o, null],
      [null, null, null],
    ]);
    final move = await aiMove(.brutal, Ruleset.gomoku, board);
    expect(move, (0, 2));
  });

  test('easy returns a cell on empty board', () async {
    final board = BoardData(List.generate(3, (_) => List<PlayerMark?>.filled(3, null)));
    final move = await aiMove(.easy, Ruleset.gomoku, board);
    expect(move.$1, inInclusiveRange(0, 2));
    expect(move.$2, inInclusiveRange(0, 2));
  });
}
