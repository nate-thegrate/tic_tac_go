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

  int get cols => _list.first.length;
  int get rows => _list.length;

  /// The number of items in a row required to win.
  int get winLength => switch ((smallest: math.min(rows, cols), biggest: math.max(rows, cols))) {
    (smallest: 3, biggest: 3 || 4) => 3,
    (smallest: _, biggest: 4 || 5) => 4,
    (smallest: 3 || 4, biggest: _) => 4,
    _ => 5,
  };

  /// If one of the players has won (by having a number of items in a row, straight or diagonally,
  /// equal to [winLength]), this getter returns that player; returns `null` otherwise.
  PlayerMark? get winner {
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
          if (won) return mark;
        }
      }
    }
    return null;
  }

  @protected
  @redeclare
  void get length => ();
}

extension on int {
  int get clamped => math.min(math.max(this, 3), 19);
}

class BoardState with ChangeNotifier implements ValueListenable<BoardData> {
  BoardState([int width = 3, int height = 3])
    : _list = List.generate(height, (_) => List.filled(width, null));

  @override
  BoardData get value => BoardData(_list);
  List<List<PlayerMark?>> _list;

  int get cols => _list.first.length;
  set cols(int value) {
    value = value.clamped;
    if (value == cols) return;
    final newState = [for (final row in _list) List.generate(value, row.elementAtOrNull)];
    _list = newState;
    notifyListeners();
  }

  int get rows => _list.length;
  set rows(int value) {
    value = value.clamped;
    if (value == rows) return;
    final newState = [
      for (int i = 0; i < value; i++) _list.elementAtOrNull(i) ?? List.filled(cols, null),
    ];
    _list = newState;
    notifyListeners();
  }

  void update(int down, int across, PlayerMark? mark) {
    final oldValue = _list[down][across];
    if (mark == oldValue) return;
    _list[down][across] = mark;
    notifyListeners();
  }

  bool _isValid() {
    if (kDebugMode) {
      final firstSublistLength = _list.first.length;
      for (final (index, row) in _list.indexed.skip(1)) {
        if (row.length != firstSublistLength) {
          throw StateError(
            'First row is $firstSublistLength wide, but row ${index + 1} is ${row.length}',
          );
        }
      }
    }
    return true;
  }

