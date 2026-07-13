import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';

/// Connect6: black places 1 on the first turn, then each turn is 2 stones; win length 6.
abstract final class Connect6 {
  /// Stones the current player has already placed this turn (0 or 1 mid-turn).
  static final stonesThisTurn = Get.it(0);

  static bool get isActive => Ruleset.current.value == .connect6;

  static void reset() {
    stonesThisTurn.value = 0;
  }

  static int _countMark(BoardData board, PlayerMark mark) {
    var count = 0;
    for (final row in board) {
      for (final cell in row) {
        if (cell == mark) count++;
      }
    }
    return count;
  }

  static int totalStones(BoardData board) {
    var count = 0;
    for (final row in board) {
      for (final cell in row) {
        if (cell != null) count++;
      }
    }
    return count;
  }

  /// How many stones [mark] must place to finish the current turn, given [board]
  /// *before* the next placement (and [stonesThisTurn] progress).
  static int stonesRequired(PlayerMark mark, BoardData board) {
    if (!isActive) return 1;
    if (mark == .o) return 2;
    // Black places a single stone only on the game's first turn.
    final xBeforeThisTurn = _countMark(board, .x) - stonesThisTurn.value;
    return xBeforeThisTurn <= 0 ? 1 : 2;
  }

  /// After a successful placement by [mark], advance turn state.
  /// Returns `true` if the player's turn is now complete (caller should switch sides).
  static bool notePlacement(PlayerMark mark, BoardData boardAfterPlace) {
    if (!isActive) return true;
    stonesThisTurn.value++;
    final required = stonesRequired(mark, boardAfterPlace);
    // stonesRequired uses stonesThisTurn; after increment, xBeforeThisTurn for black
    // first turn: countX=1, stonesThisTurn=1 → xBefore=0 → required=1. Good.
    if (stonesThisTurn.value >= required) {
      stonesThisTurn.value = 0;
      return true;
    }
    return false;
  }

  /// Recompute [Board.turn] and [stonesThisTurn] from the board after undos.
  static void recomputeTurnFromBoard(BoardData board) {
    if (!isActive) return;
    final n = totalStones(board);
    if (n == 0) {
      Board.turn.value = .x;
      stonesThisTurn.value = 0;
      return;
    }
    // First stone is always black's single opening; then O,O, X,X, O,O, ...
    final k = n - 1;
    stonesThisTurn.value = k.isOdd ? 1 : 0;
    final pairIndex = k ~/ 2;
    Board.turn.value = pairIndex.isEven ? .o : .x;
  }
}
