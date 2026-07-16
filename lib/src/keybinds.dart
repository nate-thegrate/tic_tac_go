/// @docImport 'package:tic_tac_go/main.dart';
library;

import 'package:flutter/services.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/menu.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';
import 'package:tic_tac_go/src/rules/swap2.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

final _keyboard = HardwareKeyboard.instance;

Future<void> configureKeybinds() async {
  if (defaultTargetPlatform case .windows || .macOS || .linux when !kIsWeb) {
    await windowManager.ensureInitialized();
  }
  _keyboard.addHandler(handleKeyEvent);
}

bool handleKeyEvent(KeyEvent event) {
  if (event is KeyUpEvent) return false;

  late final isPlaying = playing.value;
  late final controlPressed = _keyboard.isControlPressed || _keyboard.isMetaPressed;
  late final onBoardSize = !isPlaying && MenuPage.current.value == .boardSize;
  late final isMacOSDesktop = !kIsWeb && defaultTargetPlatform == .macOS;
  late final fullScreenF11 = switch (defaultTargetPlatform) {
    .windows || .linux => !kIsWeb,
    _ => false,
  };

  switch (event.logicalKey) {
    case final key && (.arrowLeft || .arrowRight || .arrowUp || .arrowDown) when !isPlaying:
    case final key && (.keyW || .keyA || .keyS || .keyD) when !isPlaying:
      switch ((MenuPage.current.value, key)) {
        case (.players, .arrowLeft || .keyA) when event is KeyDownEvent:
          twoPlayer.value = false;
        case (.players, .arrowRight || .keyD) when event is KeyDownEvent:
          twoPlayer.value = true;

        case (.boardSize, .arrowUp || .keyW):
          Board.state.rows -= 1;
        case (.boardSize, .arrowDown || .keyS):
          Board.state.rows += 1;
        case (.boardSize, .arrowLeft || .keyA):
          Board.state.cols -= 1;
        case (.boardSize, .arrowRight || .keyD):
          Board.state.cols += 1;

        case (.rules, .arrowUp || .arrowDown || .keyW || .keyS):
          final delta = (key == .arrowUp || key == .keyW) ? -1 : 1;
          final minDim = Board.state.rows < Board.state.cols ? Board.state.rows : Board.state.cols;
          final allowed = Ruleset.filtered(minDim).toList();

          final index = allowed.indexOf(Ruleset.current.value);
          final from = index < 0 ? 0 : index;
          final next = (from + delta) % allowed.length;
          Ruleset.current.value = allowed[next < 0 ? next + allowed.length : next];

        default:
          return !controlPressed;
      }

    case .equal || .numpadAdd || .add when onBoardSize:
      Board.state
        ..rows += 1
        ..cols += 1;

    case .minus || .numpadSubtract || .underscore when onBoardSize:
      Board.state
        ..rows -= 1
        ..cols -= 1;

    case _ when event is! KeyDownEvent:
      return true;

    case .keyZ when isPlaying && controlPressed:
    case .keyU when isPlaying:
      if (!Board.canUndo.value) return false;
      Board.undo();

    case .f11 when fullScreenF11:
    case .keyF when isMacOSDesktop && controlPressed:
      windowManager.isFullScreen().then((value) => windowManager.setFullScreen(!value));

    case .escape when isPlaying || MenuPage.current.value != .players:
      goBack();

    case .keyG:
      goMode.toggle();

    case .enter || .numpadEnter || .space when Swap2.isChoosing || !isPlaying:
      primaryAction();

    case .keyR when isPlaying:
      Board.startNewGame();

    case final key && (.digit1 || .numpad1 || .digit2 || .numpad2)
        when !isPlaying && MenuPage.current.value == .players:
      twoPlayer.value = key == .digit1 || key == .numpad1;

    default:
      return !controlPressed;
  }
  return true;
}
