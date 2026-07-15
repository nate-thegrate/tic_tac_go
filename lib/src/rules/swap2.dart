import 'dart:math' as math;

import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

/// Swap2 opening / color-choice flow.
enum Swap2Phase {
  /// Not in a swap2 opening (normal play or other ruleset).
  none,

  /// First player places 3 stones: black, white, black.
  opening3,

  /// Second player chooses color (and optionally "add 2 moves").
  chooseAfter3,

  /// Second player places 2 more stones after choosing "add 2 moves".
  extra2,

  /// First player chooses color only (after the extra two stones).
  chooseAfter5;

  bool get isChoosing => switch (this) {
    chooseAfter3 || chooseAfter5 => true,
    _ => false,
  };

  bool get isPlacing => switch (this) {
    opening3 || extra2 => true,
    _ => false,
  };
}

/// Swap2 rules: balanced openings, placement phases, and color choice.
abstract final class Swap2 {
  static final phase = Get.it(Swap2Phase.none);

  /// When [phase] is a choose-* state: whether the option overlay is shown.
  static final optionsVisible = Get.it(true);

  /// Stones placed in the current placement phase (opening3 or extra2).
  static final placedInPhase = Get.it(0);

  /// Whether the physical first player is the human (1-player); unused in 2-player.
  static var firstPlayerIsHuman = true;

  static bool get isChoosing => phase.value.isChoosing;
  static bool get isPlacing => phase.value.isPlacing;

  /// Marks for the current placement phase: opening3 is BWB; extra2 is WB.
  static List<PlayerMark> get currentMarks =>
      phase.value == .extra2 ? const [.o, .x] : const [.x, .o, .x];

  static PlayerMark get nextMark => currentMarks[placedInPhase.value];

  /// Who places stones in the current placement phase.
  static bool get humanPlacesCurrentPhase {
    if (Board.humanPlayer.value == null) return true; // 2-player
    return switch (phase.value) {
      .opening3 => firstPlayerIsHuman, // first player
      .extra2 => !firstPlayerIsHuman, // second player
      _ => false,
    };
  }

  static bool get humanIsChooser {
    if (Board.humanPlayer.value == null) return true; // 2-player: always show UI
    final chooserIsFirst = phase.value == .chooseAfter5;
    return chooserIsFirst ? firstPlayerIsHuman : !firstPlayerIsHuman;
  }

  static void reset() {
    phase.value = .none;
    optionsVisible.value = true;
    placedInPhase.value = 0;
    firstPlayerIsHuman = true;
  }

  static void beginIfNeeded() {
    if (Ruleset.current.value != .swap2) {
      reset();
      return;
    }
    placedInPhase.value = 0;
    optionsVisible.value = true;
    phase.value = .opening3;
  }

  static void toggleOptionsView() {
    if (!isChoosing) return;
    final show = !optionsVisible.value;
    optionsVisible.value = show;
    GameEnd.opacity.jumpTo(show ? 1 : 0);
  }

  static void _enterChoice(Swap2Phase choicePhase) {
    phase.value = choicePhase;
    optionsVisible.value = true;
    GameEnd.opacity.jumpTo(1);
    if (!humanIsChooser) {
      _aiResolveChoice();
    }
  }

  static void _aiResolveChoice() {
    if (phase.value == .chooseAfter3) {
      final pickBlack = _rng.nextDouble() < 0.35;
      applyColorChoice(pickBlack ? .x : .o);
    } else {
      applyColorChoice(_rng.nextDouble() < 0.5 ? .x : .o);
    }
  }

  /// [chooserPlaysAs] is the color the deciding player will play for the rest of the game.
  static Future<void> applyColorChoice(PlayerMark chooserPlaysAs) async {
    if (!isChoosing) return;

    final chooserIsFirst = phase.value == .chooseAfter5;
    if (Board.humanPlayer.value != null) {
      final chooserIsHuman = chooserIsFirst ? firstPlayerIsHuman : !firstPlayerIsHuman;
      Board.humanPlayer.value = chooserIsHuman ? chooserPlaysAs : chooserPlaysAs.opponent;
    }

    Board.history.clear();
    phase.value = .none;
    optionsVisible.value = true;
    GameEnd.opacity.reset();
    // After swap2 placement, white moves next.
    Board.turn.value = .o;

    await Board.maybeAiTurn(Ruleset.current.value);
  }

  static Future<void> applyAddTwoMoves() async {
    if (phase.value != .chooseAfter3) return;
    phase.value = .extra2;
    placedInPhase.value = 0;
    optionsVisible.value = true;
    Board.history.clear();
    GameEnd.opacity.reset();
    Board.turn.value = nextMark;

    // Second player places the two stones; AI only if second player is the AI.
    if (!humanPlacesCurrentPhase) {
      await runAiPlacement();
    }
  }

