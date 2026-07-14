import 'package:flutter_test/flutter_test.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tic_tac_go/src/ai_move.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/menu.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Stored.init(prefs: prefs);
  });

  setUp(() {
    playing.value = false;
    MenuPage.current.value = MenuPage.players;
    Board.state
      ..rows = 3
      ..cols = 3;
    Ruleset.current.value = .gomoku;
    twoPlayer.value = false;
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
  });
}
