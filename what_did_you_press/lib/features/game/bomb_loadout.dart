import 'dart:math';

import 'package:what_did_you_press/core/game_models.dart';

enum ModuleStatus { pending, solved }

class BombModuleState {
  const BombModuleState({
    required this.id,
    required this.type,
    required this.variant,
    this.status = ModuleStatus.pending,
    this.failureCount = 0,
  });

  final String id;
  final ModuleType type;
  final int variant;
  final ModuleStatus status;
  final int failureCount;

  bool get solved => status == ModuleStatus.solved;

  BombModuleState copyWith({ModuleStatus? status, int? failureCount}) =>
      BombModuleState(
        id: id,
        type: type,
        variant: variant,
        status: status ?? this.status,
        failureCount: failureCount ?? this.failureCount,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'variant': variant,
    'status': status.name,
    'failureCount': failureCount,
  };

  factory BombModuleState.fromJson(Map<String, dynamic> json) =>
      BombModuleState(
        id: json['id'] as String,
        type: ModuleType.values.byName(json['type'] as String),
        variant: json['variant'] as int,
        status: ModuleStatus.values.byName(json['status'] as String),
        failureCount: json['failureCount'] as int,
      );
}

class BombLoadout {
  const BombLoadout({required this.seed, required this.modules});

  /// Five modules fit the five-minute timer:
  /// - one AR module (they make the operator walk around, so they are slow);
  /// - one of Ângulo/Bússola, which play alike (a sequence, a sum, orient
  ///   the phone), kept apart from AR so sensor modules do not pile up;
  /// - three of the four classic modules.
  /// [moduleCount] is smaller only in tests.
  static const int defaultModuleCount = 5;

  factory BombLoadout.generate({
    required int seed,
    int moduleCount = defaultModuleCount,
  }) {
    final random = Random(seed);
    ModuleType pick(List<ModuleType> slot) => slot[random.nextInt(slot.length)];
    final classics = [...ModuleType.classic]..shuffle(random);
    final types = [
      pick(ModuleType.augmented),
      pick(ModuleType.orientation),
      ...classics.take(3),
    ]..shuffle(random);
    assert(types.length == defaultModuleCount);
    final modules = List.generate(moduleCount, (index) {
      final type = types[index];
      return BombModuleState(
        id: 'module-$index',
        type: type,
        // A seed for the module's generated puzzle, not a table index.
        variant: random.nextInt(1 << 30),
      );
    });
    return BombLoadout(seed: seed, modules: List.unmodifiable(modules));
  }

  final int seed;
  final List<BombModuleState> modules;

  BombLoadout copyWith({List<BombModuleState>? modules}) => BombLoadout(
    seed: seed,
    modules: List.unmodifiable(modules ?? this.modules),
  );

  List<Map<String, dynamic>> toJson() =>
      modules.map((module) => module.toJson()).toList();

  factory BombLoadout.fromJson({
    required int seed,
    required List<dynamic> json,
  }) => BombLoadout(
    seed: seed,
    modules: List.unmodifiable(
      json.map(
        (module) =>
            BombModuleState.fromJson(Map<String, dynamic>.from(module as Map)),
      ),
    ),
  );
}
