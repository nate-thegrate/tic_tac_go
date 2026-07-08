import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meta/meta.dart';
import 'package:tic_tac_go/app.dart';

enum PlayerMark {
  x,
  o;

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

  /// The number of items in a row required to win.
  int get winLength => math.min(math.min(rows, cols), 5);

  static final _winningRunCache = Expando<List<(int row, int col)>>();

  /// The first winning run found, if any.
  List<(int row, int col)>? get winningRun {
    if (_winningRunCache[this] case final cached?) {
      return cached.isEmpty ? null : cached;
    }

    final needed = winLength;
    const directions = [
      (0, 1), // horizontal →
      (1, 0), // vertical ↓
      (1, 1), // diagonal ↘
      (1, -1), // diagonal ↙
    ];

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
    _winningRunCache[this] = [];
    return null;
  }

  /// If one of the players has won (by having a number of items in a row, straight or diagonally,
  /// equal to [winLength]), this getter returns that player; returns `null` otherwise.
  PlayerMark? get winner => switch (winningRun?.firstOrNull) {
    (final row, final col) => _list[row][col],
    null => null,
  };

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

class BoardTextures extends StatelessWidget {
  const BoardTextures({super.key});

  static late final ui.ImageShader woodShader;
  static const woodSize = Size(4824.0, 3216.0);
  static late final ui.FragmentShader boardPaperShader;
  static late final ui.FragmentShader backdropPaperShader;

