import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/services/tilt_service.dart';

final tiltServiceProvider = Provider<TiltService>((ref) => TiltService());

/// Module-scoped sensor state. Riverpod cancels the subscription on disposal.
final tiltProvider = StreamProvider.autoDispose<TiltSample>(
  (ref) => ref.watch(tiltServiceProvider).watchTilt(),
);

class GyroAlignment {
  const GyroAlignment({this.sample, this.isAligning = false});

  final TiltSample? sample;
  final bool isAligning;
}

final gyroAlignmentProvider =
    NotifierProvider.autoDispose<GyroController, GyroAlignment>(
      GyroController.new,
    );

/// Captures the angle only during a deliberate press; release locks it.
class GyroController extends Notifier<GyroAlignment> {
  @override
  GyroAlignment build() {
    ref.listen(tiltProvider, (_, next) {
      if (state.isAligning) {
        state = GyroAlignment(sample: next.asData?.value, isAligning: true);
      }
    });
    return const GyroAlignment();
  }

  void startAlignment() {
    state = GyroAlignment(
      sample: ref.read(tiltProvider).asData?.value,
      isAligning: true,
    );
  }

  void lockAlignment() {
    state = GyroAlignment(sample: state.sample);
  }
}