  static Future<void> _finishPlacementStep() async {
    placedInPhase.value++;
    if (placedInPhase.value < currentMarks.length) {
      Board.turn.value = nextMark;
      return;
    }

    if (phase.value == .opening3) {
      _enterChoice(.chooseAfter3);
    } else if (phase.value == .extra2) {
      _enterChoice(.chooseAfter5);
    }
  }

  /// AI places the current phase using balanced opening templates.
  static Future<void> runAiPlacement() async {
    final ruleset = Ruleset.current.value;
    final plan = switch (phase.value) {
      .opening3 => planOpening3(Board.state.rows, Board.state.cols),
      .extra2 => planExtra2(Board.state.value.copyMutable()),
      _ => const <(int, int)>[],
    };
    assert(
      plan.length == currentMarks.length,
      'Swap2 AI plan length ${plan.length} != ${currentMarks.length}',
    );

    Board.inputLocked = true;
    try {
      var planIndex = 0;
      while (isPlacing && planIndex < plan.length) {
        final mark = nextMark;
        Board.turn.value = mark;
        var (row, col) = plan[planIndex++];
        if (row < 0 ||
            row >= Board.state.rows ||
            col < 0 ||
            col >= Board.state.cols ||
            Board.state.value[row][col] != null) {
          (row, col) = await aiMove(Difficulty.selected.value, ruleset, Board.state.value, mark);
        }
        var result = await Board.placeAndResolve(
          row,
          col,
          mark,
          ruleset,
          advanceTurn: false,
          onGameOver: reset,
        );
        if (result == null) {
          // Illegal plan cell under renju etc. — try a search move.
          final (r2, c2) = await aiMove(
            Difficulty.selected.value,
            ruleset,
            Board.state.value,
            mark,
          );
          result = await Board.placeAndResolve(
            r2,
            c2,
            mark,
            ruleset,
            advanceTurn: false,
            onGameOver: reset,
          );
          if (result == null) continue;
        }
        if (result.gameOver) return;
        await _finishPlacementStep();
        if (!isPlacing) break;
      }
    } finally {
      Board.inputLocked = false;
    }
  }

  static Future<void> placeHumanMark(int row, int col) async {
    final ruleset = Ruleset.current.value;
    final mark = nextMark;
    final result = await Board.placeAndResolve(
      row,
      col,
      mark,
      ruleset,
      advanceTurn: false,
      onGameOver: reset,
    );
    if (result == null || result.gameOver) return;
    await _finishPlacementStep();
  }

  /// Undo one stone during an opening/extra placement phase, or from a
  /// color-choice phase back into that placement (2-player).
  static void undoPlacementStone(void Function() undoOnce) {
    if (isChoosing) {
      phase.value = phase.value == .chooseAfter3 ? .opening3 : .extra2;
      optionsVisible.value = true;
      GameEnd.opacity.reset();
    }
    undoOnce();
    if (placedInPhase.value > 0) placedInPhase.value--;
    Board.turn.value = nextMark;
  }

  static final _rng = math.Random();

  /// Absolute cells for the initial three stones: black, white, black.
  static List<(int row, int col)> planOpening3(int rows, int cols) {
    final center = (rows ~/ 2, cols ~/ 2);
    final template = _opening3Templates[_rng.nextInt(_opening3Templates.length)];
    final rot = _rng.nextInt(4);
    final mirror = _rng.nextBool();
    return _mapTemplate(template, center, rot, mirror, rows, cols);
  }

  /// Absolute cells for the extra two stones: white, black.
  static List<(int row, int col)> planExtra2(List<List<PlayerMark?>> board) {
    final rows = board.length;
    final cols = board.first.length;
    final occupied = board.occupiedCells.toSet();
    final center = _centroid(occupied, rows, cols);

    final pairs = List.of(_extra2Templates)..shuffle(_rng);
    final rot = _rng.nextInt(4);
    final mirror = _rng.nextBool();
    for (final pair in pairs) {
      final mapped = _mapTemplate(pair, center, rot, mirror, rows, cols);
      if (mapped[0] != mapped[1] &&
          !occupied.contains(mapped[0]) &&
          !occupied.contains(mapped[1])) {
        return mapped;
      }
    }

    final white =
        _firstFreeNear(board, center, preferDistance: 2) ??
        _firstFreeNear(board, center, preferDistance: 1) ??
        board.centerCell;
    final black =
        _firstFreeNear(board, center, preferDistance: 3, exclude: {white}) ??
        _firstFreeNear(board, center, preferDistance: 2, exclude: {white}) ??
        _firstFreeNear(board, white, preferDistance: 2, exclude: {white})!;
    return [white, black];
  }

