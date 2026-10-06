import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';


class MenuPage extends StatelessWidget{
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: GamePage());
  }
}


class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  
  void navegation() => { print("navegay") };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MenuButton(label: 'JOGAR', onPressed: navegation, color: AppColors.neonBlue),
            const SizedBox(height: 16),
            MenuButton(label: 'AJUDA', onPressed: navegation, color: AppColors.amber),
            const SizedBox(height: 16),
            MenuButton(label: 'DEFINIÇÕES', onPressed: navegation, color: AppColors.metalGrey),
          ],
        ),
      ),
    );
  }
}


class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.danger,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
              ),
        ),
      ),
    );
  }
}