import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/player_mark.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

List<List<PlayerMark?>> emptyBoard(int rows, int cols) =>
    List.generate(rows, (_) => List<PlayerMark?>.filled(cols, null));

void place(List<List<PlayerMark?>> board, PlayerMark mark, List<(int, int)> cells) {
  for (final (r, c) in cells) {
    board[r][c] = mark;
  }
}

void main() {
  test('brutal blocks dual open-three fork (loss 1)', () async {
    final board = emptyBoard(19, 13);
    place(board, .x, [(6, 8), (4, 4), (12, 8), (14, 7)]);
    place(board, .o, [(8, 6), (6, 6), (7, 5), (7, 7)]);
    expect(await aiMove(.brutal, Ruleset.gomoku, BoardData(board), .x), (7, 6));
  });

  test('brutal occupies tempo-fork square (loss 2)', () async {
    final board = emptyBoard(19, 13);
    place(board, .x, [(8, 6), (9, 6), (8, 7), (9, 8), (10, 7), (10, 6)]);
    place(board, .o, [(4, 7), (7, 6), (10, 5), (8, 8), (9, 7)]);
    expect(await aiMove(.brutal, Ruleset.gomoku, BoardData(board), .o), (11, 6));
  });

  test('brutal blocks open three before own attack (loss 3)', () async {
    final board = emptyBoard(19, 13);
    place(board, .x, [
      (9, 6),
      (9, 5),
      (8, 6),
      (11, 5),
      (6, 10),
      (10, 4),
      (9, 4),
      (11, 4),
      (11, 6),
      (10, 3),
      (8, 5),
    ]);
    place(board, .o, [
      (10, 6),
      (9, 7),
      (8, 8),
      (7, 9),
      (10, 5),
      (7, 7),
      (9, 3),
      (8, 4),
      (11, 3),
      (12, 4),
    ]);
    // Open three ends on the eventual winning diagonal.
    final move = await aiMove(.brutal, Ruleset.gomoku, BoardData(board), .o);
    expect([(7, 6), (11, 2)], contains(move));
  });
}
