import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Widget _buildCard(
    String title,
    String content, {
    Color color = AppColors.amber,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      color: AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 20)),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.danger,
        title: Text('AJUDA'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            _buildCard(
              'A MISSÃO',
              'Tu e o teu parceiro têm de desarmar um engenho explosivo altamente instável. Um de vocês vê a bomba, mas não consegue ler o manual. O outro tem o manual, mas não vê a bomba.',
              color: AppColors.danger,
            ),
            _buildCard(
              'O OPERADOR',
              'O teu ecrã mostra a bomba e os seus módulos. Tens de descrever o que vês ao teu parceiro e seguir as instruções à risca. Um passo em falso e acabou.',
              color: AppColors.amber,
            ),
            _buildCard(
              'O LEITOR DO MANUAL',
              'Tens o manual de desarmamento. Procura depressa as instruções certas a partir do que o operador descreve. Comunica de forma clara e rápida.',
              color: AppColors.neonBlue,
            ),
            _buildCard(
              'COMUNICAÇÃO',
              'Fala. Grita. Faz o que for preciso para passar a informação certa. O tempo está a acabar. "O que é que carregaste?!" podem ser as últimas palavras que ouves.',
              color: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }
}
