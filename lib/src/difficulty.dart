import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';

final twoPlayer = Get.it(false);

typedef _AiInput = ({List<List<PlayerMark?>> board, int winLength});

enum Difficulty {
  easy,
  hard,
  brutal;

  /// The user's chosen difficulty.
  static final current = Get.compute((ref) => ref.watch(twoPlayer) ? null : ref.watch(selected));

  static final selected = Get.it(easy);

  Future<(int row, int col)> aiMove(Ruleset ruleset, BoardData data) async {
    final winLength = ruleset.winLength(data);
    final board = [for (final row in data) List<PlayerMark?>.of(row)];
    final input = (board: board, winLength: winLength);

    return switch (this) {
      // If the AI can make a winning move, do it.
      // If the AI can block an opponent's winning move, do it.
      // Otherwise, move in a random spot.
      // Return a SynchronousFuture instead of using `compute`.
      easy => SynchronousFuture(_aiEasy(input)),

      // If the AI can make a winning move, do it.
      // If the AI can block an opponent's winning move, do it.
      // If either player has a segment that's (winLength - 2) pieces long and isn't blocked at either end, the list of moves to consider should be narrowed down to the unoccupied spaces at those two ends.
      // Each space under consideration should be given a ranking equal to the total number of winLength-long segments that include the space (the player's number of segments and the AI's number of segments should be added together). Move in the spot with the highest ranking (if there's a tie, pick one at random).
      hard => compute(_aiHard, input),

      // Follow the same process as Difficulty.hard, but if the ranking results in a tie, do the following:
      // - If the choice is perfectly symmetrical, move in a random spot.
      // - Otherwise, pick the optimal space by looking several moves ahead (assume that both the user and the AI follow the Difficulty.hard algorithm and account for every possibility when there's a tied ranking.)
      brutal => compute(_aiBrutal, input),
    };
  }
}

