import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/external_app_checker.dart';

/// The tracked app used by the version-probe tests below.
TrackedApp _probeApp() => TrackedApp(
      repoOwner: 'io',
      repoName: 'linsticky',
      displayName: 'Linsticky',
      launchCommand: 'linsticky',
      packageName: 'linsticky',
      createdAt: DateTime(2026, 1, 1),
    );

/// Installs a runner that answers only the commands the version probe issues:
/// `which` always resolves to [scriptPath], `dpkg-query` never matches, and the
/// owning-package lookups return [dpkgS] / [rpm] verbatim.
void _installRunner({
  required String scriptPath,
  required ProcessResult dpkgS,
  required ProcessResult rpm,
}) {
  ExternalAppChecker.processRunner = (executable, args) async {
    if (executable == 'dpkg-query') return ProcessResult(0, 1, '', '');
    if (executable == 'which') return ProcessResult(0, 0, scriptPath, '');
    if (executable == 'dpkg' && args.length == 2 && args[0] == '-S') {
      return dpkgS;
    }
    if (executable == 'rpm' && args.length == 4 && args[0] == '-qf') {
      return rpm;
    }
    return ProcessResult(0, 1, '', '');
  };
}

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

    test('falls back to rpm when no dpkg package owns the binary', () async {
      _installRunner(
        scriptPath: scriptPath,
        // Not owned by any dpkg package: dpkg -S exits non-zero.
        dpkgS: ProcessResult(0, 1, '', 'dpkg-query: no path found matching pattern'),
        rpm: ProcessResult(0, 0, '2.0.3\n', ''),
      );

      final version = await ExternalAppChecker.getExternalVersion(_probeApp());

      expect(version, '2.0.3');
      expect(File(markerPath).existsSync(), isFalse,
          reason: 'the owning package answered, so the binary must not run');
    });

    test('falls back to rpm when dpkg -S names an owner with no version',
        () async {
      _installRunner(
        scriptPath: scriptPath,
        dpkgS: ProcessResult(0, 0, 'io.linsticky.app: $scriptPath', ''),
        // dpkg-query for that owner yields nothing (exit 1 from the runner's
        // dpkg-query branch), so the probe must continue to rpm.
        rpm: ProcessResult(0, 0, '2.0.3\n', ''),
      );

      final version = await ExternalAppChecker.getExternalVersion(_probeApp());

      expect(version, '2.0.3');
      expect(File(markerPath).existsSync(), isFalse,
          reason: 'the owning package answered, so the binary must not run');
    });

    test('returns the raw rpm output when it holds no parseable version',
        () async {
      _installRunner(
        scriptPath: scriptPath,
        dpkgS: ProcessResult(0, 1, '', ''),
        rpm: ProcessResult(0, 0, 'unknown\n', ''),
      );

      final version = await ExternalAppChecker.getExternalVersion(_probeApp());

      expect(version, 'unknown');
      expect(File(markerPath).existsSync(), isFalse,
          reason: 'the owning package answered, so the binary must not run');
    });

    test('still executes the binary when no package owns it', () async {
      _installRunner(
        scriptPath: scriptPath,
        dpkgS: ProcessResult(0, 1, '', ''),
        rpm: ProcessResult(0, 1, '', ''),
      );

      final version = await ExternalAppChecker.getExternalVersion(_probeApp());

      // The canary prints nothing, so no version is discoverable...
      expect(version, isNull);
      // ...but the marker proves the --version probe still ran. Without this,
      // the "never execute" fix could silently break plain PATH binaries.
      expect(File(markerPath).existsSync(), isTrue,
          reason: 'an unowned binary must still be probed directly');
    });

    test('waits out a slow package lookup instead of executing the binary',
        () async {
      // `dpkg -S` scans the whole package file database rather than an index:
      // measured at ~1.8 s warm on a 3808-package system. The original 2 s
      // budget expired there and fell through to running the launcher, so the
      // lookup must tolerate well past that.
      ExternalAppChecker.processRunner = (executable, args) async {
        if (executable == 'which') return ProcessResult(0, 0, scriptPath, '');
        if (executable == 'dpkg' && args.length == 2 && args[0] == '-S') {
          await Future<void>.delayed(const Duration(milliseconds: 2500));
          return ProcessResult(0, 0, 'io.linsticky.app: $scriptPath', '');
        }
        if (executable == 'dpkg-query' &&
            args.length == 3 &&
            args[2] == 'io.linsticky.app') {
          return ProcessResult(0, 0, '2.0.3', '');
        }
        return ProcessResult(0, 1, '', '');
      };

      final version = await ExternalAppChecker.getExternalVersion(_probeApp());

      expect(version, '2.0.3');
      expect(File(markerPath).existsSync(), isFalse,
          reason: 'a slow lookup must not fall back to running the launcher');
    });
  });

  group('ExternalAppChecker.isExecutableOnPath', () {
    late Future<ProcessResult> Function(String, List<String>) originalRunner;

    setUp(() {
      originalRunner = ExternalAppChecker.processRunner;
    });

    tearDown(() {
      ExternalAppChecker.processRunner = originalRunner;
    });

    test('true when which resolves a path', () async {
      ExternalAppChecker.processRunner = (executable, args) async => ProcessResult(
            0,
            0,
            '/usr/bin/mq\n',
            '',
          );
      expect(await ExternalAppChecker.isExecutableOnPath('mq'), isTrue);
    });

    test('false when nothing by that name runs', () async {
      // FluxDown: the repository name is not the name of anything installed.
      ExternalAppChecker.processRunner =
          (executable, args) async => ProcessResult(0, 1, '', '');
      expect(await ExternalAppChecker.isExecutableOnPath('fluxdown'), isFalse);
    });

    test('false for an empty name, without running anything', () async {
      var called = false;
      ExternalAppChecker.processRunner = (executable, args) async {
        called = true;
        return ProcessResult(0, 0, '/usr/bin/x', '');
      };
      expect(await ExternalAppChecker.isExecutableOnPath(''), isFalse);
      expect(called, isFalse, reason: 'an empty name cannot be a command');
    });

    test('false when which succeeds but prints no path', () async {
      ExternalAppChecker.processRunner =
          (executable, args) async => ProcessResult(0, 0, '', '');
      expect(await ExternalAppChecker.isExecutableOnPath('mq'), isFalse);
    });
  });
}
