import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meta/meta.dart';

enum PlayerMark {
  x,
  o;

  Color get color => switch (this) {
    x => const Color(0xFFFF6010),
    o => const Color(0xFF0098A0),
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

class Board extends StatelessWidget {
  const Board({super.key});

  static final state = BoardState()
    ..update(0, 0, .o)
    ..update(1, 1, .x);

  static final turn = Get.it(PlayerMark.x);

  static (int, int)? currentMark;
  static final playerMarkAnimation = Get.vsync();

  static late final ui.FragmentShader paperShader;
  static late final ui.FragmentProgram markerProgram;
  static final _markerShaders = <(Color, double grain), ui.FragmentShader>{};

  static Future<void> loadShaders() async {
    final (paper, marker) = await (
      ui.FragmentProgram.fromAsset('shaders/paper.frag'),
      ui.FragmentProgram.fromAsset('shaders/marker.frag'),
    ).wait;
    paperShader = paper.fragmentShader();
    markerProgram = marker;
  }

  static final _devicePixelRatio =
      WidgetsBinding.instance.renderViews.first.configuration.devicePixelRatio;

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
      final shader = _markerShaders[(ink, grain)] ??= markerProgram.fragmentShader()
        ..setFloat(0, width)
        ..setFloat(1, height)
        ..setFloat(2, ink.r)
        ..setFloat(3, ink.g)
        ..setFloat(4, ink.b)
        ..setFloat(5, ink.a)
        ..setFloat(6, _devicePixelRatio)
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
    final PaintRef(:canvas, :size) = ref;
    final Size(:width, :height) = size;
    final BoardData(:cols, :rows) = board;
    if (cols <= 0 || rows <= 0) return;

    final cellWidth = width / cols;
    final cellHeight = height / rows;
    final minCell = math.min(cellWidth, cellHeight);
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
          final jitter = i == count ? 0.0 : (_rng(seed + i * 17) - 0.5) * 0.015 * minCell * falloff;
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
    final t = ref.watch(playerMarkAnimation);

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

    final child = Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 1, spreadRadius: 1)],
        ),
        child: RefPaint(
          (ref) {
            final PaintRef(:canvas, :size) = ref;
            const baseColor = Color(0xFFFAF8F3);

            paperShader
              ..setFloat(0, size.width)
              ..setFloat(1, size.height)
              ..setFloat(2, baseColor.r)
              ..setFloat(3, baseColor.g)
              ..setFloat(4, baseColor.b)
              ..setFloat(5, baseColor.a)
              ..setFloat(6, 0.06)
              ..setFloat(7, 0.6)
              ..setFloat(8, _devicePixelRatio);
            canvas.drawRect(Offset.zero & size, Paint()..shader = paperShader);
          },
          expanded: false,
          child: Padding(
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
                  return Text(
                    ' ${ref.watch(turn)}\'s move ',
                    style: GoogleFonts.permanentMarker(fontSize: 24),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: .all(math.min(constraints.maxWidth, constraints.maxHeight) / 32),
        child: child,
      ),
    );
  }
}
