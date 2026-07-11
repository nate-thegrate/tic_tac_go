import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:meta/meta.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/menu.dart';

enum PlayerMark {
  x,
  o;

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

  String get goMode => switch (this) {
    x => 'Black',
    o => 'White',
  };

  @override
  String toString({bool goMode = false}) => goMode ? this.goMode : name.toUpperCase();
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

  static final _winningRunCache = Expando<List<(int row, int col)>>();

  /// The first winning run found, if any.
  ///
  /// Returns `[(-1, -1)]` if the game is a draw.
  List<(int row, int col)>? winningRun(Ruleset ruleset) {
    if (_winningRunCache[this] case final cached?) {
      return cached.isEmpty ? null : cached;
    }

    final needed = ruleset.winLength(this);

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final mark = _list[row][col];
        if (mark == null) continue;

        for (final (dRow, dCol) in directions) {
          final endRow = row + (needed - 1) * dRow;
          final endCol = col + (needed - 1) * dCol;
          if (endRow < 0 || endRow >= rows || endCol < 0 || endCol >= cols) continue;

          var won = true;
          for (var i = 1; i < needed; i++) {
            if (_list[row + i * dRow][col + i * dCol] != mark) {
              won = false;
              break;
            }
          }
          if (won) {
            return _winningRunCache[this] = [
              for (var i = 0; i < needed; i++) (row + i * dRow, col + i * dCol),
            ];
          }
        }
      }
    }
    if (isFull) {
      return _winningRunCache[this] = [(-1, -1)];
    }

    _winningRunCache[this] = [];
    return null;
  }

  /// If one of the players has won (by having a number of items in a row, straight or diagonally,
  /// equal to [winLength]), this getter returns that player; returns `null` otherwise.
  PlayerMark? winner(Ruleset ruleset) => switch (winningRun(ruleset)?.firstOrNull) {
    (-1, -1) => null,
    (final row, final col) => _list[row][col],
    null => null,
  };

  bool get isFull {
    for (final row in _list) {
      for (final cell in row) {
        if (cell == null) return false;
      }
    }
    return true;
  }

  /// Whether the game has a winner or the board is completely filled.
  bool isGameOver(Ruleset ruleset) => winner(ruleset) != null || isFull;

  @protected
  @redeclare
  void get length => ();
}

extension on int {
  int get clampedBoardSize => math.min(math.max(this, 3), 19);
}

class BoardState with ChangeNotifier implements ValueListenable<BoardData> {
  BoardState([int rows = 3, int cols = 3])
    : _list = List.generate(rows, (_) => List.filled(cols, null));

  @override
  BoardData get value => _value;
  late BoardData _value = BoardData(_list);
  List<List<PlayerMark?>> _list;

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

  static void undo([_]) {
    if (history.isEmpty) return;
    final (row, col) = history.removeLast();
    state.update(row, col, null);
    turn.value = turn.value.opponent;
  }

  /// Clears the board and starts a new game without leaving play mode.
  static void playAgain([_]) {
    GameEnd.opacity.reset();
    state.clear();
    history.clear();
    turn.value = .x;
    currentMark = null;
  }

  /// Leaves play mode and returns to the setup menu.
  static void backToMenu([_]) async {
    await playingTransition.reverse();
    GameEnd.opacity.reset();
    state.clear();
    history.clear();
    turn.value = .x;
    currentMark = null;
  }

  static (int, int)? currentMark;
  static final playerMarkAnimation = Get.vsync();

  static late final ui.FragmentProgram markerProgram;
  static final _markerShaders = <(Size, Color, double grain), ui.FragmentShader>{};

  static final int _gameSeed = math.Random().nextInt(0x1000);
  static double _rng(int seed) {
    var x = (seed + _gameSeed) * 1103515245 + 12345;
    x = (x ^ (x >> 16)) & 0x7fffffff;
    return x / 0x7fffffff;
  }

  static void drawMarker(
    void Function(Paint paint) draw, {
    required Size size,
    PlayerMark? player,
    required double strokeWidth,
  }) {
    final color = player?.color ?? Colors.black;

    Paint paint({required double grain, double opacity = 1}) {
      final Size(:width, :height) = size;
      final ink = opacity >= 1 ? color : color.withValues(alpha: color.a * opacity);
      final shader = _markerShaders[(size, ink, grain)] ??= markerProgram.fragmentShader()
        ..setFloat(0, width)
        ..setFloat(1, height)
        ..setFloat(2, ink.r)
        ..setFloat(3, ink.g)
        ..setFloat(4, ink.b)
        ..setFloat(5, ink.a)
        ..setFloat(6, devicePixelRatio)
        ..setFloat(7, grain);

      return Paint()
        ..style = .stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = .round
        ..strokeJoin = .round
        ..blendMode = .multiply
        ..shader = shader;
    }

    final double opacity = switch (player) {
      .x => 1,
      .o => 0.2,
      null => 0.4,
    };
    draw(paint(grain: 2));
    draw(paint(grain: 0, opacity: opacity));
  }

