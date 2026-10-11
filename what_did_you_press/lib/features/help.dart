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
              'THE MISSION',
              'You and your partner are tasked with defusing a highly volatile explosive device. One of you can see the bomb, but cannot read the manual. The other has the manual, but cannot see the bomb.',
              color: AppColors.danger,
            ),
            _buildCard(
              'THE DEFUSER',
              'Your screen shows the bomb and its various modules. You must describe what you see to your partner and execute their instructions perfectly. One wrong move, and it\'s game over.',
              color: AppColors.amber,
            ),
            _buildCard(
              'THE MANUAL OPERATOR',
              'You hold the defusal manual. You must quickly navigate its pages to find the correct instructions based on the Defuser\'s descriptions. Communicate clearly and quickly.',
              color: AppColors.neonBlue,
            ),
            _buildCard(
              'COMMUNICATION',
              'Talk. Yell. Do whatever it takes to relay information accurately. Time is running out. "What did you press?!" might be the last words you hear.',
              color: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }
}
