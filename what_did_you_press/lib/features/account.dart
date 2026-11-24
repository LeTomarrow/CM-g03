import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/core/widgets.dart';
import 'package:what_did_you_press/features/app_state.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});
  @override ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _name = TextEditingController();
  @override void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 800, imageQuality: 85);
      if (file != null && mounted) await ref.read(profileProvider.notifier).setPhoto(file);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível escolher essa foto neste dispositivo.')));
    }
  }

  Future<void> _photoMenu(ProfileState profile) async {
    await showModalBottomSheet<void>(context: context, backgroundColor: AppColors.card, builder: (context) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo_library), title: const Text('Escolher da galeria'), onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.gallery); }),
      ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Tirar fotografia'), onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.camera); }),
      if (profile.photoBase64 != null) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remover fotografia'), onTap: () { Navigator.pop(context); ref.read(profileProvider.notifier).removePhoto(); }),
    ])));
  }

  @override Widget build(BuildContext context) {
    final async = ref.watch(profileProvider);
    final profile = async.asData?.value;
    if (profile != null && _name.text.isEmpty) _name.text = profile.name;
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final winRate = profile.games == 0 ? 0 : (profile.defused / profile.games * 100).round();
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: AppColors.success, title: const Text('PERFIL')), body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      Center(child: GestureDetector(onTap: () => _photoMenu(profile), child: Stack(alignment: Alignment.bottomRight, children: [
        CircleAvatar(radius: 52, backgroundColor: AppColors.metalGrey, backgroundImage: profile.photoBase64 == null ? null : MemoryImage(base64Decode(profile.photoBase64!)), child: profile.photoBase64 == null ? const Icon(Icons.person, size: 52, color: AppColors.textPrimary) : null),
        Container(padding: const EdgeInsets.all(7), decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 17, color: Colors.black)),
      ]))),
      const SizedBox(height: 8), Center(child: Text('Toca na fotografia para a alterar', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
      const SizedBox(height: 24), Text('NOME DE OPERADOR', style: TextStyle(color: AppColors.textSecondary)), const SizedBox(height: 8),
      TextField(controller: _name, maxLength: 24, style: const TextStyle(color: AppColors.textPrimary), decoration: const InputDecoration(hintText: 'Nome que o parceiro verá')),
      const SizedBox(height: 20), Text('ESTATÍSTICAS', style: TextStyle(color: AppColors.textSecondary, fontSize: 18)), const SizedBox(height: 12),
      Row(children: [_stat('JOGOS', '${profile.games}', AppColors.neonBlue), const SizedBox(width: 8), _stat('VITÓRIAS', '${profile.defused}', AppColors.success), const SizedBox(width: 8), _stat('DERROTAS', '${profile.exploded}', AppColors.danger)]),
      const SizedBox(height: 8), Row(children: [_stat('TAXA', '$winRate%', AppColors.amber), const SizedBox(width: 8), _stat('NOME', profile.name, AppColors.neonPurple)]),
      const SizedBox(height: 28), Text('CONQUISTAS', style: TextStyle(color: AppColors.textSecondary, fontSize: 18)), const SizedBox(height: 12),
      _achievement('PRIMEIRO CONTACTO', 'Completa a tua primeira partida.', profile.games >= 1, Icons.waving_hand),
      _achievement('BOMBA DESARMADA', 'Desarma uma bomba.', profile.defused >= 1, Icons.verified),
      _achievement('VETERANO', 'Joga cinco partidas.', profile.games >= 5, Icons.military_tech),
      _achievement('ESPECIALISTA', 'Desarma cinco bombas.', profile.defused >= 5, Icons.workspace_premium),
      const SizedBox(height: 24), MenuButton(label: 'GUARDAR PERFIL', color: AppColors.success, onPressed: () async { await ref.read(profileProvider.notifier).setName(_name.text); if (context.mounted) Navigator.pop(context); }),
    ])));
  }

  Widget _stat(String label, String value, Color color) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4), color: AppColors.card, child: Column(children: [Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 22)), const SizedBox(height: 4), Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11))])));
  Widget _achievement(String title, String description, bool unlocked, IconData icon) => Container(margin: const EdgeInsets.only(bottom: 8), color: AppColors.card, child: ListTile(leading: Icon(icon, color: unlocked ? AppColors.amber : AppColors.textDim), title: Text(title, style: TextStyle(color: unlocked ? AppColors.textPrimary : AppColors.textDim)), subtitle: Text(description, style: TextStyle(color: AppColors.textSecondary)), trailing: Icon(unlocked ? Icons.check_circle : Icons.lock_outline, color: unlocked ? AppColors.success : AppColors.textDim)));
}
