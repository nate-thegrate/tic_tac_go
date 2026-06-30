import 'package:flutter/material.dart';
import 'package:get_hooked/get_hooked.dart';
import 'package:tic_tac_go/board.dart';

final goMode = Get.it(false);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(child: Board(dimensions: (3, 3))),
      ),
    );
  }
}
