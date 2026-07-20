/// @docImport './board.dart';
/// @docImport './rules/connect6.dart';
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/player_mark.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

/// Chooses a cell for [toMove] under [ruleset] / [difficulty].
///
/// [toMove] must be the side about to place (e.g. [Board.turn]); do not infer it
/// from stone counts — that is wrong mid-turn under connect6 (two stones per turn).
Future<(int row, int col)> aiMove(
  Difficulty difficulty,
  Ruleset ruleset,
  BoardData data,
  PlayerMark toMove,
) {
  final winLength = ruleset.winLengthForSize(data.rows, data.cols);
  final board = data.copyMutable();
  final input = (board: board, winLength: winLength, ruleset: ruleset, toMove: toMove);

  // Easy AI does a good move a third of the time.
  if (difficulty == .easy && rng.nextDouble() < 1 / 3) difficulty = .hard;

  return switch (difficulty) {
    .easy => SynchronousFuture(_aiEasy(input)),
    .hard => compute(_aiHard, input),
    .brutal => compute(_aiBrutal, input),
  };
}

final twoPlayer = Stored('two player', false);

enum Difficulty {
  easy,
  hard,
  brutal;

  static final current = Get.compute((ref) => ref.watch(twoPlayer) ? null : ref.watch(selected));

  static final selected = Stored.enumValue(values, easy);

  @override
  String toString() => name[0].toUpperCase() + name.substring(1);
}

typedef _AiInput = ({
  List<List<PlayerMark?>> board,
  int winLength,
  Ruleset ruleset,
  PlayerMark toMove,
});
typedef _Cell = (int row, int col);
typedef _OpenThreats = ({int openFours, int openThrees});

extension<T> on List<T> {
  T get random {
    assert(isNotEmpty);
    return this[rng.nextInt(length)];
  }
}

/// Side to move after a stone was just placed, for multi-ply search.
///
/// Connect6: black places 1, then OO / XX / OO / … (matches [Connect6.recomputeTurnFromBoard]).
PlayerMark _sideToMoveAfter(List<List<PlayerMark?>> board, Ruleset ruleset, PlayerMark justMoved) {
  if (ruleset != .connect6) return justMoved.opponent;

  final n = board.stoneCount;
  if (n == 0) return .x;
  // First stone is black's opening; then pairs alternate O, X, O, …
  final pairIndex = (n - 1) ~/ 2;
  return pairIndex.isEven ? .o : .x;
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
      final cell = (r, c);
      if (!cell.inBounds(board) || board[r][c] != null) continue;
      if (!includeCenter && r == row && c == col) continue;
      cells.add(cell);
    }
  }
  return cells;
}

/// Nearby empties; center only on an empty board.
List<_Cell> _candidateMoves(List<List<PlayerMark?>> board, int winLength) {
  final occupied = board.occupiedCells;
  if (occupied.isEmpty) return [board.centerCell];

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
  return candidates.isEmpty ? board.emptyCells : candidates;
}

List<_Cell> _legalPool(
  List<List<PlayerMark?>> board,
  int winLength,
  Ruleset ruleset,
  PlayerMark mark,
) {
  return [
    for (final cell in _movePool(board, winLength))
      if (cell.isLegalOn(board, mark, ruleset)) cell,
  ];
}

