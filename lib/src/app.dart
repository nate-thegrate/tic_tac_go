import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/menu.dart';

final playing = playingTransition.toggler;
final playingTransition = Get.vsync(duration: const Duration(milliseconds: 175));

final goMode = goModeTransition.toggler;
final goModeTransition = Get.vsync(duration: const Duration(milliseconds: 175));

final devicePixelRatio = WidgetsBinding.instance.renderViews.first.configuration.devicePixelRatio;
const root3over2 = 0.8660254037844386;

enum Ruleset {
  gomoku,
  swap2,
  renju,
  connect6;

  static Iterable<Ruleset> filtered(int minBoardDimension) => values.take(minBoardDimension - 2);

  ({String label, String description}) text(int minBoardDimension, bool isGoMode) {
    late final first = isGoMode ? 'black' : 'X';
    late final second = isGoMode ? 'white' : 'O';
    late final stones = isGoMode ? 'stones' : 'Xs';
    return switch (this) {
      gomoku when minBoardDimension == 3 => (
        label: isGoMode ? '3 in a row' : 'tic-tac-toe',
        description:
            'Players take turns ${isGoMode ? 'placing stones' : 'marking the board'} '
            'until somebody gets three in a row!\n\n'
            '(This is the only available ruleset for a ${Board.state.cols}x${Board.state.rows} board.)',
      ),
      gomoku => (
        label: minBoardDimension == 4 ? '4 in a row' : 'gomoku',
        description:
            'Players take turns ${isGoMode ? 'placing stones' : 'marking the board'} '
            'until somebody has ${minBoardDimension == 4 ? 'four' : 'five'} in a row '
            '(vertically, horizontally, or diagonally).\n\n'
            'No other restrictions apply'
            '${isGoMode ? ': the black player has an advantage since they go first' : ', so the first player has an advantage'}.',
      ),
      swap2 => (
        label: 'swap 2',
        description:
            'First, the $first player makes 3 moves ($first, $second, $first).\n'
            'Afterward, the $second player has 3 options:\n\n'
            '  1. Continue playing\n'
            '  2. Swap: the first player must play as $second and the second player plays as $first\n'
            '  3. Make 2 more moves, and then let the first player decide whether to swap\n\n'
            'Then players take turns as normal until someone gets ${minBoardDimension == 4 ? 'four' : 'five'} in a row.',
      ),
      renju when minBoardDimension < 5 => throw StateError(
        'Can\'t pick connect6 with board dimension of $minBoardDimension',
      ),
      renju => (
        label: 'renju',
        description:
            'Some restrictions apply to the '
            '${isGoMode ? 'black player to offset the advantage of going first' : 'first player to offset their advantage'}:\n\n'
            '  • They can\'t simultaneously form two rows of 3 $stones '
            'if both rows are unblocked on either side\n'
            '  • They can\'t ever simultaneously form two rows of 4 $stones\n'
            '  • They must have exactly 5 in a row in order to win '
            '(6 or more doesn\'t count)',
      ),
      connect6 when minBoardDimension < 6 => throw StateError(
        'Can\'t pick connect6 with board dimension of $minBoardDimension',
      ),
      connect6 => (
        label: 'connect 6',
        description: isGoMode
            ? 'The black player places 1 stone on their first turn. '
                  'From then on, players go back and forth, placing 2 stones each turn.\n\n'
                  'The game ends when a player has 6 in a row.'
            : 'The first player marks a single square with an X. '
                  'From then on, players go back and forth, marking 2 squares at a time.\n\n'
                  'The game ends when a player has 6 in a row.',
      ),
    };
  }

  int winLength(BoardData data) {
    return this == connect6 ? 6 : math.min(math.min(data.rows, data.cols), 5);
  }

  static final current = Get.it(gomoku);
}

class Black extends Color {
  const Black([double alpha = 1.0]) : super.from(alpha: alpha, red: 0, blue: 0, green: 0);
}

