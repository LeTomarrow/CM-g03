import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:what_did_you_press/services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  error,
}

class UpdateState {
  const UpdateState({
    this.version,
    this.build,
    this.status = UpdateStatus.idle,
    this.latest,
    this.progress,
    this.message,
  });

  final String? version;
  final String? build;
  final UpdateStatus status;
  final AppRelease? latest;

  /// Download progress from 0 to 1, while downloading.
  final double? progress;
  final String? message;

  /// A published version newer than the installed one is known.
  bool get hasNewer =>
      latest != null &&
      version != null &&
      compareVersions(latest!.version, version!) > 0;

  /// Nothing in flight, and a newer version to install (again, after an
  /// error).
  bool get canInstall =>
      hasNewer &&
      (status == UpdateStatus.available || status == UpdateStatus.error);

  UpdateState copyWith({
    String? version,
    String? build,
    UpdateStatus? status,
    AppRelease? latest,
    double? progress,
    String? message,
  }) => UpdateState(
    version: version ?? this.version,
    build: build ?? this.build,
    status: status ?? this.status,
    latest: latest ?? this.latest,
    progress: progress,
    message: message,
  );
}

/// App-wide (not auto-disposed): the menu checks once at start-up and the
/// settings page shows the same result.
final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

class UpdateController extends Notifier<UpdateState> {
  StreamSubscription<OtaEvent>? _download;

  @override
  UpdateState build() {
    ref.onDispose(() => _download?.cancel());
    return const UpdateState();
  }

  UpdateService get _service => ref.read(updateServiceProvider);

  bool get canSelfUpdate => _service.canSelfUpdate;

  Future<void> check() async {
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.installing) {
      return;
    }
    state = state.copyWith(status: UpdateStatus.checking);
    try {
      final current = await _service.currentVersion();
      state = state.copyWith(
        version: current.version,
        build: current.build,
        status: UpdateStatus.checking,
      );
      final latest = await _service.latestRelease();
      if (latest == null) {
        state = state.copyWith(
          status: UpdateStatus.error,
          message: 'Não foi possível consultar as versões publicadas.',
        );
      } else if (compareVersions(latest.version, current.version) > 0) {
        state = state.copyWith(status: UpdateStatus.available, latest: latest);
      } else {
        state = state.copyWith(status: UpdateStatus.upToDate, latest: latest);
      }
    } catch (_) {
      state = state.copyWith(
        status: UpdateStatus.error,
        message: 'Sem ligação. Tenta novamente mais tarde.',
      );
    }
  }

  void install() {
    final latest = state.latest;
    if (latest == null || !canSelfUpdate || !state.canInstall) return;
    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    _download?.cancel();
    _download = _service
        .install(latest)
        .listen(
          (event) => state = switch (event.status) {
            OtaStatus.DOWNLOADING => state.copyWith(
              status: UpdateStatus.downloading,
              progress: (double.tryParse(event.value ?? '') ?? 0) / 100,
            ),
            OtaStatus.INSTALLING || OtaStatus.INSTALLATION_DONE =>
              state.copyWith(status: UpdateStatus.installing),
            OtaStatus.PERMISSION_NOT_GRANTED_ERROR => state.copyWith(
              status: UpdateStatus.error,
              message:
                  'Autoriza a instalação de apps desta origem nas definições '
                  'do Android e tenta outra vez.',
            ),
            OtaStatus.CHECKSUM_ERROR => state.copyWith(
              status: UpdateStatus.error,
              message: 'O ficheiro descarregado está corrompido.',
            ),
            OtaStatus.CANCELED => state.copyWith(
              status: UpdateStatus.available,
            ),
            _ => state.copyWith(
              status: UpdateStatus.error,
              message: 'A atualização falhou. Tenta novamente.',
            ),
          },
          onError: (Object _) => state = state.copyWith(
            status: UpdateStatus.error,
            message: 'A atualização falhou. Tenta novamente.',
          ),
        );
  }
}
