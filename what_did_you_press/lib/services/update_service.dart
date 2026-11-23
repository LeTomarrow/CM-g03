import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A published version of the app (a GitHub release with an APK attached).
class AppRelease {
  const AppRelease({
    required this.version,
    required this.apkUrl,
    this.sha256,
    this.notes = '',
  });

  /// `X.Y.Z`, from the release tag `vX.Y.Z`.
  final String version;
  final String apkUrl;

  /// Hex digest of the APK, checked after download when GitHub provides it.
  final String? sha256;
  final String notes;
}

/// Compares `X.Y.Z` versions numerically (`1.10.0` > `1.9.3`), ignoring a
/// leading `v` and any `+build` suffix. Missing parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String version) => version
      .replaceFirst(RegExp('^v'), '')
      .split('+')
      .first
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  final left = parts(a);
  final right = parts(b);
  for (var i = 0; i < 3; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// Reads a GitHub "latest release" response; null without a usable APK.
AppRelease? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  final assets = json['assets'];
  if (tag is! String || !tag.startsWith('v') || assets is! List) return null;
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'];
    final url = asset['browser_download_url'];
    if (name is! String || !name.endsWith('.apk') || url is! String) continue;
    final digest = asset['digest'];
    return AppRelease(
      version: tag.substring(1),
      apkUrl: url,
      sha256: digest is String && digest.startsWith('sha256:')
          ? digest.substring('sha256:'.length)
          : null,
      notes: json['body'] is String ? json['body'] as String : '',
    );
  }
  return null;
}

/// Version info and self-update through GitHub Releases. The repository must
/// be public: the app holds no token, so it only reads public releases.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const repository = 'LeTomarrow/CM-g03';

  final http.Client _client;

  /// Android installs APKs; iOS apps can only update through the App Store
  /// or TestFlight, and desktop builds are for development.
  bool get canSelfUpdate =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<({String version, String build})> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, build: info.buildNumber);
  }

  /// The newest published release, or null if there is none or it cannot be
  /// reached (offline, rate-limited, repository not public).
  Future<AppRelease?> latestRelease() async {
    final response = await _client
        .get(
          Uri.https('api.github.com', '/repos/$repository/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body);
    return json is Map<String, dynamic> ? parseRelease(json) : null;
  }

  /// Downloads the APK and hands it to the system installer, which asks the
  /// player to confirm (and, the first time, to allow installs from the app).
  Stream<OtaEvent> install(AppRelease release) => OtaUpdate().execute(
    release.apkUrl,
    destinationFilename: 'wdyp-${release.version}.apk',
    sha256checksum: release.sha256,
  );
}
