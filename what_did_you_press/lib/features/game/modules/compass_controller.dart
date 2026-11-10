import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:what_did_you_press/services/compass_service.dart';

final compassServiceProvider = Provider<CompassService>(
  (ref) => CompassService(),
);

/// Module-scoped sensor state. Riverpod cancels the subscription on disposal.
final compassHeadingProvider = StreamProvider.autoDispose<CompassSample>(
  (ref) => ref.watch(compassServiceProvider).watchHeading(),
);

class CompassAlignment {
  const CompassAlignment({this.sample, this.isAligning = false});

  final CompassSample? sample;
  final bool isAligning;
}

final compassAlignmentProvider =
    NotifierProvider.autoDispose<CompassController, CompassAlignment>(
      CompassController.new,
    );

/// Captures heading only during a deliberate press; release locks the answer.
class CompassController extends Notifier<CompassAlignment> {
  @override
  CompassAlignment build() {
    ref.listen(compassHeadingProvider, (_, next) {
      if (state.isAligning) {
        state = CompassAlignment(sample: next.asData?.value, isAligning: true);
      }
    });
    return const CompassAlignment();
  }

  void startAlignment() {
    state = CompassAlignment(
      sample: ref.read(compassHeadingProvider).asData?.value,
      isAligning: true,
    );
  }

  void lockAlignment() {
    state = CompassAlignment(sample: state.sample);
  }
}