  static void paint(PaintRef ref) {
    final board = ref.watch(state);
    final ruleset = ref.watch(Ruleset.current);
    final t = ref.watch(playerMarkAnimation);
    final isGoMode = ref.watch(goMode);
    final inMenu = ref.watch(playingTransition.status).isDismissed;
    final shouldSkipPaint = switch (ref.watch(goModeTransition.status)) {
      .completed => !isGoMode,
      .dismissed => isGoMode,
      .forward || .reverse => false,
    };
    if (inMenu || shouldSkipPaint) return;
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
        const double stretchX = 1.75;
        final highlightCenter = Offset(
          (center.dx - radiusX * 0.075) / stretchX,
          center.dy - radiusY * 0.7,
        );
        final highlightRadius = math.min(radiusX, radiusY) * 0.8;
        final highlightPeak = (isBlack ? 0x48 : 0xFF) / 255.0 * opacity;
        canvas
          ..save()
          ..clipRRect(RRect.fromRectAndRadius(stoneRect, .circular(0x100000)))
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
        canvas.drawShadow(Path()..addOval(shadowRect), Colors.black, elevation, true);
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

      drawMarker(size: size, strokeWidth: minCell * 0.075, (paint) {
        void drawWobblyLine(Offset start, Offset end, {required int seed}) {
          if (minCell < 60) {
            // Don't make it wobbly if the grid is small
            canvas.drawLine(start, end, paint);
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
          canvas.drawPath(path, paint);
        }

        for (var i = 1; i < cols; i++) {
          final x = width * i / cols;
          drawWobblyLine(Offset(x, gridInset), Offset(x, height - gridInset), seed: i);
        }
        for (var i = 1; i < rows; i++) {
          final y = height * i / rows;
          drawWobblyLine(Offset(gridInset, y), Offset(width - gridInset, y), seed: i + 20);
        }
      });

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

          drawMarker(
            (paint) {
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
            },
            size: size,
            player: mark,
            strokeWidth: markWidth,
          );
        }
      }

      if (winningRun case final cells? when !cells.first.$1.isNegative) {
        final (firstRow, firstCol) = cells.first;
        final (lastRow, lastCol) = cells.last;
        var start = Offset((firstCol + 0.5) * cellWidth, (firstRow + 0.5) * cellHeight);
        var end = Offset((lastCol + 0.5) * cellWidth, (lastRow + 0.5) * cellHeight);
        final delta = end - start;
        final padFactor = delta.dx != 0 && delta.dy != 0 ? 0.52 : 0.4;
        final pad = delta / delta.distance * minCell * padFactor;
        start -= pad;
        end += pad;

        drawMarker(size: size, strokeWidth: minCell * 0.05, (paint) {
          canvas.drawLine(start, Offset.lerp(start, end, t)!, paint);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: .opaque,
          onPanDown: (details) async {
            if (playerMarkAnimation.isActive) return;
            final ruleset = Ruleset.current.value;
            if (state.value.isGameOver(ruleset)) {
              GameEnd.opacity.jumpTo(1);
              return;
            }

            final box = context.findRenderObject()! as RenderBox;
            final Size(:width, :height) = box.size;
            final BoardState(:cols, :rows) = state;
            final Offset(:dx, :dy) = details.localPosition;

            final down = (dy / height * rows).floor();
            final across = (dx / width * cols).floor();
            if (down < 0 || down >= rows || across < 0 || across >= cols) return;
            if (state.value[down][across] != null) return;

            state.update(down, across, turn.value);
            final mark = currentMark = (down, across);
            final gameOver = state.value.isGameOver(ruleset);
            gameOver ? history.clear() : history.add(mark);
            playerMarkAnimation.duration = goMode.value
                ? const Duration(milliseconds: 325)
                : const Duration(milliseconds: 225);
            await playerMarkAnimation.forward(from: 0);

            if (gameOver) {
              await Future<void>.delayed(const Duration(milliseconds: 1500));
              if (state.value.isGameOver(ruleset) && GameEnd.opacity.value == 0) {
                GameEnd.opacity.animateTo(1, duration: const Duration(milliseconds: 800));
              }
            } else {
              turn.value = turn.value.opponent;
            }
          },
          child: RefOpacity((ref) => 1 - ref.watch(GameEnd.opacity) / 2, child: RefPaint(paint)),
        ),
        const Positioned.fill(child: GameEnd()),
      ],
    );
  }
}

class GameEnd extends RefWidget {
  const GameEnd({super.key});

  static final opacity = Get.vsyncValue(0.0, curve: Curves.easeOutSine);

  static void backToMenu() {
    MenuPage.current.value = .players;
    Board.backToMenu();
  }

  @override
  Widget build(BuildContext context) {
    final ruleset = ref.watch(Ruleset.current);
    if (ref.select(Board.state, (data) => !data.isGameOver(ruleset))) {
      return const SizedBox.shrink();
    }

    return FittedBox(
      fit: .scaleDown,
      child: RefPointer(
        (ref) => ref.watch(opacity) > 0.5,
        child: RefOpacity(
          (ref) => ref.watch(opacity),
          child: const Column(
            mainAxisSize: .min,
            children: [
              _EndGameOption(label: 'Play again', onSelect: Board.playAgain),
              _EndGameOption(label: 'Back to menu', onSelect: backToMenu),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndGameOption extends StatelessWidget {
  const _EndGameOption({required this.label, required this.onSelect});

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
          fontFamily: 'permanent marker',
          fontSize: _fontSize,
          foreground: Paint()
            ..style = .stroke
            ..strokeWidth = _strokeWidth
            ..strokeJoin = .round
            ..color = Colors.white,
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
        style: TextStyle(fontFamily: 'permanent marker', fontSize: _fontSize, color: Colors.black),
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