bool _isWinningPlacement(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  PlayerMark mark,
  int winLength,
  Ruleset ruleset,
) {
  final cell = (row, col);
  if (!cell.isLegalOn(board, mark, ruleset)) return false;
  return cell.withMark(board, mark, () => cell.formsWin(board, mark, winLength, ruleset: ruleset));
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
        if ((row - dRow, col - dCol).markOn(board) == mark) continue;

        final endRow = row + (runLength - 1) * dRow;
        final endCol = col + (runLength - 1) * dCol;
        if (!(endRow, endCol).inBounds(board)) continue;

        var isRun = true;
        for (var i = 1; i < runLength; i++) {
          if (board[row + i * dRow][col + i * dCol] != mark) {
            isRun = false;
            break;
          }
        }
        if (!isRun) continue;

        // Exact length: must not extend further.
        if ((row + runLength * dRow, col + runLength * dCol).markOn(board) == mark) continue;

        final before = (row - dRow, col - dCol);
        final after = (row + runLength * dRow, col + runLength * dCol);
        if (!before.inBounds(board) || !after.inBounds(board)) continue;
        if (before.markOn(board) != null || after.markOn(board) != null) continue;

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
    for (final cell in pool)
      if (cell.markOn(board) == null)
        if (cell.withMark(board, player, () => _hasDoubleThreat(board, winLength, player, ruleset)))
          cell,
  ];
}

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
      if (!(startRow, startCol).inBounds(board) || !(endRow, endCol).inBounds(board)) continue;

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
      if ((r, c).markOn(board) == null) continue;
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

  final cell = (row, col);
  final attackBonus = cell.withMark(board, toMove, () {
    final threats = _countOpenThreats(board, winLength, toMove);
    final immediate = _immediateWinCountNear(board, row, col, toMove, winLength, ruleset);
    return _threatBonus(threats, openFour: 500, openThree: 50) + immediate * 300;
  });

  final denyBonus = cell.withMark(board, toMove.opponent, () {
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
  PlayerMark toMove,
) {
  if (candidates.isEmpty) return const [];
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
  PlayerMark toMove,
) {
  final filtered = [
    for (final move in pool)
      if (preferred.contains(move)) move,
  ];
  if (filtered.isEmpty) return null;
  return _highestRankedMoves(board, filtered, winLength, ruleset, toMove);
}

List<_Cell> _hardMoveOptions(
  List<List<PlayerMark?>> board,
  int winLength,
  Ruleset ruleset,
  PlayerMark ai,
) {
  // Empty board → center via [_candidateMoves] / [_legalPool].
  final pool = _legalPool(board, winLength, ruleset, ai);
  if (pool.isEmpty) {
    // No legal moves (extreme renju edge case) — fall back to any empty.
    return board.emptyCells;
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
        if (m.isLegalOn(board, ai, ruleset)) m,
    ];
    return legalBlocks.isNotEmpty ? legalBlocks : blocks;
  }

  // Defend before inventing attacks: an ignored open three is usually a loss.
  if (board.countMark(opponent) >= 2) {
    final defending = _doubleThreatPoints(board, pool, winLength, opponent, ruleset);
    if (defending.isNotEmpty) {
      return _highestRankedMoves(board, defending, winLength, ruleset, ai);
    }

    final openThreeEnds = _openRunEnds(board, winLength - 2, onlyMark: opponent);
    final urgent = _rankedIfAny(board, pool, openThreeEnds, winLength, ruleset, ai);
    if (urgent != null) return urgent;
  }

  if (board.countMark(ai) >= 2) {
    final attacking = _doubleThreatPoints(board, pool, winLength, ai, ruleset);
    if (attacking.isNotEmpty) {
      return _highestRankedMoves(board, attacking, winLength, ruleset, ai);
    }
  }

  // Fall back: any open-three ends, else full candidate ranking.
  final anyOpenEnds = _openRunEnds(board, winLength - 2);
  final narrowed = _rankedIfAny(board, pool, anyOpenEnds, winLength, ruleset, ai);
  return narrowed ?? _highestRankedMoves(board, pool, winLength, ruleset, ai);
}

_Cell _aiEasy(_AiInput input) {
  final (:board, :winLength, :ruleset, :toMove) = input;
  // Empty board → center via [_legalPool] / [_candidateMoves].
  final pool = _legalPool(board, winLength, ruleset, toMove);
  assert(pool.isNotEmpty, 'AI called on a full board');

  final wins = _winningPlacements(board, pool, toMove, winLength, ruleset);
  if (wins.isNotEmpty) return wins.random;

  final blocks = _winningPlacements(
    board,
    _movePool(board, winLength),
    toMove.opponent,
    winLength,
    ruleset,
  );
  final legalBlocks = [
    for (final m in blocks)
      if (m.isLegalOn(board, toMove, ruleset)) m,
  ];
  if (legalBlocks.isNotEmpty) return legalBlocks.random;
  if (blocks.isNotEmpty) return blocks.random;

  return pool.random;
}

_Cell _aiHard(_AiInput input) {
  final (:board, :winLength, :ruleset, :toMove) = input;
  final options = _hardMoveOptions(board, winLength, ruleset, toMove);
  assert(options.isNotEmpty, 'AI called on a full board');
  return options.random;
}

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
  PlayerMark toMove,
) {
  if (winnerOn(board, ruleset, winLength) case final winner?) {
    return winner == rootAi ? 1000 : -1000;
  }
  if (board.isBoardFull) return 0;
  if (depthRemaining <= 0) return _brutalHeuristic(board, winLength, rootAi);

  final options = _hardMoveOptions(board, winLength, ruleset, toMove);
  if (options.isEmpty) return 0;

  final maximizing = toMove == rootAi;
  var best = maximizing ? -0x3fffffff : 0x3fffffff;
  for (final cell in options) {
    final score = cell.withMark(board, toMove, () {
      final next = _sideToMoveAfter(board, ruleset, toMove);
      return _brutalEvaluate(board, winLength, rootAi, depthRemaining - 1, ruleset, next);
    });
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
  final (:board, :winLength, :ruleset, :toMove) = input;
  final options = _hardMoveOptions(board, winLength, ruleset, toMove);
  assert(options.isNotEmpty, 'AI called on a full board');
  // Empty board / sole option / symmetry: no multi-ply search needed.
  if (options.length == 1 || _movesAreSymmetricallyEquivalent(board, options)) {
    return options.random;
  }

  final depth = _brutalSearchDepth(board, options.length);
  var bestScore = -0x3fffffff;
  final bestMoves = <_Cell>[];
  for (final cell in options) {
    final score = cell.withMark(board, toMove, () {
      final next = _sideToMoveAfter(board, ruleset, toMove);
      return _brutalEvaluate(board, winLength, toMove, depth, ruleset, next);
    });
    if (score > bestScore) {
      bestScore = score;
      bestMoves
        ..clear()
        ..add(cell);
    } else if (score == bestScore) {
      bestMoves.add(cell);
    }
  }
  return bestMoves.random;
}