extension<T> on List<T> {
  T get random {
    assert(isNotEmpty);
    return this[math.Random().nextInt(length)];
  }
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

List<(int row, int col)> _allEmpty(List<List<PlayerMark?>> board) {
  return [
    for (var row = 0; row < board.length; row++)
      for (var col = 0; col < board[row].length; col++)
        if (board[row][col] == null) (row, col),
  ];
}

/// Unoccupied cells within Chebyshev distance [winLength] of any occupied cell.
/// On an empty board, every cell is a candidate.
List<(int row, int col)> _candidateMoves(List<List<PlayerMark?>> board, int winLength) {
  final rows = board.length;
  final cols = board.first.length;
  final occupied = <(int, int)>[
    for (var row = 0; row < rows; row++)
      for (var col = 0; col < cols; col++)
        if (board[row][col] != null) (row, col),
  ];
  if (occupied.isEmpty) return _allEmpty(board);

  final candidates = <(int, int)>{};
  for (final (occupiedRow, occupiedCol) in occupied) {
    final rowMin = math.max(0, occupiedRow - winLength);
    final rowMax = math.min(rows - 1, occupiedRow + winLength);
    final colMin = math.max(0, occupiedCol - winLength);
    final colMax = math.min(cols - 1, occupiedCol + winLength);
    for (var row = rowMin; row <= rowMax; row++) {
      for (var col = colMin; col <= colMax; col++) {
        if (board[row][col] != null) continue;
        final distance = math.max((row - occupiedRow).abs(), (col - occupiedCol).abs());
        if (distance <= winLength) candidates.add((row, col));
      }
    }
  }
  return candidates.toList();
}

bool _formsWin(List<List<PlayerMark?>> board, int row, int col, PlayerMark mark, int winLength) {
  final rows = board.length;
  final cols = board.first.length;
  for (final (dRow, dCol) in BoardData.directions) {
    var count = 1;
    for (var step = 1; step < winLength; step++) {
      final r = row + step * dRow;
      final c = col + step * dCol;
      if (r < 0 || r >= rows || c < 0 || c >= cols || board[r][c] != mark) break;
      count++;
    }
    for (var step = 1; step < winLength; step++) {
      final r = row - step * dRow;
      final c = col - step * dCol;
      if (r < 0 || r >= rows || c < 0 || c >= cols || board[r][c] != mark) break;
      count++;
    }
    if (count >= winLength) return true;
  }
  return false;
}

bool _isWinningPlacement(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  PlayerMark mark,
  int winLength,
) {
  board[row][col] = mark;
  final won = _formsWin(board, row, col, mark, winLength);
  board[row][col] = null;
  return won;
}

List<(int row, int col)> _winningPlacements(
  List<List<PlayerMark?>> board,
  List<(int row, int col)> candidates,
  PlayerMark mark,
  int winLength,
) {
  return [
    for (final (row, col) in candidates)
      if (_isWinningPlacement(board, row, col, mark, winLength)) (row, col),
  ];
}

/// Open ends of any contiguous run of length `winLength - 2` that is empty on both sides.
Set<(int row, int col)>? _openSegmentEnds(List<List<PlayerMark?>> board, int winLength) {
  final runLength = winLength - 2;
  if (runLength < 1) return null;

  final rows = board.length;
  final cols = board.first.length;
  final ends = <(int, int)>{};

  for (final (dRow, dCol) in BoardData.directions) {
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final mark = board[row][col];
        if (mark == null) continue;

        final endRow = row + (runLength - 1) * dRow;
        final endCol = col + (runLength - 1) * dCol;
        if (endRow < 0 || endRow >= rows || endCol < 0 || endCol >= cols) continue;

        var isRun = true;
        for (var i = 1; i < runLength; i++) {
          if (board[row + i * dRow][col + i * dCol] != mark) {
            isRun = false;
            break;
          }
        }
        if (!isRun) continue;

        final beforeRow = row - dRow;
        final beforeCol = col - dCol;
        final afterRow = row + runLength * dRow;
        final afterCol = col + runLength * dCol;
        final beforeInBounds =
            beforeRow >= 0 && beforeRow < rows && beforeCol >= 0 && beforeCol < cols;
        final afterInBounds = afterRow >= 0 && afterRow < rows && afterCol >= 0 && afterCol < cols;
        if (!beforeInBounds || !afterInBounds) continue;
        if (board[beforeRow][beforeCol] != null || board[afterRow][afterCol] != null) continue;

        ends
          ..add((beforeRow, beforeCol))
          ..add((afterRow, afterCol));
      }
    }
  }

  return ends.isEmpty ? null : ends;
}