  /// Fair 3-stone shapes (B, W, B) used in freestyle Swap2 practice.
  static const _opening3Templates = <List<(int, int)>>[
    [(0, 0), (2, 3), (3, -1)],
    [(0, 0), (3, 2), (-1, 3)],
    [(0, 0), (2, -3), (3, 1)],
    [(0, 0), (-3, 2), (2, 2)],
    [(0, 0), (1, 3), (3, 0)],
    [(0, 0), (3, -2), (0, 3)],
    [(0, 0), (2, 2), (-2, 3)],
    [(0, 0), (4, 1), (1, -3)],
    [(0, 0), (3, 3), (-2, 1)],
    [(0, 0), (2, -2), (-3, -1)],
    [(0, 0), (2, 1), (-1, 2)],
    [(0, 0), (1, 2), (2, -1)],
    [(0, 0), (2, -1), (-2, 1)],
    [(0, 0), (-1, 2), (2, 1)],
    [(0, 0), (1, -2), (-2, -1)],
    [(0, 0), (-2, 1), (1, 2)],
    [(0, 0), (3, 4), (-2, 3)],
    [(0, 0), (4, 2), (1, -4)],
    [(0, 0), (-3, 3), (4, 0)],
    [(0, 0), (2, -4), (-3, -2)],
  ];

  /// Extra white then black offsets from the 3-stone centroid.
  static const _extra2Templates = <List<(int, int)>>[
    [(2, 2), (-2, 3)],
    [(3, 0), (-1, 3)],
    [(2, -2), (3, 2)],
    [(-2, 2), (3, 1)],
    [(0, 3), (3, -2)],
    [(3, 1), (-3, 2)],
    [(1, -3), (-2, -2)],
    [(-3, -1), (2, -3)],
    [(2, 3), (-3, 0)],
    [(0, -3), (3, 2)],
  ];

  static List<(int row, int col)> _mapTemplate(
    List<(int, int)> template,
    (int, int) origin,
    int rot90,
    bool mirror,
    int rows,
    int cols,
  ) {
    final (originRow, originCol) = origin;
    final mapped = <(int, int)>[];
    for (final (dr0, dc0) in template) {
      var dr = dr0;
      var dc = mirror ? -dc0 : dc0;
      for (var i = 0; i < rot90; i++) {
        final nextDr = dc;
        final nextDc = -dr;
        dr = nextDr;
        dc = nextDc;
      }
      final row = (originRow + dr).clamp(1, rows - 2);
      final col = (originCol + dc).clamp(1, cols - 2);
      mapped.add((row, col));
    }

    final used = <(int, int)>{};
    for (var i = 0; i < mapped.length; i++) {
      final cell = mapped[i];
      if (!used.contains(cell) && cell.inBoardSize(rows, cols)) {
        used.add(cell);
        mapped[i] = cell;
        continue;
      }
      final nudged =
          _firstFreeNearCoords(rows, cols, cell, preferDistance: 1, exclude: used) ??
          _firstFreeNearCoords(
            rows,
            cols,
            (originRow, originCol),
            preferDistance: 2,
            exclude: used,
          );
      if (nudged != null) {
        mapped[i] = nudged;
        used.add(nudged);
      }
    }
    return mapped;
  }

  static (int, int) _centroid(Set<(int, int)> cells, int rows, int cols) {
    if (cells.isEmpty) return (rows ~/ 2, cols ~/ 2);
    var sumR = 0;
    var sumC = 0;
    for (final (r, c) in cells) {
      sumR += r;
      sumC += c;
    }
    return (sumR ~/ cells.length, sumC ~/ cells.length);
  }

  static (int, int)? _firstFreeNear(
    List<List<PlayerMark?>> board,
    (int, int) origin, {
    required int preferDistance,
    Set<(int, int)> exclude = const {},
  }) {
    return _firstFreeNearCoords(
      board.length,
      board.first.length,
      origin,
      preferDistance: preferDistance,
      exclude: {...board.occupiedCells, ...exclude},
    );
  }

  static (int, int)? _firstFreeNearCoords(
    int rows,
    int cols,
    (int, int) origin, {
    required int preferDistance,
    required Set<(int, int)> exclude,
  }) {
    final (or, oc) = origin;
    for (var dist = preferDistance; dist <= preferDistance + 4; dist++) {
      final ring = <(int, int)>[];
      for (var dr = -dist; dr <= dist; dr++) {
        for (var dc = -dist; dc <= dist; dc++) {
          if (math.max(dr.abs(), dc.abs()) != dist) continue;
          final r = or + dr;
          final c = oc + dc;
          if (r < 1 || r >= rows - 1 || c < 1 || c >= cols - 1) continue;
          if (exclude.contains((r, c))) continue;
          ring.add((r, c));
        }
      }
      if (ring.isNotEmpty) return ring[_rng.nextInt(ring.length)];
    }
    for (var r = 1; r < rows - 1; r++) {
      for (var c = 1; c < cols - 1; c++) {
        if (!exclude.contains((r, c))) return (r, c);
      }
    }
    return null;
  }
}
