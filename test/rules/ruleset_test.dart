import 'package:flutter_test/flutter_test.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';

void main() {
  group('winLengthForSize', () {
    test('gomoku caps at min dimension and 5', () {
      expect(Ruleset.gomoku.winLengthForSize(3, 3), 3);
      expect(Ruleset.gomoku.winLengthForSize(4, 4), 4);
      expect(Ruleset.gomoku.winLengthForSize(5, 5), 5);
      expect(Ruleset.gomoku.winLengthForSize(15, 15), 5);
      expect(Ruleset.gomoku.winLengthForSize(19, 13), 5);
      expect(Ruleset.gomoku.winLengthForSize(3, 19), 3);
    });

    test('swap2 and renju use same length rule as gomoku', () {
      expect(Ruleset.swap2.winLengthForSize(15, 15), 5);
      expect(Ruleset.renju.winLengthForSize(15, 15), 5);
      expect(Ruleset.swap2.winLengthForSize(4, 4), 4);
    });

    test('connect6 always requires 6', () {
      expect(Ruleset.connect6.winLengthForSize(6, 6), 6);
      expect(Ruleset.connect6.winLengthForSize(15, 15), 6);
      expect(Ruleset.connect6.winLengthForSize(19, 19), 6);
    });
  });

  group('filtered', () {
    test('3× board only allows gomoku', () {
      expect(Ruleset.filtered(3), [Ruleset.gomoku]);
    });

    test('4× board allows gomoku and swap2', () {
      expect(Ruleset.filtered(4), [Ruleset.gomoku, Ruleset.swap2]);
    });

    test('5× board adds renju', () {
      expect(Ruleset.filtered(5), [Ruleset.gomoku, Ruleset.swap2, Ruleset.renju]);
    });

    test('6+ board allows all rulesets', () {
      expect(Ruleset.filtered(6).toList(), Ruleset.values);
      expect(Ruleset.filtered(19).toList(), Ruleset.values);
    });
  });
}
