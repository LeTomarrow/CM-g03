import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/account.dart';
import 'package:what_did_you_press/features/configs.dart';
import 'package:what_did_you_press/features/help.dart';
import 'package:what_did_you_press/features/lobby.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: GamePage(),
      backgroundColor: AppColors.background,
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  void navegation(Widget nav) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => nav));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    'WDYP?!',
                    style: TextStyle(color: AppColors.danger, fontSize: 48),
                  ),
                  Text(
                    'Bomb Defusal Game',
                    style: TextStyle(color: AppColors.metalGrey, fontSize: 20),
                  ),
                ],
              ),
            ),
            SizedBox(height: 160),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MenuButton(
                      label: 'JOGAR',
                      onPressed: () => navegation(LobbyPage()),
                      color: AppColors.neonBlue,
                    ),
                    const SizedBox(height: 16),
                    MenuButton(
                      label: 'AJUDA',
                      onPressed: () => navegation(HelpPage()),
                      color: AppColors.amber,
                    ),
                    const SizedBox(height: 16),
                    MenuButton(
                      label: 'DEFINIÇÕES',
                      onPressed: () => navegation(ConfigsPage()),
                      color: AppColors.metalGrey,
                    ),
                    const SizedBox(height: 16),
                    MenuButton(
                      label: 'PERFIL',
                      onPressed: () => navegation(AccountPage()),
                      color: AppColors.success,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}