import 'package:tic_tac_go/src/board.dart';

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
    board[row][col] = .x;
    try {
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
    } finally {
      board[row][col] = null;
    }
  }

  static bool isLegalFor(PlayerMark mark, List<List<PlayerMark?>> board, int row, int col) {
    if (mark != .x) return true;
    if (board[row][col] != null) return false;
    return foulIfBlackPlays(board, row, col) == null;
  }

  /// Contiguous run length of [mark] through (row,col), including that cell.
  static int lineLength(
    List<List<PlayerMark?>> board,
    int row,
    int col,
    int dRow,
    int dCol,
    PlayerMark mark,
  ) {
    return 1 +
        _countDir(board, row, col, dRow, dCol, mark) +
        _countDir(board, row, col, -dRow, -dCol, mark);
  }

  static bool _hasExactFiveThrough(
    List<List<PlayerMark?>> board,
    int row,
    int col,
    PlayerMark mark,
  ) {
    for (final (dRow, dCol) in BoardData.directions) {
      if (lineLength(board, row, col, dRow, dCol, mark) == 5) return true;
    }
    return false;
  }

  static int _countDir(
    List<List<PlayerMark?>> board,
    int row,
    int col,
    int dRow,
    int dCol,
    PlayerMark mark,
  ) {
    final rows = board.length;
    final cols = board.first.length;
    var count = 0;
    var r = row + dRow;
    var c = col + dCol;
    while (r >= 0 && r < rows && c >= 0 && c < cols && board[r][c] == mark) {
      count++;
      r += dRow;
      c += dCol;
    }
    return count;
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
    final rows = board.length;
    final cols = board.first.length;
    var r = row + dRow;
    var c = col + dCol;
    while (r >= 0 && r < rows && c >= 0 && c < cols && board[r][c] == mark) {
      r += dRow;
      c += dCol;
    }
    if (r < 0 || r >= rows || c < 0 || c >= cols) return null;
    if (board[r][c] != null) return null;
    return (r, c);
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
    if (lineLength(board, row, col, dRow, dCol, mark) != 3) return false;
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
    if (lineLength(board, row, col, dRow, dCol, mark) != 4) return false;
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
