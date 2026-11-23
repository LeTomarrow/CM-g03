import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/core/app_theme.dart';
import 'package:what_did_you_press/features/update/update_controller.dart';

/// Checks once at start-up and offers the update, if there is one.
Future<void> checkForUpdateOnStart(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = container.read(updateControllerProvider.notifier);
  if (!controller.canSelfUpdate) return;
  await controller.check();
  final state = container.read(updateControllerProvider);
  if (!context.mounted || state.status != UpdateStatus.available) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Versão ${state.latest!.version} disponível'),
      content: Text(
        'Tens a ${state.version}. Atualizar agora? A app descarrega a nova '
        'versão e o Android pede-te para confirmar a instalação.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('MAIS TARDE'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('ATUALIZAR'),
        ),
      ],
    ),
  );
  if (accepted == true) controller.install();
}

/// Settings entry: current version and the update action.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key});

  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile> {
  @override
  void initState() {
    super.initState();
    // Fills in the version (and the check result) if start-up did not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(updateControllerProvider);
      if (state.version == null) {
        ref.read(updateControllerProvider.notifier).check();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final version = state.version == null
        ? '—'
        : '${state.version} (build ${state.build})';
    final status = switch (state.status) {
      UpdateStatus.idle || UpdateStatus.checking => 'A procurar atualizações…',
      UpdateStatus.upToDate => 'Tens a versão mais recente.',
      UpdateStatus.available => 'Nova versão: ${state.latest!.version}',
      UpdateStatus.downloading => 'A descarregar…',
      UpdateStatus.installing => 'A abrir o instalador…',
      UpdateStatus.error => state.message ?? 'Erro.',
    };
    final busy =
        state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.installing;
    final canInstall = controller.canSelfUpdate && state.canInstall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Versão'),
          trailing: Text(
            version,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Text(status, style: const TextStyle(color: AppColors.textSecondary)),
        if (state.status == UpdateStatus.downloading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.progress,
            color: AppColors.neonBlue,
            backgroundColor: AppColors.metalGrey,
          ),
        ],
        if (!controller.canSelfUpdate)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'A atualização automática só existe no Android. No iOS, as '
              'versões novas chegam pela App Store ou pelo TestFlight.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        if (canInstall)
          OutlinedButton(
            onPressed: busy ? null : controller.install,
            child: Text('ATUALIZAR PARA ${state.latest!.version}'),
          )
        else
          OutlinedButton(
            onPressed: busy ? null : controller.check,
            child: const Text('PROCURAR ATUALIZAÇÕES'),
          ),
      ],
    );
  }
}
