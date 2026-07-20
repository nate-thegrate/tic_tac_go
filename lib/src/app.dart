import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/menu.dart';

final goMode = goModeTransition.toggler;
final goModeTransition = Get.vsync(duration: const Duration(milliseconds: 175));

final playing = playingTransition.toggler;
final playingTransition = Get.vsync(
  initialValue: tutorialDone.value ? 0 : 1,
  duration: const Duration(milliseconds: 175),
);

final tutorialDone = Stored('tutorial', false);

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

  final ByteData(:buffer, :offsetInBytes, :lengthInBytes) = await rootBundle.load(
    'assets/wood_backdrop.jpg',
  );
  final codec = await ui.instantiateImageCodec(buffer.asUint8List(offsetInBytes, lengthInBytes));
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    Backdrop.woodShader = ui.ImageShader(image, .decal, .decal, Matrix4.identity().storage);
  } finally {
    codec.dispose();
  }

  final (paper, marker) = await paperMarkerFutures.wait;
  Backdrop.boardPaperShader = paper.fragmentShader();
  Board.markerProgram = marker;
}

Future<void> configureSystemUi() async {
  WidgetsBinding.instance.addObserver(SystemBackObserver());
  if (defaultTargetPlatform != .android) return;
  await SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
}

class SystemBackObserver with WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() async {
    if (!playing.value && MenuPage.current.value == .players) return false;
    goBack();
    return true;
  }
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
            statusBarColor: Black(0),
            statusBarIconBrightness: .light,
            statusBarBrightness: .dark,
            systemNavigationBarColor: Black(0),
            systemNavigationBarIconBrightness: .light,
            systemNavigationBarContrastEnforced: false,
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
      const color = Color(0xFFFAF8F3);
      boardPaperShader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, color.r)
        ..setFloat(3, color.g)
        ..setFloat(4, color.b)
        ..setFloat(5, color.a)
        ..setFloat(6, 0.06)
        ..setFloat(7, 0.6)
        ..setFloat(8, devicePixelRatio);
      canvas.drawRect(Offset.zero & size, Paint()..shader = boardPaperShader);
    }
  }

  static void paintBackdrop(PaintRef ref) {
    final PaintRef(:canvas, :size) = ref;
    final Size(:width, :height) = size;
    if (ref.watch(goMode)) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF103018));
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
      decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Black(0.38), blurRadius: 1)]),
      child: const RefPaint(
        paint,
        expanded: false,
        child: RefClip.path(_clipPath, child: MainContent()),
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

      late final widthIsTighter =
          availableWidth * minHeight <= availableHeight * BottomBar.minWidth;

      final Widget widget;
      if (wideEnough && tallEnough) {
        widget = Center(child: content);
      } else if (!wideEnough && (tallEnough || widthIsTighter)) {
        final maxHeight = availableHeight * BottomBar.minWidth / availableWidth;
        widget = FittedBox(
          fit: .fitWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: BottomBar.minWidth, maxHeight: maxHeight),
            child: content,
          ),
        );
      } else {
        final maxWidth = availableWidth * minHeight / availableHeight;
        widget = FittedBox(
          fit: .fitHeight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: minHeight, maxWidth: maxWidth),
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
