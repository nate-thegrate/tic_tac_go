import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';

enum PlayerMark {
  x,
  o;

  @override
  String toString() => name.toUpperCase();
}

class BoardState with ChangeNotifier implements ValueNotifier<List<List<PlayerMark?>>> {
  BoardState([int width = 3, int height = 3])
    : _state = List.generate(height, (_) => List.filled(width, null));

  @override
  List<List<PlayerMark?>> get value => UnmodifiableListView(_state.map(UnmodifiableListView.new));
  List<List<PlayerMark?>> _state;
  @override
  set value(List<List<PlayerMark?>> state) {
    _state = state;
    notifyListeners();
  }

  int get width => _state.first.length;
  set width(int value) {
    if (value == width) return;
    final newState = [
      for (final row in _state) [for (int i = 0; i < value; i++) row.elementAtOrNull(i)],
    ];
    _state = newState;
    notifyListeners();
  }

  int get height => _state.length;
  set height(int value) {
    if (value == height) return;
    final newState = [
      for (int i = 0; i < value; i++) _state.elementAtOrNull(i) ?? List.filled(width, null),
    ];
    _state = newState;
    notifyListeners();
  }

  void update(int down, int across, PlayerMark? mark) {
    across -= 1;
    down -= 1;

    final oldValue = _state[down][across];
    if (mark == oldValue) return;
    _state[down][across] = mark;
    notifyListeners();
  }

  bool _isValid() {
    if (kDebugMode) {
      final firstSublistLength = _state.first.length;
      for (final (index, row) in _state.indexed.skip(1)) {
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
    for (final row in _state) '  ${[for (final spot in row) spot ?? '_'].join(' ')}',
    '])',
  ].join('\n');
}

class Board extends RefWidget {
  const Board({required this.dimensions, super.key});

  final (int, int) dimensions;

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
    final board = GestureDetector(
      behavior: .opaque,
      child: RefPaint((ref) {
        // final board = ref.watch(state);
        final PaintRef(:canvas, size: Size(:width, :height)) = ref;
        final dimension = math.min(width, height);
        const radius = 0.025;
        final paint = Paint()
          ..color = Colors.black
          ..style = .stroke
          ..strokeWidth = radius * 2
          ..strokeCap = .round;

        canvas
          ..save()
          ..transform(Matrix4.diagonal3Values(dimension, dimension, 1).storage)
          ..drawLine(Offset(radius, radius), Offset(1 - radius, 1 - radius), paint)
          ..drawLine(Offset(1 - radius, radius), Offset(radius, 1 - radius), paint)
          ..restore();
      }),
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
