import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/src/board.dart';

enum Ruleset {
  gomoku,
  swap2,
  renju,
  connect6;

  static Iterable<Ruleset> filtered(int minBoardDimension) => values.take(minBoardDimension - 2);

  ({String label, List<Widget> description}) text(int minBoardDimension, bool isGoMode) {
    late final first = isGoMode ? 'black' : 'X';
    late final second = isGoMode ? 'white' : 'O';
    late final stones = isGoMode ? 'stones' : 'Xs';
    return switch (this) {
      gomoku when minBoardDimension == 3 => (
        label: isGoMode ? '3 in a row' : 'tic-tac-toe',
        description: [
          Text(
            'Players take turns ${isGoMode ? 'placing stones' : 'marking the board'} '
            'until somebody gets three in a row!',
          ),
          Text(
            '(This is the only available ruleset for a ${Board.state.cols}x${Board.state.rows} board.)',
          ),
        ],
      ),
      gomoku => (
        label: isGoMode && minBoardDimension >= 5
            ? 'gomoku'
            : '${math.min(minBoardDimension, 5)} in a row',
        description: [
          Text(
            'Players take turns ${isGoMode ? 'placing stones' : 'marking the board'} '
            'until somebody has ${minBoardDimension == 4 ? 'four' : 'five'} in a row '
            '(vertically, horizontally, or diagonally).',
          ),
          Text(
            'No other restrictions apply'
            '${isGoMode ? ': the black player has an advantage since they go first' : ', so the first player has an advantage'}.',
          ),
        ],
      ),
      swap2 => (
        label: 'swap 2',
        description: [
          Text(
            'First, the $first player makes 3 moves ($first, $second, $first).\n'
            'Afterward, the $second player has 3 options:',
          ),
          _RulesList.numbered([
            'Continue playing',
            'Swap: the first player must play as $second and the second player plays as $first',
            'Make 2 more moves, and then let the first player decide whether to swap',
          ]),
          Text(
            'Then players take turns as normal until someone gets '
            '${minBoardDimension == 4 ? 'four' : 'five'} in a row.',
          ),
        ],
      ),
      renju when minBoardDimension < 5 => throw StateError(
        "Can't pick renju with board dimension of $minBoardDimension",
      ),
      renju => (
        label: 'renju',
        description: [
          Text(
            'Some restrictions apply to the '
            '${isGoMode ? 'black player to offset the advantage of going first' : 'first player to offset their advantage'}:',
          ),
          _RulesList([
            "They can't simultaneously form two rows of 3 $stones "
                'if both rows are unblocked on either side',
            "They can't ever simultaneously form two rows of 4 $stones",
            "They must have exactly 5 in a row in order to win (6 or more doesn't count)",
          ]),
        ],
      ),
      connect6 when minBoardDimension < 6 => throw StateError(
        "Can't pick connect6 with board dimension of $minBoardDimension",
      ),
      connect6 => (
        label: 'connect 6',
        description: isGoMode
            ? const [
                Text(
                  'The black player places 1 stone on their first turn. '
                  'From then on, players go back and forth, placing 2 stones each turn.',
                ),
                Text('The game ends when a player has 6 in a row.'),
              ]
            : const [
                Text(
                  'The first player marks a single square with an X. '
                  'From then on, players go back and forth, marking 2 squares at a time.',
                ),
                Text('The game ends when a player has 6 in a row.'),
              ],
      ),
    };
  }

  int winLength(BoardData data) => winLengthForSize(data.rows, data.cols);

  /// Win length from board dimensions (for AI / bare grids without [BoardData]).
  int winLengthForSize(int rows, int cols) {
    return this == connect6 ? 6 : math.min(math.min(rows, cols), 5);
  }

  static final current = Get.it(gomoku);
}

class _RulesList extends StatelessWidget {
  const _RulesList(this.items) : numbered = false;
  const _RulesList.numbered(this.items) : numbered = true;

  final List<String> items;
  final bool numbered;

  static Widget _rulesListItem({required String marker, required String text}) {
    return Padding(
      padding: const .only(bottom: 4),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          SizedBox(width: 28, child: Text(marker)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (numbered)
          for (final (index, item) in items.indexed)
            _rulesListItem(marker: ' ${index + 1}.', text: item)
        else
          for (final item in items) _rulesListItem(marker: '  •', text: item),
      ],
    );
  }
}
