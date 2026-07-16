import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/menu.dart';

final playing = playingTransition.toggler;
final playingTransition = Get.vsync(duration: const Duration(milliseconds: 175));

final goMode = goModeTransition.toggler;
final goModeTransition = Get.vsync(duration: const Duration(milliseconds: 175));

final devicePixelRatio = WidgetsBinding.instance.renderViews.first.configuration.devicePixelRatio;
const root3over2 = 0.8660254037844386;

final rng = math.Random();

abstract final class Font {
  static const patrickHand = 'patrick hand';
  static const permanentMarker = 'permanent marker';
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
    final start = ui.clampDouble(reveal - softness, 0.0, 1.0);
    final end = ui.clampDouble(reveal + softness, 0.0, 1.0);

    final Gradient gradient;
    if (start < end) {
      gradient = LinearGradient(
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
    return const Directionality(
      textDirection: .ltr,
      child: DefaultTextStyle(
        style: TextStyle(fontFamily: Font.permanentMarker, fontSize: 22, color: Black()),
        child: AnnotatedRegion(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: .light,
            statusBarBrightness: .dark,
          ),
          child: Stack(
            fit: .expand,
            children: [
              Backdrop(isGoMode: false),
              RefShaderMask(_goReveal, blendMode: .dstIn, child: Backdrop(isGoMode: true)),
            ],
          ),
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
      final pad = maxSize.shortestSide / 32;
      final queryPad = MediaQuery.paddingOf(context);
      final padding = EdgeInsets.fromLTRB(
        math.max(pad, queryPad.left),
        math.max(pad, queryPad.top),
        math.max(pad, queryPad.right),
        math.max(pad, queryPad.bottom),
      );

      const minHeight = 650.0;
      final availableWidth = maxSize.width - padding.left - padding.right;
      final availableHeight = maxSize.height - padding.top - padding.bottom;
      final wideEnough = availableWidth >= BottomBar.minWidth;
      final tallEnough = availableHeight >= minHeight;

      final widthIsTighter = availableWidth * minHeight <= availableHeight * BottomBar.minWidth;

      final Widget widget;
      if (wideEnough && tallEnough) {
        widget = Center(child: content);
      } else if (!wideEnough && (tallEnough || widthIsTighter)) {
        final maxHeight = availableHeight * BottomBar.minWidth / availableWidth;
        widget = FittedBox(
          fit: .fitWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: BottomBar.minWidth,
              maxWidth: BottomBar.minWidth,
              maxHeight: maxHeight,
            ),
            child: content,
          ),
        );
      } else {
        final maxWidth = availableWidth * minHeight / availableHeight;
        widget = FittedBox(
          fit: .fitHeight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minHeight,
              maxHeight: minHeight,
              maxWidth: maxWidth,
            ),
            child: content,
          ),
        );
      }
      return Padding(padding: padding, child: widget);
    }

    return GetScope(
      substitutes: {Substitution.value(goMode, isGoMode)},
      child: RefPaint(paintBackdrop, child: LayoutBuilder(builder: layoutBuilder)),
    );
  }
}
