import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
  String toString() => name.toUpperCase();
}

/// A read-only view of the data in [BoardState].
extension type BoardData._(List<List<PlayerMark?>> _list) implements List<List<PlayerMark?>> {
  BoardData(List<List<PlayerMark?>> list)
    : _list = UnmodifiableListView(list.map(UnmodifiableListView.new));

  int get cols => _list.first.length;
  int get rows => _list.length;

  @protected
  @redeclare
  void get length => ();
}

class BoardState with ChangeNotifier implements ValueListenable<BoardData> {
  BoardState([int width = 3, int height = 3])
    : _list = List.generate(height, (_) => List.filled(width, null));

  @override
  BoardData get value => BoardData(_list);
  List<List<PlayerMark?>> _list;
  set value(List<List<PlayerMark?>> list) {
    _list = list;
    notifyListeners();
  }

  int get cols => _list.first.length;
  set cols(int value) {
    if (value == cols) return;
    final newState = [for (final row in _list) List.generate(value, row.elementAtOrNull)];
    _list = newState;
    notifyListeners();
  }

  int get rows => _list.length;
  set rows(int value) {
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

  static void _paintPaper(ui.FragmentShader shader, Size size, Color baseColor, {
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
            ..color = Color(0xFFE7C28B)
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
              child: RepaintBoundary(
                child: RefPaint(
                  paint,
                  expanded: false,
                  child: Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, 6), child: Board()),
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
        ..strokeWidth = math.max(1.0, minCell * 0.03)
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
            final jitter = i == count
                ? 0.0
                : (_rng(seed + i * 17) - 0.5) * 0.015 * minCell * falloff;
            final Offset(:dx, :dy) = point + normal * jitter;
            path.lineTo(dx, dy);
          }
          canvas.drawPath(path, paint);
        }

        for (var i = 1; i < cols; i++) {
          final x = width * i / cols;
          drawWobblyLine(Offset(x, gridInset), Offset(x, height - gridInset), seed: 100 + i * 31);
        }
        for (var i = 1; i < rows; i++) {
          final y = height * i / rows;
          drawWobblyLine(Offset(gridInset, y), Offset(width - gridInset, y), seed: 200 + i * 37);
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
            if (playerMarkAnimation.isActive) return;

            final size = context.size;
            if (size == null || size.isEmpty) return;
            final Size(:width, :height) = size;
            final BoardState(:cols, :rows) = state;

            final across = (details.localPosition.dx / width * cols).floor();
            final down = (details.localPosition.dy / height * rows).floor();

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
            final playerText = ref.watch(goMode) ? player.goMode : player.toString();
            return Text(' $playerText\'s move ', style: GoogleFonts.permanentMarker(fontSize: 24));
          }),
        ],
      ),
    );
  }
}
