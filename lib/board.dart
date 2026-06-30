import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
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

  void update(int down, int across, PlayerMark? mark) {
    across -= 1;
    down -= 1;

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
          throw FlutterError(
            'First row is $firstSublistLength wide, but row ${index + 1} is ${row.length}',
          );
        }
      }
    }
    return true;
  }

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
  static void mark(int down, int across) {
    state.update(down, across, turn.value);
    turn.value = switch (turn.value) {
      .x => .o,
      .o => .x,
    };
  }

  @override
  Widget build(BuildContext context) {
    final board = Builder(
      builder: (context) {
        return GestureDetector(
          behavior: .opaque,
          onTapUp: (details) {
            final box = context.findRenderObject()! as RenderBox;
            final Size(:width, :height) = box.size;
            final cols = state.width;
            final rows = state.height;
            if (cols <= 0 || rows <= 0 || width <= 0 || height <= 0) return;

            final across = (details.localPosition.dx / width * cols).floor() + 1;
            final down = (details.localPosition.dy / height * rows).floor() + 1;
            if (across < 1 || across > cols || down < 1 || down > rows) return;

            mark(down, across);
          },
          child: RefPaint((ref) {
            final board = ref.watch(state);
            final PaintRef(:canvas, size: Size(:width, :height)) = ref;
            final cols = board.width;
            final rows = board.height;
            if (cols <= 0 || rows <= 0) return;

            final stroke = math.min(width / cols, height / rows) * 0.05;
            final paint = Paint()
              ..color = Colors.black
              ..style = .stroke
              ..strokeWidth = stroke
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

                switch (mark) {
                  case .x:
                    canvas
                      ..drawLine(rect.topLeft, rect.bottomRight, paint)
                      ..drawLine(rect.topRight, rect.bottomLeft, paint);
                  case .o:
                    canvas.drawOval(rect, paint);
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
      child: Center(
        child: PaperPadding(
          child: RefPaint(
            (ref) {
              ref.canvas.drawRect(Offset.zero & ref.size, Paint()..color = Colors.white);
            },
            child: Column(
              children: [
                Expanded(flex: 3, child: board),
                Expanded(
                  child: RefBuilder((context) {
                    return FittedBox(child: Text(' ${ref.watch(turn)}\'s move '));
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    child.layoutPadding(.all(math.min(width, height) / 12));
  }
}
