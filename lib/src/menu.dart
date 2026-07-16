import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/rules/connect6.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';
import 'package:tic_tac_go/src/rules/swap2.dart';
import 'package:tic_tac_go/src/tap_detector.dart';

class MainContent extends StatelessWidget {
  const MainContent({super.key});

  static double _boardAspectRatio(Ref ref) =>
      ref.select(Board.state, (data) => data.cols / data.rows);

  @override
  Widget build(BuildContext context) {
    return _MainContentLayout(
      menu: Menu(),
      board: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: .all(constraints.biggest.shortestSide / 32),
            child: const RefAspectRatio(_boardAspectRatio, child: Board()),
          );
        },
      ),
      bottomBar: const BottomBar(),
    );
  }
}

class _MainContentLayout extends RefLayout {
  const _MainContentLayout({required this.board, required this.menu, required this.bottomBar});

  final Widget board;
  final Widget menu;
  final Widget bottomBar;

  @override
  RefLayoutState<_MainContentLayout> createState() => _MainContentLayoutState();
}

class _MainContentLayoutState extends RefLayoutState<_MainContentLayout> {
  late final board = delegate((widget) => widget.board);
  late final menu = delegate((widget) => widget.menu);
  late final bottomBar = delegate((widget) => widget.bottomBar);

  @override
  void performLayout(LayoutRef ref) {
    final t = Curves.easeInOutCubic.transform(ref.watch(playingTransition));
    const sizeAdjustment = Offset(0, BottomBar.height);

    var menuSize = (ref.constraints.biggest - sizeAdjustment) as Size;
    final contentConstraints = BoxConstraints.loose(menuSize);

    final extraHeight = menuSize.height - menuSize.width;
    const minWidth = 900.0;
    const minExtraHeight = -400.0;
    const maxExtraHeight = 300.0;
    if (extraHeight > maxExtraHeight) {
      menuSize = Size(menuSize.width, menuSize.width + maxExtraHeight);
    } else if (extraHeight < minExtraHeight) {
      menuSize = Size(math.max(menuSize.height - minExtraHeight, minWidth), menuSize.height);
    }

    final boardSize = board.layout(constraints: contentConstraints);
    var Size(:width, :height) = Size.lerp(menuSize, boardSize, t)! + sizeAdjustment;
    width = math.max(width, BottomBar.minWidth);
    ref.size = Size(width, height);

    bottomBar.layoutAlign(.bottomCenter, size: Size(width, BottomBar.height));
    menu.layoutRect(
      Offset(-menuSize.width, (boardSize.height - menuSize.height) / 2) * t & menuSize,
    );
    board.offset = Offset(
      ((menuSize.width - boardSize.width) / 2 + menuSize.width) * (1 - t) +
          (width - boardSize.width) * t / 2,
      (menuSize.height - boardSize.height) / 2 * (1 - t),
    );
  }
}

/// Back chevron / Esc: leave play or go to the previous menu page.
void goBack([_, _]) {
  if (playing.value) return Board.backToMenu();

  final page = MenuPage.current;
  if (page.value.index == 0) return;

  page.value = MenuPage.values[page.value.index - 1];
  BottomBar.backTransition.reverse(from: 1);
}

/// Center strip / Enter: next menu page, start game, or toggle swap2 options.
void primaryAction([_, _]) {
  if (playing.value) {
    if (Swap2.isChoosing) {
      Swap2.toggleOptionsView();
    }
    return;
  }

  switch (MenuPage.current.value) {
    case .players:
      MenuPage.current.value = .boardSize;
    case .boardSize:
      MenuPage.current.value = .rules;
    case .rules:
      playing.value = true;
      Board.startNewGame();
  }
}

class BottomBar extends StatelessWidget {
  const BottomBar({super.key});

  static const height = 48.0;
  static const minWidth = 392.0;

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

