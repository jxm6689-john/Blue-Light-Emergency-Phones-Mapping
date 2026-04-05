import 'package:flutter/material.dart';
import 'package:blue_light_emergency_phones_mapping/screens/map_screen.dart';

void main() {
  runApp(const CampusSafetyApp());
}

class CampusSafetyApp extends StatelessWidget {
  const CampusSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UM Campus Safety Route',
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: const CampusMapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}