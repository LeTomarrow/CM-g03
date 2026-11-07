import 'dart:async';
import 'dart:isolate';

class BombEngineState {
  const BombEngineState({
    required this.timeLeft,
    required this.strikes,
    required this.solvedModules,
    required this.status,
  });

  final Duration timeLeft;
  final int strikes;
  final Set<int> solvedModules;
  final BombEngineStatus status;
}

enum BombEngineStatus { running, defused, exploded }

/// Authoritative timer and score, created only on the defuser device.
class BombEngine {
  BombEngine._(this._commands, this.states);

  final SendPort _commands;
  final Stream<BombEngineState> states;
  Isolate? _isolate;
  late final Future<void> Function() _cleanup;

  static Future<BombEngine> start({
    required Duration duration,
    required int moduleCount,
    int maxStrikes = 3,
  }) async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    final stateController = StreamController<BombEngineState>.broadcast();
    final isolate = await Isolate.spawn(_run, {
      'port': receive.sendPort,
      'durationMs': duration.inMilliseconds,
      'moduleCount': moduleCount,
      'maxStrikes': maxStrikes,
    });
    late final StreamSubscription<Object?> subscription;
    subscription = receive.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is Map) {
        stateController.add(_stateFrom(message));
      }
    });
    final commands = await ready.future;
    final engine = BombEngine._(commands, stateController.stream);
    engine._isolate = isolate;
    engine._cleanup = () async {
      await subscription.cancel();
      receive.close();
      await stateController.close();
    };
    return engine;
  }

  void solveModule(int index) =>
      _commands.send({'command': 'solve', 'index': index});

  void registerStrike() => _commands.send({'command': 'strike'});

  Future<void> dispose() async {
    _commands.send({'command': 'dispose'});
    _isolate?.kill(priority: Isolate.immediate);
    await _cleanup();
  }

  static BombEngineState _stateFrom(Map message) => BombEngineState(
    timeLeft: Duration(milliseconds: message['timeLeftMs'] as int),
    strikes: message['strikes'] as int,
    solvedModules: (message['solved'] as List).cast<int>().toSet(),
    status: BombEngineStatus.values.byName(message['status'] as String),
  );
}

void _run(Map<String, dynamic> args) {
  final receive = ReceivePort();
  final parent = args['port'] as SendPort;
  parent.send(receive.sendPort);
  final duration = Duration(milliseconds: args['durationMs'] as int);
  final moduleCount = args['moduleCount'] as int;
  final maxStrikes = args['maxStrikes'] as int;
  final startedAt = DateTime.now();
  final solved = <int>{};
  var strikes = 0;
  var status = BombEngineStatus.running;

  void emit() {
    final left = duration - DateTime.now().difference(startedAt);
    if (left <= Duration.zero && status == BombEngineStatus.running) {
      status = BombEngineStatus.exploded;
    }
    parent.send({
      'timeLeftMs': left.isNegative ? 0 : left.inMilliseconds,
      'strikes': strikes,
      'solved': solved.toList(),
      'status': status.name,
    });
  }

  emit();
  final timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (status == BombEngineStatus.running) emit();
  });
  receive.listen((message) {
    if (message is! Map || status != BombEngineStatus.running) return;
    switch (message['command']) {
      case 'solve':
        final index = message['index'];
        if (index is int && index >= 0 && index < moduleCount) {
          solved.add(index);
        }
        if (solved.length == moduleCount) status = BombEngineStatus.defused;
        emit();
      case 'strike':
        strikes++;
        if (strikes >= maxStrikes) status = BombEngineStatus.exploded;
        emit();
      case 'dispose':
        timer.cancel();
        receive.close();
    }
  });
}
