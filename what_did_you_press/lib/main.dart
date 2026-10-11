import 'package:flutter/material.dart';
import 'package:what_did_you_press/features/menu.dart';
import 'package:what_did_you_press/core/app_theme.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: AppTheme.darkTheme, home: const MenuPage());
  }
}
