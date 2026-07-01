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

  @override
  String toString() => name.toUpperCase();
}

extension type BoardData._(List<List<PlayerMark?>> _list) implements List<List<PlayerMark?>> {
  BoardData(List<List<PlayerMark?>> list)
    : _list = UnmodifiableListView(list.map(UnmodifiableListView.new));

  int get width => _list.first.length;
  int get height => _list.length;

  @protected
  @redeclare
  void get length {}
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

  int get width => _list.first.length;
  set width(int value) {
    if (value == width) return;
    final newState = [
      for (final row in _list) [for (int i = 0; i < value; i++) row.elementAtOrNull(i)],
    ];
    _list = newState;
    notifyListeners();
  }

  int get height => _list.length;
  set height(int value) {
    if (value == height) return;
    final newState = [
      for (int i = 0; i < value; i++) _list.elementAtOrNull(i) ?? List.filled(width, null),
    ];
    _list = newState;
    notifyListeners();
  }

  /// Updates the cell at `[down][across]` using **0-based** row/column indices.
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

class Board extends RefWidget {
  const Board({super.key});

  static final state = BoardState();
  static final turn = Get.it(PlayerMark.x);
  static void mark(int down, int across) async {
    currentMark = (down, across);
    state.update(down, across, turn.value);
    await playerMarkAnimation.forward(from: 0);
    turn.value = switch (turn.value) {
      .x => .o,
      .o => .x,
    };
  }

  static (int, int)? currentMark;
  static final playerMarkAnimation = Get.vsync();

  /// Paper grain is drawn with shaders/paper.frag once it finishes loading.
  static late final ui.FragmentShader paperShader;
  static Future<void> loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/paper.frag');
    Board.paperShader = program.fragmentShader();
  }

  @override
  Widget build(BuildContext context) {
    final board = Builder(
      builder: (context) {
        return GestureDetector(
          behavior: .opaque,
          onPanDown: (details) {
            if (playerMarkAnimation.isActive) return;

            final box = context.findRenderObject()! as RenderBox;
            final Size(:width, :height) = box.size;
            final cols = state.width;
            final rows = state.height;
            if (cols <= 0 || rows <= 0 || width <= 0 || height <= 0) return;

            final across = (details.localPosition.dx / width * cols).floor();
            final down = (details.localPosition.dy / height * rows).floor();
            if (across < 0 || across >= cols || down < 0 || down >= rows) return;

            mark(down, across);
          },
          child: RefPaint((ref) {
            final board = ref.watch(state);
            final PaintRef(:canvas, size: Size(:width, :height)) = ref;
            final cols = board.width;
            final rows = board.height;
            if (cols <= 0 || rows <= 0) return;

            final paint = Paint()
              ..color = Color(0xFF404040)
              ..style = .stroke
              ..strokeWidth = 3
              ..strokeCap = .round;

            for (var i = 1; i < cols; i++) {
              final x = width * i / cols;
              canvas.drawLine(Offset(x, 0), Offset(x, height), paint);
            }
            for (var i = 1; i < rows; i++) {
              final y = height * i / rows;
              canvas.drawLine(Offset(0, y), Offset(width, y), paint);
            }

            final cellWidth = width / cols;
            final cellHeight = height / rows;
            final inset = math.min(cellWidth, cellHeight) * 0.15;
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

                switch (mark) {
                  case .x:
                    _drawX(canvas, rect, paint, progress);
                  case .o:
                    _drawO(canvas, rect, paint, progress);
                }
              }
            }
          }),
        );
      },
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: .cover,
          image: AssetImage('assets/pexels-ksw-photographer-2372420-5467852.jpg'),
        ),
      ),
      child: PaperPadding(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 1, spreadRadius: 1)],
            ),
            child: RefPaint(
              (ref) {
                final PaintRef(:canvas, :size) = ref;
                const baseColor = Color(0xFFFFFFFF);

                // FlutterFragCoord is logical; uDpr maps grain into physical pixels (HiDPI/4K).
                // Uniforms: uSize, uBaseColor (rgba 0-1), uGrain, uScale, uDpr — see shaders/paper.frag
                paperShader
                  ..setFloat(0, size.width)
                  ..setFloat(1, size.height)
                  ..setFloat(2, baseColor.r)
                  ..setFloat(3, baseColor.g)
                  ..setFloat(4, baseColor.b)
                  ..setFloat(5, baseColor.a)
                  ..setFloat(6, 0.04)
                  ..setFloat(7, 0.5)
                  ..setFloat(8, MediaQuery.devicePixelRatioOf(ref.context));
                canvas.drawRect(Offset.zero & size, Paint()..shader = paperShader);
              },
              expanded: false,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: .min,
                  spacing: 8,
                  children: [
                    Flexible(
                      child: RefAspectRatio(
                        (ref) => ref.select(state, (data) => data.width / data.height),
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
        ),
      ),
    );
  }
}

/// Draws an X into [rect], revealing the strokes as [progress] goes 0→1
/// (first diagonal, then the second).
void _drawX(Canvas canvas, Rect rect, Paint paint, double progress) {
  final Rect(:topLeft, :topRight, :bottomLeft, :bottomRight) = rect;

  if (progress < 0.5) {
    final t = progress * 2;
    canvas.drawLine(topLeft, Offset.lerp(topLeft, bottomRight, t)!, paint);
    return;
  }

  canvas.drawLine(topLeft, bottomRight, paint);
  final t = (progress - 0.5) * 2;
  canvas.drawLine(topRight, Offset.lerp(topRight, bottomLeft, t.clamp(0.0, 1.0))!, paint);
}

/// Draws an O into [rect], sweeping the stroke as [progress] goes 0→1.
void _drawO(Canvas canvas, Rect rect, Paint paint, double progress) {
  canvas.drawArc(rect, -math.pi / 2, progress.clamp(0.0, 1.0) * math.pi * 2, false, paint);
}

class PaperPadding extends RefLayout {
  const PaperPadding({super.key, required this.child});

  final Widget child;

  @override
  RefLayoutState<PaperPadding> createState() => _PaperPaddingState();
}

class _PaperPaddingState extends RefLayoutState<PaperPadding> {
  late final child = delegate((widget) => widget.child);

  @override
  void performLayout(LayoutRef ref) {
    final Size(:width, :height) = ref.constraints.biggest;
    child.layoutPadding(.all(math.min(width, height) / 32));
  }
}
