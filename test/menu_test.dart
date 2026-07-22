import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/keybinds.dart';
import 'package:tic_tac_go/src/menu.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';
import 'package:tic_tac_go/src/rules/swap2.dart';

KeyDownEvent keyDown(LogicalKeyboardKey key) {
  return KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.escape, // physical unused by handler
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Stored.init(prefs: prefs);
    await loadShaders();
  });

  setUp(() {
    // Jump transitions so toggler status updates without pumping frames.
    playingTransition.value = 0;
    goModeTransition.value = 0;
    tutorialDone.value = true;
    MenuPage.current.value = MenuPage.players;
    Board.state
      ..rows = 3
      ..cols = 3
      ..clear();
    Board.history.clear();
    Board.humanPlayer.value = null;
    Board.inputLocked = false;
    Board.turn.value = .x;
    Ruleset.current.value = .gomoku;
    twoPlayer.value = false;
    Difficulty.selected.value = .easy;
    Swap2.reset();
  });

  testWidgets('Can load the menu and start a game', (tester) async {
    await tester.pumpWidget(const App());
    MenuPage.current.value = .rules;
    primaryAction();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('goBack', () {
    test('no-ops on Players page', () {
      MenuPage.current.value = .players;
      goBack();
      expect(MenuPage.current.value, MenuPage.players);
    });

    test('steps back one menu page', () {
      MenuPage.current.value = .rules;
      goBack();
      expect(MenuPage.current.value, MenuPage.boardSize);
      goBack();
      expect(MenuPage.current.value, MenuPage.players);
    });
  });

  group('primaryAction', () {
    test('advances menu pages', () {
      MenuPage.current.value = .players;
      primaryAction();
      expect(MenuPage.current.value, MenuPage.boardSize);
      primaryAction();
      expect(MenuPage.current.value, MenuPage.rules);
    });

    test('starts game from Rules page', () {
      MenuPage.current.value = .rules;
      Board.humanPlayer.value = null;
      primaryAction();
      // beginGame assigns sides (1-player default). The playing toggler is
      // animated and may not report true without a running frame scheduler.
      expect(Board.humanPlayer.value, isNotNull);
    });

    test('while playing only toggles swap2 options when choosing', () {
      playingTransition.value = 1;
      expect(playing.value, isTrue);

      Swap2.phase.value = .none;
      primaryAction(); // no-op when not choosing
      expect(Swap2.optionsVisible.value, isTrue);

      Swap2.phase.value = .chooseAfter3;
      Swap2.optionsVisible.value = true;
      primaryAction();
      expect(Swap2.optionsVisible.value, isFalse);
    });
  });

  group('handleKeyEvent', () {
    test('ignores non-KeyDown events', () {
      const up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyG,
        logicalKey: LogicalKeyboardKey.keyG,
        timeStamp: Duration.zero,
      );
      expect(handleKeyEvent(up), isFalse);
    });

    test('G is handled (starts go-mode transition)', () {
      // toggle() drives an animation; without pumping frames status may not
      // flip, but the shortcut must still claim the key.
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.keyG)), isTrue);
    });

    test('digit 1/2 set player count on players page', () {
      MenuPage.current.value = .players;
      twoPlayer.value = true;
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.digit1)), isTrue);
      expect(twoPlayer.value, isFalse);

      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.digit2)), isTrue);
      expect(twoPlayer.value, isTrue);
    });

    test('arrows adjust board size on boardSize page', () {
      MenuPage.current.value = .boardSize;
      Board.state
        ..rows = 5
        ..cols = 5;
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.arrowDown)), isTrue);
      expect(Board.state.rows, 6);
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.arrowRight)), isTrue);
      expect(Board.state.cols, 6);
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.arrowUp)), isTrue);
      expect(Board.state.rows, 5);
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.arrowLeft)), isTrue);
      expect(Board.state.cols, 5);
    });

    test('plus/minus scale both board dimensions', () {
      MenuPage.current.value = .boardSize;
      Board.state
        ..rows = 5
        ..cols = 5;
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.equal)), isTrue);
      expect(Board.state.rows, 6);
      expect(Board.state.cols, 6);
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.minus)), isTrue);
      expect(Board.state.rows, 5);
      expect(Board.state.cols, 5);
    });

    test('arrows cycle ruleset on rules page', () {
      MenuPage.current.value = .rules;
      Board.state
        ..rows = 15
        ..cols = 15;
      Ruleset.current.value = .gomoku;
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.arrowDown)), isTrue);
      expect(Ruleset.current.value, Ruleset.swap2);
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.arrowUp)), isTrue);
      expect(Ruleset.current.value, Ruleset.gomoku);
    });

    test('Enter advances menu via primaryAction', () {
      MenuPage.current.value = .players;
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.enter)), isTrue);
      expect(MenuPage.current.value, MenuPage.boardSize);
    });

    test('Escape steps back menu', () {
      MenuPage.current.value = .boardSize;
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.escape)), isTrue);
      expect(MenuPage.current.value, MenuPage.players);
    });

    test('unrelated key without control is consumed', () {
      expect(handleKeyEvent(keyDown(LogicalKeyboardKey.keyQ)), isTrue);
    });
  });
}
