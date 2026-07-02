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
        backgroundColor: Color(0xfff5c782),
        body: DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              fit: .cover,
              image: AssetImage('assets/pexels-ksw-photographer-2372420-5467852.jpg'),
            ),
          ),
          child: Board(),
        ),
      ),
    );
  }
}
