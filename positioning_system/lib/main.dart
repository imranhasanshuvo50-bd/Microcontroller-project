import 'package:flutter/material.dart';

import 'robot_position_page.dart';

void main() => runApp(const PositioningApp());

class PositioningApp extends StatelessWidget {
  const PositioningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Positioning System',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const RobotPositionPage(),
    );
  }
}
