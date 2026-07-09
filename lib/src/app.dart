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

final twoPlayer = Get.it(false);

enum Difficulty {
  easy,
  hard,
  brutal;

  /// The user's chosen difficulty.
  static final current = Get.compute((ref) => ref.watch(twoPlayer) ? null : ref.watch(selected));

  static final selected = Get.it(easy);
}

enum Ruleset {
  gomoku,
  renju,
  swap2,
  connect6;

  static Iterable<Ruleset> filtered(int minBoardDimension) {
    return minBoardDimension >= 6 ? values : values.where((ruleset) => ruleset != .connect6);
  }

  ({String label, String description}) text(int minBoardDimension) => switch (this) {
    gomoku when minBoardDimension == 3 => (label: 'tic-tac-toe', description: ''),
    gomoku => (label: 'gomoku', description: ''),
    renju => (label: 'renju', description: ''),
    swap2 => (label: 'swap 2', description: ''),
    connect6 when minBoardDimension < 6 => throw StateError(
      'Can\'t pick connect6 with board dimension of $minBoardDimension',
    ),
    connect6 => (label: 'connect 6', description: ''),
  };

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

  static Widget _buildGoBoard(BuildContext context) {
    return GetScope(substitutes: {Substitution.value(goMode, true)}, child: const Backdrop());
  }

  static Widget _buildGoReveal(BuildContext context) {
    const revealSoftness = 0.22;
    final progress = ref.watch(goModeTransition);

    return ShaderMask(
      blendMode: .dstIn,
      shaderCallback: (Rect bounds) {
        final softness = revealSoftness;
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
        return gradient.createShader(bounds);
      },
      child: const Builder(builder: _buildGoBoard),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xfff5c782),
        body: Stack(
          fit: .expand,
          children: [
            GetScope(substitutes: {Substitution.value(goMode, false)}, child: const Backdrop()),
            const RefBuilder(_buildGoReveal),
          ],
        ),
      ),
    );
  }
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key});

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
