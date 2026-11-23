import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/core/manual_data.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/game/modules/module_frame.dart';

class MorseModulePage extends StatefulWidget {
  const MorseModulePage({super.key, this.variant = 0});

  final int variant;

  @override
  State<MorseModulePage> createState() => _MorseModulePageState();
}

class _MorseModulePageState extends State<MorseModulePage> {
  static const Duration _unit = Duration(milliseconds: 250);

  String get _word =>
      morseFrequencies.keys.elementAt(widget.variant % morseFrequencies.length);
  bool _playing = false;
  bool _ledOn = false;
  String? _selected;

  /// Plays the word once: dot = 1 unit, dash = 3 units, gap between letters = 3.
  Future<void> _playSignal() async {
    if (_playing) return;
    setState(() => _playing = true);

    for (final letter in _word.split('')) {
      for (final symbol in morseCode[letter]!.split('')) {
        if (!mounted) return;
        final duration = symbol == '.' ? _unit : _unit * 3;
        setState(() => _ledOn = true);
        _buzz(duration);
        await Future.delayed(duration);
        if (!mounted) return;
        setState(() => _ledOn = false);
        await Future.delayed(_unit);
      }
      await Future.delayed(_unit * 2);
    }

    if (mounted) setState(() => _playing = false);
  }

  /// Vibrates for the symbol's real length so dots and dashes can be felt.
  void _buzz(Duration duration) {
    Vibration.vibrate(
      duration: duration.inMilliseconds,
    ).catchError((Object _) => HapticFeedback.heavyImpact());
  }

  @override
  void dispose() {
    Vibration.cancel().catchError((Object _) {});
    super.dispose();
  }

  void _confirm() {
    if (_selected == null) return;
    Navigator.of(context).pop(_selected == morseFrequencies[_word]);
  }

  Widget _buildFrequency(String frequency) {
    final isSelected = frequency == _selected;

    return InkWell(
      onTap: () => setState(() => _selected = frequency),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(
            color: isSelected ? AppColors.success : AppColors.metalGrey,
          ),
        ),
        child: Text(
          frequency,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? AppColors.success : AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frequencies = morseFrequencies.values.toList()..sort();

    return ModuleFrame(
      type: ModuleType.morse,
      subtitle: 'Recebe o sinal, descodifica a palavra e escolhe a frequência.',
      onConfirm: _confirm,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: glowingCardDecoration(
            glowColor: AppColors.success.withValues(alpha: 0.18),
            borderColor: AppColors.success.withValues(alpha: 0.5),
          ),
          child: Column(
            children: [
              StatusLed(
                color: _ledOn ? AppColors.amber : AppColors.metalGrey,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _playing ? 'A TRANSMITIR...' : 'SINAL EM ESPERA',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MenuButton(
          label: 'RECEBER SINAL',
          onPressed: _playSignal,
          color: _playing ? AppColors.metalGrey : AppColors.success,
        ),
        const SizedBox(height: 32),
        Text(
          'FREQUÊNCIA',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
        ),
        const SizedBox(height: 16),
        for (final frequency in frequencies) ...[
          _buildFrequency(frequency),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
