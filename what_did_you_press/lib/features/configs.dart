import 'package:flutter/material.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/features/menu.dart';

class ConfigsPage extends StatefulWidget {
  const ConfigsPage({super.key});

  @override
  State<ConfigsPage> createState() => _ConfigsPageState();
}

class _ConfigsPageState extends State<ConfigsPage> {
  double _sfxVolume = 0.8;
  double _musicVolume = 0.5;
  bool _vibration = true;
  bool _screenAlwaysOn = true;

  Widget _buildTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 16),
      child: Text(
        title,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.neonBlue,
        title: Text('DEFINIÇÕES'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            _buildTitle('ÁUDIO'),
            Text('Efeitos', style: TextStyle(color: AppColors.textPrimary)),
            Slider(
              value: _sfxVolume,
              activeColor: AppColors.neonBlue,
              inactiveColor: AppColors.metalGrey,
              onChanged: (val) => setState(() => _sfxVolume = val),
            ),
            const SizedBox(height: 16),
            Text('Música', style: TextStyle(color: AppColors.textPrimary)),
            Slider(
              value: _musicVolume,
              activeColor: AppColors.neonBlue,
              inactiveColor: AppColors.metalGrey,
              onChanged: (val) => setState(() => _musicVolume = val),
            ),
            _buildTitle('DISPOSITIVO'),
            SwitchListTile(
              title: Text(
                'Vibração',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              value: _vibration,
              activeThumbColor: AppColors.neonBlue,
              onChanged: (val) => setState(() => _vibration = val),
            ),
            SwitchListTile(
              title: Text(
                'Ecrã sempre ligado',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              value: _screenAlwaysOn,
              activeThumbColor: AppColors.neonBlue,
              onChanged: (val) => setState(() => _screenAlwaysOn = val),
            ),
            const SizedBox(height: 48),
            MenuButton(
              label: 'GUARDAR',
              onPressed: () => Navigator.of(context).pop(),
              color: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }
}
