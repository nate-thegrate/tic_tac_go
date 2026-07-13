import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/rules/renju.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

final twoPlayer = Get.it(false);

Future<(int row, int col)> aiMove(Difficulty difficulty, Ruleset ruleset, BoardData data) async {
  final winLength = ruleset.winLength(data);
  final board = [for (final row in data) List<PlayerMark?>.of(row)];
  final input = (board: board, winLength: winLength, ruleset: ruleset);

  return switch (difficulty) {
    // Win → block → random. SynchronousFuture (no isolate).
    .easy => SynchronousFuture(_aiEasy(input)),
    // Win → block → defend threats → attack → rank open-segment ends.
    .hard => compute(_aiHard, input),
    // Hard's option set, then symmetry / multi-ply search on ties.
    .brutal => compute(_aiBrutal, input),
  };
}

enum Difficulty {
  easy,
  hard,
  brutal;

  /// The user's chosen difficulty.
  static final current = Get.compute((ref) => ref.watch(twoPlayer) ? null : ref.watch(selected));

  static final selected = Get.it(easy);

  @override
  String toString() => name[0].toUpperCase() + name.substring(1);
}

typedef _AiInput = ({List<List<PlayerMark?>> board, int winLength, Ruleset ruleset});
typedef _Cell = (int row, int col);
typedef _OpenThreats = ({int openFours, int openThrees});

extension<T> on List<T> {
  T get random {
    assert(isNotEmpty);
    return this[math.Random().nextInt(length)];
  }
}

// --- Board helpers -----------------------------------------------------------

bool _inBounds(List<List<PlayerMark?>> board, int row, int col) {
  return row >= 0 && row < board.length && col >= 0 && col < board.first.length;
}

PlayerMark? _at(List<List<PlayerMark?>> board, int row, int col) {
  return _inBounds(board, row, col) ? board[row][col] : null;
}

/// X always moves first, so the side to move is X when both have the same count.
PlayerMark _sideToMove(List<List<PlayerMark?>> board) {
  var xCount = 0;
  var oCount = 0;
  for (final row in board) {
    for (final cell in row) {
      switch (cell) {
        case .x:
          xCount++;
        case .o:
          oCount++;
        case null:
          break;
      }
    }
  }
  return xCount == oCount ? .x : .o;
}

bool _boardIsEmpty(List<List<PlayerMark?>> board) {
  for (final row in board) {
    for (final cell in row) {
      if (cell != null) return false;
    }
  }
  return true;
}

bool _boardIsFull(List<List<PlayerMark?>> board) {
  for (final row in board) {
    for (final cell in row) {
      if (cell == null) return false;
    }
  }
  return true;
}

_Cell _centerMove(List<List<PlayerMark?>> board) => (board.length ~/ 2, board.first.length ~/ 2);

int _markCount(List<List<PlayerMark?>> board, PlayerMark mark) {
  var count = 0;
  for (final row in board) {
    for (final cell in row) {
      if (cell == mark) count++;
    }
  }
  return count;
}

List<_Cell> _allEmpty(List<List<PlayerMark?>> board) {
  return [
    for (var row = 0; row < board.length; row++)
      for (var col = 0; col < board[row].length; col++)
        if (board[row][col] == null) (row, col),
  ];
}

/// Empty cells within Chebyshev [radius] of (row, col), optionally including the center if empty.
List<_Cell> _emptiesNear(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  int radius, {
  bool includeCenter = false,
}) {
  final cells = <_Cell>[];
  for (var r = row - radius; r <= row + radius; r++) {
    for (var c = col - radius; c <= col + radius; c++) {
      if (!_inBounds(board, r, c) || board[r][c] != null) continue;
      if (!includeCenter && r == row && c == col) continue;
      cells.add((r, c));
    }
  }
  return cells;
}

/// Temporarily place [mark], run [body], always restore.
T _withMark<T>(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  PlayerMark mark,
  T Function() body,
) {
  board[row][col] = mark;
  try {
    return body();
  } finally {
    board[row][col] = null;
  }
}

