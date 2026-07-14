import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/prefs.dart';
import 'package:tic_tac_go/src/shortcuts.dart';

void main() async {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  await (loadShaders(), loadPrefs()).wait;
  HardwareKeyboard.instance.addHandler(handleKeyEvent);
  runApp(const App());
}