Future<void> loadShaders() async {
  final paperMarkerFutures = (
    ui.FragmentProgram.fromAsset('shaders/paper.frag'),
    ui.FragmentProgram.fromAsset('shaders/marker.frag'),
  );

  final backgroundBuffer = await ui.ImmutableBuffer.fromAsset('assets/wood_backdrop.jpg');
  final descriptor = await ui.ImageDescriptor.encoded(backgroundBuffer);
  final codec = await descriptor.instantiateCodec();
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    Backdrop.woodShader = ui.ImageShader(image, .decal, .decal, Matrix4.identity().storage);
  } finally {
    codec.dispose();
    descriptor.dispose();
    backgroundBuffer.dispose();
  }

  final (paper, marker) = await paperMarkerFutures.wait;
  Backdrop.boardPaperShader = paper.fragmentShader();
  Backdrop.backdropPaperShader = paper.fragmentShader();
  Board.markerProgram = marker;
}

class App extends StatelessWidget {
  const App({super.key});

  static Shader _goReveal(ShaderRef ref) {
    final progress = ref.watch(goModeTransition);
    const softness = 0.22;
    final reveal = ui.lerpDouble(-softness, 1.0 + softness, progress)!;
    final start = (reveal - softness).clamp(0.0, 1.0);
    final end = (reveal + softness).clamp(0.0, 1.0);

    final Gradient gradient;
    if (start < end) {
      gradient = LinearGradient(
        begin: .centerLeft,
        end: .centerRight,
        colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        stops: [start, end],
      );
    } else {
      gradient = LinearGradient(
        colors: progress >= 0.5
            ? const [Color(0xFFFFFFFF), Color(0xFFFFFFFF)]
            : const [Color(0x00FFFFFF), Color(0x00FFFFFF)],
      );
    }
    return gradient.createShader(ref.bounds);
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          fit: .expand,
          children: [
            Backdrop(isGoMode: false),
            RefShaderMask(_goReveal, blendMode: .dstIn, child: Backdrop(isGoMode: true)),
          ],
        ),
      ),
    );
  }
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.isGoMode});

  final bool isGoMode;

  static late final ui.ImageShader woodShader;
  static const woodSize = Size(4824.0, 3216.0);
  static late final ui.FragmentShader boardPaperShader;
  static late final ui.FragmentShader backdropPaperShader;

  static void _configureShader(
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
      _configureShader(boardPaperShader, size, const Color(0xFFFAF8F3), grain: 0.06, scale: 0.6);
      canvas.drawRect(Offset.zero & size, Paint()..shader = boardPaperShader);
    }
  }

  static void paintBackdrop(PaintRef ref) {
    final PaintRef(:canvas, :size) = ref;
    final Size(:width, :height) = size;
    if (ref.watch(goMode)) {
      _configureShader(backdropPaperShader, size, const Color(0xFF103018), grain: 0.04, scale: 0.6);
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

  static Path _clipPath(ClipRef ref) {
    if (ref.select(playingTransition.status, (status) => status.isCompleted)) {
      return Path()..addRect(Rect.fromLTRB(0, -1.0E9, 1.0E9, 1.0E9));
    }
    return Path()..addRect(Offset.zero & ref.size);
  }

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      key: GlobalObjectKey(context),
      decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 1)]),
      child: const RepaintBoundary(
        child: RefPaint(
          paint,
          expanded: false,
          child: RefClip.path(_clipPath, child: MainContent()),
        ),
      ),
    );

    Widget layoutBuilder(BuildContext context, BoxConstraints constraints) {
      final maxSize = constraints.biggest;
      final padding = maxSize.shortestSide / 32;

      if (maxSize.width - 2 * padding >= BottomBar.minWidth) {
        return Padding(
          padding: .all(padding),
          child: Center(child: content),
        );
      }

      final maxHeight =
          (maxSize.height - 2 * padding) * BottomBar.minWidth / (maxSize.width - 2 * padding);
      return Padding(
        padding: .all(padding),
        child: FittedBox(
          fit: .fitWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: BottomBar.minWidth,
              maxWidth: BottomBar.minWidth,
              maxHeight: maxHeight,
            ),
            child: content,
          ),
        ),
      );
    }

    return GetScope(
      substitutes: {Substitution.value(goMode, isGoMode)},
      child: RefPaint(
        paintBackdrop,
        child: SafeArea(child: LayoutBuilder(builder: layoutBuilder)),
      ),
    );
  }
}
