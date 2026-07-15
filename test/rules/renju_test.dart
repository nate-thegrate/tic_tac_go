import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/player_mark.dart';
import 'package:tic_tac_go/src/rules/renju.dart';

import '../helpers/board_helpers.dart';

void main() {
  group('fouls', () {
    test('black double-three is a foul', () {
      // Horizontal open two at (7,5)(7,6); vertical open two at (5,7)(6,7).
      // (7,7) completes both open threes.
      final board = emptyBoard(15);
      place(board, .x, [(7, 5), (7, 6), (5, 7), (6, 7)]);
      expect(Renju.foulIfBlackPlays(board, 7, 7), isTrue);
      expect((7, 7).isLegalOn(board, .x, .renju), isFalse);
    });

    test('black double-four is a foul', () {
      // Place at (7,5): horizontal xx.x → four; vertical xx.x → four (not five).
      final board = emptyBoard(15);
      place(board, .x, [
        (7, 3), (7, 4), (7, 6), // + (7,5) → four horizontal
        (5, 5), (6, 5), (8, 5), // + (7,5) → four vertical
      ]);
      expect(Renju.foulIfBlackPlays(board, 7, 5), isTrue);
      expect((7, 5).isLegalOn(board, .x, .renju), isFalse);
    });

    test('black exact five is legal and not a foul', () {
      final board = emptyBoard(15);
      placeHorizontal(board, .x, row: 7, startCol: 3, length: 4);
      expect(Renju.foulIfBlackPlays(board, 7, 7), isFalse);
      expect((7, 7).isLegalOn(board, .x, .renju), isTrue);
    });

    test('exact five overrides double-three foul (4×3 allowed)', () {
      // Classic: a five that also creates open threes is still legal.
      final board = emptyBoard(15);
      // Horizontal four ready for five at (7,7)
      placeHorizontal(board, .x, row: 7, startCol: 3, length: 4); // 3-6
      // Vertical open two that would become open three at (7,7)
      place(board, .x, [(5, 7), (6, 7)]);
      // Another open two for a second three — if five forms first, not a foul
      place(board, .x, [(7, 9), (7, 10)]);
      // Wait: placing (7,7) with stones at 3,4,5,6 and empty 8 gives exact five?
      // 3,4,5,6,7 = five. The open threes may also form.
      // As long as exact five exists, foul is false.
      expect(Renju.foulIfBlackPlays(board, 7, 7), isFalse);
    });

    test('black overline is legal but not a foul', () {
      final board = emptyBoard(15);
      placeHorizontal(board, .x, row: 7, startCol: 2, length: 5); // 2-6 already five
      // Placing (7,7) makes six — allowed, just not a win
      expect(Renju.foulIfBlackPlays(board, 7, 7), isFalse);
      expect((7, 7).isLegalOn(board, .x, .renju), isTrue);
    });

    test('white has no fouls', () {
      final board = emptyBoard(15);
      place(board, .o, [(7, 5), (7, 6), (5, 7), (6, 7)]);
      expect((7, 7).isLegalOn(board, .o, .renju), isTrue);
    });

    test('single open three is legal for black', () {
      final board = emptyBoard(15);
      place(board, .x, [(7, 5), (7, 6)]);
      // Completing one open three only
      expect(Renju.foulIfBlackPlays(board, 7, 7), isFalse);
    });
  });

  group('BoardData renju wins', () {
    test('black overline does not win', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .x, row: 7, startCol: 2, length: 6);
      expect(BoardData(list).winner(.renju), isNull);
    });

    test('black exact five wins', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .x, row: 7, startCol: 3, length: 5);
      expect(BoardData(list).winner(.renju), PlayerMark.x);
    });

    test('white overline wins', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .o, row: 7, startCol: 2, length: 6);
      expect(BoardData(list).winner(.renju), PlayerMark.o);
    });

    test('white exact five wins', () {
      final list = emptyBoard(15);
      placeHorizontal(list, .o, row: 7, startCol: 3, length: 5);
      expect(BoardData(list).winner(.renju), PlayerMark.o);
    });
  });
}
