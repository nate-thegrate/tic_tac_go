import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/board.dart';

final playing = playingTransition.toggler;
final playingTransition = Get.vsync(duration: const Duration(milliseconds: 175));

final goMode = goModeTransition.toggler;
final goModeTransition = Get.vsync(duration: const Duration(milliseconds: 175));

final devicePixelRatio = WidgetsBinding.instance.renderViews.first.configuration.devicePixelRatio;

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
    BoardTextures.woodShader = ui.ImageShader(image, .decal, .decal, Matrix4.identity().storage);
  } finally {
    codec.dispose();
    descriptor.dispose();
    backgroundBuffer.dispose();
  }

  final (paper, marker) = await paperMarkerFutures.wait;
  BoardTextures.boardPaperShader = paper.fragmentShader();
  BoardTextures.backdropPaperShader = paper.fragmentShader();
  Board.markerProgram = marker;
}

class App extends StatelessWidget {
  const App({super.key});

  static Widget _buildGoBoard(BuildContext context) {
    return GetScope(substitutes: {Substitution.value(goMode, true)}, child: const BoardTextures());
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

  static Widget _buildFab(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: playingTransition.toggle,
      label: Text('playing'),
      icon: IgnorePointer(
        child: Checkbox(value: ref.watch(playing), onChanged: (_) {}),
      ),
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
            GetScope(
              substitutes: {Substitution.value(goMode, false)},
              child: const BoardTextures(),
            ),
            const RefBuilder(_buildGoReveal),
          ],
        ),
        floatingActionButton: const RefBuilder(_buildFab),
      ),
    );
  }
}
