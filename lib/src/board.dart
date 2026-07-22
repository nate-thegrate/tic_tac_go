import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/menu.dart';
import 'package:tic_tac_go/src/player_mark.dart';
import 'package:tic_tac_go/src/rules/connect6.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';
import 'package:tic_tac_go/src/rules/swap2.dart';
import 'package:tic_tac_go/src/tap_detector.dart';

export 'package:tic_tac_go/src/player_mark.dart';

extension on int {
  int get clampedBoardSize => math.min(math.max(this, 3), 19);
}

class BoardState with ChangeNotifier implements ValueListenable<BoardData> {
  BoardState();

  @override
  BoardData get value => _value;
  late var _value = BoardData(_list);
  var _list = <List<PlayerMark?>>[
    [.x, .o, .x],
    [.o, .x, .o],
    [.x, .o, .x],
  ];

  int get cols => _list.first.length;
  set cols(int value) {
    value = value.clampedBoardSize;
    if (value == cols) return;
    final newState = [for (final row in _list) List.generate(value, row.elementAtOrNull)];
    _list = newState;
    notifyListeners();
  }

  int get rows => _list.length;
  set rows(int value) {
    value = value.clampedBoardSize;
    if (value == rows) return;
    final newState = [
      for (int i = 0; i < value; i++) _list.elementAtOrNull(i) ?? List.filled(cols, null),
    ];
    _list = newState;
    notifyListeners();
  }

  void update(int row, int col, PlayerMark? mark) {
    final oldValue = _list[row][col];
    if (mark == oldValue) return;
    _list[row][col] = mark;
    notifyListeners();
  }

  void clear() {
    _list = List.generate(rows, (_) => List.filled(cols, null));
    notifyListeners();
  }

  @protected
  @override
  void notifyListeners() {
    _value = BoardData(_list);
    super.notifyListeners();
  }

  @override
  String toString() => [
    'BoardState([',
    for (final row in _list) '  ${[for (final spot in row) spot ?? '_'].join(' ')}',
    '])',
  ].join('\n');
}

class StoneData {
  StoneData(
    this.row,
    this.col,
    this.mark, {
    required Offset center,
    required double radius,
    required double height,
    required double maxHeight,
  }) : rect = .fromCircle(
         center: center.translate(0, -height),
         radius: radius * scaleForHeight(height, maxHeight),
       ),
       shadowRect = .fromCircle(center: center, radius: radius),
       elevation = 2.0 + height * 0.1,
       opacity = opacityForHeight(height, maxHeight);

  /// How far the stone is from the board, as a 0–1 fraction of [maxHeight].
  static double heightFactor(double height, double maxHeight) {
    if (maxHeight <= 0) return 0;
    return (height / maxHeight).clamp(0.0, 1.0);
  }

  /// Stones higher above the board read as closer to the camera.
  static double scaleForHeight(double height, double maxHeight) {
    return 1.0 + heightFactor(height, maxHeight) * 0.15;
  }

  /// Soft stand-in for depth-of-field: higher stones are slightly more translucent.
  static double opacityForHeight(double height, double maxHeight) {
    return 1.0 - heightFactor(height, maxHeight) * 0.22;
  }

  final int row;
  final int col;
  final PlayerMark mark;
  final Rect rect;
  final Rect shadowRect;
  final double elevation;
  final double opacity;
}

class Board extends StatelessWidget {
  const Board({super.key});

  static final state = BoardState();
  static final history = Get.list<(int row, int col)>();

  static final turn = Get.it(PlayerMark.x);

  /// The human's mark in a 1-player game; `null` in 2-player.
  static final humanPlayer = Get.it<PlayerMark?>(tutorialDone.value ? null : .x);

  /// True while a move animation and/or AI computation is in progress.
  static var inputLocked = false;

  static void _assignSides() {
    if (twoPlayer.value) {
      humanPlayer.value = null;
      Swap2.firstPlayerIsHuman = true;
    } else {
      humanPlayer.value = PlayerMark.userSelection.value ?? (rng.nextBool() ? .x : .o);
      // First player places the swap2 opening; human is first iff they play black initially.
      Swap2.firstPlayerIsHuman = humanPlayer.value == .x;
    }
    turn.value = .x;
  }

