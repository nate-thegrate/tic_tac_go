import 'package:tic_tac_go/src/player_mark.dart';

/// Renju restrictions for black (X): double-three and double-four are fouls.
/// White (O) has no fouls. Black wins only with an exact five — an overline
/// (6+) is legal to play but does not count as a win for black.
///
/// A move that creates an exact five is always legal and wins, even if it also
/// forms a double-three or double-four (the classic 4×3 is allowed).
abstract final class Renju {
  /// Returns a foul if black placing at [row],[col] is illegal.
  ///
  /// [board] must be empty at [row],[col]; the stone is not yet placed.
  /// Overlines are not fouls — they simply do not win (see [BoardData.winningRun]).
  static RenjuFoul? foulIfBlackPlays(List<List<PlayerMark?>> board, int row, int col) {
    assert(board[row][col] == null);
    return (row, col).withMark(board, .x, () {
      // Exact five wins and is never a foul.
      if (_hasExactFiveThrough(board, row, col, .x)) return null;

      var openThrees = 0;
      var fours = 0;
      for (final (dRow, dCol) in BoardData.directions) {
        if (_isOpenThreeThrough(board, row, col, dRow, dCol, .x)) openThrees++;
        if (_isFourThrough(board, row, col, dRow, dCol, .x)) fours++;
      }
      if (fours >= 2) return .doubleFour;
      if (openThrees >= 2) return .doubleThree;
      return null;
    });
  }

  static bool _hasExactFiveThrough(
    List<List<PlayerMark?>> board,
    int row,
    int col,
    PlayerMark mark,
  ) {
    for (final (dRow, dCol) in BoardData.directions) {
      if ((row, col).runLengthThrough(board, mark, dRow, dCol) == 5) return true;
    }
    return false;
  }

  /// First empty cell beyond the contiguous [mark] run in [dRow],[dCol], or null.
  static (int, int)? _endBeyondRun(
    List<List<PlayerMark?>> board,
    int row,
    int col,
    int dRow,
    int dCol,
    PlayerMark mark,
  ) {
    var r = row + dRow;
    var c = col + dCol;
    while ((r, c).markOn(board) == mark) {
      r += dRow;
      c += dCol;
    }
    final end = (r, c);
    if (!end.inBounds(board) || board[r][c] != null) return null;
    return end;
  }

  /// Open three: contiguous length 3 through the stone, both ends empty.
  static bool _isOpenThreeThrough(
    List<List<PlayerMark?>> board,
    int row,
    int col,
    int dRow,
    int dCol,
    PlayerMark mark,
  ) {
    if ((row, col).runLengthThrough(board, mark, dRow, dCol) != 3) return false;
    final a = _endBeyondRun(board, row, col, dRow, dCol, mark);
    final b = _endBeyondRun(board, row, col, -dRow, -dCol, mark);
    return a != null && b != null;
  }

  /// Four: contiguous length 4 through the stone with at least one empty end
  /// (so one more stone can complete five).
  static bool _isFourThrough(
    List<List<PlayerMark?>> board,
    int row,
    int col,
    int dRow,
    int dCol,
    PlayerMark mark,
  ) {
    if ((row, col).runLengthThrough(board, mark, dRow, dCol) != 4) return false;
    final a = _endBeyondRun(board, row, col, dRow, dCol, mark);
    final b = _endBeyondRun(board, row, col, -dRow, -dCol, mark);
    return a != null || b != null;
  }
}

enum RenjuFoul {
  doubleThree,
  doubleFour;

  String get label => switch (this) {
    doubleThree => 'double-three',
    doubleFour => 'double-four',
  };
}