// --- Candidates --------------------------------------------------------------

/// Nearby empties; center only on an empty board.
List<_Cell> _candidateMoves(List<List<PlayerMark?>> board, int winLength) {
  final rows = board.length;
  final cols = board.first.length;
  final occupied = <_Cell>[
    for (var row = 0; row < rows; row++)
      for (var col = 0; col < cols; col++)
        if (board[row][col] != null) (row, col),
  ];
  if (occupied.isEmpty) return [_centerMove(board)];

  // Early game: stay tight; full winLength radius dilutes ranking.
  final maxDist = occupied.length <= 4 ? 2 : winLength - 1;
  final candidates = <_Cell>{};
  for (final (occupiedRow, occupiedCol) in occupied) {
    for (final cell in _emptiesNear(board, occupiedRow, occupiedCol, maxDist)) {
      final (row, col) = cell;
      final distance = math.max((row - occupiedRow).abs(), (col - occupiedCol).abs());
      if (distance <= maxDist) candidates.add(cell);
    }
  }
  return candidates.toList();
}

List<_Cell> _movePool(List<List<PlayerMark?>> board, int winLength) {
  final candidates = _candidateMoves(board, winLength);
  return candidates.isEmpty ? _allEmpty(board) : candidates;
}

bool _isLegalAiMove(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  PlayerMark mark,
  Ruleset ruleset,
) {
  if (board[row][col] != null) return false;
  if (ruleset != .renju || mark != .x) return true;
  return Renju.isLegalFor(.x, board, row, col);
}

List<_Cell> _legalPool(
  List<List<PlayerMark?>> board,
  int winLength,
  Ruleset ruleset,
  PlayerMark mark,
) {
  return [
    for (final (row, col) in _movePool(board, winLength))
      if (_isLegalAiMove(board, row, col, mark, ruleset)) (row, col),
  ];
}

// --- Wins --------------------------------------------------------------------

bool _formsWin(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  PlayerMark mark,
  int winLength, {
  required Ruleset ruleset,
}) {
  for (final (dRow, dCol) in BoardData.directions) {
    var count = 1;
    for (final sign in const [1, -1]) {
      for (var step = 1; step < winLength + 2; step++) {
        final r = row + sign * step * dRow;
        final c = col + sign * step * dCol;
        if (_at(board, r, c) != mark) break;
        count++;
      }
    }
    if (ruleset == .renju && mark == .x) {
      // Black: exact five only (overline does not win).
      if (count == 5) return true;
    } else if (count >= winLength) {
      return true;
    }
  }
  return false;
}

bool _isWinningPlacement(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  PlayerMark mark,
  int winLength,
  Ruleset ruleset,
) {
  if (!_isLegalAiMove(board, row, col, mark, ruleset)) return false;
  return _withMark(
    board,
    row,
    col,
    mark,
    () => _formsWin(board, row, col, mark, winLength, ruleset: ruleset),
  );
}

List<_Cell> _winningPlacements(
  List<List<PlayerMark?>> board,
  List<_Cell> candidates,
  PlayerMark mark,
  int winLength,
  Ruleset ruleset,
) {
  return [
    for (final (row, col) in candidates)
      if (_isWinningPlacement(board, row, col, mark, winLength, ruleset)) (row, col),
  ];
}

/// Immediate wins available to [player] near a focus cell (avoids full-board scans).
int _immediateWinCountNear(
  List<List<PlayerMark?>> board,
  int focusRow,
  int focusCol,
  PlayerMark player,
  int winLength,
  Ruleset ruleset,
) {
  final nearby = _emptiesNear(board, focusRow, focusCol, winLength, includeCenter: true);
  return _winningPlacements(board, nearby, player, winLength, ruleset).length;
}

// --- Open runs / threats -----------------------------------------------------

