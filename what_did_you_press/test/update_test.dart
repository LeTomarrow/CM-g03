import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ota_update/ota_update.dart';
import 'package:what_did_you_press/features/update/update_controller.dart';
import 'package:what_did_you_press/services/update_service.dart';

Map<String, dynamic> _release(String tag, {String? digest}) => {
  'tag_name': tag,
  'body': 'notas',
  'assets': [
    {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt'},
    {
      'name': 'wdyp-$tag.apk',
      'browser_download_url': 'https://x/wdyp.apk',
      'digest': ?digest,
    },
  ],
};

class _FakeService extends UpdateService {
  _FakeService({this.installed = '1.0.0', this.published});

  final String installed;
  final AppRelease? published;
  final installs = StreamController<OtaEvent>.broadcast();

  @override
  bool get canSelfUpdate => true;

  @override
  Future<({String version, String build})> currentVersion() async =>
      (version: installed, build: '7');

  @override
  Future<AppRelease?> latestRelease() async => published;

  @override
  Stream<OtaEvent> install(AppRelease release) => installs.stream;
}

void main() {
  group('compareVersions', () {
    test('compares numerically, not as text', () {
      expect(compareVersions('1.10.0', '1.9.3'), greaterThan(0));
      expect(compareVersions('0.2.0', '0.10.0'), lessThan(0));
    });

    test('ignores the v prefix, the build number and missing parts', () {
      expect(compareVersions('v1.2.0', '1.2.0+15'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.1', '1.2'), greaterThan(0));
    });
  });

  group('parseRelease', () {
    test('takes the APK asset and its sha256 digest', () {
      final release = parseRelease(
        _release('v0.3.0', digest: 'sha256:abc123'),
      )!;
      expect(release.version, '0.3.0');
      expect(release.apkUrl, 'https://x/wdyp.apk');
      expect(release.sha256, 'abc123');
      expect(release.notes, 'notas');
    });

    test('rejects releases without an APK or a vX tag', () {
      expect(parseRelease({'tag_name': 'v1.0.0', 'assets': []}), isNull);
      expect(parseRelease(_release('latest')), isNull);
      expect(parseRelease(_release('v1.0.0'))!.sha256, isNull);
    });
  });

  group('UpdateService.latestRelease', () {
    test('reads the public GitHub API without credentials', () async {
      late http.Request sent;
      final service = UpdateService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode(_release('v2.0.0')), 200);
        }),
      );
      final release = await service.latestRelease();
      expect(release!.version, '2.0.0');
      expect(
        sent.url.toString(),
        'https://api.github.com/repos/${UpdateService.repository}'
        '/releases/latest',
      );
      expect(sent.headers.containsKey('Authorization'), isFalse);
    });

    test('a private repo or no releases (404) means no update', () async {
      final service = UpdateService(
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      expect(await service.latestRelease(), isNull);
    });
  });

  group('UpdateController', () {
    const newer = AppRelease(version: '1.1.0', apkUrl: 'https://x/a.apk');

    ProviderContainer containerWith(_FakeService service) {
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a newer release is offered; the same one is not', () async {
      final container = containerWith(_FakeService(published: newer));
      await container.read(updateControllerProvider.notifier).check();
      final state = container.read(updateControllerProvider);
      expect(state.status, UpdateStatus.available);
      expect(state.version, '1.0.0');
      expect(state.build, '7');
      expect(state.canInstall, isTrue);

      final same = containerWith(
        _FakeService(installed: '1.1.0', published: newer),
      );
      await same.read(updateControllerProvider.notifier).check();
      expect(same.read(updateControllerProvider).status, UpdateStatus.upToDate);
      expect(same.read(updateControllerProvider).canInstall, isFalse);
    });

    test('unreachable releases are an error, not an update', () async {
      final container = containerWith(_FakeService());
      await container.read(updateControllerProvider.notifier).check();
      final state = container.read(updateControllerProvider);
      expect(state.status, UpdateStatus.error);
      expect(state.canInstall, isFalse);
    });

    test('install reports progress, then hands over to Android', () async {
      final service = _FakeService(published: newer);
      final container = containerWith(service);
      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      controller.install();
      service.installs.add(OtaEvent(OtaStatus.DOWNLOADING, '40'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(updateControllerProvider).progress, 0.4);
      service.installs.add(OtaEvent(OtaStatus.INSTALLING, null));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(updateControllerProvider).status,
        UpdateStatus.installing,
      );
    });

    test('a refused install permission can be retried', () async {
      final service = _FakeService(published: newer);
      final container = containerWith(service);
      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      controller.install();
      service.installs.add(
        OtaEvent(OtaStatus.PERMISSION_NOT_GRANTED_ERROR, null),
      );
      await Future<void>.delayed(Duration.zero);
      final state = container.read(updateControllerProvider);
      expect(state.status, UpdateStatus.error);
      expect(state.message, contains('Autoriza'));
      expect(state.canInstall, isTrue);
    });
  });
}
