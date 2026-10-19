import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:what_did_you_press/features/menu.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: AppTheme.darkTheme, home: const MenuPage());
  }
}
