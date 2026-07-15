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

/// App-wide keyboard shortcuts.
///
/// Registered once from [main] via [HardwareKeyboard.addHandler].
bool handleKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return false;

  final isPlaying = playing.value;
  final keyboard = HardwareKeyboard.instance;
  final onBoardSize = !isPlaying && MenuPage.current.value == .boardSize;

  switch (event.logicalKey) {
    // Undo: Ctrl/Cmd+Z or U while playing
    case .keyZ when isPlaying && (keyboard.isControlPressed || keyboard.isMetaPressed):
    case .keyU when isPlaying:
      if (!Board.canUndo.value) return false;
      Board.undo();

    // Esc: back
    case .escape when isPlaying || MenuPage.current.value != .players:
      goBack();

    // G: go mode
    case .keyG:
      goMode.toggle();

    // Enter / Space: primary (next/play or swap2 view toggle)
    case .enter || .numpadEnter || .space when !isPlaying || Swap2.isChoosing:
      primaryAction();

    // R: restart
    case .keyR when isPlaying:
      Board.beginGame();

    // Digits: swap2 options → game over → menu players 1/2
    case final key && (.digit1 || .numpad1 || .digit2 || .numpad2 || .digit3 || .numpad3):
      final digit = switch (key) {
        .digit1 || .numpad1 => 1,
        .digit2 || .numpad2 => 2,
        .digit3 || .numpad3 => 3,
        _ => throw StateError('unreachable'),
      };

      if (isPlaying) {
        if (Swap2.isChoosing && Swap2.optionsVisible.value) {
          switch (digit) {
            case 1:
              Swap2.applyColorChoice(.o);
            case 2:
              Swap2.applyColorChoice(.x);
            case 3 when Swap2.phase.value == .chooseAfter3:
              Swap2.applyAddTwoMoves();
            default:
              return false;
          }
        } else if (Board.state.value.isGameOver(Ruleset.current.value)) {
          switch (digit) {
            case 1:
              Board.beginGame();
            case 2:
              GameEnd.backToMenu();
            default:
              return false;
          }
        } else {
          return false;
        }
      } else if (MenuPage.current.value == .players && digit <= 2) {
        twoPlayer.value = digit == 2;
      } else {
        return false;
      }

    // Arrows: players 1P/2P, board-size nudge, rules ↑/↓ cycle
    case final key && (.arrowLeft || .arrowRight || .arrowUp || .arrowDown) when !isPlaying:
      switch ((MenuPage.current.value, key)) {
        case (.players, .arrowLeft):
          twoPlayer.value = false;
        case (.players, .arrowRight):
          twoPlayer.value = true;

        case (.boardSize, .arrowUp):
          Board.state.rows -= 1;
        case (.boardSize, .arrowDown):
          Board.state.rows += 1;
        case (.boardSize, .arrowLeft):
          Board.state.cols -= 1;
        case (.boardSize, .arrowRight):
          Board.state.cols += 1;

        case (.rules, .arrowUp || .arrowDown):
          final delta = key == .arrowUp ? -1 : 1;
          final minDim = Board.state.rows < Board.state.cols ? Board.state.rows : Board.state.cols;
          final allowed = Ruleset.filtered(minDim).toList();

          final index = allowed.indexOf(Ruleset.current.value);
          final from = index < 0 ? 0 : index;
          final next = (from + delta) % allowed.length;
          Ruleset.current.value = allowed[next < 0 ? next + allowed.length : next];

        default:
          return false;
      }

    // +/- : board size both dims
    case .equal || .numpadAdd || .add when onBoardSize:
      Board.state
        ..rows += 1
        ..cols += 1;

    case .minus || .numpadSubtract || .underscore when onBoardSize:
      Board.state
        ..rows -= 1
        ..cols -= 1;

    default:
      return false;
  }
  return true;
}
