import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profileNames = <String>[
  'Agente Zero', 'Fio Vermelho', 'Operador Delta', 'Capitão Fusível',
  'Mestre do Pavio', 'Código 404', 'Sentinela', 'Último Recurso',
];

class ProfileState {
  const ProfileState({required this.name, this.games = 0, this.defused = 0, this.exploded = 0, this.photoBase64});
  final String name;
  final int games;
  final int defused;
  final int exploded;
  final String? photoBase64;
  ProfileState copyWith({String? name, int? games, int? defused, int? exploded, String? photoBase64}) => ProfileState(
    name: name ?? this.name, games: games ?? this.games, defused: defused ?? this.defused,
    exploded: exploded ?? this.exploded, photoBase64: photoBase64 ?? this.photoBase64,
  );
}

final profileProvider = AsyncNotifierProvider<ProfileController, ProfileState>(ProfileController.new);

class ProfileController extends AsyncNotifier<ProfileState> {
  late SharedPreferences _prefs;
  @override
  Future<ProfileState> build() async {
    _prefs = await SharedPreferences.getInstance();
    return ProfileState(
      name: _prefs.getString('profile.name') ?? profileNames.first,
      games: _prefs.getInt('profile.games') ?? 0,
      defused: _prefs.getInt('profile.defused') ?? 0,
      exploded: _prefs.getInt('profile.exploded') ?? 0,
      photoBase64: _prefs.getString('profile.photo'),
    );
  }

  Future<void> setPhoto(XFile file) async {
    final current = state.asData?.value;
    if (current == null) return;
    final encoded = base64Encode(await file.readAsBytes());
    state = AsyncData(current.copyWith(photoBase64: encoded));
    await _prefs.setString('profile.photo', encoded);
  }

  Future<void> removePhoto() async {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(ProfileState(name: current.name, games: current.games, defused: current.defused, exploded: current.exploded));
    await _prefs.remove('profile.photo');
  }

  Future<void> setName(String value) async {
    final current = state.asData?.value;
    if (current == null) return;
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return;
    final safe = name.substring(0, name.length > 24 ? 24 : name.length);
    state = AsyncData(current.copyWith(name: safe));
    await _prefs.setString('profile.name', safe);
  }

  Future<void> recordGame({required bool defused}) async {
    final current = state.asData?.value;
    if (current == null) return;
    final next = current.copyWith(
      games: current.games + 1,
      defused: current.defused + (defused ? 1 : 0),
      exploded: current.exploded + (defused ? 0 : 1),
    );
    state = AsyncData(next);
    await _prefs.setInt('profile.games', next.games);
    await _prefs.setInt('profile.defused', next.defused);
    await _prefs.setInt('profile.exploded', next.exploded);
  }
}

class SettingsState {
  const SettingsState({this.sfxVolume = .8, this.musicVolume = .5, this.vibration = true, this.screenAlwaysOn = true});
  final double sfxVolume;
  final double musicVolume;
  final bool vibration;
  final bool screenAlwaysOn;
  SettingsState copyWith({double? sfxVolume, double? musicVolume, bool? vibration, bool? screenAlwaysOn}) => SettingsState(
    sfxVolume: sfxVolume ?? this.sfxVolume, musicVolume: musicVolume ?? this.musicVolume,
    vibration: vibration ?? this.vibration, screenAlwaysOn: screenAlwaysOn ?? this.screenAlwaysOn,
  );
}

final settingsProvider = AsyncNotifierProvider<SettingsController, SettingsState>(SettingsController.new);

class SettingsController extends AsyncNotifier<SettingsState> {
  late SharedPreferences _prefs;
  @override
  Future<SettingsState> build() async {
    _prefs = await SharedPreferences.getInstance();
    return SettingsState(
      sfxVolume: _prefs.getDouble('settings.sfx') ?? .8,
      musicVolume: _prefs.getDouble('settings.music') ?? .5,
      vibration: _prefs.getBool('settings.vibration') ?? true,
      screenAlwaysOn: _prefs.getBool('settings.screen') ?? true,
    );
  }
  Future<void> updateSettings(SettingsState next) async {
    state = AsyncData(next);
    await Future.wait([
      _prefs.setDouble('settings.sfx', next.sfxVolume),
      _prefs.setDouble('settings.music', next.musicVolume),
      _prefs.setBool('settings.vibration', next.vibration),
      _prefs.setBool('settings.screen', next.screenAlwaysOn),
    ]);
  }
}
