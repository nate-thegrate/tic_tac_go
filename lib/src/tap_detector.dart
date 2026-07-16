import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class TapDetector extends SingleChildRenderObjectWidget {
  const TapDetector(
    this.callback, {
    super.key,
    this.respondToDrag = false,
    required Widget super.child,
  });

  final TapCallback callback;
  final bool respondToDrag;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTapDetector(
      callback: (position, size) => (context.widget as TapDetector).callback(position, size),
      respondToDrag: () => (context.widget as TapDetector).respondToDrag,
    );
  }
}

typedef TapCallback = void Function(Offset position, Size size);

class RenderTapDetector extends RenderProxyBoxWithHitTestBehavior {
  RenderTapDetector({required this.callback, required this.respondToDrag, super.child})
    : super(behavior: .opaque);

  final TapCallback callback;

  final ValueGetter<bool> respondToDrag;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    assert(debugHandleEvent(event, entry));
    if (event is PointerDownEvent || event is PointerMoveEvent && respondToDrag()) {
      if (event.buttons == kPrimaryMouseButton || event.kind == .touch) {
        callback(event.localPosition, size);
      }
    }
  }
}