/// Open both-ends runs of exactly [runLength] for optional [onlyMark].
List<({PlayerMark mark, _Cell a, _Cell b})> _openRuns(
  List<List<PlayerMark?>> board,
  int runLength, {
  PlayerMark? onlyMark,
}) {
  if (runLength < 1) return const [];

  final runs = <({PlayerMark mark, _Cell a, _Cell b})>[];

  for (final (dRow, dCol) in BoardData.directions) {
    for (var row = 0; row < board.length; row++) {
      for (var col = 0; col < board[row].length; col++) {
        final mark = board[row][col];
        if (mark == null || (onlyMark != null && mark != onlyMark)) continue;

        // Count each run once: skip if previous cell continues the same mark.
        if (_at(board, row - dRow, col - dCol) == mark) continue;

        final endRow = row + (runLength - 1) * dRow;
        final endCol = col + (runLength - 1) * dCol;
        if (!_inBounds(board, endRow, endCol)) continue;

        var isRun = true;
        for (var i = 1; i < runLength; i++) {
          if (board[row + i * dRow][col + i * dCol] != mark) {
            isRun = false;
            break;
          }
        }
        if (!isRun) continue;

        // Exact length: must not extend further.
        if (_at(board, row + runLength * dRow, col + runLength * dCol) == mark) continue;

        final before = (row - dRow, col - dCol);
        final after = (row + runLength * dRow, col + runLength * dCol);
        if (!_inBounds(board, before.$1, before.$2) || !_inBounds(board, after.$1, after.$2)) {
          continue;
        }
        if (board[before.$1][before.$2] != null || board[after.$1][after.$2] != null) continue;

        runs.add((mark: mark, a: before, b: after));
      }
    }
  }
  return runs;
}

Set<_Cell> _openRunEnds(List<List<PlayerMark?>> board, int runLength, {PlayerMark? onlyMark}) {
  final runs = _openRuns(board, runLength, onlyMark: onlyMark);
  return {for (final run in runs) run.a, for (final run in runs) run.b};
}

/// Open fours (winLength−1) and open threes (winLength−2) for [player].
_OpenThreats _countOpenThreats(List<List<PlayerMark?>> board, int winLength, PlayerMark player) {
  return (
    openFours: _openRuns(board, winLength - 1, onlyMark: player).length,
    openThrees: _openRuns(board, winLength - 2, onlyMark: player).length,
  );
}

/// Open four, dual open threes, dual immediate wins, or must-block + leftover open three.
bool _hasDoubleThreat(
  List<List<PlayerMark?>> board,
  int winLength,
  PlayerMark player,
  Ruleset ruleset,
) {
  final threats = _countOpenThreats(board, winLength, player);
  if (threats.openFours >= 1 || threats.openThrees >= 2) return true;

  final pool = _legalPool(board, winLength, ruleset, player);
  final immediate = _winningPlacements(board, pool, player, winLength, ruleset);
  return immediate.length >= 2 || (immediate.isNotEmpty && threats.openThrees >= 1);
}

/// Empty cells where placing for [player] creates a double threat.
List<_Cell> _doubleThreatPoints(
  List<List<PlayerMark?>> board,
  List<_Cell> pool,
  int winLength,
  PlayerMark player,
  Ruleset ruleset,
) {
  return [
    for (final (row, col) in pool)
      if (board[row][col] == null)
        if (_withMark(
          board,
          row,
          col,
          player,
          () => _hasDoubleThreat(board, winLength, player, ruleset),
        ))
          (row, col),
  ];
}

// --- Ranking -----------------------------------------------------------------

int _segmentCountForPlayer(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  int winLength,
  PlayerMark player,
) {
  var count = 0;

  for (final (dRow, dCol) in BoardData.directions) {
    for (var offset = 0; offset < winLength; offset++) {
      final startRow = row - offset * dRow;
      final startCol = col - offset * dCol;
      final endRow = startRow + (winLength - 1) * dRow;
      final endCol = startCol + (winLength - 1) * dCol;
      if (!_inBounds(board, startRow, startCol) || !_inBounds(board, endRow, endCol)) continue;

      var valid = true;
      for (var i = 0; i < winLength; i++) {
        final cell = board[startRow + i * dRow][startCol + i * dCol];
        if (cell != null && cell != player) {
          valid = false;
          break;
        }
      }
      if (valid) count++;
    }
  }
  return count;
}

