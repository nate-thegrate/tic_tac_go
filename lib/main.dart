import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:tic_tac_go/src/app.dart';
import 'package:tic_tac_go/src/prefs.dart';
import 'package:tic_tac_go/src/keybinds.dart';

void main() async {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  await (loadShaders(), loadPrefs(), configureKeybinds()).wait;
  runApp(const App());
}
