import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

/// Connect6: black places 1 on the first turn, then each turn is 2 stones; win length 6.
abstract final class Connect6 {
  /// Stones the current player has already placed this turn (0 or 1 mid-turn).
  static final stonesThisTurn = Get.it(0);

  static bool get isActive => Ruleset.current.value == .connect6;

  static void reset() {
    stonesThisTurn.value = 0;
  }

  /// How many stones [mark] must place to finish the current turn on [board].
  ///
  /// Safe with either the pre-placement board or the board after commit (including
  /// the post-commit / pre-[notePlacement] animation window): black still needs
  /// only one stone until white has played.
  static int stonesNeeded(PlayerMark mark, BoardData board) {
    if (!isActive) return 1;
    if (mark == .o) return 2;
    // Black places a single stone only on the opening turn (while white has none).
    return board.countMark(.o) == 0 ? 1 : 2;
  }

  /// After a successful placement by [mark], advance turn state.
  /// Returns `true` if the player's turn is now complete (caller should switch sides).
  static bool notePlacement(PlayerMark mark, BoardData boardAfterPlace) {
    if (!isActive) return true;
    stonesThisTurn.value++;
    final required = stonesNeeded(mark, boardAfterPlace);
    if (stonesThisTurn.value >= required) {
      stonesThisTurn.value = 0;
      return true;
    }
    return false;
  }

  /// Recompute [Board.turn] and [stonesThisTurn] from the board after undos.
  static void recomputeTurnFromBoard(BoardData board) {
    if (!isActive) return;
    final n = board.stoneCount;
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

  /// Undo one stone, or a full prior turn (and the human's, in 1-player).
  static void undo(void Function() undoStoneOnly) {
    if (stonesThisTurn.value > 0) {
      // Mid-turn: revert only the last stone of the current player.
      undoStoneOnly();
      recomputeTurnFromBoard(Board.state.value);
      return;
    }

    // Start of a turn: undo the previous player's full turn.
    PlayerMark? lastMark;
    var undone = 0;
    while (Board.history.isNotEmpty && undone < 2) {
      final (row, col) = Board.history.last;
      final mark = Board.state.value[row][col];
      if (mark == null) break;
      if (lastMark == null) {
        lastMark = mark;
      } else if (mark != lastMark) {
        break;
      }
      undoStoneOnly();
      undone++;
    }

    // In 1-player, also undo the human's full turn when undoing an AI reply.
    final human = Board.humanPlayer.value;
    if (human != null && lastMark != null && lastMark != human && Board.history.isNotEmpty) {
      undone = 0;
      while (Board.history.isNotEmpty && undone < 2) {
        final (row, col) = Board.history.last;
        final mark = Board.state.value[row][col];
        if (mark != human) break;
        undoStoneOnly();
        undone++;
      }
    }

    recomputeTurnFromBoard(Board.state.value);
  }
}