int _proximityScore(List<List<PlayerMark?>> board, int row, int col) {
  var score = 0;
  // Only stones within distance 3 contribute.
  for (var r = row - 3; r <= row + 3; r++) {
    for (var c = col - 3; c <= col + 3; c++) {
      if (_at(board, r, c) == null) continue;
      final distance = math.max((r - row).abs(), (c - col).abs());
      score += switch (distance) {
        1 => 14,
        2 => 6,
        3 => 2,
        _ => 0,
      };
    }
  }
  return score;
}

int _threatBonus(_OpenThreats threats, {required int openFour, required int openThree}) {
  return threats.openFours * openFour + threats.openThrees * openThree;
}

int _moveRank(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  int winLength,
  PlayerMark toMove,
  Ruleset ruleset,
) {
  final base =
      _segmentCountForPlayer(board, row, col, winLength, .x) +
      _segmentCountForPlayer(board, row, col, winLength, .o);

  final attackBonus = _withMark(board, row, col, toMove, () {
    final threats = _countOpenThreats(board, winLength, toMove);
    final immediate = _immediateWinCountNear(board, row, col, toMove, winLength, ruleset);
    return _threatBonus(threats, openFour: 500, openThree: 50) + immediate * 300;
  });

  final denyBonus = _withMark(board, row, col, toMove.opponent, () {
    final threats = _countOpenThreats(board, winLength, toMove.opponent);
    final immediate = _immediateWinCountNear(board, row, col, toMove.opponent, winLength, ruleset);
    return _threatBonus(threats, openFour: 400, openThree: 40) + immediate * 250;
  });

  return base + attackBonus + denyBonus + _proximityScore(board, row, col);
}

List<_Cell> _highestRankedMoves(
  List<List<PlayerMark?>> board,
  List<_Cell> candidates,
  int winLength,
  Ruleset ruleset,
) {
  if (candidates.isEmpty) return const [];
  final toMove = _sideToMove(board);
  var bestRank = -1;
  final best = <_Cell>[];
  for (final (row, col) in candidates) {
    final rank = _moveRank(board, row, col, winLength, toMove, ruleset);
    if (rank > bestRank) {
      bestRank = rank;
      best
        ..clear()
        ..add((row, col));
    } else if (rank == bestRank) {
      best.add((row, col));
    }
  }
  return best;
}

/// Prefer non-empty [preferred] filtered to [pool]; otherwise null.
List<_Cell>? _rankedIfAny(
  List<List<PlayerMark?>> board,
  List<_Cell> pool,
  Iterable<_Cell> preferred,
  int winLength,
  Ruleset ruleset,
) {
  final filtered = [
    for (final move in pool)
      if (preferred.contains(move)) move,
  ];
  if (filtered.isEmpty) return null;
  return _highestRankedMoves(board, filtered, winLength, ruleset);
}

// --- Hard policy -------------------------------------------------------------