  static final canUndo = Get.compute((ref) {
    if (ref.watch(history).isEmpty) return false;

    final human = ref.watch(humanPlayer);
    if (human == null) return true;
    if (ref.watch(Swap2.phase).isChoosing) return false;

    final board = ref.watch(state);
    for (final (row, col) in history) {
      if (board[row][col] == human) return true;
    }
    return false;
  });

  static void undo([_, _]) {
    if (inputLocked || !canUndo.value || !tutorialDone.value) return;
    BottomBar.undoTransition.forward(from: 0);

    void undoOnce() {
      if (history.isEmpty) return;
      final (row, col) = history.removeLast();
      state.update(row, col, null);
      turn.value = turn.value.opponent;
    }

    void undoStoneOnly() {
      if (history.isEmpty) return;
      final (row, col) = history.removeLast();
      state.update(row, col, null);
    }

    if (Swap2.isPlacing || Swap2.isChoosing) {
      Swap2.undoPlacementStone(undoOnce);
      return;
    }

    if (Connect6.isActive) {
      Connect6.undo(undoStoneOnly);
      return;
    }

    // After an AI move it's the human's turn, so the last history entry is the AI's.
    final undoAiAndUser = humanPlayer.value != null && turn.value == humanPlayer.value;
    undoOnce();
    if (undoAiAndUser && history.isNotEmpty) undoOnce();
  }

  static Future<void> runGameEndSequence(Ruleset ruleset) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    tutorialDone.value = true;
    if (!state.value.isGameOver(ruleset)) return;

