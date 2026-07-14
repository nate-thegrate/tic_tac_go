import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/player_mark.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

void main() {
  test('connect6 winLength is 6', () {
    final data = BoardData(List.generate(15, (_) => List<PlayerMark?>.filled(15, null)));
    expect(Ruleset.connect6.winLengthForSize(data.rows, data.cols), 6);
  });

  test('connect6 five in a row is not a win', () {
    final list = List.generate(15, (_) => List<PlayerMark?>.filled(15, null));
    for (var c = 0; c < 5; c++) {
      list[7][c] = PlayerMark.x;
    }
    final data = BoardData(list);
    expect(data.winner(Ruleset.connect6), isNull);
    expect(data.isGameOver(Ruleset.connect6), isFalse);
  });

  test('connect6 six in a row is a win', () {
    final list = List.generate(15, (_) => List<PlayerMark?>.filled(15, null));
    for (var c = 0; c < 6; c++) {
      list[7][c] = PlayerMark.x;
    }
    final data = BoardData(list);
    expect(data.winner(Ruleset.connect6), PlayerMark.x);
    expect(data.winningRun(Ruleset.connect6)?.length, 6);
  });

  test('winningRun cache is ruleset-specific', () {
    final list = List.generate(15, (_) => List<PlayerMark?>.filled(15, null));
    for (var c = 0; c < 5; c++) {
      list[7][c] = PlayerMark.x;
    }
    final data = BoardData(list);
    // Gomoku (capped at 5) wins
    expect(data.winner(Ruleset.gomoku), PlayerMark.x);
    // Same BoardData must not report a connect6 win
    expect(data.winner(Ruleset.connect6), isNull);
  });
}