List<_Cell> _hardMoveOptions(List<List<PlayerMark?>> board, int winLength, Ruleset ruleset) {
  if (_boardIsEmpty(board)) return [_centerMove(board)];

  final ai = _sideToMove(board);
  final pool = _legalPool(board, winLength, ruleset, ai);
  if (pool.isEmpty) {
    // No legal moves (extreme renju edge case) — fall back to any empty.
    return _allEmpty(board);
  }

  final opponent = ai.opponent;

  final wins = _winningPlacements(board, pool, ai, winLength, ruleset);
  if (wins.isNotEmpty) return wins;

  // Opponent blocks ignore our fouls; they may play any empty cell that wins for them.
  final blockPool = _movePool(board, winLength);
  final blocks = _winningPlacements(board, blockPool, opponent, winLength, ruleset);
  if (blocks.isNotEmpty) {
    // Prefer legal blocks for us; any block cell is fine if we are white.
    final legalBlocks = [
      for (final m in blocks)
        if (_isLegalAiMove(board, m.$1, m.$2, ai, ruleset)) m,
    ];
    return legalBlocks.isNotEmpty ? legalBlocks : blocks;
  }

  // Defend before inventing attacks: an ignored open three is usually a loss.
  if (_markCount(board, opponent) >= 2) {
    final defending = _doubleThreatPoints(board, pool, winLength, opponent, ruleset);
    if (defending.isNotEmpty) return _highestRankedMoves(board, defending, winLength, ruleset);

    final openThreeEnds = _openRunEnds(board, winLength - 2, onlyMark: opponent);
    final urgent = _rankedIfAny(board, pool, openThreeEnds, winLength, ruleset);
    if (urgent != null) return urgent;
  }

  if (_markCount(board, ai) >= 2) {
    final attacking = _doubleThreatPoints(board, pool, winLength, ai, ruleset);
    if (attacking.isNotEmpty) return _highestRankedMoves(board, attacking, winLength, ruleset);
  }

  // Fall back: any open-three ends, else full candidate ranking.
  final anyOpenEnds = _openRunEnds(board, winLength - 2);
  final narrowed = _rankedIfAny(board, pool, anyOpenEnds, winLength, ruleset);
  return narrowed ?? _highestRankedMoves(board, pool, winLength, ruleset);
}

// --- Difficulty entry points -------------------------------------------------

_Cell _aiEasy(_AiInput input) {
  final (:board, :winLength, :ruleset) = input;
  if (_boardIsEmpty(board)) return _centerMove(board);

  final ai = _sideToMove(board);
  final pool = _legalPool(board, winLength, ruleset, ai);
  assert(pool.isNotEmpty, 'AI called on a full board');

  final wins = _winningPlacements(board, pool, ai, winLength, ruleset);
  if (wins.isNotEmpty) return wins.random;

  final blocks = _winningPlacements(
    board,
    _movePool(board, winLength),
    ai.opponent,
    winLength,
    ruleset,
  );
  final legalBlocks = [
    for (final m in blocks)
      if (_isLegalAiMove(board, m.$1, m.$2, ai, ruleset)) m,
  ];
  if (legalBlocks.isNotEmpty) return legalBlocks.random;
  if (blocks.isNotEmpty) return blocks.random;

  return pool.random;
}

_Cell _aiHard(_AiInput input) {
  final (:board, :winLength, :ruleset) = input;
  if (_boardIsEmpty(board)) return _centerMove(board);
  final options = _hardMoveOptions(board, winLength, ruleset);
  assert(options.isNotEmpty, 'AI called on a full board');
  return options.random;
}

// --- Brutal search -----------------------------------------------------------

List<_Cell Function(_Cell)> _boardSymmetries(List<List<PlayerMark?>> board) {
  final rows = board.length;
  final cols = board.first.length;

  final transforms = <_Cell Function(_Cell)>[
    (cell) => cell,
    if (rows == cols) ...[
      (cell) => (cell.$2, rows - 1 - cell.$1), // 90° CW
      (cell) => (rows - 1 - cell.$1, cols - 1 - cell.$2), // 180°
      (cell) => (cols - 1 - cell.$2, cell.$1), // 270° CW
      (cell) => (cell.$1, cols - 1 - cell.$2),
      (cell) => (rows - 1 - cell.$1, cell.$2),
      (cell) => (cell.$2, cell.$1),
      (cell) => (cols - 1 - cell.$2, rows - 1 - cell.$1),
    ] else ...[
      (cell) => (cell.$1, cols - 1 - cell.$2),
      (cell) => (rows - 1 - cell.$1, cell.$2),
      (cell) => (rows - 1 - cell.$1, cols - 1 - cell.$2),
    ],
  ];

  bool preserves(_Cell Function(_Cell) transform) {
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final (tr, tc) = transform((row, col));
        if (board[row][col] != board[tr][tc]) return false;
      }
    }
    return true;
  }

  return [
    for (final transform in transforms)
      if (preserves(transform)) transform,
  ];
}

