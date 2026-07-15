import 'package:flutter_test/flutter_test.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/rules/connect6.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

import '../helpers/board_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Stored.init(prefs: prefs);
  });

  setUp(() {
    Ruleset.current.value = .connect6;
    Connect6.reset();
    Board.state
      ..rows = 15
      ..cols = 15
      ..clear();
    Board.history.clear();
    Board.turn.value = .x;
    Board.humanPlayer.value = null;
  });

  tearDown(() {
    Connect6.reset();
    Ruleset.current.value = .gomoku;
  });

  group('win detection', () {
    test('winLength is 6', () {
      final data = BoardData(emptyBoard(15));
      expect(Ruleset.connect6.winLengthForSize(data.rows, data.cols), 6);
    });

    test('five in a row is not a win', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .x, row: 7, startCol: 0, length: 5);
      final data = BoardData(list);
      expect(data.winner(.connect6), isNull);
      expect(data.isGameOver(.connect6), isFalse);
    });

    test('six in a row is a win', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .x, row: 7, startCol: 0, length: 6);
      final data = BoardData(list);
      expect(data.winner(.connect6), PlayerMark.x);
      expect(data.winningRun(.connect6)?.length, 6);
      expect(data.isGameOver(.connect6), isTrue);
    });

    test('winningRun cache is ruleset-specific', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .x, row: 7, startCol: 0, length: 5);
      final data = BoardData(list);
      expect(data.winner(.gomoku), PlayerMark.x);
      expect(data.winner(.connect6), isNull);
    });
  });

  group('turn progress', () {
    test('isActive follows Ruleset.current', () {
      Ruleset.current.value = .gomoku;
      expect(Connect6.isActive, isFalse);
      Ruleset.current.value = .connect6;
      expect(Connect6.isActive, isTrue);
    });

    test('stonesNeeded: black places 1 on opening, then 2', () {
      final empty = BoardData(emptyBoard(15));
      expect(Connect6.stonesNeeded(.x, empty), 1);
      expect(Connect6.stonesNeeded(.o, empty), 2);

      final afterBlack = emptyBoard(15);
      afterBlack[7][7] = .x;
      // Mid-turn after black's opening: stonesThisTurn tracks progress.
      // Before any notePlacement, count X=1 means black already finished opening.
      Connect6.stonesThisTurn.value = 0;
      expect(Connect6.stonesNeeded(.x, BoardData(afterBlack)), 2);
    });

    test('notePlacement completes black opening after one stone', () {
      final after = emptyBoard(15)..[0][0] = .x;
      final turnDone = Connect6.notePlacement(.x, BoardData(after));
      expect(turnDone, isTrue);
      expect(Connect6.stonesThisTurn.value, 0);
    });

    test('notePlacement requires two stones for white', () {
      final board = emptyBoard(15);
      board[0][0] = .x;
      board[0][1] = .o;
      final mid = Connect6.notePlacement(.o, BoardData(board));
      expect(mid, isFalse);
      expect(Connect6.stonesThisTurn.value, 1);

      board[0][2] = .o;
      final done = Connect6.notePlacement(.o, BoardData(board));
      expect(done, isTrue);
      expect(Connect6.stonesThisTurn.value, 0);
    });

    test('recomputeTurnFromBoard after black opening', () {
      final board = emptyBoard(15)..[5][5] = .x;
      Connect6.recomputeTurnFromBoard(BoardData(board));
      expect(Board.turn.value, PlayerMark.o);
      expect(Connect6.stonesThisTurn.value, 0);
    });

    test('recomputeTurnFromBoard mid white pair', () {
      final board = emptyBoard(15);
      place(board, .x, [(0, 0)]);
      place(board, .o, [(1, 1)]);
      // 2 stones: after black opening, white placed 1 of 2 → stonesThisTurn=1, still white
      Connect6.recomputeTurnFromBoard(BoardData(board));
      expect(Board.turn.value, PlayerMark.o);
      expect(Connect6.stonesThisTurn.value, 1);
    });

    test('recomputeTurnFromBoard empty resets to black', () {
      Connect6.stonesThisTurn.value = 1;
      Board.turn.value = .o;
      Connect6.recomputeTurnFromBoard(BoardData(emptyBoard(15)));
      expect(Board.turn.value, PlayerMark.x);
      expect(Connect6.stonesThisTurn.value, 0);
    });

    test('recomputeTurnFromBoard after full white turn is black pair', () {
      final board = emptyBoard(15);
      place(board, .x, [(0, 0)]);
      place(board, .o, [(1, 0), (1, 1)]);
      // 3 stones: black done, white done → black to place (first of pair)
      Connect6.recomputeTurnFromBoard(BoardData(board));
      expect(Board.turn.value, PlayerMark.x);
      expect(Connect6.stonesThisTurn.value, 0);
    });
  });
}