  @protected
  @override
  void notifyListeners() {
    assert(_isValid());
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
          padding: .all(math.min(constraints.maxWidth, constraints.maxHeight) / 32),
          child: const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 1)],
              ),
              child: RefPaint(
                paint,
                expanded: false,
                child: ClipRect(
                  child: BoardMenuWrapper(
                    menu: Menu(),
                    board: RepaintBoundary(child: Board()),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Board extends StatelessWidget {
  const Board({super.key});

  static final state = BoardState();

  static final turn = Get.it(PlayerMark.x);

  static (int, int)? currentMark;
  static final playerMarkAnimation = Get.vsync();

  static late final ui.FragmentProgram markerProgram;
  static final _markerShaders = <(Color, double grain), ui.FragmentShader>{};

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
      // Uniforms are read at raster time, so re-apply them on every draw even for
      // cached shader instances — otherwise a later setFloat on another draw can
      // clobber this ink (most noticeable on the low-alpha cyan "O" pass).
      final shader = _markerShaders[(ink, grain)] ??= markerProgram.fragmentShader();
      shader
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
    final PaintRef(:canvas, :size) = ref;
    final Size(:width, :height) = size;
    final BoardData(:cols, :rows) = board;

    final cellWidth = width / cols;
    final cellHeight = height / rows;
    final minCell = math.min(cellWidth, cellHeight);

    if (ref.watch(goMode)) {
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
      const impactAt = 0.68;

      double heightAboveBoard(double progress) {
        progress = progress.clamp(0.0, 1.0);
        if (progress <= impactAt) {
          return dropHeight * (1 - Curves.easeInQuad.transform(progress / impactAt));
        }
        final bounceT = (progress - impactAt) / (1 - impactAt);
        final bounceHeight = dropHeight * 0.1;
        return bounceHeight * math.sin(bounceT * math.pi) * math.pow(1 - bounceT, 1.25);
      }

      ({PlayerMark mark, Rect stoneRect, Rect shadowRect, double elevation})? layoutStone(
        int row,
        int col,
        PlayerMark mark,
        double progress,
      ) {
        if (progress <= 0) return null;

        final restCenter = intersectionOf(col, row);
        final height = heightAboveBoard(progress);
        final center = restCenter.translate(0, -height);

        return (
          mark: mark,
          stoneRect: .fromCircle(center: center, radius: stoneRadius),
          shadowRect: .fromCircle(center: restCenter, radius: stoneRadius),
          elevation: 2.0 + height * 0.1,
        );
      }

      void drawStone(({PlayerMark mark, Rect stoneRect, Rect shadowRect, double elevation}) stone) {
        final (:mark, :stoneRect, shadowRect: _, elevation: _) = stone;
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

      final stones = <({PlayerMark mark, Rect stoneRect, Rect shadowRect, double elevation})>[];
      ({int row, int col, PlayerMark mark})? fallingStone;
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < cols; col++) {
          final mark = board[row][col];
          if (mark == null) continue;
          if (currentMark == (row, col) && t < 1) {
            fallingStone = (row: row, col: col, mark: mark);
            continue;
          }
          if (layoutStone(row, col, mark, 1) case final stone?) stones.add(stone);
        }
      }
      if (fallingStone case (:final row, :final col, :final mark)?) {
        if (layoutStone(row, col, mark, t) case final stone?) stones.add(stone);
      }

      for (final (:shadowRect, :elevation, mark: _, stoneRect: _) in stones) {
        canvas.drawShadow(Path()..addOval(shadowRect), Colors.black, elevation, true);
      }
      for (final stone in stones) {
        drawStone(stone);
      }
    } else {
      final markWidth = minCell * 0.15;
      final gridInset = minCell * 0.05;

      drawMarker(size: size, strokeWidth: minCell * 0.075, (paint) {
        void drawWobblyLine(Offset start, Offset end, {required int seed}) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = Builder(
      builder: (context) {
        return GestureDetector(
          behavior: .opaque,
          onPanDown: (details) async {
            if (playerMarkAnimation.isActive || state.value.winner != null) return;

            final size = context.size;
            if (size == null || size.isEmpty) return;

            final Size(:width, :height) = size;
            final BoardState(:cols, :rows) = state;

            final across = (details.localPosition.dx / width * cols).floor();
            final down = (details.localPosition.dy / height * rows).floor();
            if (state.value[down][across] != null) return;

            currentMark = (down, across);
            state.update(down, across, turn.value);
            playerMarkAnimation.duration = goMode.value
                ? const Duration(milliseconds: 350)
                : const Duration(milliseconds: 225);
            await playerMarkAnimation.forward(from: 0);
            turn.value = switch (turn.value) {
              .x => .o,
              .o => .x,
            };
          },
          child: const RefPaint(paint),
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          Flexible(
            child: RefAspectRatio(
              (ref) => ref.select(state, (data) => data.cols / data.rows),
              child: board,
            ),
          ),
          RefBuilder((context) {
            final player = ref.watch(turn);
            final winner = ref.select(state, (data) => data.winner);
            final playerText = (winner ?? player).toString(goMode: ref.watch(goMode));
            return Text(
              winner != null ? '$playerText wins!' : ' $playerText\'s move ',
              style: GoogleFonts.permanentMarker(fontSize: 24),
            );
          }),
        ],
      ),
    );
  }
}

class BoardMenuWrapper extends RefLayout {
  const BoardMenuWrapper({super.key, required this.board, required this.menu});

  final Widget board;
  final Widget menu;

  @override
  RefLayoutState<BoardMenuWrapper> createState() => _BoardMenuWrapperState();
}

class _BoardMenuWrapperState extends RefLayoutState<BoardMenuWrapper> {
  late final board = delegate((widget) => widget.board);
  late final menu = delegate((widget) => widget.menu);

  @override
  void performLayout(LayoutRef ref) {
    final t = Curves.easeInOutCubic.transform(ref.watch(playingTransition));
    final maxSize = ref.constraints.biggest;
    menu.layoutRect(Offset.zero & maxSize);
    final boardSize = board.layout();
    menu.offset = Offset(-t * maxSize.width, (boardSize.height - maxSize.height) / 2 * t);
    board.offset = Offset(
      ((maxSize.width - boardSize.width) / 2 + maxSize.width) * (1 - t),
      (maxSize.height - boardSize.height) / 2 * (1 - t),
    );
    ref.size = Size.lerp(maxSize, boardSize, t)!;
  }
}

class Menu extends StatelessWidget {
  const Menu({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: GoogleFonts.permanentMarker(fontSize: 24, color: Colors.black),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text('Board size'),
              FractionallySizedBox(
                widthFactor: 19 / 20,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Builder(
                    builder: (context) {
                      void handleGesture(PositionedGestureDetails details) async {
                        final size = context.size;
                        if (size == null || size.isEmpty) return;

                        final Size(:width, :height) = size;
                        Board.state
                          ..cols = (details.localPosition.dx / width * 19).ceil()
                          ..rows = (details.localPosition.dy / height * 19).ceil();
                      }

                      return GestureDetector(
                        onPanDown: handleGesture,
                        onPanUpdate: handleGesture,
                        child: RefPaint((ref) {
                          final PaintRef(:canvas, size: Size(:width, :height)) = ref;
                          final BoardData(:rows, :cols) = ref.watch(Board.state);

                          final opaque = Paint()..color = Colors.black;
                          final translucent = Paint()..color = opaque.color.withValues(alpha: 0.25);
                          for (var row = 0; row < 19; row++) {
                            for (var col = 0; col < 19; col++) {
                              canvas.drawRect(
                                Rect.fromLTWH(
                                  width * col / 19,
                                  height * row / 19,
                                  width / 19,
                                  height / 19,
                                ).deflate(width / 150),
                                row < rows && col < cols ? opaque : translucent,
                              );
                            }
                          }
                        }),
                      );
                    },
                  ),
                ),
              ),
              RefBuilder((context) {
                return Text(
                  'Get ${ref.select(Board.state, (data) => data.winLength)} in a row to win',
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
