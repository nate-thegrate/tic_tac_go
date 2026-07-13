/// Session transcript for improving [Difficulty.brutal] from human wins.
///
/// When the human beats brutal, a JSON object is appended to [logFilePath]
/// and printed as a single `[brutal_loss] …` line so a Grok `monitor`
/// (e.g. tailing the log file) can pick it up.
///
/// Import with a prefix: `import '.../game_log.dart' as game_log;`
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

/// One committed placement in the current game (survives [Board.history] clears).
class GameLogMove {
  const GameLogMove({required this.row, required this.col, required this.mark, required this.byAi});

  final int row;
  final int col;
  final PlayerMark mark;
  final bool byAi;

  Map<String, Object?> toJson() => {
    'row': row,
    'col': col,
    'mark': mark.name,
    'by': byAi ? 'ai' : 'human',
  };
}

/// Flip to `true` to record games and emit brutal-loss training lines.
var loggingEnabled = false;

const logFilePath = 'logs/brutal_losses.jsonl';
const stdoutMarker = '[brutal_loss]';

Difficulty? _difficulty;
Ruleset? _ruleset;
int? _rows;
int? _cols;
PlayerMark? _human;
var _goMode = false;
final moves = <GameLogMove>[];
var _emittedForCurrentGame = false;

void startGame({
  required Difficulty? difficulty,
  required Ruleset ruleset,
  required int rows,
  required int cols,
  required PlayerMark? human,
  required bool goMode,
}) {
  if (!loggingEnabled) return;
  _difficulty = difficulty;
  _ruleset = ruleset;
  _rows = rows;
  _cols = cols;
  _human = human;
  _goMode = goMode;
  moves.clear();
  _emittedForCurrentGame = false;
}

/// Call after swap2 (or similar) reassigns who plays which color.
void setHuman(PlayerMark? human) {
  if (!loggingEnabled) return;
  _human = human;
}

void recordMove({
  required int row,
  required int col,
  required PlayerMark mark,
  required bool byAi,
}) {
  if (!loggingEnabled) return;
  moves.add(GameLogMove(row: row, col: col, mark: mark, byAi: byAi));
}

void undoLast([int count = 1]) {
  if (!loggingEnabled) return;
  for (var i = 0; i < count && moves.isNotEmpty; i++) {
    moves.removeLast();
  }
}

void clear() {
  if (!loggingEnabled) return;
  _difficulty = null;
  _ruleset = null;
  _rows = null;
  _cols = null;
  _human = null;
  _goMode = false;
  moves.clear();
  _emittedForCurrentGame = false;
}

/// Emit a training record when the human just beat [Difficulty.brutal].
void maybeEmitBrutalLoss({
  required PlayerMark? winner,
  required List<(int row, int col)>? winningRun,
}) {
  if (!loggingEnabled) return;
  if (_emittedForCurrentGame) return;
  if (_difficulty != Difficulty.brutal) return;
  final human = _human;
  if (human == null || winner != human) return;

  // Guard against stale side assignment (e.g. swap2 color choice not reflected):
  // the winner's stones should mostly have been placed by the human.
  final winnerPlacedByHuman = moves.where((m) => m.mark == winner && !m.byAi).length;
  final winnerPlacedByAi = moves.where((m) => m.mark == winner && m.byAi).length;
  if (winnerPlacedByHuman == 0 || winnerPlacedByHuman < winnerPlacedByAi) {
    debugPrint(
      'game_log: skip brutal_loss (human=$human winner=$winner '
      'humanStones=$winnerPlacedByHuman aiStones=$winnerPlacedByAi)',
    );
    return;
  }

  _emittedForCurrentGame = true;
  final payload = <String, Object?>{
    'type': 'brutal_loss',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'ruleset': _ruleset?.name,
    'rows': _rows,
    'cols': _cols,
    'human': human.name,
    'ai': human.opponent.name,
    'goMode': _goMode,
    'difficulty': _difficulty?.name,
    'winner': human.name,
    'winningRun': [
      for (final (row, col) in winningRun ?? const <(int, int)>[])
        if (row >= 0) {'row': row, 'col': col},
    ],
    'moves': [for (final move in moves) move.toJson()],
  };

  final line = jsonEncode(payload);
  // Distinct prefix for process stdout / log-tail monitors.
  debugPrint('$stdoutMarker $line');
  // ignore: avoid_print
  print('$stdoutMarker $line');

  try {
    final file = File(logFilePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (error, stack) {
    debugPrint('game_log: failed to write $logFilePath: $error\n$stack');
  }
}
