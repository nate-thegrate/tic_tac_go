/// @docImport 'board.dart';
library;

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:meta/meta.dart';
import 'package:tic_tac_go/src/rules/renju.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

enum PlayerMark {
  x,
  o;

  /// The user's selection for turn order in 1-player games.
  ///
  /// - `x`: The user goes first, playing as "X" or black.
  /// - `o`: The AI goes first; the user plays as "O" or white.
  /// - `null`: Random player order.
  static final userSelection = Stored.enumValue<PlayerMark?>(values, null);

  PlayerMark get opponent => switch (this) {
    x => .o,
    o => .x,
  };

  Color get color => switch (this) {
    x => const Color(0xFFFF6010),
    o => const Color(0xFF0098A0),
  };

  Color get winnerGlow => switch (this) {
    x => const Color(0xFFFFF1D4),
    o => const Color(0xFFFFFFFF),
  };

  @override
  String toString({bool goMode = false}) => switch (this) {
    _ when !goMode => name.toUpperCase(),
    x => 'Black',
    o => 'White',
  };
}

/// Whether [length] counts as a win for [mark] under [ruleset] / [winLength].
///
/// Renju black wins only with an exact five (overline does not count).
bool isWinningRunLength(int length, PlayerMark mark, int winLength, Ruleset ruleset) {
  if (ruleset == .renju && mark == .x) return length == 5;
  return length >= winLength;
}

/// Grid cell helpers shared by UI placement, AI search, and rules (renju).
extension BoardCell on (int row, int col) {
  bool inBounds(List<List<PlayerMark?>> board) {
    final (row, col) = this;
    return row >= 0 && row < board.length && col >= 0 && col < board.first.length;
  }

  bool inBoardSize(int rows, int cols) {
    final (row, col) = this;
    return row >= 0 && row < rows && col >= 0 && col < cols;
  }

  /// Mark at this cell, or `null` if out of bounds or empty.
  PlayerMark? markOn(List<List<PlayerMark?>> board) {
    final (row, col) = this;
    return inBounds(board) ? board[row][col] : null;
  }

  /// Temporarily place [mark], run [body], always clear the cell afterward.
  T withMark<T>(List<List<PlayerMark?>> board, PlayerMark mark, T Function() body) {
    final (row, col) = this;
    board[row][col] = mark;
    try {
      return body();
    } finally {
      board[row][col] = null;
    }
  }

  /// Whether [mark] may be placed here under [ruleset] (occupancy + renju fouls).
  ///
  /// [board] must be mutable when checking renju (trial-place + restore).
  bool isLegalOn(List<List<PlayerMark?>> board, PlayerMark mark, Ruleset ruleset) {
    final (row, col) = this;
    if (!inBounds(board) || board[row][col] != null) return false;
    if (ruleset == .renju && mark == .x) {
      return !Renju.foulIfBlackPlays(board, row, col);
    }
    return true;
  }

  /// Contiguous [mark] count through this cell along [dRow],[dCol] (both ways).
  ///
  /// This cell is assumed to hold [mark] (not re-checked).
  int runLengthThrough(List<List<PlayerMark?>> board, PlayerMark mark, int dRow, int dCol) {
    final (row, col) = this;
    var count = 1;
    for (final sign in const [1, -1]) {
      for (var step = 1; ; step++) {
        final r = row + sign * step * dRow;
        final c = col + sign * step * dCol;
        if ((r, c).markOn(board) != mark) break;
        count++;
      }
    }
    return count;
  }

  /// Whether this cell (already holding [mark]) completes a win under [ruleset].
  bool formsWin(
    List<List<PlayerMark?>> board,
    PlayerMark mark,
    int winLength, {
    required Ruleset ruleset,
  }) {
    for (final (dRow, dCol) in BoardData.directions) {
      final length = runLengthThrough(board, mark, dRow, dCol);
      if (isWinningRunLength(length, mark, winLength, ruleset)) return true;
    }
    return false;
  }

  /// A display segment for a win through this cell, or `null` if none.
  ///
  /// Length is [winLength] (or exact five for renju black), from the start of the line.
  List<(int row, int col)>? winningRunThrough(
    List<List<PlayerMark?>> board,
    PlayerMark mark,
    int winLength, {
    required Ruleset ruleset,
  }) {
    final (row, col) = this;
    for (final (dRow, dCol) in BoardData.directions) {
      var startRow = row;
      var startCol = col;
      while ((startRow - dRow, startCol - dCol).markOn(board) == mark) {
        startRow -= dRow;
        startCol -= dCol;
      }

      var length = 0;
      var r = startRow;
      var c = startCol;
      while ((r, c).markOn(board) == mark) {
        length++;
        r += dRow;
        c += dCol;
      }
      if (!isWinningRunLength(length, mark, winLength, ruleset)) continue;

      final take = ruleset == .renju && mark == .x ? 5 : winLength;
      return [for (var i = 0; i < take; i++) (startRow + i * dRow, startCol + i * dCol)];
    }
    return null;
  }
}

