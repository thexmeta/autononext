// ignore_for_file: avoid_print
// READ-ONLY audit — NOT part of the test suite.
// Run: dart run tool/hidden_updates_audit.dart
//
// Lists every tracked app whose installed and latest versions DIFFER but which
// is not flagged as having an update, with the reason. This is how the hidden
// updates for biomejs/biome (`@biomejs/biome@2.5.15`) and refactoringhq/tolaria
// (`alpha-v2026.9.25-alpha.0006`) were found — both were real updates that the
// version-shape check was suppressing.
import 'dart:convert';
import 'dart:io';
import 'package:autononext/models/tracked_app.dart';

void main() {
  final raw = File('${Platform.environment['HOME']}/.local/share/com.autononext/apps.json').readAsStringSync();
  final apps = (jsonDecode(raw) as List)
      .cast<Map<String, dynamic>>()
      .map(TrackedApp.fromMap)
      .toList();

  var hidden = 0;
  for (final a in apps) {
    final inst = a.installedVersion;
    final latest = a.latestVersion;
    if (inst == null || latest == null) continue;
    if (a.hasUpdate) continue;
    final ni = normalizeVersion(inst);
    final nl = normalizeVersion(latest);
    if (ni == nl) continue; // genuinely the same version
    hidden++;
    print('HIDDEN  ${a.repoOwner}/${a.repoName}  inst=$inst  latest=$latest  '
        'looksLikeVersion=${looksLikeVersion(latest)}  isNewer=${isNewerVersion(nl, ni)}');
  }
  print('total=${apps.length} hasUpdate=${apps.where((a) => a.hasUpdate).length} hiddenCandidates=$hidden');
}
