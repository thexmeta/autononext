// End-to-end proof: real GitHub release -> real asset download -> real install
// into a throwaway target under /tmp. Nothing outside /tmp is written.
//
// NOTE: do NOT call TestWidgetsFlutterBinding.ensureInitialized() here — under
// flutter test that binding stubs every HttpClient to return 400, so live
// network probes silently stop working. Plain test() keeps the real event loop
// AND the real network.
//
// Run with: flutter test tool/e2e_upgrade_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/services/installer_service.dart';

void main() {
  test('E2E: real release asset installs as a working binary', () async {
    final gh = GitHubService();
    final installer = InstallerService();

    // 1. Real asset selection against live GitHub.
    final info = await gh.getLatestReleaseWithPackageInfo(
      'Dicklesworthstone',
      'beads_rust',
      assetFilterPattern: '*tar.gz',
      architectures: ['amd64'],
    );
    expect(info, isNotNull, reason: 'release lookup must succeed');
    final assetName = info!['packageName'] as String?;
    final downloadUrl = info['downloadUrl'] as String?;
    // ignore: avoid_print
    print('PROBE asset=$assetName');
    expect(assetName, isNotNull);
    expect(downloadUrl, isNotNull);
    expect(assetName, contains('linux'),
        reason: 'must not select a darwin/windows asset');

    // 2. Real download through the app's own downloader. This exercises the
    //    https check, the manual redirect following (GitHub redirects to
    //    objects.githubusercontent.com) and the streaming size cap against the
    //    live service, which a fake client cannot prove.
    final supportDir = Directory.systemTemp.createTempSync('autononext_support_');
    installer.appSupportDirectory = () async => supportDir;
    final file = await installer.downloadFile(downloadUrl!, assetName!);
    // ignore: avoid_print
    print('PROBE downloaded=${file.path} bytes=${await file.length()}');
    expect(await file.length(), greaterThan(1000));

    // 3. Real install into a throwaway target.
    final type = installer.identifyAssetType(assetName);
    // ignore: avoid_print
    print('PROBE identifiedType=$type');
    expect(type, isNotNull, reason: 'archive must map to InstallType.binary');
    expect(type!.name, 'binary');

    final outDir = Directory.systemTemp.createTempSync('autononext_e2e_');
    final target = '${outDir.path}/br';
    File(target).writeAsStringSync('OLD-BINARY-BYTES'); // pre-existing target

    final result = await installer.installPackage(
      file,
      type,
      targetPath: target,
      binaryName: 'br',
    );
    // ignore: avoid_print
    print('PROBE result=($result)');
    expect(result.launchCommand, target);

    final installed = File(target);
    expect(await installed.exists(), isTrue);

    final st = await installed.stat();
    // ignore: avoid_print
    print('PROBE mode=${st.modeString()} size=${st.size}');
    expect(st.mode & 0x111, isNonZero, reason: 'must be executable');

    final bytes = await installed.readAsBytes();
    expect(bytes[0], 0x7F);
    expect(bytes[1], 0x45); // E
    expect(bytes[2], 0x4C); // L
    expect(bytes[3], 0x46); // F
    // ignore: avoid_print
    print('PROBE ELF magic OK size=${bytes.length}');

    // Previous binary must survive as <target>.bak with the OLD content.
    final bak = File('$target.bak');
    expect(await bak.exists(), isTrue, reason: 'previous binary must be backed up');
    expect(bak.readAsStringSync(), 'OLD-BINARY-BYTES');
    // ignore: avoid_print
    print('PROBE backup preserved old bytes');

    // The installed binary must actually run.
    final run = await Process.run(target, ['--version']);
    // ignore: avoid_print
    print('PROBE exec exit=${run.exitCode} out=${(run.stdout as String).trim()}');
    expect(run.exitCode, 0);

    // Cleanup: only files this test created.
    supportDir.deleteSync(recursive: true);
    outDir.deleteSync(recursive: true);
    // ignore: avoid_print
    print('PROBE cleanup done');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