  static final undoTransition = Get.vsync(duration: const Duration(milliseconds: 400));
  static final backTransition = Get.vsync();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      mainAxisAlignment: .center,
      children: [
        TapDetector(
          goBack,
          child: SizedBox.square(
            dimension: height,
            child: RepaintBoundary(
              child: RefPaint((ref) {
                final t = Curves.easeInSine.transform(ref.watch(backTransition));
                final disappearing = ref.select(MenuPage.current, (page) => page == .players);
                final PaintRef(:canvas, size: Size(:width, :height)) = ref;
                const strokeWidth = 5.0;
                const xPad = 16.0;
                const yPad = 12.0;

                final strokePaint = Paint()
                  ..style = .stroke
                  ..strokeWidth = strokeWidth
                  ..strokeCap = .round
                  ..color = Black(disappearing ? t : 1);
                canvas
                  ..translate(-t * 10, 0)
                  ..drawPath(
                    Path()
                      ..moveTo(width - xPad, yPad)
                      ..lineTo(xPad, height / 2)
                      ..lineTo(width - xPad, height - yPad),
                    strokePaint,
                  );
              }),
            ),
          ),
        ),
        TapDetector(
          Board.undo,
          child: SizedBox.square(
            dimension: height,
            child: RepaintBoundary(
              child: RefPaint((ref) {
                final PaintRef(:canvas, :size) = ref;
                const strokeWidth = 5.0;
                const arrowWidth = 12.0;

                final t = ref.watch(undoTransition);
                const shrinkTime = 1 / 3;
                final double shrinkProgress = Curves.easeInSine.transform(
                  math.min(t / shrinkTime, 1),
                );
                double growProgress = Curves.ease.transform(
                  math.max((t - shrinkTime) / (1 - shrinkTime), 0),
                );

                final canUndo = ref.watch(Board.canUndo);
                final playingAlpha = math.max(ref.watch(playingTransition) * 2 - 1, 0.0);
                final paint = Paint()
                  ..color = Black(
                    canUndo
                        ? playingAlpha
                        : undoTransition.isActive
                        ? 1 - growProgress
                        : 0.0,
                  );
                if (!canUndo) growProgress = 0;
                final Offset(:dx, :dy) = size.center(Offset.zero);
                final angle = (5 / 12 - growProgress) * 2 * math.pi;
                final transform = Matrix4.identity()
                  ..translateByDouble(dx, dy, 0, 1)
                  ..rotateZ(angle)
                  ..translateByDouble(-dx, -dy, 0, 1);

                final arcRect = (Offset.zero & size).deflate(strokeWidth + arrowWidth / 2);
                // [Board.canUndo] also depends on Swap2 phase and human side.
                ref.watch(Swap2.phase);

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
                    -math.pi * 3 / 2 * (shrinkProgress - growProgress),
                    -math.pi * 3 / 2 * (1 - shrinkProgress + growProgress),
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
        ),
        Expanded(
          child: TapDetector(
            primaryAction,
            child: RefBuilder((context) {
              final player = ref.watch(Board.turn);
              final ruleset = ref.watch(Ruleset.current);
              // Use Ruleset.current inside the selector: RefElement pins the first
              // select() closure, so a captured [ruleset] would go stale.
              final (winner, isDraw) = ref.select(
                Board.state,
                (data) => (data.winner(Ruleset.current.value), data.isBoardFull),
              );
              final menuPage = ref.watch(MenuPage.current);
              final t = ref.watch(playingTransition);
              final isGoMode = ref.watch(goMode);
              final playerText = (winner ?? player).toString(goMode: isGoMode).toUpperCase();
              final human = ref.watch(Board.humanPlayer);
              final usersTurn = human != null && player == human;
              final swap2Phase = ref.watch(Swap2.phase);
              final swap2OptionsVisible = ref.watch(Swap2.optionsVisible);

              final TextSpan textSpan;
              if (t < 0.5) {
                textSpan = switch (menuPage) {
                  .players || .boardSize => const TextSpan(text: 'NEXT'),
                  .rules => const TextSpan(
                    text: 'PLAY  ',
                    children: [
                      WidgetSpan(
                        alignment: .middle,
                        child: SizedBox(
                          width: 16 * root3over2,
                          height: 16,
                          child: RefPaint(_playArrow),
                        ),
                      ),
                    ],
                  ),
                };
              } else if (swap2Phase == .chooseAfter3 || swap2Phase == .chooseAfter5) {
                textSpan = TextSpan(text: swap2OptionsVisible ? 'VIEW BOARD' : 'VIEW OPTIONS');
              } else if (swap2Phase == .opening3 || swap2Phase == .extra2) {
                final total = swap2Phase == .extra2 ? 2 : 3;
                final done = ref.watch(Swap2.placedInPhase);
                textSpan = TextSpan(text: 'BEGIN: ${done + 1}/$total');
              } else if (ruleset == .connect6 && winner == null && !isDraw) {
                final placed = ref.watch(Connect6.stonesThisTurn);
                final total = Connect6.stonesNeeded(player, ref.watch(Board.state));

                textSpan = TextSpan(
                  text: total > 1
                      ? '$playerText: ${placed + 1}/$total'
                      : usersTurn
                      ? 'YOUR MOVE'
                      : "$playerText'S MOVE",
                );
              } else {
                textSpan = TextSpan(
                  text: winner != null
                      ? '$playerText WINS!'
                      : isDraw
                      ? 'DRAW!'
                      : usersTurn
                      ? 'YOUR MOVE'
                      : "$playerText'S MOVE",
                );
              }

              return Text.rich(
                textSpan,
                style: TextStyle(fontSize: 24, color: Black((2 * t - 1).abs())),
                textAlign: .center,
              );
            }),
          ),
        ),
        const SizedBox(width: 48),
        TapDetector(
          (_, _) => goMode.toggle(),
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

  static final GetValue<MenuPage> current = Get.it(players)
    ..hooked.addListener(() {
      if (current.value != .rules) return;

      switch (Ruleset.current.value) {
        case .gomoku || .swap2:
          return;
        case .renju:
          if (Board.state.value case BoardData(rows: >= 5, cols: >= 5)) return;
        case .connect6:
          if (Board.state.value case BoardData(rows: >= 6, cols: >= 6)) return;
      }

      Ruleset.current.value = .gomoku;
    });
}

class Menu extends RefWidget {
  const Menu({super.key});

  static Widget _boardSize(BuildContext context) {
    return TapDetector(
      (position, size) async {
        final Offset(:dx, :dy) = position;
        final Size(:width, :height) = size;
        Board.state
          ..cols = (dx / width * 19).ceil()
          ..rows = (dy / height * 19).ceil();
      },
      respondToDrag: true,
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
    const tinySpace = TextSpan(text: ' ', style: TextStyle(fontSize: 4));
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$cols'),
          tinySpace,
          TextSpan(text: 'x'),
          tinySpace,
          TextSpan(text: '$rows'),
        ],
      ),
      style: TextStyle(fontFamily: Font.patrickHand, fontWeight: .w600, fontSize: 18),
    );
  }

  static Widget _option({
    required String label,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return TapDetector(
      (_, _) => onSelect(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Black(selected ? 0 : 0.1),
          border: selected
              ? BoxBorder.symmetric(horizontal: BorderSide(color: Black(0.1), width: 4))
              : null,
        ),
        child: Padding(
          padding: const .symmetric(vertical: 32),
          child: Center(child: Text(label.toUpperCase())),
        ),
      ),
    );
  }

  static Widget _radioGroup<T>({
    required String title,
    required Iterable<T> values,
    required String Function(T value) labelOf,
    required bool Function(T value) isSelected,
    required ValueChanged<T> onSelect,
  }) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        SizedBox(width: 185, child: Text(title, style: const TextStyle(fontSize: 28))),
        const SizedBox(height: 6),
        for (final value in values)
          TapDetector(
            (_, _) => onSelect(value),
            child: Row(
              mainAxisSize: .min,
              spacing: 14,
              children: [
                SizedBox.square(
                  dimension: 15,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: .circle,
                      color: isSelected(value) ? Colors.black : null,
                      border: .all(color: const Black(), width: 2),
                    ),
                  ),
                ),
                Text(
                  labelOf(value),
                  style: const TextStyle(fontFamily: Font.patrickHand, fontSize: 22),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Widget _players(BuildContext context) {
    final difficulty = ref.watch(Difficulty.current);
    final isTwoPlayer = difficulty == null;
    return Column(
      spacing: 4,
      children: [
        if (!isTwoPlayer)
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 16),
                Expanded(
                  child: Center(
                    child: RefBuilder((context) {
                      final selection = ref.watch(PlayerMark.userSelection);
                      final isGoMode = ref.watch(goMode);
                      return _radioGroup(
                        title: 'PLAY AS',
                        values: const [...PlayerMark.values, null],
                        labelOf: (option) => option?.toString(goMode: isGoMode) ?? 'Random',
                        isSelected: (option) => selection == option,
                        onSelect: (option) => PlayerMark.userSelection.value = option,
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _radioGroup(
                      title: 'DIFFICULTY',
                      values: Difficulty.values,
                      labelOf: (level) => level.toString(),
                      isSelected: (level) => difficulty == level,
                      onSelect: (level) => Difficulty.selected.value = level,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Spacer(),
        Row(
          children: [
            Expanded(
              child: _option(
                label: '1 player',
                selected: !isTwoPlayer,
                onSelect: () => twoPlayer.value = false,
              ),
            ),
            Expanded(
              child: _option(
                label: '2 players',
                selected: isTwoPlayer,
                onSelect: () => twoPlayer.value = true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _rules(BuildContext context) {
    final ruleset = ref.watch(Ruleset.current);
    final minDimension = ref.select(Board.state, (data) => math.min(data.rows, data.cols));
    final isGoMode = ref.watch(goMode);
    final selected = ruleset.text(minDimension, isGoMode);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: FractionallySizedBox(
            widthFactor: 0.95,
            child: Align(
              alignment: const .xy(-1, 1 / 3),
              child: SingleChildScrollView(
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontFamily: Font.patrickHand,
                    fontSize: 22,
                    color: Black(),
                  ),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    spacing: 12,
                    children: [
                      Text(
                        selected.label.toUpperCase(),
                        style: const TextStyle(fontFamily: Font.permanentMarker, fontSize: 32),
                      ),
                      ...selected.description,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final option in Ruleset.filtered(minDimension))
          if (option.text(minDimension, isGoMode) case (:final label, description: _))
            TapDetector(
              (_, _) => Ruleset.current.value = option,
              child: DecoratedBox(
                decoration: ruleset == option
                    ? BoxDecoration(border: Border.all(width: 4))
                    : BoxDecoration(color: Black(0.1)),
                child: Padding(
                  padding: const .symmetric(vertical: 8.0),
                  child: Center(child: Text.rich(TextSpan(text: label.toUpperCase()))),
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = ref.watch(MenuPage.current);
    final Widget contents = switch (currentPage) {
      .players => RefBuilder(_players),
      .boardSize => const Column(
        mainAxisAlignment: .center,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: 1,
              child: FractionallySizedBox(
                widthFactor: 0.96,
                heightFactor: 0.96,
                child: Builder(builder: _boardSize),
              ),
            ),
          ),
          RefBuilder(_boardSizeLabel),
          SizedBox(height: 8),
        ],
      ),
      .rules => RefBuilder(_rules),
    };
    return Center(
      child: Column(
        children: [
          Row(
            children: [
              for (final page in MenuPage.values)
                Expanded(
                  child: TapDetector(
                    (_, _) => MenuPage.current.value = page,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Black(page == currentPage ? 0 : 0.1)),
                      child: Padding(
                        padding: const .symmetric(vertical: 5.0),
                        child: Center(
                          child: Text(
                            page.label.toUpperCase(),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(child: contents),
        ],
      ),
    );
  }
}