/// First winning run on [board], or `null` if nobody has won yet.
///
/// Does not encode draws — callers that need a full-board draw check [BoardGrid.isBoardFull].
List<(int row, int col)>? winningRunOn(
  List<List<PlayerMark?>> board,
  Ruleset ruleset, [
  int? winLength,
]) {
  final needed = winLength ?? ruleset.winLengthForSize(board.length, board.first.length);
  for (var row = 0; row < board.length; row++) {
    for (var col = 0; col < board[row].length; col++) {
      final mark = board[row][col];
      if (mark == null) continue;
      final run = (row, col).winningRunThrough(board, mark, needed, ruleset: ruleset);
      if (run != null) return run;
    }
  }
  return null;
}

/// Winner on [board], or `null` if none (draws are not distinguished).
PlayerMark? winnerOn(List<List<PlayerMark?>> board, Ruleset ruleset, [int? winLength]) {
  final run = winningRunOn(board, ruleset, winLength);
  if (run == null) return null;
  final (row, col) = run.first;
  return board[row][col];
}

/// Board-wide scans shared by UI ([BoardData]), AI, Connect6, and Swap2.
extension BoardGrid on List<List<PlayerMark?>> {
  int countMark(PlayerMark mark) {
    var count = 0;
    for (final row in this) {
      for (final cell in row) {
        if (cell == mark) count++;
      }
    }
    return count;
  }

  /// Non-null cells (stones / marks placed).
  int get stoneCount {
    var count = 0;
    for (final row in this) {
      for (final cell in row) {
        if (cell != null) count++;
      }
    }
    return count;
  }

  bool get isBoardFull {
    for (final row in this) {
      for (final cell in row) {
        if (cell == null) return false;
      }
    }
    return true;
  }

  (int row, int col) get centerCell => (length ~/ 2, first.length ~/ 2);

  /// Deep copy of each row (mutable), for AI search / renju trial places.
  List<List<PlayerMark?>> copyMutable() => [for (final row in this) List<PlayerMark?>.of(row)];

  List<(int row, int col)> get emptyCells => [
    for (var row = 0; row < length; row++)
      for (var col = 0; col < this[row].length; col++)
        if (this[row][col] == null) (row, col),
  ];

  List<(int row, int col)> get occupiedCells => [
    for (var row = 0; row < length; row++)
      for (var col = 0; col < this[row].length; col++)
        if (this[row][col] != null) (row, col),
  ];
}

/// A read-only view of the data in [BoardState].
extension type BoardData._(List<List<PlayerMark?>> _list) implements List<List<PlayerMark?>> {
  BoardData(List<List<PlayerMark?>> list)
    : _list = UnmodifiableListView(list.map(UnmodifiableListView.new));

  int get cols => first.length;
  int get rows => _list.length;

  /// Unit steps for horizontal, vertical, and both diagonals.
  static const directions = [
    (0, 1), // horizontal →
    (1, 0), // vertical ↓
    (1, 1), // diagonal ↘
    (1, -1), // diagonal ↙
  ];

  /// Cached per board snapshot and [Ruleset] — win length and renju overline
  /// rules differ, so a result for one ruleset must not be reused for another.
  static final _winningRunCache = Expando<Map<Ruleset, List<(int row, int col)>>>();

  /// The first winning run found, if any.
  ///
  /// Returns `[(-1, -1)]` if the game is a draw.
  ///
  /// Under renju: black wins only with an exact five (not overline); white wins
  /// with five or more.
  List<(int row, int col)>? winningRun(Ruleset ruleset) {
    final byRuleset = _winningRunCache[this] ??= {};
    if (byRuleset[ruleset] case final cached?) {
      return cached.isEmpty ? null : cached;
    }

    final run = winningRunOn(_list, ruleset, ruleset.winLengthForSize(rows, cols));
    if (run != null) return byRuleset[ruleset] = run;
    if (isBoardFull) return byRuleset[ruleset] = [(-1, -1)];
    byRuleset[ruleset] = [];
    return null;
  }

  /// If one of the players has won (by having a number of items in a row, straight or diagonally,
  /// equal to [Ruleset.winLengthForSize]), this getter returns that player; returns `null` otherwise.
  PlayerMark? winner(Ruleset ruleset) => switch (winningRun(ruleset)?.firstOrNull) {
    (-1, -1) => null,
    (final row, final col) => _list[row][col],
    null => null,
  };

  /// Whether the game has a winner or the board is completely filled.
  bool isGameOver(Ruleset ruleset) => winner(ruleset) != null || isBoardFull;

  @protected
  @redeclare
  void get length => ();
}
