import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/difficulty.dart';

class MainContent extends StatelessWidget {
  const MainContent({super.key});

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
          onPanDown: (_) {
            Board.reset();
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
              final ruleset = ref.watch(Ruleset.current);
              final (winner, isDraw) = ref.select(
                Board.state,
                (data) => (data.winner(ruleset), data.isFull),
              );
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
                  text: winner != null
                      ? '$playerText wins!'
                      : isDraw
                      ? 'DRAW!'
                      : ' $playerText\'s move ',
                );
              }

              return Text.rich(
                textSpan,
                style: TextStyle(
                  fontFamily: 'permanent marker',
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
      children: [
        Flexible(
          child: _MainContentLayout(
            menu: Menu(),
            board: RefAspectRatio(
              (ref) => ref.select(Board.state, (data) => data.cols / data.rows),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Padding(
                    padding: .all(constraints.biggest.shortestSide / 32),
                    child: const Board(),
                  );
                },
              ),
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
      ((maxSize.width - boardSize.width) / 2 + maxSize.width + glowSpread) * (1 - t),
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
            ..color = const Black()
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
            ..color = const Black()
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

  static Widget _boardSizeLabel(BuildContext context) {
    final (rows, cols) = ref.select(Board.state, (data) => (data.rows, data.cols));
    return Text('${cols}x$rows', style: TextStyle(fontWeight: .w600, fontSize: 16));
  }

  static Widget _option({
    required String label,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: .opaque,
        onPanDown: (_) => onSelect(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Black(selected ? 0 : 0.1),
            border: selected
                ? BoxBorder.symmetric(horizontal: BorderSide(color: Black(0.1), width: 4))
                : null,
          ),
          child: Padding(
            padding: const .symmetric(vertical: 8.0),
            child: Center(
              child: Text(label.toUpperCase(), style: const TextStyle(fontFamily: 'permanent marker', fontSize: 22)),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _radioOption({
    required String label,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return GestureDetector(
      behavior: .opaque,
      onPanDown: (_) => onSelect(),
      child: Row(
        mainAxisSize: .min,
        spacing: 14,
        children: [
          SizedBox.square(
            dimension: 15,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: .circle,
                color: selected ? Colors.black : null,
                border: .all(color: const Black(), width: 2),
              ),
            ),
          ),
          Text(label, style: const TextStyle(fontFamily: 'permanent marker', fontSize: 22)),
        ],
      ),
    );
  }

  static Widget _players(BuildContext context) {
    final difficulty = ref.watch(Difficulty.current);
    final isTwoPlayer = difficulty == null;
    return Column(
      spacing: 4,
      children: [
        Spacer(),
        Row(
          children: [
            _option(
              label: '1 player',
              selected: !isTwoPlayer,
              onSelect: () => twoPlayer.value = false,
            ),
            _option(
              label: '2 players',
              selected: isTwoPlayer,
              onSelect: () => twoPlayer.value = true,
            ),
          ],
        ),
        if (!isTwoPlayer)
          Expanded(
            child: Align(
              alignment: .xy(0, -0.75),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  for (final level in Difficulty.values)
                    _radioOption(
                      label: level.name.toUpperCase(),
                      selected: difficulty == level,
                      onSelect: () => Difficulty.selected.value = level,
                    ),
                ],
              ),
            ),
          )
        else
          Spacer(),
      ],
    );
  }

  static Widget _rules(BuildContext context) {
    final ruleset = ref.watch(Ruleset.current);
    final minDimension = ref.select(Board.state, (data) => math.min(data.rows, data.cols));
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final option in Ruleset.filtered(minDimension))
          if (option.text(minDimension) case (:final label, :final description))
            Expanded(
              child: GestureDetector(
                behavior: .opaque,
                onPanDown: (_) => Ruleset.current.value = option,
                child: DecoratedBox(
                  decoration: ruleset == option
                      ? BoxDecoration(border: Border.all(width: 4))
                      : BoxDecoration(color: Black(0.1)),
                  child: Padding(
                    padding: const .symmetric(vertical: 8.0),
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          text: label.toUpperCase(),
                          children: [TextSpan(text: '\n$description')],
                        ),
                        style: const TextStyle(fontFamily: 'permanent marker', fontSize: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = ref.watch(MenuPage.current);
    final List<Widget> contents = switch (currentPage) {
      .players => const [Expanded(child: RefBuilder(_players))],
      .boardSize => const [
        Flexible(
          child: AspectRatio(aspectRatio: 1, child: Builder(builder: _boardSize)),
        ),
        RefBuilder(_boardSizeLabel),
      ],
      .rules => const [Expanded(child: RefBuilder(_rules))],
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
                          child: Text(
                            page.label.toUpperCase(),
                            style: const TextStyle(fontFamily: 'permanent marker', fontSize: 18),
                          ),
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