  static void _paintPaper(
    ui.FragmentShader shader,
    Size size,
    Color baseColor, {
    required double grain,
    required double scale,
  }) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, baseColor.r)
      ..setFloat(3, baseColor.g)
      ..setFloat(4, baseColor.b)
      ..setFloat(5, baseColor.a)
      ..setFloat(6, grain)
      ..setFloat(7, scale)
      ..setFloat(8, devicePixelRatio);
  }

  static void paint(PaintRef ref) {
    final PaintRef(:canvas, :size) = ref;
    if (ref.watch(goMode)) {
      final Size(:width, :height) = size;
      final Size(width: imageWidth, height: imageHeight) = woodSize;
      final fittedScale = math.max(width / imageWidth, height / imageHeight);
      final dx = (width - imageWidth * fittedScale) / 2;
      final dy = (height - imageHeight * fittedScale) / 2;

      canvas
        ..clipRect(Offset.zero & size)
        ..save()
        ..translate(dx, dy)
        ..scale(fittedScale)
        ..drawRect(Offset.zero & woodSize, Paint()..shader = woodShader)
        ..drawPaint(Paint()..color = Color(0xC0f5c782))
        ..restore();
    } else {
      _paintPaper(boardPaperShader, size, const Color(0xFFFAF8F3), grain: 0.06, scale: 0.6);
      canvas.drawRect(Offset.zero & size, Paint()..shader = boardPaperShader);
    }
  }

  static void paintBackdrop(PaintRef ref) {
    final PaintRef(:canvas, :size) = ref;
    final Size(:width, :height) = size;
    if (ref.watch(goMode)) {
      _paintPaper(backdropPaperShader, size, const Color(0xFF103018), grain: 0.04, scale: 0.6);
      canvas.drawRect(Offset.zero & size, Paint()..shader = backdropPaperShader);
    } else {
      final Size(width: imageWidth, height: imageHeight) = woodSize;
      final fittedScale = math.max(width / imageWidth, height / imageHeight);
      final dx = (width - imageWidth * fittedScale) / 2;
      final dy = (height - imageHeight * fittedScale) / 2;

      canvas
        ..save()
        ..translate(dx, dy)
        ..scale(fittedScale)
        ..drawRect(Offset.zero & woodSize, Paint()..shader = woodShader)
        ..restore()
        ..drawPaint(
          Paint()
            ..color = const Color(0xFF6C4827)
            ..blendMode = .multiply,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefPaint(
      paintBackdrop,
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: .all(constraints.biggest.shortestSide / 32),
          child: const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 1)],
              ),
              child: RepaintBoundary(
                child: RefPaint(paint, expanded: false, child: ClipRect(child: MainContent())),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StoneData {
  StoneData(
    this.row,
    this.col,
    this.mark, {
    required Offset center,
    required double radius,
    required double height,
  }) : rect = .fromCircle(center: center.translate(0, -height), radius: radius),
       shadowRect = .fromCircle(center: center, radius: radius),
       elevation = 2.0 + height * 0.1;

  final int row;
  final int col;
  final PlayerMark mark;
  final Rect rect;
  final Rect shadowRect;
  final double elevation;
}

class Board extends StatelessWidget {
  const Board({super.key});

  static final state = BoardState();
  static final history = Get.list<(int row, int col)>();

  static final turn = Get.it(PlayerMark.x);
  static void switchTurn() {
    turn.value = switch (turn.value) {
      .x => .o,
      .o => .x,
    };
  }

  static void undo([_]) {
    if (history.isEmpty) return;
    final (row, col) = history.removeLast();
    state.update(row, col, null);
    switchTurn();
  }

  static void reset() {}

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
    final t = ref.watch(playerMarkAnimation);
    final isGoMode = ref.watch(goMode);
    final shouldSkipPaint = switch (ref.watch(goModeTransition.status)) {
      .completed => !isGoMode,
      .dismissed => isGoMode,
      .forward || .reverse => false,
    };
    if (shouldSkipPaint) return;

    final PaintRef(:canvas, :size) = ref;
    final Size(:width, :height) = size;
    final BoardData(:cols, :rows) = board;

    final cellWidth = width / cols;
    final cellHeight = height / rows;
    final minCell = math.min(cellWidth, cellHeight);

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
          height = dropHeight * (1 - impactProgress * impactProgress);
        } else {
          final bounceProgress = (progress - impactAt) / (1 - impactAt);
          height = dropHeight * 0.25 * bounceProgress * (1 - bounceProgress);
        }

        return StoneData(
          row,
          col,
          mark,
          center: intersectionOf(col, row),
          height: height,
          radius: stoneRadius,
        );
      }

      void drawStone(StoneData stone) {
        final StoneData(:mark, rect: stoneRect) = stone;
        final isBlack = mark == .x;
        final baseColor = isBlack ? const Color(0xFF101010) : const Color(0xFFE0DCD1);
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
        canvas
          ..save()
          ..clipRRect(RRect.fromRectAndRadius(stoneRect, .circular(0x100000)))
          ..transform(Matrix4.diagonal3Values(stretchX, 1, 1).storage)
          ..drawCircle(
            highlightCenter,
            highlightRadius,
            Paint()
              ..shader = ui.Gradient.radial(highlightCenter, highlightRadius, [
                if (isBlack) const Color(0x48FFFAED) else const Color(0xFFFFFAED),
                const Color(0x00FFFAED),
              ]),
          )
          ..restore();
      }

      final winningCells = {...?board.winningRun};
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
      for (final StoneData(rect: stoneRect, :mark) in stones.where(isWinning)) {
        final Rect(:center) = stoneRect;
        final winnerGlow = mark.winnerGlow;
        final glowRadius = stoneRect.shortestSide / 2 * 1.5;
        canvas.drawCircle(
          center,
          glowRadius,
          Paint()
            ..shader = ui.Gradient.radial(
              center,
              glowRadius,
              [winnerGlow, winnerGlow, winnerGlow.withValues(alpha: 0)],
              const [0.0, 0.7, 1.0],
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

      if (board.winningRun case final cells?) {
        final (firstRow, firstCol) = cells.first;
        final (lastRow, lastCol) = cells.last;
        final start = Offset((firstCol + 0.5) * cellWidth, (firstRow + 0.5) * cellHeight);
        final end = Offset((lastCol + 0.5) * cellWidth, (lastRow + 0.5) * cellHeight);
        final delta = end - start;
        final padFactor = delta.dx != 0 && delta.dy != 0 ? 0.52 : 0.4;
        final pad = delta / delta.distance * minCell * padFactor;

        drawMarker(size: size, strokeWidth: minCell * 0.05, (paint) {
          canvas.drawLine(start - pad, end + pad, paint);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: .opaque,
      onPanDown: (details) async {
        if (playerMarkAnimation.isActive || state.value.winner != null) return;

        final Size(:width, :height) = context.size!;
        final BoardState(:cols, :rows) = state;

        final across = (details.localPosition.dx / width * cols).floor();
        final down = (details.localPosition.dy / height * rows).floor();
        if (state.value[down][across] != null) return;

        history.add(currentMark = (down, across));
        state.update(down, across, turn.value);
        playerMarkAnimation.duration = goMode.value
            ? const Duration(milliseconds: 300)
            : const Duration(milliseconds: 225);
        await playerMarkAnimation.forward(from: 0);
        switchTurn();
      },
      child: const RefPaint(paint),
    );
  }
}

class MainContent extends StatelessWidget {
  const MainContent({super.key});

  static const padding = 12.0;

  static void _playArrow(PaintRef ref) {
    final PaintRef(:canvas, size: Size(:width, :height)) = ref;
    canvas.drawPath(
      Path()
        ..lineTo(width, height / 2)
        ..lineTo(0, height)
        ..close(),
      Paint()..color = Black((ref.watch(playingTransition) * 2 - 1).abs()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomBar = Row(
      mainAxisSize: .min,
      mainAxisAlignment: .center,
      children: [
        GestureDetector(
          behavior: .opaque,
          onPanDown: (details) async {
            await playingTransition.reverse();
            Board.state.clear();
            Board.history.clear();
          },
          child: SizedBox.square(
            dimension: 48,
            child: RefPaint((ref) {
              final PaintRef(:canvas, size: Size(:width, :height)) = ref;
              const strokeWidth = 5.0;
              const xPad = 16.0;
              const yPad = 12.0;

              final strokePaint = Paint()
                ..style = .stroke
                ..strokeWidth = strokeWidth
                ..strokeCap = .round
                ..color = Black(math.max(ref.watch(playingTransition) * 2 - 1, 0));
              canvas.drawPath(
                Path()
                  ..moveTo(width - xPad, yPad)
                  ..lineTo(xPad, height / 2)
                  ..lineTo(width - xPad, height - yPad),
                strokePaint,
              );
            }),
          ),
        ),
        GestureDetector(
          behavior: .opaque,
          onPanDown: Board.undo,
          child: SizedBox.square(
            dimension: 48,
            child: RefPaint((ref) {
              final PaintRef(:canvas, :size) = ref;
              const strokeWidth = 5.0;
              const arrowWidth = 12.0;

              final Offset(:dx, :dy) = size.center(Offset.zero);
              final angle = 5 * math.pi / 6;
              final transform = Matrix4.identity()
                ..translateByDouble(dx, dy, 0, 1)
                ..rotateZ(angle)
                ..translateByDouble(-dx, -dy, 0, 1);

              final arcRect = (Offset.zero & size).deflate(strokeWidth + arrowWidth / 2);
              final playingAlpha = math.max(ref.watch(playingTransition) * 2 - 1, 0.0);
              final hasHistory = ref.select(Board.history, (history) => history.isNotEmpty);
              final paint = Paint()..color = Black(hasHistory ? playingAlpha : 0.0);

              canvas
                ..save()
                ..transform(transform.storage)
                ..drawPath(
                  Path()
                    ..moveTo(size.width / 2, size.height - arrowWidth / 2)
                    ..relativeLineTo(0, -arrowWidth)
                    ..relativeLineTo(arrowWidth * root3over2, arrowWidth / 2)
                    ..close(),
                  paint,
                )
                ..drawArc(
                  arcRect,
                  0,
                  -math.pi * 3 / 2,
                  false,
                  paint
                    ..style = .stroke
                    ..strokeWidth = strokeWidth
                    ..strokeCap = .round,
                )
                ..restore();
            }),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: .opaque,
            onPanDown: (details) {
              switch (MenuPage.current.value) {
                case .players:
                  MenuPage.current.value = .boardSize;
                case .boardSize:
                  MenuPage.current.value = .rules;
                case .rules:
                  playing.value = true;
              }
            },
            child: RefBuilder((context) {
              final player = ref.watch(Board.turn);
              final winner = ref.select(Board.state, (data) => data.winner);
              final menuPage = ref.watch(MenuPage.current);
              final t = ref.watch(playingTransition);
              final playerText = (winner ?? player).toString(goMode: ref.watch(goMode));

              final TextSpan textSpan;
              if (t < 0.5) {
                textSpan = switch (menuPage) {
                  .players || .boardSize => const TextSpan(text: 'NEXT'),
                  .rules => const TextSpan(
                    text: 'Play  ',
                    children: [
                      WidgetSpan(
                        alignment: .middle,
                        child: SizedBox(
                          width: 12 * root3over2,
                          height: 12,
                          child: RefPaint(_playArrow),
                        ),
                      ),
                    ],
                  ),
                };
              } else {
                textSpan = TextSpan(
                  text: winner != null ? '$playerText wins!' : ' $playerText\'s move ',
                );
              }

              return Text.rich(
                textSpan,
                style: GoogleFonts.permanentMarker(
                  fontSize: 24,
                  color: Color.from(alpha: (2 * t - 1).abs(), red: 0, green: 0, blue: 0),
                ),
                textAlign: .center,
              );
            }),
          ),
        ),
        const SizedBox(width: 48),
        GestureDetector(
          onPanDown: (details) {
            goMode.toggle();
          },
          child: SizedBox.square(
            dimension: 48,
            child: RefPaint(
              (ref) {
                ref.canvas.drawRect(
                  Offset.zero & ref.size,
                  Paint()
                    ..color = ref.watch(goMode) ? const Color(0x60FFFFFF) : const Color(0x60F5C782),
                );
              },
              child: Padding(
                padding: const .all(3),
                child: RefPaint((ref) {
                  final PaintRef(:canvas, size: Size(:width, :height)) = ref;
                  if (ref.watch(goMode)) {
                    final paint = Paint()
                      ..style = .stroke
                      ..strokeWidth = 3
                      ..strokeCap = .round;
                    const pad = 4.0;
                    canvas
                      ..drawLine(Offset(width / 3, pad), Offset(width / 3, height - pad), paint)
                      ..drawLine(
                        Offset(width * 2 / 3, pad),
                        Offset(width * 2 / 3, height - pad),
                        paint,
                      )
                      ..drawLine(Offset(pad, height / 3), Offset(width - pad, height / 3), paint)
                      ..drawLine(
                        Offset(pad, height * 2 / 3),
                        Offset(width - pad, height * 2 / 3),
                        paint,
                      );
                  } else {
                    canvas
                      ..drawRect(
                        Rect.fromLTWH(width / 4, height / 4, width / 2, height / 2),
                        Paint()
                          ..style = .stroke
                          ..strokeWidth = 3,
                      )
                      ..drawCircle(
                        Offset(width / 4, height / 4),
                        width / 4,
                        Paint()..color = const Color(0xFF101010),
                      )
                      ..drawCircle(
                        Offset(width * 3 / 4, height * 3 / 4),
                        width / 4,
                        Paint()..color = const Color(0xFFFFFAED),
                      );
                  }
                }),
              ),
            ),
          ),
        ),
      ],
    );

    return Column(
      mainAxisSize: .min,
      spacing: 16,
      children: [
        Flexible(
          child: _MainContentLayout(
            menu: Menu(),
            board: RefAspectRatio(
              (ref) => ref.select(Board.state, (data) => data.cols / data.rows),
              child: Board(),
            ),
          ),
        ),
        bottomBar,
      ],
    );
  }
}

class _MainContentLayout extends RefLayout {
  const _MainContentLayout({required this.board, required this.menu});

  final Widget board;
  final Widget menu;

  @override
  RefLayoutState<_MainContentLayout> createState() => _MainContentLayoutState();
}

class _MainContentLayoutState extends RefLayoutState<_MainContentLayout> {
  late final board = delegate((widget) => widget.board);
  late final menu = delegate((widget) => widget.menu);

  @override
  void performLayout(LayoutRef ref) {
    final maxSize = ref.constraints.biggest;
    final t = Curves.easeInOutCubic.transform(ref.watch(playingTransition));
    final glowSpread = ref.select(Board.state, (data) {
      return math.min(maxSize.width / data.cols, maxSize.height / data.rows) * 0.25;
    });
    menu.layoutRect(Offset.zero & maxSize);
    final boardSize = board.layout();
    menu.offset = Offset(-t * maxSize.width, (boardSize.height - maxSize.height) / 2 * t);
    board.offset = Offset(
      ((maxSize.width - boardSize.width) / 2 + maxSize.width + MainContent.padding + glowSpread) *
          (1 - t),
      (maxSize.height - boardSize.height) / 2 * (1 - t),
    );
    ref.size = Size.lerp(maxSize, boardSize, t)!;
  }
}

enum MenuPage {
  players,
  boardSize,
  rules;

  String get label => switch (this) {
    players || rules => name,
    boardSize => 'board size',
  };

  static final current = Get.it(MenuPage.players);
}

class Menu extends RefWidget {
  const Menu({super.key});

  static Widget _boardSize(BuildContext context) {
    void handleGesture(PositionedGestureDetails details) async {
      final Offset(:dx, :dy) = details.localPosition;
      final Size(:width, :height) = context.size!;
      Board.state
        ..cols = (dx / width * 19).ceil()
        ..rows = (dy / height * 19).ceil();
    }

    return GestureDetector(
      onPanDown: handleGesture,
      onPanUpdate: handleGesture,
      child: RefPaint((ref) {
        final PaintRef(:canvas, size: Size(:width, :height)) = ref;
        final (rows, cols) = ref.select(Board.state, (data) => (data.rows, data.cols));
        final cellWidth = width / 19;
        final cellHeight = height / 19;

        if (ref.watch(goMode)) {
          final linePaint = Paint()
            ..color = const Black(1)
            ..strokeWidth = 2
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
        } else {
          final double strokeWidth = math.max(2, math.min(cellWidth, cellHeight) * 0.1);
          final linePaint = Paint()
            ..color = const Black(1)
            ..strokeWidth = strokeWidth
            ..strokeCap = .round;

          for (var i = 1; i < cols; i++) {
            final x = cellWidth * i;
            canvas.drawLine(
              Offset(x, strokeWidth),
              Offset(x, rows * cellHeight - strokeWidth),
              linePaint,
            );
          }
          for (var i = 1; i < rows; i++) {
            final y = cellHeight * i;
            canvas.drawLine(
              Offset(strokeWidth, y),
              Offset(cols * cellWidth - strokeWidth, y),
              linePaint,
            );
          }
        }

        final translucent = Paint()..color = const Black(0.1);
        for (var row = 0; row < 19; row++) {
          for (var col = 0; col < 19; col++) {
            if (row < rows && col < cols) continue;

            canvas.drawRect(
              Rect.fromLTWH(
                width * col / 19,
                height * row / 19,
                width / 19,
                height / 19,
              ).deflate(1.5),
              translucent,
            );
          }
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = ref.watch(MenuPage.current);
    final List<Widget> contents = switch (currentPage) {
      .players => [],
      .boardSize => [
        const Flexible(
          child: AspectRatio(aspectRatio: 1, child: Builder(builder: _boardSize)),
        ),
        RefBuilder((_) {
          final (rows, cols) = ref.select(Board.state, (data) => (data.rows, data.cols));
          return Text('${cols}x$rows', style: TextStyle(fontWeight: .w600, fontSize: 16));
        }),
      ],
      .rules => [],
    };
    return Center(
      child: Column(
        children: [
          Row(
            children: [
              for (final page in MenuPage.values)
                Expanded(
                  child: GestureDetector(
                    onPanDown: (details) {
                      MenuPage.current.value = page;
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Black(page == currentPage ? 0 : 0.1)),
                      child: Padding(
                        padding: const .symmetric(vertical: 5.0),
                        child: Center(
                          child: Text(page.label, style: GoogleFonts.permanentMarker(fontSize: 18)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          ...contents,
        ],
      ),
    );
  }
}