bool _movesAreSymmetricallyEquivalent(List<List<PlayerMark?>> board, List<_Cell> moves) {
  if (moves.length <= 1) return true;
  final symmetries = _boardSymmetries(board);
  if (symmetries.length <= 1) return false;

  final moveSet = moves.toSet();
  final orbit = <_Cell>{moves.first};
  final queue = [moves.first];
  while (queue.isNotEmpty) {
    final cell = queue.removeLast();
    for (final transform in symmetries) {
      final image = transform(cell);
      if (moveSet.contains(image) && orbit.add(image)) queue.add(image);
    }
  }
  return orbit.length == moveSet.length;
}

PlayerMark? _findWinner(List<List<PlayerMark?>> board, int winLength, Ruleset ruleset) {
  for (var row = 0; row < board.length; row++) {
    for (var col = 0; col < board[row].length; col++) {
      final mark = board[row][col];
      if (mark == null) continue;
      if (_formsWin(board, row, col, mark, winLength, ruleset: ruleset)) return mark;
    }
  }
  return null;
}

int _brutalSearchDepth(List<List<PlayerMark?>> board, int optionCount) {
  final cells = board.length * board.first.length;
  if (optionCount <= 4) {
    if (cells <= 9) return 10;
    if (cells <= 25) return 8;
    if (cells <= 81) return 6;
    return 5;
  }
  if (cells <= 9) return 8;
  if (cells <= 25) return 5;
  return 3;
}

int _brutalHeuristic(List<List<PlayerMark?>> board, int winLength, PlayerMark rootAi) {
  final us = _countOpenThreats(board, winLength, rootAi);
  final them = _countOpenThreats(board, winLength, rootAi.opponent);
  return _threatBonus(us, openFour: 50, openThree: 5) -
      _threatBonus(them, openFour: 50, openThree: 5);
}

int _brutalEvaluate(
  List<List<PlayerMark?>> board,
  int winLength,
  PlayerMark rootAi,
  int depthRemaining,
  Ruleset ruleset,
) {
  if (_findWinner(board, winLength, ruleset) case final winner?) {
    return winner == rootAi ? 1000 : -1000;
  }
  if (_boardIsFull(board)) return 0;
  if (depthRemaining <= 0) return _brutalHeuristic(board, winLength, rootAi);

  final toMove = _sideToMove(board);
  final options = _hardMoveOptions(board, winLength, ruleset);
  if (options.isEmpty) return 0;

  final maximizing = toMove == rootAi;
  var best = maximizing ? -0x3fffffff : 0x3fffffff;
  for (final (row, col) in options) {
    final score = _withMark(
      board,
      row,
      col,
      toMove,
      () => _brutalEvaluate(board, winLength, rootAi, depthRemaining - 1, ruleset),
    );
    if (maximizing) {
      if (score > best) best = score;
      if (best >= 1000) break;
    } else {
      if (score < best) best = score;
      if (best <= -1000) break;
    }
  }
  return best;
}

_Cell _aiBrutal(_AiInput input) {
  final (:board, :winLength, :ruleset) = input;
  if (_boardIsEmpty(board)) return _centerMove(board);

  final options = _hardMoveOptions(board, winLength, ruleset);
  assert(options.isNotEmpty, 'AI called on a full board');
  if (options.length == 1 || _movesAreSymmetricallyEquivalent(board, options)) {
    return options.random;
  }

  final ai = _sideToMove(board);
  final depth = _brutalSearchDepth(board, options.length);
  var bestScore = -0x3fffffff;
  final bestMoves = <_Cell>[];
  for (final (row, col) in options) {
    final score = _withMark(
      board,
      row,
      col,
      ai,
      () => _brutalEvaluate(board, winLength, ai, depth, ruleset),
    );
    if (score > bestScore) {
      bestScore = score;
      bestMoves
        ..clear()
        ..add((row, col));
    } else if (score == bestScore) {
      bestMoves.add((row, col));
    }
  }
  return bestMoves.random;
}
