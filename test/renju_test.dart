import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/renju.dart';

List<List<PlayerMark?>> empty(int n) =>
    List.generate(n, (_) => List<PlayerMark?>.filled(n, null));

void main() {
  test('black double-three is a foul', () {
    // Open horizontal three ready at row 7: .xxx. through cols 3-5 if we add? 
    // Classic: two open twos that become open threes with one stone.
    // Simpler: place open three already, and another open two that becomes three.
    // Board:
    // row 5: . x x . . with room for open three via center
    // Actually: 
    //   x x . at (5,5)(5,6) empty (5,4)(5,7) — adding (5,7) or (5,4) makes open three
    //   x
    //   x  at (6,5)(7,5) — adding (5,5) if empty makes vertical open three
    // Place at (5,5): connects horizontal? 
    // Horizontal at row 5: need stones
    final b = empty(15);
    // Horizontal open two that becomes open three: (7,5)(7,6), ends (7,4)(7,7)
    // Adding (7,7) with (7,5)(7,6) contiguous → open three if (7,4) and (7,8) empty
    b[7][5] = PlayerMark.x;
    b[7][6] = PlayerMark.x;
    // Vertical open two: (5,7)(6,7), ends (4,7)(7,7)
    b[5][7] = PlayerMark.x;
    b[6][7] = PlayerMark.x;
    // (7,7) completes both open threes
    expect(Renju.foulIfBlackPlays(b, 7, 7), RenjuFoul.doubleThree);
  });

  test('black exact five is legal and not a foul', () {
    final b = empty(15);
    b[7][3] = PlayerMark.x;
    b[7][4] = PlayerMark.x;
    b[7][5] = PlayerMark.x;
    b[7][6] = PlayerMark.x;
    // Place (7,7) for exact five
    expect(Renju.foulIfBlackPlays(b, 7, 7), isNull);
  });

  test('black overline is legal but not a foul', () {
    final b = empty(15);
    for (var c = 2; c <= 6; c++) {
      b[7][c] = PlayerMark.x;
    }
    // five already; placing at (7,7) makes six — allowed, just not a win
    expect(Renju.foulIfBlackPlays(b, 7, 7), isNull);
    expect(Renju.isLegalFor(PlayerMark.x, b, 7, 7), isTrue);
  });

  test('white has no fouls', () {
    final b = empty(15);
    b[7][5] = PlayerMark.o;
    b[7][6] = PlayerMark.o;
    b[5][7] = PlayerMark.o;
    b[6][7] = PlayerMark.o;
    expect(Renju.isLegalFor(PlayerMark.o, b, 7, 7), isTrue);
  });

  test('BoardData renju: black overline does not win', () {
    final list = empty(15);
    for (var c = 2; c <= 7; c++) {
      list[7][c] = PlayerMark.x;
    }
    final data = BoardData(list);
    expect(data.winner(Ruleset.renju), isNull);
  });

  test('BoardData renju: black exact five wins', () {
    final list = empty(15);
    for (var c = 3; c <= 7; c++) {
      list[7][c] = PlayerMark.x;
    }
    final data = BoardData(list);
    expect(data.winner(Ruleset.renju), PlayerMark.x);
  });

  test('BoardData renju: white overline wins', () {
    final list = empty(15);
    for (var c = 2; c <= 7; c++) {
      list[7][c] = PlayerMark.o;
    }
    final data = BoardData(list);
    expect(data.winner(Ruleset.renju), PlayerMark.o);
  });
}
