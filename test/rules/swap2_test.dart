import 'package:flutter_test/flutter_test.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tic_tac_go/src/board.dart';
import 'package:tic_tac_go/src/rules/ruleset.dart';
import 'package:tic_tac_go/src/rules/swap2.dart';

import '../helpers/board_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Stored.init(prefs: prefs);
  });

  setUp(() {
    Swap2.reset();
    Ruleset.current.value = .swap2;
    Board.state
      ..rows = 15
      ..cols = 15
      ..clear();
    Board.history.clear();
    Board.turn.value = .x;
    Board.humanPlayer.value = null;
    Board.inputLocked = false;
  });

  tearDown(() {
    Swap2.reset();
    Ruleset.current.value = .gomoku;
  });

  group('phase helpers', () {
    test('reset clears opening state', () {
      Swap2.phase.value = .opening3;
      Swap2.placedInPhase.value = 2;
      Swap2.optionsVisible.value = false;
      Swap2.firstPlayerIsHuman = false;
      Swap2.reset();
      expect(Swap2.phase.value, Swap2Phase.none);
      expect(Swap2.placedInPhase.value, 0);
      expect(Swap2.optionsVisible.value, isTrue);
      expect(Swap2.firstPlayerIsHuman, isTrue);
    });

    test('beginIfNeeded starts opening3 only for swap2', () {
      Ruleset.current.value = .gomoku;
      Swap2.beginIfNeeded();
      expect(Swap2.phase.value, Swap2Phase.none);

      Ruleset.current.value = .swap2;
      Swap2.beginIfNeeded();
      expect(Swap2.phase.value, Swap2Phase.opening3);
      expect(Swap2.placedInPhase.value, 0);
      expect(Swap2.isPlacing, isTrue);
      expect(Swap2.isChoosing, isFalse);
    });

    test('currentMarks and nextMark for opening3 and extra2', () {
      Swap2.phase.value = .opening3;
      Swap2.placedInPhase.value = 0;
      expect(Swap2.currentMarks, [PlayerMark.x, PlayerMark.o, PlayerMark.x]);
      expect(Swap2.nextMark, PlayerMark.x);

      Swap2.placedInPhase.value = 1;
      expect(Swap2.nextMark, PlayerMark.o);

      Swap2.phase.value = .extra2;
      Swap2.placedInPhase.value = 0;
      expect(Swap2.currentMarks, [PlayerMark.o, PlayerMark.x]);
      expect(Swap2.nextMark, PlayerMark.o);
    });

    test('isChoosing / isPlacing flags', () {
      for (final phase in Swap2Phase.values) {
        Swap2.phase.value = phase;
        final choosing = phase == .chooseAfter3 || phase == .chooseAfter5;
        final placing = phase == .opening3 || phase == .extra2;
        expect(Swap2.isChoosing, choosing, reason: '$phase isChoosing');
        expect(Swap2.isPlacing, placing, reason: '$phase isPlacing');
      }
    });

    test('humanPlacesCurrentPhase: 2-player always places', () {
      Board.humanPlayer.value = null;
      Swap2.phase.value = .opening3;
      expect(Swap2.humanPlacesCurrentPhase, isTrue);
      Swap2.phase.value = .extra2;
      expect(Swap2.humanPlacesCurrentPhase, isTrue);
    });

    test('humanPlacesCurrentPhase: 1-player opening vs extra', () {
      Board.humanPlayer.value = .x;
      Swap2.firstPlayerIsHuman = true;
      Swap2.phase.value = .opening3;
      expect(Swap2.humanPlacesCurrentPhase, isTrue);
      Swap2.phase.value = .extra2;
      expect(Swap2.humanPlacesCurrentPhase, isFalse);

      Swap2.firstPlayerIsHuman = false;
      Swap2.phase.value = .opening3;
      expect(Swap2.humanPlacesCurrentPhase, isFalse);
      Swap2.phase.value = .extra2;
      expect(Swap2.humanPlacesCurrentPhase, isTrue);
    });

    test('humanIsChooser: second player after 3, first after 5', () {
      Board.humanPlayer.value = .x;
      Swap2.firstPlayerIsHuman = true;
      Swap2.phase.value = .chooseAfter3;
      expect(Swap2.humanIsChooser, isFalse); // second player chooses
      Swap2.phase.value = .chooseAfter5;
      expect(Swap2.humanIsChooser, isTrue); // first player chooses

      Swap2.firstPlayerIsHuman = false;
      Swap2.phase.value = .chooseAfter3;
      expect(Swap2.humanIsChooser, isTrue);
      Swap2.phase.value = .chooseAfter5;
      expect(Swap2.humanIsChooser, isFalse);
    });

    test('undoPlacementStone rewinds placedInPhase', () {
      Swap2.phase.value = .opening3;
      Swap2.placedInPhase.value = 2;
      Board.turn.value = .x;
      var undid = false;
      Swap2.undoPlacementStone(() {
        undid = true;
      });
      expect(undid, isTrue);
      expect(Swap2.placedInPhase.value, 1);
      expect(Board.turn.value, Swap2.nextMark);
    });

    test('undoPlacementStone from chooseAfter3 returns to opening3', () {
      Swap2.phase.value = .chooseAfter3;
      Swap2.placedInPhase.value = 3;
      GameEnd.opacity.jumpTo(1);
      Swap2.undoPlacementStone(() {});
      expect(Swap2.phase.value, Swap2Phase.opening3);
      expect(Swap2.placedInPhase.value, 2);
      expect(GameEnd.opacity.value, 0);
      expect(Board.turn.value, Swap2.nextMark);
    });

    test('undoPlacementStone from chooseAfter5 returns to extra2', () {
      Swap2.phase.value = .chooseAfter5;
      Swap2.placedInPhase.value = 2;
      GameEnd.opacity.jumpTo(1);
      Swap2.undoPlacementStone(() {});
      expect(Swap2.phase.value, Swap2Phase.extra2);
      expect(Swap2.placedInPhase.value, 1);
      expect(GameEnd.opacity.value, 0);
      expect(Board.turn.value, Swap2.nextMark);
    });

    test('canUndo during color choice only in 2-player', () {
      Board.history.add((0, 0));
      Swap2.phase.value = .chooseAfter3;
      Board.humanPlayer.value = null;
      expect(Board.canUndo, isTrue);

      Board.humanPlayer.value = .x;
      expect(Board.canUndo, isFalse);

      Swap2.phase.value = .chooseAfter5;
      Board.humanPlayer.value = null;
      expect(Board.canUndo, isTrue);
      Board.humanPlayer.value = .o;
      expect(Board.canUndo, isFalse);
    });
  });

  group('opening plans', () {
    test('planOpening3 returns three distinct in-bounds cells', () {
      for (var i = 0; i < 20; i++) {
        final plan = Swap2.planOpening3(15, 15);
        expect(plan, hasLength(3));
        expect(plan.toSet(), hasLength(3), reason: 'distinct: $plan');
        for (final (row, col) in plan) {
          expect(row, inInclusiveRange(0, 14));
          expect(col, inInclusiveRange(0, 14));
        }
      }
    });

    test('planOpening3 works on non-square boards', () {
      final plan = Swap2.planOpening3(19, 13);
      expect(plan, hasLength(3));
      for (final (row, col) in plan) {
        expect(row, inInclusiveRange(0, 18));
        expect(col, inInclusiveRange(0, 12));
      }
    });

    test('planExtra2 returns two free distinct cells', () {
      final board = emptyBoard(15);
      // Simulate a 3-stone opening near center
      place(board, .x, [(7, 7), (9, 8)]);
      place(board, .o, [(8, 10)]);
      final plan = Swap2.planExtra2(board);
      expect(plan, hasLength(2));
      expect(plan[0], isNot(plan[1]));
      expect(board[plan[0].$1][plan[0].$2], isNull);
      expect(board[plan[1].$1][plan[1].$2], isNull);
    });
  });

  group('color choice', () {
    test('applyColorChoice no-ops when not choosing', () async {
      Swap2.phase.value = .none;
      await Swap2.applyColorChoice(.x);
      expect(Swap2.phase.value, Swap2Phase.none);
    });

    test('applyColorChoice ends opening and sets white to move', () async {
      Board.humanPlayer.value = null; // 2-player
      Swap2.phase.value = .chooseAfter3;
      await Swap2.applyColorChoice(.o);
      expect(Swap2.phase.value, Swap2Phase.none);
      expect(Board.turn.value, PlayerMark.o);
    });

    test('applyColorChoice sets human mark when chooser is human', () async {
      Board.humanPlayer.value = .x;
      Swap2.firstPlayerIsHuman = false; // human is second → chooses after 3
      Swap2.phase.value = .chooseAfter3;
      await Swap2.applyColorChoice(.o);
      expect(Board.humanPlayer.value, PlayerMark.o);
      expect(Swap2.phase.value, Swap2Phase.none);
    });

    test('applyAddTwoMoves enters extra2', () async {
      Board.humanPlayer.value = null;
      Swap2.phase.value = .chooseAfter3;
      await Swap2.applyAddTwoMoves();
      expect(Swap2.phase.value, Swap2Phase.extra2);
      expect(Swap2.placedInPhase.value, 0);
      expect(Swap2.nextMark, PlayerMark.o);
    });

    test('applyAddTwoMoves no-ops outside chooseAfter3', () async {
      Swap2.phase.value = .chooseAfter5;
      await Swap2.applyAddTwoMoves();
      expect(Swap2.phase.value, Swap2Phase.chooseAfter5);
    });
  });
}