    if (GameEnd.opacity.isDismissed) {
      await GameEnd.opacity.animateTo(1, curve: Curves.easeOutSine);
    } else {
      GameEnd.opacity.value = 1;
    }
  }

  static Future<void> animatePlacement() async {
    playerMarkAnimation.duration = goMode.value
        ? const Duration(milliseconds: 325)
        : const Duration(milliseconds: 225);
    await playerMarkAnimation.forward(from: 0);
  }

  /// Whether [mark] may be placed at [row],[col] under [ruleset] (renju fouls, occupancy).
  ///
  /// BoardData rows are unmodifiable; renju trial-place needs a mutable copy.
  static bool isLegalPlacement(int row, int col, PlayerMark mark, Ruleset ruleset) {
    final List<List<PlayerMark?>> board = ruleset == .renju && mark == .x
        ? state.value.copyMutable()
        : state.value;
    return (row, col).isLegalOn(board, mark, ruleset);
  }

  /// Places [mark] at [row],[col], updates history, and returns whether the game ended.
  ///
  /// Returns `null` if the placement is illegal (e.g. renju foul for black).
  static bool? commitMark(int row, int col, PlayerMark mark, Ruleset ruleset) {
    if (!isLegalPlacement(row, col, mark, ruleset)) return null;

    state.update(row, col, mark);
    currentMark = (row, col);
    final gameOver = state.value.isGameOver(ruleset);
    gameOver ? history.clear() : history.add((row, col));
    return gameOver;
  }

  /// Commits [mark], animates placement, updates Connect6 turn progress, and
  /// optionally switches [turn] / runs the game-end sequence.
  ///
  /// Returns `null` if the placement is illegal. Otherwise:
  /// - `gameOver`: true if the game ended ([runGameEndSequence] already awaited)
  /// - `turnDone`: whether this player's turn is complete (always true outside connect6)
  ///
  /// Set [advanceTurn] to false when the caller manages turn/phase itself (e.g. swap2).
  /// [onGameOver] runs after Connect6 reset and before the end-sequence animation.
  static Future<({bool gameOver, bool turnDone})?> placeAndResolve(
    int row,
    int col,
    PlayerMark mark,
    Ruleset ruleset, {
    bool advanceTurn = true,
    void Function()? onGameOver,
  }) async {
    final gameOver = commitMark(row, col, mark, ruleset);
    if (gameOver == null) return null;

    await animatePlacement();

    if (gameOver) {
      if (Connect6.isActive) Connect6.reset();
      onGameOver?.call();
      await runGameEndSequence(ruleset);
      return (gameOver: true, turnDone: true);
    }

    final turnDone = !Connect6.isActive || Connect6.notePlacement(mark, state.value);
    if (turnDone && advanceTurn) {
      turn.value = mark.opponent;
    }
    return (gameOver: false, turnDone: turnDone);
  }

  /// Plays a full turn for the side to move (1 stone normally; 1 or 2 under connect6).
  static Future<void> _playAiMove(Ruleset ruleset) async {
    final difficulty = Difficulty.selected.value;
    final aiMark = turn.value;
    final stonesNeeded = Connect6.stonesNeeded(aiMark, state.value);

    for (var i = 0; i < stonesNeeded; i++) {
      if (state.value.isGameOver(ruleset)) break;
      final (row, col) = await aiMove(difficulty, ruleset, state.value, aiMark);
      final result = await placeAndResolve(row, col, aiMark, ruleset);
      if (result == null) {
        // Illegal AI move (shouldn't happen if the AI filters renju fouls).
        return;
      }
      if (result.gameOver || result.turnDone) return;
    }

    // Safety: e.g. loop `break` when the board was already terminal.
    if (state.value.isGameOver(ruleset) && GameEnd.opacity.value == 0) {
      await runGameEndSequence(ruleset);
    }
  }

  static Future<void> maybeAiTurn(Ruleset ruleset) async {
    final human = humanPlayer.value;
    if (human == null || turn.value == human || state.value.isGameOver(ruleset)) return;
    inputLocked = true;
    try {
      await _playAiMove(ruleset);
    } finally {
      inputLocked = false;
    }
  }

  /// Resolves sides and starts the game (including an opening AI move when needed).
  static Future<void> startNewGame() async {
    GameEnd.opacity.value = 0;
    state.clear();
    history.clear();
    inputLocked = false;
    currentMark = null;
    Connect6.reset();
    _assignSides();
    Swap2.beginIfNeeded();

    if (Swap2.phase.value == .opening3) {
      turn.value = Swap2.nextMark;
      final humanPlacesOpening = humanPlayer.value == null || Swap2.firstPlayerIsHuman;
      if (!humanPlacesOpening) {
        await Swap2.runAiPlacement();
      }
      return;
    }

    if (humanPlayer.value == .o) {
      await maybeAiTurn(Ruleset.current.value);
    }
  }

  /// Leaves play mode and returns to the setup menu.
  static void backToMenu([_]) async {
    await playingTransition.reverse();
    GameEnd.opacity.value = 0;
    state.clear();
    history.clear();
    turn.value = .x;
    humanPlayer.value = null;
    inputLocked = false;
    currentMark = null;
    Swap2.reset();
    Connect6.reset();
  }

  static (int, int)? currentMark;
  static final playerMarkAnimation = Get.vsync();

  static late final ui.FragmentProgram markerProgram;
  static final markerShaders = <Color, ui.FragmentShader>{
    if (GetQuery.size.value case Size(:final width, :final height))
      for (final color in [const Black(), PlayerMark.x.color, PlayerMark.o.color])
        color: markerProgram.fragmentShader()
          ..setFloat(0, width)
          ..setFloat(1, height)
          ..setFloat(2, color.r)
          ..setFloat(3, color.g)
          ..setFloat(4, color.b)
          ..setFloat(5, color.a)
          ..setFloat(6, devicePixelRatio)
          ..setFloat(7, 1),
  };

  static final int _gameSeed = rng.nextInt(0x1000);
  static double _rng(int seed) {
    var x = (seed + _gameSeed) * 1103515245 + 12345;
    x = (x ^ (x >> 16)) & 0x7fffffff;
    return x / 0x7fffffff;
  }

  static Paint markerPaint({required Size size, PlayerMark? player, required double strokeWidth}) {
    final color = player?.color ?? const Black();
    final Size(:width, :height) = size;
    final shader = markerShaders[color] ??= markerProgram.fragmentShader()
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, color.r)
      ..setFloat(3, color.g)
      ..setFloat(4, color.b)
      ..setFloat(5, color.a)
      ..setFloat(6, devicePixelRatio)
      ..setFloat(7, 1);

    return Paint()
      ..style = .stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = .round
      ..strokeJoin = .round
      ..blendMode = .multiply
      ..shader = shader;
  }

  static void paint(PaintRef ref) {
    markerShaders; // ignore: unnecessary_statements, ensuring the map is initialized
    final board = ref.watch(state);
    final ruleset = ref.watch(Ruleset.current);
    final t = ref.watch(playerMarkAnimation);
    final isGoMode = ref.watch(goMode);
    if (playerMarkAnimation.isActive) ref.setWillChangeHint();

    final PaintRef(:canvas, :size) = ref;
    final Size(:width, :height) = size;
    final BoardData(:cols, :rows) = board;

    final cellWidth = width / cols;
    final cellHeight = height / rows;
    final minCell = math.min(cellWidth, cellHeight);
    final winningRun = board.winningRun(ruleset);

    if (isGoMode) {
      final linePaint = Paint()
        ..color = const Color(0xFF1A1208)
        ..strokeWidth = math.max(2.0, minCell * 0.04)
        ..strokeCap = .square;

      Offset intersectionOf(int col, int row) =>
          Offset((col + 0.5) * cellWidth, (row + 0.5) * cellHeight);

      final topLeft = intersectionOf(0, 0);
      final bottomRight = intersectionOf(cols - 1, rows - 1);

      for (var col = 0; col < cols; col++) {
        final Offset(:dx) = intersectionOf(col, 0);
        canvas.drawLine(Offset(dx, topLeft.dy), Offset(dx, bottomRight.dy), linePaint);
      }
      for (var row = 0; row < rows; row++) {
        final Offset(:dy) = intersectionOf(0, row);
        canvas.drawLine(Offset(topLeft.dx, dy), Offset(bottomRight.dx, dy), linePaint);
      }

      final stoneRadius = minCell * 0.5;
      final dropHeight = minCell * 1.8;

      StoneData stoneData(int row, int col, PlayerMark mark, double progress) {
        progress = progress.clamp(0.0, 1.0);
        const impactAt = 0.68;

        final double height;
        if (progress <= impactAt) {
          final impactProgress = progress / impactAt;
          height = dropHeight * (1 - (impactProgress * impactProgress * 2 + impactProgress) / 3);
        } else {
          final bounceProgress = (progress - impactAt) / (1 - impactAt);
          height = dropHeight * 0.16 * bounceProgress * (1 - bounceProgress);
        }

        return StoneData(
          row,
          col,
          mark,
          center: intersectionOf(col, row),
          height: height,
          maxHeight: dropHeight,
          radius: stoneRadius,
        );
      }

      void drawStone(StoneData stone) {
        final StoneData(:mark, rect: stoneRect, :opacity) = stone;
        final isBlack = mark == .x;
        final baseColor = (isBlack ? const Color(0xFF101010) : const Color(0xFFE0DCD1)).withValues(
          alpha: opacity,
        );
        canvas.drawOval(stoneRect, Paint()..color = baseColor);

        final Rect(:center, :width, :height) = stoneRect;
        final radiusX = width / 2;
        final radiusY = height / 2;
        const stretchX = 1.75;
        final highlightCenter = Offset(
          (center.dx - radiusX * 0.075) / stretchX,
          center.dy - radiusY * 0.7,
        );
        final highlightRadius = math.min(radiusX, radiusY) * 0.8;
        final highlightPeak = (isBlack ? 0x48 : 0xFF) / 255.0 * opacity;
        canvas
          ..save()
          ..clipRRect(RRect.fromRectAndRadius(stoneRect, const .circular(0x100000)))
          ..transform(Matrix4.diagonal3Values(stretchX, 1, 1).storage)
          ..drawCircle(
            highlightCenter,
            highlightRadius,
            Paint()
              ..shader = ui.Gradient.radial(highlightCenter, highlightRadius, [
                Color.from(alpha: highlightPeak, red: 1, green: 250 / 255, blue: 237 / 255),
                const Color(0x00FFFAED),
              ]),
          )
          ..restore();
      }

      final winningCells = {...?winningRun};
      final stones = <StoneData>[];
      StoneData? fallingStone;
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < cols; col++) {
          final mark = board[row][col];
          if (mark == null) continue;
          if (currentMark == (row, col) && t < 1) {
            fallingStone = stoneData(row, col, mark, t);
            continue;
          }
          stones.add(stoneData(row, col, mark, 1));
        }
      }
      if (fallingStone case final stone?) {
        stones.add(stone);
      }

      bool isWinning(StoneData stone) => winningCells.contains((stone.row, stone.col));
      bool notWinning(StoneData stone) => !isWinning(stone);

      // Layer order: shadow / glow drawn underneath stones, winning stones drawn on top
      for (final StoneData(:shadowRect, :elevation) in stones.where(notWinning)) {
        canvas.drawShadow(Path()..addOval(shadowRect), const Black(), elevation, true);
      }
      stones.where(notWinning).forEach(drawStone);
      for (final StoneData(rect: stoneRect, :mark, :opacity) in stones.where(isWinning)) {
        ref.setIsComplexHint();
        final Rect(:center) = stoneRect;
        final winnerGlow = mark.winnerGlow.withValues(alpha: mark.winnerGlow.a * opacity);
        final glowRadius = stoneRect.shortestSide * 0.64;
        canvas.drawCircle(
          center,
          glowRadius,
          Paint()
            ..shader = ui.Gradient.radial(
              center,
              glowRadius,
              [winnerGlow, winnerGlow, winnerGlow.withValues(alpha: 0)],
              const [0.0, 0.8, 1.0],
            ),
        );
      }
      stones.where(isWinning).forEach(drawStone);
    } else {
      final markWidth = minCell * 0.15;
      final gridInset = minCell * 0.05;
      final gridPaint = markerPaint(size: size, strokeWidth: minCell * 0.075);

      void drawWobblyLine(Offset start, Offset end, {required int seed}) {
        if (minCell < 60) {
          // Don't make it wobbly if the grid is small
          canvas.drawLine(start, end, gridPaint);
          return;
        }

        final delta = end - start;
        final direction = delta / delta.distance;
        final normal = Offset(-direction.dy, direction.dx);

        final path = Path()..moveTo(start.dx, start.dy);
        const count = 14;
        for (var i = 1; i <= count; i++) {
          final t = i / count;
          final point = Offset.lerp(start, end, t)!;
          final falloff = math.sin(t * math.pi);
          final jitter = i == count ? 0.0 : (_rng(seed + i) - 0.5) * 0.015 * minCell * falloff;
          final Offset(:dx, :dy) = point + normal * jitter;
          path.lineTo(dx, dy);
        }
        canvas.drawPath(path, gridPaint);
      }

      for (var i = 1; i < cols; i++) {
        final x = width * i / cols;
        drawWobblyLine(Offset(x, gridInset), Offset(x, height - gridInset), seed: i);
      }
      for (var i = 1; i < rows; i++) {
        final y = height * i / rows;
        drawWobblyLine(Offset(gridInset, y), Offset(width - gridInset, y), seed: i + 20);
      }

      final inset = minCell * 0.25;

      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < cols; col++) {
          final mark = board[row][col];
          if (mark == null) continue;

          final rect = Rect.fromLTWH(
            col * cellWidth,
            row * cellHeight,
            cellWidth,
            cellHeight,
          ).deflate(inset);

          final progress = currentMark == (row, col) ? t : 1.0;
          if (progress <= 0) continue;

          final paint = markerPaint(size: size, player: mark, strokeWidth: markWidth);
          switch (mark) {
            case .x:
              final Rect(:topLeft, :topRight, :bottomLeft, :bottomRight) = rect;
              final p1 = math.min(progress * 2, 1.0);
              canvas.drawLine(topLeft, Offset.lerp(topLeft, bottomRight, p1)!, paint);
              if (progress > 0.5) {
                final p2 = (progress - 0.5) * 2;
                canvas.drawLine(topRight, Offset.lerp(topRight, bottomLeft, p2)!, paint);
              }
            case .o:
              canvas.drawArc(rect, -math.pi / 2, progress * math.pi * 2, false, paint);
          }
        }
      }

      if (winningRun case final cells? when t > 0 && !cells.first.$1.isNegative) {
        final (firstRow, firstCol) = cells.first;
        final (lastRow, lastCol) = cells.last;
        var start = Offset((firstCol + 0.5) * cellWidth, (firstRow + 0.5) * cellHeight);
        var end = Offset((lastCol + 0.5) * cellWidth, (lastRow + 0.5) * cellHeight);
        final delta = end - start;
        final padFactor = delta.dx != 0 && delta.dy != 0 ? 0.52 : 0.4;
        final pad = delta / delta.distance * minCell * padFactor;
        start -= pad;
        end += pad;

        canvas.drawLine(
          start,
          Offset.lerp(start, end, t)!,
          markerPaint(size: size, strokeWidth: minCell * 0.05),
        );
      }
    }
  }

  static void _handleTap(Offset position, Size size) async {
    if (!tutorialDone.value && GameEnd.opacity.isCompleted) {
      startNewGame();
      return;
    }
    final ruleset = Ruleset.current.value;
    if (state.value.isGameOver(ruleset)) {
      GameEnd.opacity.value = 1;
      tutorialDone.value = true;
      return;
    }

    if (inputLocked || playerMarkAnimation.isActive) return;

    if (Swap2.isChoosing) {
      if (!Swap2.optionsVisible.value) {
        Swap2.toggleOptionsView();
      }
      return;
    }

    final human = humanPlayer.value;
    final isUsersTurn = human == null || turn.value == human;
    if (Swap2.isPlacing) {
      if (!Swap2.humanPlacesCurrentPhase) return;
    } else if (!isUsersTurn) {
      return;
    }

    final Offset(:dx, :dy) = position;
    final Size(:width, :height) = size;
    final BoardState(:cols, :rows) = state;

    final down = (dy / height * rows).floor();
    final across = (dx / width * cols).floor();
    if (down < 0 || down >= rows || across < 0 || across >= cols) return;
    if (state.value[down][across] != null) return;

    inputLocked = true;
    try {
      if (Swap2.isPlacing) {
        await Swap2.placeHumanMark(down, across);
        return;
      }

      final userMark = turn.value;
      final result = await placeAndResolve(down, across, userMark, ruleset);
      if (result == null || result.gameOver || !result.turnDone) return;

      if (Difficulty.current.value != null) {
        await _playAiMove(ruleset);
      }
    } finally {
      inputLocked = false;
    }
  }

  static double _opacity(Ref ref) {
    final swap2Choice =
        ref.watch(Swap2.phase) == .chooseAfter3 || ref.watch(Swap2.phase) == .chooseAfter5;
    final hideOverlay = swap2Choice && !ref.watch(Swap2.optionsVisible);
    if (hideOverlay) return 1.0;
    return 1 - ref.watch(GameEnd.opacity) / 2;
  }

  static double _boardAspectRatio(Ref ref) =>
      ref.select(Board.state, (data) => data.cols / data.rows);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: .all(constraints.biggest.shortestSide / 32),
          child: const RefAspectRatio(
            _boardAspectRatio,
            child: Stack(
              children: [
                TapDetector(
                  _handleTap,
                  child: RepaintBoundary(child: RefOpacity(_opacity, child: RefPaint(paint))),
                ),
                Positioned.fill(child: GameEnd()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GameEnd extends RefWidget {
  const GameEnd({super.key});

  static final opacity = Get.vsync(
    initialValue: tutorialDone.value ? 0 : 1,
    duration: const Duration(milliseconds: 800),
  );

  static final gameOver = Get.compute((ref) {
    return ref.watch(Board.state).isGameOver(ref.watch(Ruleset.current));
  });

  static void backToMenu() {
    MenuPage.current.value = .players;
    Board.backToMenu();
  }

  @override
  Widget build(BuildContext context) {
    final swap2Phase = ref.watch(Swap2.phase);
    final swap2Visible = ref.watch(Swap2.optionsVisible);
    final isTutorialDone = ref.watch(tutorialDone);
    final isGoMode = ref.watch(goMode);
    final isGameOver = ref.watch(gameOver);

    final List<Widget> options;
    late final click = switch (defaultTargetPlatform) {
      .android || .iOS || .fuchsia => 'Tap',
      .linux || .macOS || .windows => 'Click',
    };
    if (!isTutorialDone) {
      options = [
        const _BoardOverlayText(label: 'Try to get 3 in a row!', onSelect: Board.startNewGame),
        _BoardOverlayText(label: '$click anywhere to start.', onSelect: Board.startNewGame),
      ];
    } else if (swap2Phase == .chooseAfter3 || swap2Phase == .chooseAfter5) {
      if (!swap2Visible) return const SizedBox.shrink();
      options = [
        _BoardOverlayText(
          label: 'Play as ${PlayerMark.o.toString(goMode: isGoMode)}',
          onSelect: () => Swap2.applyColorChoice(.o),
        ),
        _BoardOverlayText(
          label: 'Play as ${PlayerMark.x.toString(goMode: isGoMode)}',
          onSelect: () => Swap2.applyColorChoice(.x),
        ),
        if (swap2Phase == .chooseAfter3)
          const _BoardOverlayText(label: 'Add 2 moves', onSelect: Swap2.applyAddTwoMoves),
      ];
    } else if (isGameOver) {
      options = const [
        _BoardOverlayText(label: 'Play again', onSelect: Board.startNewGame),
        _BoardOverlayText(label: 'Back to menu', onSelect: backToMenu),
      ];
    } else {
      return const SizedBox.shrink();
    }

    return FittedBox(
      fit: .scaleDown,
      child: RefPointer(
        (ref) => ref.watch(opacity) > 0.5,
        child: RefOpacity(
          (ref) => ref.watch(opacity),
          child: Column(mainAxisSize: .min, children: options),
        ),
      ),
    );
  }
}

class _BoardOverlayText extends StatelessWidget {
  const _BoardOverlayText({required this.label, required this.onSelect});

  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: .opaque,
      onPanDown: (_) => onSelect(),
      child: Padding(
        padding: const .all(32),
        child: _OutlinedText(label: label.toUpperCase()),
      ),
    );
  }
}

class _OutlinedText extends LeafRenderObjectWidget {
  const _OutlinedText({required this.label});

  final String label;

  @override
  _RenderOutlinedText createRenderObject(BuildContext context) {
    return _RenderOutlinedText(label);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderOutlinedText renderObject) {
    renderObject.label = label;
  }
}

class _RenderOutlinedText extends RenderBox {
  _RenderOutlinedText(this._label) {
    _rebuildPainters();
  }

  static const _fontSize = 48.0;
  static const _strokeWidth = 6.0;

  /// Half the stroke extends outside the text metrics; pad so it isn't clipped.
  static const _strokePad = _strokeWidth / 2;

  String get label => _label;
  String _label;
  set label(String value) {
    if (_label == value) return;
    _label = value;
    _rebuildPainters();
    markNeedsLayout();
  }

  late TextPainter _stroke;
  late TextPainter _fill;

  void _rebuildPainters() {
    _stroke = TextPainter(
      text: TextSpan(
        text: _label,
        style: TextStyle(
          fontFamily: Font.permanentMarker,
          fontSize: _fontSize,
          foreground: Paint()
            ..style = .stroke
            ..strokeWidth = _strokeWidth
            ..strokeJoin = .round
            ..color = const Color(0xFFFFFFFF),
          shadows: const [
            Shadow(blurRadius: 12),
            Shadow(blurRadius: 12),
            Shadow(blurRadius: 12),
            Shadow(blurRadius: 12),
            Shadow(blurRadius: 12),
            Shadow(blurRadius: 12),
          ],
        ),
      ),
      textAlign: .center,
      textDirection: .ltr,
    );
    _fill = TextPainter(
      text: TextSpan(
        text: _label,
        style: const TextStyle(
          fontFamily: Font.permanentMarker,
          fontSize: _fontSize,
          color: Black(),
        ),
      ),
      textAlign: .center,
      textDirection: .ltr,
    );
  }

  double _maxTextWidthFor(double maxWidth) {
    if (!maxWidth.isFinite) return double.infinity;
    return math.max(0.0, maxWidth - _strokePad * 2);
  }

  Size _layoutPainters({double maxWidth = double.infinity}) {
    final textMaxWidth = _maxTextWidthFor(maxWidth);
    _stroke.layout(maxWidth: textMaxWidth);
    _fill.layout(maxWidth: textMaxWidth);
    return Size(_fill.width + _strokePad * 2, _fill.height + _strokePad * 2);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _layoutPainters().width;

  @override
  double computeMaxIntrinsicWidth(double height) => _layoutPainters().width;

  @override
  double computeMinIntrinsicHeight(double width) => _layoutPainters(maxWidth: width).height;

  @override
  double computeMaxIntrinsicHeight(double width) => _layoutPainters(maxWidth: width).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    // Ephemeral painters so dry layout has no lasting side effects.
    final textMaxWidth = _maxTextWidthFor(constraints.maxWidth);
    final fill = TextPainter(text: _fill.text, textAlign: .center, textDirection: .ltr)
      ..layout(maxWidth: textMaxWidth);
    return constraints.constrain(Size(fill.width + _strokePad * 2, fill.height + _strokePad * 2));
  }

  @override
  void performLayout() {
    size = constraints.constrain(_layoutPainters(maxWidth: constraints.maxWidth));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final textOffset = offset.translate(
      (size.width - _fill.width) / 2,
      (size.height - _fill.height) / 2,
    );
    _stroke.paint(context.canvas, textOffset);
    _fill.paint(context.canvas, textOffset);
  }

  @override
  bool hitTestSelf(Offset position) => true;
}
