import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/board.dart';

final goMode = Get.it(true);
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

  static Widget _buildFab(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: goMode.toggle,
      label: Text('Go mode'),
      icon: IgnorePointer(
        child: Checkbox(value: ref.watch(goMode), onChanged: (_) {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xfff5c782),
        body: BoardTextures(),
        floatingActionButton: RefBuilder(_buildFab),
      ),
    );
  }
}
