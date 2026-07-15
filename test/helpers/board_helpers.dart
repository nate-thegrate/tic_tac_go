import 'package:tic_tac_go/src/player_mark.dart';

/// Empty [rows]×[cols] grid of nullable marks.
List<List<PlayerMark?>> emptyBoard(int rows, [int? cols]) {
  cols ??= rows;
  return List.generate(rows, (_) => List<PlayerMark?>.filled(cols!, null));
}

/// Place [mark] on each of [cells] (row, col).
void place(List<List<PlayerMark?>> board, PlayerMark mark, List<(int, int)> cells) {
  for (final (row, col) in cells) {
    board[row][col] = mark;
  }
}

/// Contiguous horizontal run of [mark] on [row] from [startCol] for [length] cells.
void placeHorizontal(
  List<List<PlayerMark?>> board,
  PlayerMark mark, {
  required int row,
  required int startCol,
  required int length,
}) {
  for (var i = 0; i < length; i++) {
    board[row][startCol + i] = mark;
  }
}

/// Contiguous vertical run of [mark] on [col] from [startRow] for [length] cells.
void placeVertical(
  List<List<PlayerMark?>> board,
  PlayerMark mark, {
  required int col,
  required int startRow,
  required int length,
}) {
  for (var i = 0; i < length; i++) {
    board[startRow + i][col] = mark;
  }
}
