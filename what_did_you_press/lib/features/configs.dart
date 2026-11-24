import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/app_state.dart';
import 'package:what_did_you_press/features/update/update_ui.dart';

class ConfigsPage extends ConsumerWidget {
  const ConfigsPage({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider).asData?.value ?? const SettingsState();
    Future<void> update(SettingsState next) => ref.read(settingsProvider.notifier).updateSettings(next);
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: AppColors.neonBlue, title: const Text('DEFINIÇÕES')), body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      _title('ÁUDIO'), _slider('Efeitos', current.sfxVolume, (v) => update(current.copyWith(sfxVolume: v))), _slider('Música', current.musicVolume, (v) => update(current.copyWith(musicVolume: v))),
      _title('DISPOSITIVO'), SwitchListTile(title: const Text('Vibração'), subtitle: const Text('Feedback nos ataques e falhas'), value: current.vibration, activeThumbColor: AppColors.neonBlue, onChanged: (v) => update(current.copyWith(vibration: v))),
      SwitchListTile(title: const Text('Ecrã sempre ligado'), subtitle: const Text('Mantém a bomba visível durante a partida'), value: current.screenAlwaysOn, activeThumbColor: AppColors.neonBlue, onChanged: (v) => update(current.copyWith(screenAlwaysOn: v))),
      _title('SOBRE'), const UpdateTile(), const SizedBox(height: 32),
      MenuButton(label: 'FECHAR', color: AppColors.success, onPressed: () => Navigator.pop(context)),
    ])));
  }
  Widget _title(String text) => Padding(padding: const EdgeInsets.only(top: 24, bottom: 12), child: Text(text, style: TextStyle(color: AppColors.textSecondary, fontSize: 18)));
  Widget _slider(String label, double value, ValueChanged<double> onChanged) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Slider(value: value, activeColor: AppColors.neonBlue, inactiveColor: AppColors.metalGrey, onChanged: onChanged)]);
}