/// How many [winLength]-windows containing [row],[col] are still achievable for [player].
int _segmentCountForPlayer(
  List<List<PlayerMark?>> board,
  int row,
  int col,
  int winLength,
  PlayerMark player,
) {
  final rows = board.length;
  final cols = board.first.length;
  var count = 0;

  for (final (dRow, dCol) in BoardData.directions) {
    for (var offset = 0; offset < winLength; offset++) {
      final startRow = row - offset * dRow;
      final startCol = col - offset * dCol;
      final endRow = startRow + (winLength - 1) * dRow;
      final endCol = startCol + (winLength - 1) * dCol;
      if (startRow < 0 ||
          startRow >= rows ||
          startCol < 0 ||
          startCol >= cols ||
          endRow < 0 ||
          endRow >= rows ||
          endCol < 0 ||
          endCol >= cols) {
        continue;
      }

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

int _moveRank(List<List<PlayerMark?>> board, int row, int col, int winLength) {
  return _segmentCountForPlayer(board, row, col, winLength, .x) +
      _segmentCountForPlayer(board, row, col, winLength, .o);
}

List<(int row, int col)> _highestRankedMoves(
  List<List<PlayerMark?>> board,
  List<(int row, int col)> candidates,
  int winLength,
) {
  var bestRank = -1;
  final best = <(int, int)>[];
  for (final (row, col) in candidates) {
    final rank = _moveRank(board, row, col, winLength);
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

/// Candidate list after win/block filtering is handled separately; applies open-segment narrowing.
List<(int row, int col)> _narrowedCandidates(List<List<PlayerMark?>> board, int winLength) {
  var candidates = _candidateMoves(board, winLength);
  if (candidates.isEmpty) candidates = _allEmpty(board);

  final ends = _openSegmentEnds(board, winLength);
  if (ends != null) {
    final narrowed = [
      for (final move in candidates)
        if (ends.contains(move)) move,
    ];
    if (narrowed.isNotEmpty) return narrowed;
  }
  return candidates;
}

/// All moves [Difficulty.hard] would consider equally best (for branching under brutal).
List<(int row, int col)> _hardMoveOptions(List<List<PlayerMark?>> board, int winLength) {
  final ai = _sideToMove(board);
  final candidates = _candidateMoves(board, winLength);
  final pool = candidates.isEmpty ? _allEmpty(board) : candidates;
  if (pool.isEmpty) return const [];

  final wins = _winningPlacements(board, pool, ai, winLength);
  if (wins.isNotEmpty) return wins;

  final blocks = _winningPlacements(board, pool, ai.opponent, winLength);
  if (blocks.isNotEmpty) return blocks;

  return _highestRankedMoves(board, _narrowedCandidates(board, winLength), winLength);
}

(int row, int col) _aiEasy(_AiInput input) {
  final (:board, :winLength) = input;
  final ai = _sideToMove(board);
  final candidates = _candidateMoves(board, winLength);
  final pool = candidates.isEmpty ? _allEmpty(board) : candidates;
  assert(pool.isNotEmpty, 'AI called on a full board');

  final wins = _winningPlacements(board, pool, ai, winLength);
  if (wins.isNotEmpty) return wins.random;

  final blocks = _winningPlacements(board, pool, ai.opponent, winLength);
  if (blocks.isNotEmpty) return blocks.random;

  return pool.random;
}

(int row, int col) _aiHard(_AiInput input) {
  final (:board, :winLength) = input;
  final options = _hardMoveOptions(board, winLength);
  assert(options.isNotEmpty, 'AI called on a full board');
  return options.random;
}

/// Board-preserving maps under the square dihedral group (identity included).
List<(int, int) Function(int row, int col)> _boardSymmetries(List<List<PlayerMark?>> board) {
  final rows = board.length;
  final cols = board.first.length;
  // Non-square boards only admit reflections through axes parallel to the sides when dimensions match the transform.
  final transforms = <(int, int) Function(int, int)>[
    (r, c) => (r, c),
    if (rows == cols) ...[
      (r, c) => (c, rows - 1 - r), // 90° CW
      (r, c) => (rows - 1 - r, cols - 1 - c), // 180°
      (r, c) => (cols - 1 - c, r), // 270° CW
      (r, c) => (r, cols - 1 - c), // reflect vertical axis
      (r, c) => (rows - 1 - r, c), // reflect horizontal axis
      (r, c) => (c, r), // reflect main diagonal
      (r, c) => (cols - 1 - c, rows - 1 - r), // reflect anti-diagonal
    ] else ...[
      (r, c) => (r, cols - 1 - c),
      (r, c) => (rows - 1 - r, c),
      (r, c) => (rows - 1 - r, cols - 1 - c),
    ],
  ];

  bool preserves((int, int) Function(int, int) transform) {
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final (tr, tc) = transform(row, col);
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

/// True when every move in [moves] lies in one orbit under the board's symmetry group.
bool _movesAreSymmetricallyEquivalent(
  List<List<PlayerMark?>> board,
  List<(int row, int col)> moves,
) {
  if (moves.length <= 1) return true;
  final symmetries = _boardSymmetries(board);
  if (symmetries.length <= 1) return false;

  final moveSet = moves.toSet();
  final orbit = <(int, int)>{moves.first};
  final queue = [moves.first];
  while (queue.isNotEmpty) {
    final (row, col) = queue.removeLast();
    for (final transform in symmetries) {
      final image = transform(row, col);
      if (moveSet.contains(image) && orbit.add(image)) {
        queue.add(image);
      }
    }
  }
  return orbit.length == moveSet.length;
}

bool _isFull(List<List<PlayerMark?>> board) {
  for (final row in board) {
    for (final cell in row) {
      if (cell == null) return false;
    }
  }
  return true;
}

/// Outcome from the root AI's perspective: +1 win, -1 loss, 0 draw / horizon.
int _brutalEvaluate(
  List<List<PlayerMark?>> board,
  int winLength,
  PlayerMark rootAi,
  int depthRemaining,
) {
  // Terminal checks use the last move's side; scan is fine at this scale.
  if (_findWinner(board, winLength) case final winner?) {
    return winner == rootAi ? 1 : -1;
  }
  if (_isFull(board) || depthRemaining <= 0) return 0;

  final toMove = _sideToMove(board);
  final options = _hardMoveOptions(board, winLength);
  if (options.isEmpty) return 0;

  if (toMove == rootAi) {
    var best = -2;
    for (final (row, col) in options) {
      board[row][col] = toMove;
      final score = _brutalEvaluate(board, winLength, rootAi, depthRemaining - 1);
      board[row][col] = null;
      if (score > best) best = score;
      if (best == 1) break;
    }
    return best;
  } else {
    var worst = 2;
    for (final (row, col) in options) {
      board[row][col] = toMove;
      final score = _brutalEvaluate(board, winLength, rootAi, depthRemaining - 1);
      board[row][col] = null;
      if (score < worst) worst = score;
      if (worst == -1) break;
    }
    return worst;
  }
}

PlayerMark? _findWinner(List<List<PlayerMark?>> board, int winLength) {
  final rows = board.length;
  final cols = board.first.length;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      final mark = board[row][col];
      if (mark == null) continue;
      for (final (dRow, dCol) in BoardData.directions) {
        final endRow = row + (winLength - 1) * dRow;
        final endCol = col + (winLength - 1) * dCol;
        if (endRow < 0 || endRow >= rows || endCol < 0 || endCol >= cols) continue;
        var won = true;
        for (var i = 1; i < winLength; i++) {
          if (board[row + i * dRow][col + i * dCol] != mark) {
            won = false;
            break;
          }
        }
        if (won) return mark;
      }
    }
  }
  return null;
}

int _brutalSearchDepth(List<List<PlayerMark?>> board) {
  final cells = board.length * board.first.length;
  if (cells <= 9) return 8;
  if (cells <= 25) return 5;
  if (cells <= 81) return 3;
  return 2;
}

(int row, int col) _aiBrutal(_AiInput input) {
  final (:board, :winLength) = input;
  final ai = _sideToMove(board);
  final candidates = _candidateMoves(board, winLength);
  final pool = candidates.isEmpty ? _allEmpty(board) : candidates;
  assert(pool.isNotEmpty, 'AI called on a full board');

  final wins = _winningPlacements(board, pool, ai, winLength);
  if (wins.isNotEmpty) return wins.random;

  final blocks = _winningPlacements(board, pool, ai.opponent, winLength);
  if (blocks.isNotEmpty) return blocks.random;

  final ranked = _highestRankedMoves(board, _narrowedCandidates(board, winLength), winLength);
  assert(ranked.isNotEmpty);
  if (ranked.length == 1) return ranked.single;

  if (_movesAreSymmetricallyEquivalent(board, ranked)) {
    return ranked.random;
  }

  final depth = _brutalSearchDepth(board);
  var bestScore = -2;
  final bestMoves = <(int, int)>[];
  for (final (row, col) in ranked) {
    board[row][col] = ai;
    final score = _brutalEvaluate(board, winLength, ai, depth);
    board[row][col] = null;
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
