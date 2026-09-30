import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/external_app_checker.dart';

void main() {
  group('ExternalAppChecker.extractVersion', () {
    test('extracts standard semantic versions', () {
      expect(ExternalAppChecker.extractVersion('1.2.3'), '1.2.3');
      expect(ExternalAppChecker.extractVersion('v1.2.3'), '1.2.3');
      expect(ExternalAppChecker.extractVersion('Version 1.2.3'), '1.2.3');
      expect(ExternalAppChecker.extractVersion('version 1.2.3'), '1.2.3');
    });

    test('extracts versions with pre-release tags', () {
      expect(ExternalAppChecker.extractVersion('1.2.3-beta.1'), '1.2.3-beta.1');
      expect(ExternalAppChecker.extractVersion('v2.0.0-rc1'), '2.0.0-rc1');
      expect(ExternalAppChecker.extractVersion('1.0.0-alpha'), '1.0.0-alpha');
    });

    test('extracts versions from messy output', () {
      expect(ExternalAppChecker.extractVersion('git version 2.34.1'), '2.34.1');
      expect(ExternalAppChecker.extractVersion('Docker version 24.0.5, build ced0996'), '24.0.5');
      expect(ExternalAppChecker.extractVersion('Python 3.10.12'), '3.10.12');
      expect(ExternalAppChecker.extractVersion('autononext 0.3.5'), '0.3.5');
    });

    test('extracts short versions', () {
      expect(ExternalAppChecker.extractVersion('1.2'), '1.2');
      expect(ExternalAppChecker.extractVersion('v1.2'), '1.2');
    });

    test('returns null for unparseable output', () {
      expect(ExternalAppChecker.extractVersion('command not found'), isNull);
      expect(ExternalAppChecker.extractVersion('No package found matching'), isNull);
    });
  });

  group('ExternalAppChecker.getExternalVersion', () {
    late Directory tempDir;
    late String scriptPath;
    late String markerPath;
    late Future<ProcessResult> Function(String, List<String>) originalRunner;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ext_app_checker_test');
      scriptPath = '${tempDir.path}/linsticky';
      markerPath = '${tempDir.path}/launched.marker';
      // A launcher that discards its arguments and starts a GUI. Writing the
      // marker is the observable side effect of it being run.
      await File(scriptPath).writeAsString('#!/bin/sh\ntouch "$markerPath"\n');
      await Process.run('chmod', ['+x', scriptPath]);
      originalRunner = ExternalAppChecker.processRunner;
    });

    tearDown(() {
      ExternalAppChecker.processRunner = originalRunner;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('a package-owned launcher that ignores arguments is never executed',
        () async {
      ExternalAppChecker.processRunner = (executable, args) async {
        if (executable == 'which' &&
            args.length == 1 &&
            args.first == 'linsticky') {
          return ProcessResult(0, 0, scriptPath, '');
        }
        if (executable == 'dpkg' &&
            args.length == 2 &&
            args[0] == '-S' &&
            args[1] == scriptPath) {
          return ProcessResult(0, 0, 'io.linsticky.app: $scriptPath', '');
        }
        if (executable == 'dpkg-query' &&
            args.length == 3 &&
            args[0] == '-W' &&
            args[1] == r'--showformat=${Version}' &&
            args[2] == 'io.linsticky.app') {
          return ProcessResult(0, 0, '2.0.3', '');
        }
        return ProcessResult(0, 1, '', '');
      };

      final app = TrackedApp(
        repoOwner: 'io',
        repoName: 'linsticky',
        displayName: 'Linsticky',
        launchCommand: 'linsticky',
        packageName: 'linsticky',
        createdAt: DateTime(2026, 1, 1),
      );

      final version = await ExternalAppChecker.getExternalVersion(app);

      expect(version, '2.0.3');
      expect(File(markerPath).existsSync(), isFalse,
          reason: 'the launcher must not be executed by the version probe');
    });
  });
}
