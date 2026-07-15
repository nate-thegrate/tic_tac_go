import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/board.dart';

import 'helpers/board_helpers.dart';

void main() {
  group('BoardData', () {
    test('rows and cols match grid', () {
      final data = BoardData(emptyBoard(4, 6));
      expect(data.rows, 4);
      expect(data.cols, 6);
    });

    test('tic-tac-toe: three in a row wins', () {
      final list = emptyBoard(3);
      placeHorizontal(list, .x, row: 0, startCol: 0, length: 3);
      final data = BoardData(list);
      expect(data.winner(.gomoku), PlayerMark.x);
      expect(data.isGameOver(.gomoku), isTrue);
      expect(data.winningRun(.gomoku), [(0, 0), (0, 1), (0, 2)]);
    });

    test('tic-tac-toe: vertical and diagonal wins', () {
      final vertical = emptyBoard(3);
      placeVertical(vertical, .o, col: 2, startRow: 0, length: 3);
      expect(BoardData(vertical).winner(.gomoku), PlayerMark.o);

      final diagonal = emptyBoard(3);
      place(diagonal, .x, [(0, 2), (1, 1), (2, 0)]);
      expect(BoardData(diagonal).winner(.gomoku), PlayerMark.x);
    });

    test('draw: full board with no winner', () {
      // X O X
      // X O O
      // O X X
      final List<List<PlayerMark?>> list = [
        [PlayerMark.x, PlayerMark.o, PlayerMark.x],
        [PlayerMark.x, PlayerMark.o, PlayerMark.o],
        [PlayerMark.o, PlayerMark.x, PlayerMark.x],
      ];
      final data = BoardData(list);
      expect(data.winner(.gomoku), isNull);
      expect(data.isGameOver(.gomoku), isTrue);
      expect(data.winningRun(.gomoku), [(-1, -1)]);
    });

    test('gomoku five on larger board', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .x, row: 7, startCol: 3, length: 5);
      final data = BoardData(list);
      expect(data.winner(.gomoku), PlayerMark.x);
      expect(data.winningRun(.gomoku)?.length, 5);
    });

    test('four-in-a-row on 4×4 is a win (winLength caps at min dim)', () {
      final list = emptyBoard(4);
      placeHorizontal(list, .o, row: 0, startCol: 0, length: 4);
      expect(BoardData(list).winner(.gomoku), PlayerMark.o);
    });

    test('empty board is not game over', () {
      final data = BoardData(emptyBoard(3));
      expect(data.isGameOver(.gomoku), isFalse);
      expect(data.winner(.gomoku), isNull);
      expect(data.winningRun(.gomoku), isNull);
    });

    test('winningRun cache is ruleset-specific', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .x, row: 7, startCol: 0, length: 5);
      final data = BoardData(list);
      expect(data.winner(.gomoku), PlayerMark.x);
      expect(data.winner(.connect6), isNull);
      // Re-query gomoku still wins (cache not polluted)
      expect(data.winner(.gomoku), PlayerMark.x);
    });
  });

  group('BoardState', () {
    late BoardState state;

    setUp(() {
      state = BoardState();
    });

    test('starts empty with given size', () {
      expect(state.rows, 3);
      expect(state.cols, 3);
      expect(state.value.isBoardFull, isFalse);
      expect(state.value.stoneCount, 0);
    });

    test('update places and clears marks', () {
      var notifications = 0;
      state.addListener(() => notifications++);

      state.update(1, 1, .x);
      expect(state.value[1][1], PlayerMark.x);
      expect(notifications, 1);

      state.update(1, 1, .x); // no-op
      expect(notifications, 1);

      state.update(1, 1, null);
      expect(state.value[1][1], isNull);
      expect(notifications, 2);
    });

    test('clear empties the board keeping size', () {
      state.update(0, 0, .x);
      state.update(2, 2, .o);
      state.clear();
      expect(state.rows, 3);
      expect(state.cols, 3);
      expect(state.value.stoneCount, 0);
    });

    test('rows/cols clamp to 3–19', () {
      state.rows = 1;
      expect(state.rows, 3);
      state.rows = 100;
      expect(state.rows, 19);
      state.cols = 2;
      expect(state.cols, 3);
      state.cols = 50;
      expect(state.cols, 19);
    });

    test('resizing preserves overlapping cells', () {
      state.update(0, 0, .x);
      state.update(1, 1, .o);
      state.rows = 5;
      state.cols = 4;
      expect(state.value[0][0], PlayerMark.x);
      expect(state.value[1][1], PlayerMark.o);
      expect(state.rows, 5);
      expect(state.cols, 4);
      // New cells empty
      expect(state.value[4][0], isNull);
    });

    test('shrinking drops out-of-range cells', () {
      state.rows = 5;
      state.cols = 5;
      state.update(4, 4, .x);
      state.rows = 3;
      state.cols = 3;
      expect(state.rows, 3);
      expect(state.cols, 3);
      // (4,4) no longer exists
      expect(() => state.value[4][4], throwsRangeError);
    });

    test('setting same size does not notify', () {
      var notifications = 0;
      state.addListener(() => notifications++);
      state.rows = 3;
      state.cols = 3;
      expect(notifications, 0);
    });
  });

  group('StoneData height helpers', () {
    test('heightFactor clamps 0–1', () {
      expect(StoneData.heightFactor(0, 100), 0);
      expect(StoneData.heightFactor(50, 100), 0.5);
      expect(StoneData.heightFactor(100, 100), 1);
      expect(StoneData.heightFactor(200, 100), 1);
      expect(StoneData.heightFactor(10, 0), 0);
    });

    test('scaleForHeight grows with height', () {
      expect(StoneData.scaleForHeight(0, 100), 1.0);
      expect(StoneData.scaleForHeight(100, 100), closeTo(1.15, 1e-9));
    });

    test('opacityForHeight falls with height', () {
      expect(StoneData.opacityForHeight(0, 100), 1.0);
      expect(StoneData.opacityForHeight(100, 100), closeTo(0.78, 1e-9));
    });
  });
}
