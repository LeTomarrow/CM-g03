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

  factory BombLoadout.generate({required int seed, int moduleCount = 5}) {
    final random = Random(seed);
    final types = [...ModuleType.values]..shuffle(random);
    final modules = List.generate(moduleCount, (index) {
      final type = types[index % types.length];
      return BombModuleState(
        id: 'module-$index',
        type: type,
        variant: random.nextInt(3),
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
