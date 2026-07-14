import 'package:get_hooked/get_hooked.dart';
import 'package:get_hooked_storage/get_hooked_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/board.dart';

Future<void> loadPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  Stored.init(prefs: prefs);

  if (prefs.getBool('go mode') case final isGoMode?) {
    goModeTransition.value = isGoMode ? 1 : 0;
  }
  goMode.hooked.addListener(() {
    prefs.setBool('go mode', goMode.value);
  });

  if (prefs.getInt('board rows') case final rows?) Board.state.rows = rows;
  if (prefs.getInt('board cols') case final cols?) Board.state.cols = cols;
  var BoardState(:rows, :cols) = Board.state;
  Board.state.addListener(() {
    final BoardState(rows: newRows, cols: newCols) = Board.state;
    if (newRows != rows) prefs.setInt('board rows', rows = newRows);
    if (newCols != cols) prefs.setInt('board cols', cols = newCols);
  });
}
