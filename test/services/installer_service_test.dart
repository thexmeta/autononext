import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:autononext/models/install_type.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/installer_service.dart';

/// Answers every request from [handler] so download behaviour can be driven
/// without a network.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

/// A response that carries [body] in [chunkSize] pieces.
///
/// [declareLength] is false to omit `Content-Length`, so a test can prove the
/// streaming guard catches an oversized body on its own.
http.StreamedResponse _body(
  http.BaseRequest request,
  List<int> body, {
  int statusCode = 200,
  int? contentLength,
  bool declareLength = true,
  int chunkSize = 16,
}) {
  final controller = StreamController<List<int>>();
  for (var i = 0; i < body.length; i += chunkSize) {
    controller.add(body.sublist(i, (i + chunkSize).clamp(0, body.length)));
  }
  controller.close();
  return http.StreamedResponse(
    controller.stream,
    statusCode,
    contentLength: declareLength ? (contentLength ?? body.length) : null,
    request: request,
  );
}

/// The exact wording shown when an archive contains no executable.
const noBinaryWarning =
    'This entry cant be installable. It doesnt include binary/executable.';

void main() {
  group('InstallerService.identifyAssetType', () {
    final service = InstallerService();
    test('maps archive suffixes to binary because they carry an extractable payload', () {
      for (final name in const [
        'tool.tar.gz',
        'tool.tgz',
        'tool.tar.xz',
        'tool.txz',
        'tool.tar.bz2',
        'tool.tbz2',
        'tool.tar.zst',
        'tool.zip',
      ]) {
        expect(service.identifyAssetType(name), InstallType.binary, reason: name);
      }
    });

    test('maps extension-less release asset names to binary', () {
      expect(
        service.identifyAssetType('computer-use-linux-x86_64-unknown-linux-gnu'),
        InstallType.binary,
      );
      expect(service.identifyAssetType('waza-linux-amd64'), InstallType.binary);
    });

    test('returns null for a script or json so they are never installed as executables', () {
      expect(service.identifyAssetType('download_cli.sh'), isNull);
      expect(service.identifyAssetType('latest.json'), isNull);
    });

    test('keeps deb/rpm/appimage detection so package formats still win', () {
      expect(service.identifyAssetType('tool.deb'), InstallType.deb);
      expect(service.identifyAssetType('tool.rpm'), InstallType.rpm);
      expect(service.identifyAssetType('Tool.AppImage'), InstallType.appImage);
    });

    test('rejects extension-less documentation and metadata so they are never offered as binaries', () {
      for (final name in const [
        'LICENSE',
        'README',
        'SHA256SUMS',
        'CHANGELOG',
        'latest',
        'checksums',
        '.gitignore',
      ]) {
        expect(service.identifyAssetType(name), isNull, reason: name);
      }
      // Real binaries must still be recognised.
      expect(
        service.identifyAssetType('computer-use-linux-x86_64-unknown-linux-gnu'),
        InstallType.binary,
      );
      expect(service.identifyAssetType('waza-linux-amd64'), InstallType.binary);
    });

    test('refuses an unanticipated extension-less metadata name, which no denylist can enumerate in advance', () {
      // The old rule was default-open: any extension-less name was a binary
      // unless it happened to be on the denylist. These all leaked through it.
      for (final name in const [
        'checksums-2026',
        'SHA256SUMS-2026',
        'release-info',
        'build-3',
        'notes',
        'KEYS',
        'SOURCE',
      ]) {
        expect(service.identifyAssetType(name), isNull, reason: name);
      }
    });

    test('still accepts an extension-less Linux binary because its name carries a platform token', () {
      for (final name in const [
        'waza-linux-amd64',
        'biome-linux-x64-musl',
        'computer-use-linux-x86_64-unknown-linux-gnu',
        'mytool-linux',
        'mytool-arm64',
        'mytool-musl',
      ]) {
        expect(service.identifyAssetType(name), InstallType.binary, reason: name);
      }
    });

    test('recognises a bare extension-less asset as the app binary when the name matches the app', () {
      // A release that ships a single bare `mytool` has no platform token to go
      // on, so the app's own name is the only positive signal available.
      final app = TrackedApp(
        repoOwner: 'owner',
        repoName: 'mytool',
        displayName: 'My Tool',
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      expect(
        service.identifyAssetType('mytool', app: app),
        InstallType.binary,
      );
      expect(
        service.identifyAssetType('Mytool', app: app),
        InstallType.binary,
      );
      // With no app context there is nothing to match, so it stays unclassified
      // rather than being assumed installable.
      expect(service.identifyAssetType('mytool'), isNull);
      // An unrelated bare name must not be matched by a different app.
      expect(service.identifyAssetType('othertool', app: app), isNull);
    });

    test('matches the expected executable through the launch command and package name', () {
      final app = TrackedApp(
        repoOwner: 'owner',
        repoName: 'repo',
        displayName: 'Repo',
        launchCommand: '/usr/local/bin/launched-tool --flag',
        packageName: 'pkg-tool',
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      expect(service.identifyAssetType('launched-tool', app: app), InstallType.binary);
      expect(service.identifyAssetType('pkg-tool', app: app), InstallType.binary);
    });
  });

  group('InstallerService.installPackage binary', () {
    final service = InstallerService();
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('autononext_inst_test_');
    });

    tearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    List<String> systemTempEntries() =>
        Directory.systemTemp.listSync().map((e) => p.basename(e.path)).toList();

    /// Copies a real ELF executable into [path] and marks it executable.
    File makeElf(String path) {
      final file = File('/usr/bin/true').copySync(path);
      Process.runSync('chmod', ['755', file.path]);
      return file;
    }

    test('installs an executable from a .tar.gz and preserves the old target as .bak', () async {
      final build = Directory(p.join(tmp.path, 'build'))..createSync();
      final binDir = Directory(p.join(build.path, 'bin'))..createSync();
      final tool = makeElf(p.join(binDir.path, 'mytool'));

      final archive = File(p.join(tmp.path, 'mytool.tar.gz'));
      final tarResult = Process.runSync(
        'tar',
        ['-czf', archive.path, '-C', build.path, 'bin'],
      );
      expect(tarResult.exitCode, 0, reason: tarResult.stderr.toString());

      final outDir = Directory(p.join(tmp.path, 'out'))..createSync();
      final target = File(p.join(outDir.path, 'mytool'))
        ..writeAsStringSync('OLD-BYTES');
      Process.runSync('chmod', ['755', target.path]);

      final before = systemTempEntries();

      final result = await service.installPackage(
        archive,
        InstallType.binary,
        targetPath: target.path,
        binaryName: 'mytool',
      );

      expect(target.existsSync(), isTrue);
      expect(target.statSync().mode & 0x49, isNot(0));
      expect(target.readAsBytesSync(), equals(tool.readAsBytesSync()));

      final backup = File('${target.path}.bak');
      expect(backup.existsSync(), isTrue);
      expect(backup.readAsStringSync(), 'OLD-BYTES');

      expect(result.launchCommand, target.path);
      expect(result.packageName, 'mytool');

      // No staging file left behind on the success path.
      expect(File('${target.path}.tmp').existsSync(), isFalse);

      final leftovers = systemTempEntries()
          .where((e) => e.startsWith('autononext_binary_') && !before.contains(e))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('installs an executable from a .zip', () async {
      final build = Directory(p.join(tmp.path, 'zbuild'))..createSync();
      final tool = makeElf(p.join(build.path, 'mytool'));

      final archive = File(p.join(tmp.path, 'mytool.zip'));
      final zipResult = Process.runSync(
        'zip',
        ['-q', '-r', archive.path, 'mytool'],
        workingDirectory: build.path,
      );
      expect(zipResult.exitCode, 0, reason: zipResult.stderr.toString());

      final outDir = Directory(p.join(tmp.path, 'zout'))..createSync();
      final target = File(p.join(outDir.path, 'mytool'));

      final result = await service.installPackage(
        archive,
        InstallType.binary,
        targetPath: target.path,
        binaryName: 'mytool',
      );

      expect(target.existsSync(), isTrue);
      expect(target.readAsBytesSync(), equals(tool.readAsBytesSync()));
      expect(result.packageName, 'mytool');
    });

    test('installs a raw ELF binary that has no archive suffix', () async {
      final raw = makeElf(p.join(tmp.path, 'rawtool'));

      final outDir = Directory(p.join(tmp.path, 'rout'))..createSync();
      final target = File(p.join(outDir.path, 'rawtool'));

      final result = await service.installPackage(
        raw,
        InstallType.binary,
        targetPath: target.path,
      );

      expect(target.existsSync(), isTrue);
      expect(result.packageName, 'rawtool');
    });

    test('refuses a non-ELF file and names it in the error', () async {
      final text = File(p.join(tmp.path, 'notabinary'))
        ..writeAsStringSync('hello world');
      final outDir = Directory(p.join(tmp.path, 'tout'))..createSync();
      final target = p.join(outDir.path, 'notabinary');

      await expectLater(
        service.installPackage(text, InstallType.binary, targetPath: target),
        throwsA(predicate((e) => e.toString().contains('notabinary'))),
      );
    });

    test('rejects an archive payload that is not ELF, so a README-like script is never installed', () async {
      // An executable-bit shell script is exactly what the old code installed
      // when an archive carried no real binary.
      final build = Directory(p.join(tmp.path, 'sbuild'))..createSync();
      final script = File(p.join(build.path, 'mytool'))
        ..writeAsStringSync('#!/bin/sh\necho not-a-binary\n');
      Process.runSync('chmod', ['755', script.path]);

      final archive = File(p.join(tmp.path, 'script.tar.gz'));
      Process.runSync('tar', ['-czf', archive.path, '-C', build.path, 'mytool']);

      final outDir = Directory(p.join(tmp.path, 'sout'))..createSync();
      final target = p.join(outDir.path, 'mytool');

      await expectLater(
        service.installPackage(
          archive,
          InstallType.binary,
          targetPath: target,
          binaryName: 'mytool',
        ),
          throwsA(predicate((e) => e.toString().contains(noBinaryWarning))),
        );
        expect(File(target).existsSync(), isFalse);
      });

      test('refuses a source-only archive with the plain warning the user asked for', () async {
        // Real case: Anselmoo/mcp-server-analyzer publishes only a .mcpb, a
        // wheel and this sdist, so a `*tar.gz` filter matches something that
        // can never be installed as a native binary.
        final build = Directory(p.join(tmp.path, 'pbuild'))..createSync();
        final pkg = Directory(p.join(build.path, 'src', 'mcp_server_analyzer'))
          ..createSync(recursive: true);
        File(
          p.join(build.path, 'pyproject.toml'),
        ).writeAsStringSync('[project]\nname = "mcp-server-analyzer"\n');
        File(p.join(pkg.path, '__main__.py')).writeAsStringSync('print("hi")\n');

        final archive = File(p.join(tmp.path, 'sdist.tar.gz'));
        Process.runSync('tar', ['-czf', archive.path, '-C', build.path, '.']);

        final outDir = Directory(p.join(tmp.path, 'pout'))..createSync();
        final target = p.join(outDir.path, '__main__.py');

        await expectLater(
          service.installPackage(
            archive,
            InstallType.binary,
            targetPath: target,
            binaryName: '__main__.py',
          ),
          throwsA(
            predicate((e) => e.toString().contains(noBinaryWarning)),
          ),
        );
        expect(File(target).existsSync(), isFalse);
      });

    test('picks the executable-bit file from an archive, not the larger README', () async {
      // README is 5000 bytes at mode 644; mytool is a real ELF at mode 755.
      // Pre-fix, with no binaryName, the "largest non-doc file" fallback
      // installed README. Proving the pick by size rather than by an error
      // message keeps the assertion independent of the failure wording.
      final build = Directory(p.join(tmp.path, 'abuild'))..createSync();
      File(p.join(build.path, 'README')).writeAsStringSync('R' * 5000);
      final tool = makeElf(p.join(build.path, 'mytool'));

      final archive = File(p.join(tmp.path, 'app.tar.gz'));
      Process.runSync('tar', ['-czf', archive.path, '-C', build.path, '.']);

      final outDir = Directory(p.join(tmp.path, 'aout'))..createSync();
      final target = p.join(outDir.path, 'installed');

      await service.installPackage(
        archive,
        InstallType.binary,
        targetPath: target,
      );

      final installed = File(target);
      expect(installed.existsSync(), isTrue);
      expect(installed.lengthSync(), tool.lengthSync());
      expect(
        installed.lengthSync(),
        isNot(5000),
        reason: 'README is the largest candidate and must not be chosen',
      );
    });

    test('selects the same executable from an archive on every run so the pick is deterministic', () async {
      final build = Directory(p.join(tmp.path, 'dbuild'))..createSync();
      File(p.join(build.path, 'README')).writeAsStringSync('R' * 5000);
      File(p.join(build.path, 'libfoo.so')).writeAsStringSync('L' * 2000);
      final tool = makeElf(p.join(build.path, 'mytool'));

      final archive = File(p.join(tmp.path, 'app.tar.gz'));
      Process.runSync('tar', ['-czf', archive.path, '-C', build.path, '.']);
      final archive2 = File(p.join(tmp.path, 'app2.tar.gz'))
        ..writeAsBytesSync(archive.readAsBytesSync());

      final out1 = File(p.join(tmp.path, 'out1', 'mytool'));
      final out2 = File(p.join(tmp.path, 'out2', 'mytool'));

      // No binaryName: selection must fall back to the execute bit.
      await service.installPackage(archive, InstallType.binary, targetPath: out1.path);
      await service.installPackage(archive2, InstallType.binary, targetPath: out2.path);

      final elfBytes = tool.readAsBytesSync();
      expect(out1.readAsBytesSync(), equals(elfBytes));
      expect(out2.readAsBytesSync(), equals(elfBytes));
    });

    test('rejects a target whose basename starts with "-" so install cannot treat it as an option', () async {
      final raw = makeElf(p.join(tmp.path, 'rawtool2'));
      final target = p.join(tmp.path, '-t');

      await expectLater(
        service.installPackage(raw, InstallType.binary, targetPath: target),
        throwsA(predicate((e) => e.toString().contains('must not start with "-"'))),
      );
    });

    test('rejects a directory target, a symlink target, a /dev target and a relative target', () async {
      final raw = makeElf(p.join(tmp.path, 'rawtool3'));
      final outDir = Directory(p.join(tmp.path, 'vout'))..createSync();

      final directoryTarget = Directory(p.join(outDir.path, 'isdir'))..createSync();
      await expectLater(
        service.installPackage(raw, InstallType.binary, targetPath: directoryTarget.path),
        throwsA(predicate((e) => e.toString().contains('is a directory'))),
      );

      final realFile = File(p.join(outDir.path, 'real'))..writeAsStringSync('x');
      final linkPath = p.join(outDir.path, 'alink');
      Link(linkPath).createSync(realFile.path);
      await expectLater(
        service.installPackage(raw, InstallType.binary, targetPath: linkPath),
        throwsA(predicate((e) => e.toString().contains('symbolic link'))),
      );

      await expectLater(
        service.installPackage(raw, InstallType.binary, targetPath: '/dev/autononext-not-a-device'),
        throwsA(predicate((e) => e.toString().contains('Refusing to install into /dev'))),
      );

      await expectLater(
        service.installPackage(raw, InstallType.binary, targetPath: 'relative/tool'),
        throwsA(predicate((e) => e.toString().contains('must be absolute'))),
      );
    });

    test('keys the app-data backup by full path so same-named targets do not collide', () {
      final first = InstallerService.appDataBackupName('/opt/a/tool');
      final second = InstallerService.appDataBackupName('/opt/b/tool');

      expect(first, isNot(second));
      expect(first, endsWith('.bak'));
      expect(second, endsWith('.bak'));
      expect(first, startsWith('tool.'));
      expect(second, startsWith('tool.'));
    });

    test('removes the staged .tmp and leaves the old target intact when backup fails', () async {
      final raw = makeElf(p.join(tmp.path, 'rawtool4'));
      final outDir = Directory(p.join(tmp.path, 'hout'))..createSync();
      final target = File(p.join(outDir.path, 'tool'))..writeAsStringSync('OLD');
      // A directory at <target>.bak makes the backup copy fail after staging.
      Directory('${target.path}.bak').createSync();

      await expectLater(
        service.installPackage(raw, InstallType.binary, targetPath: target.path),
        throwsA(isA<FileSystemException>()),
      );

      expect(target.readAsStringSync(), 'OLD');
      expect(File('${target.path}.tmp').existsSync(), isFalse);
    });
  });

  group('InstallerService.downloadFile transport limits', () {
    late InstallerService service;
    late Directory tmp;

    setUp(() {
      service = InstallerService();
      tmp = Directory.systemTemp.createTempSync('autononext_dl_test_');
      service.appSupportDirectory = () async => tmp;
      // Lowered so the limit can be exercised without streaming a gigabyte.
      service.maxDownloadBytes = 1024;
    });

    tearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    File downloaded(String name) => File(p.join(tmp.path, 'downloads', name));

    test('refuses a plaintext url so the installed bytes cannot be chosen in transit', () async {
      await expectLater(
        service.downloadFile('http://example.test/tool.tar.gz', 'tool.tar.gz'),
        throwsA(
          predicate(
            (e) => e.toString().contains('Refusing to download over http'),
          ),
        ),
      );
      expect(downloaded('tool.tar.gz').existsSync(), isFalse);
    });

    test('refuses a redirect that downgrades to plaintext so an on-path attacker cannot supply the binary', () async {
      service.httpClientFactory = () => _FakeClient(
        (request) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          request: request,
          headers: {'location': 'http://evil.test/tool.tar.gz'},
          isRedirect: true,
        ),
      );

      await expectLater(
        service.downloadFile('https://good.test/tool.tar.gz', 'tool.tar.gz'),
        throwsA(
          predicate(
            (e) => e.toString().contains('downgraded to http://evil.test'),
          ),
        ),
      );
    });

    test('refuses an oversized Content-Length before the disk is touched', () async {
      service.httpClientFactory = () => _FakeClient(
        (request) async =>
            _body(request, List.filled(64, 7), contentLength: 4096),
      );

      await expectLater(
        service.downloadFile('https://good.test/tool.tar.gz', 'tool.tar.gz'),
        throwsA(
          predicate((e) => e.toString().contains('exceeds the 1024 byte limit')),
        ),
      );
      expect(downloaded('tool.tar.gz').existsSync(), isFalse);
    });

    test('aborts a body that grows past the cap and deletes the partial file', () async {
      service.httpClientFactory = () => _FakeClient(
        (request) async =>
            _body(request, List.filled(4096, 7), declareLength: false),
      );

      await expectLater(
        service.downloadFile('https://good.test/tool.tar.gz', 'tool.tar.gz'),
        throwsA(
          predicate((e) => e.toString().contains('exceeded the 1024 byte limit')),
        ),
      );
      // A truncated file must not survive to be installed.
      expect(downloaded('tool.tar.gz').existsSync(), isFalse);
    });

    test('still writes a normal https body under the cap', () async {
      service.httpClientFactory = () => _FakeClient(
        (request) async => _body(request, List.filled(512, 7)),
      );

      final file = await service.downloadFile(
        'https://good.test/tool.tar.gz',
        'tool.tar.gz',
      );

      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), 512);
    });
  });

  group('InstallerService privileged install path', () {
    late InstallerService service;
    late Directory tmp;
    late Directory appData;
    late List<List<String>> recorded;

    setUp(() {
      service = InstallerService();
      tmp = Directory.systemTemp.createTempSync('autononext_priv_test_');
      appData = Directory(p.join(tmp.path, 'appdata'))..createSync();
      recorded = [];
      service.appSupportDirectory = () async => appData;
      // pkexec must never run in a test; record the argv instead.
      service.privilegedProcessRunner =
          (executable, args, {workingDirectory}) async {
            recorded.add([executable, ...args]);
            return ProcessResult(0, 0, '', '');
          };
    });

    tearDown(() {
      try {
        for (final dir in Directory(
          tmp.path,
        ).listSync(recursive: true).whereType<Directory>()) {
          try {
            Process.runSync('chmod', ['755', dir.path]);
          } catch (_) {}
        }
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    File makeElf(String path) {
      final file = File('/usr/bin/true').copySync(path);
      Process.runSync('chmod', ['755', file.path]);
      return file;
    }

    /// A directory the test user genuinely cannot write, holding [content].
    ///
    /// The condition is real rather than mocked, so the privileged branch is
    /// chosen by the same check production uses.
    String readOnlyTargetWith(String name, String content) {
      final dir = Directory(p.join(tmp.path, 'ro'))..createSync();
      final target = p.join(dir.path, name);
      File(target).writeAsStringSync(content);
      Process.runSync('chmod', ['555', dir.path]);
      return target;
    }

    test('backs up beside the target through the privileged copier when the directory is not writable', () async {
      final target = readOnlyTargetWith('tool', 'OLD-BINARY');
      final payload = makeElf(p.join(tmp.path, 'payload'));

      await service.installPackage(
        payload,
        InstallType.binary,
        targetPath: target,
        binaryName: 'tool',
      );

      // The backup must land where the user can find it, not in app data.
      // `contains(equals(...))` is required because list equality in Dart is
      // identity-based, so a bare `contains([...])` would never match.
      expect(
        recorded,
        contains(equals(['pkexec', 'cp', '-p', '--', target, '$target.bak'])),
      );
    });

    test('stages then renames in ONE privileged call, with the exact argv and positional paths', () async {
      final target = readOnlyTargetWith('tool', 'OLD-BINARY');
      final payload = makeElf(p.join(tmp.path, 'payload'));

      await service.installPackage(
        payload,
        InstallType.binary,
        targetPath: target,
        binaryName: 'tool',
      );

      // `pkexec` plus the exact 6-element argv handed to `sh`. `$1`/`$2` must
      // stay literal — a path interpolated into the script would be parsed as
      // shell source, which is the whole reason for the positional form.
      expect(
        recorded.last,
        equals([
          'pkexec',
          'sh',
          '-c',
          'install -m 755 -- "\$1" "\$2.autononext-new" && '
              'mv -f -- "\$2.autononext-new" "\$2"',
          'sh',
          payload.path,
          target,
        ]),
      );
      // The paths never appear inside the script text.
      expect(recorded.last[3], isNot(contains(payload.path)));
      expect(recorded.last[3], isNot(contains(target)));
    });

    test('falls back to an app-data backup keyed by full path when the privileged copy fails', () async {
      final target = readOnlyTargetWith('tool', 'OLD-BINARY');
      final payload = makeElf(p.join(tmp.path, 'payload'));
      service.privilegedProcessRunner =
          (executable, args, {workingDirectory}) async {
            recorded.add([executable, ...args]);
            if (args.isNotEmpty && args.first == 'cp') {
              return ProcessResult(0, 1, '', 'cp failed');
            }
            return ProcessResult(0, 0, '', '');
          };

      await service.installPackage(
        payload,
        InstallType.binary,
        targetPath: target,
        binaryName: 'tool',
      );

      final expected = p.join(
        appData.path,
        'binary_backups',
        InstallerService.appDataBackupName(target),
      );
      expect(File(expected).existsSync(), isTrue);
      expect(File(expected).readAsStringSync(), 'OLD-BINARY');
      expect(p.basename(expected), matches(RegExp(r'^tool\.[0-9a-f]{8}\.bak$')));
    });

    test('keys app-data backups by full path so same-named targets do not clobber each other', () {
      final a = InstallerService.appDataBackupName('/opt/one/tool');
      final b = InstallerService.appDataBackupName('/opt/two/tool');

      expect(a, isNot(b));
      expect(p.basename(a), startsWith('tool.'));
    });

    test('leaves the target untouched and throws when the privileged install fails', () async {
      final target = readOnlyTargetWith('tool', 'OLD-BINARY');
      final payload = makeElf(p.join(tmp.path, 'payload'));
      service.privilegedProcessRunner =
          (executable, args, {workingDirectory}) async {
            recorded.add([executable, ...args]);
            if (args.isNotEmpty && args.first == 'sh') {
              return ProcessResult(0, 1, '', 'install failed');
            }
            return ProcessResult(0, 0, '', '');
          };

      await expectLater(
        service.installPackage(
          payload,
          InstallType.binary,
          targetPath: target,
          binaryName: 'tool',
        ),
        throwsA(isA<Exception>()),
      );

      expect(File(target).readAsStringSync(), 'OLD-BINARY');
    });

    test('cleans up a surviving staging file through the privileged runner after a failed install', () async {
      final dir = Directory(p.join(tmp.path, 'ro2'))..createSync();
      final target = p.join(dir.path, 'tool');
      File(target).writeAsStringSync('OLD-BINARY');
      final staging = '$target.autononext-new';
      // Pre-create the staging file while the directory is still writable so
      // the failure path has something to clean up.
      File(staging).writeAsStringSync('half-written');
      Process.runSync('chmod', ['555', dir.path]);

      final payload = makeElf(p.join(tmp.path, 'payload'));
      service.privilegedProcessRunner =
          (executable, args, {workingDirectory}) async {
            recorded.add([executable, ...args]);
            if (args.isNotEmpty && args.first == 'sh') {
              return ProcessResult(0, 1, '', 'install failed');
            }
            if (args.isNotEmpty && args.first == 'rm') {
              // Simulate what root can do: drop the staging file.
              Process.runSync('chmod', ['755', dir.path]);
              if (File(staging).existsSync()) File(staging).deleteSync();
              Process.runSync('chmod', ['555', dir.path]);
            }
            return ProcessResult(0, 0, '', '');
          };

      await expectLater(
        service.installPackage(
          payload,
          InstallType.binary,
          targetPath: target,
          binaryName: 'tool',
        ),
        throwsA(isA<Exception>()),
      );

      expect(recorded.last, equals(['pkexec', 'rm', '-f', '--', staging]));
      expect(File(staging).existsSync(), isFalse);
      expect(File(target).readAsStringSync(), 'OLD-BINARY');
    });

    test('installs a .deb through an ABSOLUTE path, because pkexec resets cwd',
        () async {
      // Regression: pkexec runs the target program with its working directory
      // set to the target user's home (/root) regardless of the caller's cwd.
      // A relative './<basename>' argument therefore never resolves, and apt-get
      // aborts with
      //   E: Unsupported file ./cliptoo_2.17.1-1_amd64.deb given on commandline
      // (exit code 100). The path handed to apt-get must be absolute.
      final deb = File(
        p.join(tmp.path, 'downloads', 'cliptoo_2.17.1-1_amd64.deb'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('not-really-a-deb');

      await service.installPackage(deb, InstallType.deb);

      final argv = recorded.single;
      expect(argv.take(4), equals(['pkexec', 'apt-get', 'install', '-y']));
      final pathArg = argv[4];
      expect(pathArg, equals(deb.path));
      expect(
        p.isAbsolute(pathArg),
        isTrue,
        reason: 'pkexec resets cwd, so a relative path would not resolve',
      );
      expect(pathArg.startsWith('./'), isFalse);
    });

    test('reports stdout before stderr so apt output reads in command order',
        () async {
      // Regression: apt writes the actionable diagnosis ("Reading package
      // lists...", "The following packages have unmet dependencies: ...") to
      // stdout and only terse "E:" lines to stderr. The message shown to the
      // user must lead with stdout, in the order the command produced it.
      final deb = File(
        p.join(tmp.path, 'downloads', 'cliptoo_2.17.1-1_amd64.deb'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('not-really-a-deb');

      service.privilegedProcessRunner =
          (executable, args, {workingDirectory}) async {
        recorded.add([executable, ...args]);
        return ProcessResult(
          100,
          100,
          'Reading package lists...\n'
              'The following packages have unmet dependencies:\n'
              ' cliptoo : Depends: libqt6gui6t64 (>= 6.1.2) but it is not installable',
          'E: Unable to correct problems, you have held broken packages.',
        );
      };

      Object? thrown;
      try {
        await service.installPackage(deb, InstallType.deb);
      } catch (e) {
        thrown = e;
      }

      expect(
        thrown,
        isNotNull,
        reason: 'a failing apt-get must surface an error',
      );
      final message = thrown.toString();
      expect(message, contains('exit code 100'));
      expect(message, contains('Reading package lists'));
      expect(message, contains('E: Unable to correct problems'));
      expect(
        message.indexOf('Reading package lists'),
        lessThan(message.indexOf('E: Unable to correct problems')),
        reason: 'stdout carries the actionable diagnosis and must come first',
      );
    });
  });

  group('InstallerService.chooseLaunchCommand', () {
    test('prefers the desktop entry when a package ships several binaries', () {
      // FluxDown ships an agent and a desktop binary; only the desktop entry
      // says which one the user actually launches.
      final files = [
        '/usr/bin/fluxdown-agent',
        '/usr/bin/fluxdown-desktop',
        '/usr/share/applications/com.fluxdown.app.desktop',
      ];
      expect(
        InstallerService.chooseLaunchCommand(files, {
          '/usr/share/applications/com.fluxdown.app.desktop':
              'fluxdown-desktop %U',
        }),
        '/usr/bin/fluxdown-desktop',
      );
    });

    test('uses the only binary when the package name is not the executable', () {
      // mq-run is a CLI tool whose executable is /usr/bin/mq.
      expect(
        InstallerService.chooseLaunchCommand(
          ['/usr/bin/mq', '/usr/share/doc/mq-run/README.md'],
          const {},
        ),
        '/usr/bin/mq',
      );
    });

    test('refuses to guess between several binaries', () {
      expect(
        InstallerService.chooseLaunchCommand(
          ['/usr/bin/agent', '/usr/bin/desktop'],
          const {},
        ),
        isNull,
      );
    });

    test('ignores a desktop entry that names no shipped binary', () {
      expect(
        InstallerService.chooseLaunchCommand(
          [
            '/usr/bin/agent',
            '/usr/bin/desktop',
            '/usr/share/applications/x.desktop',
          ],
          const {'/usr/share/applications/x.desktop': 'not-shipped %U'},
        ),
        isNull,
      );
    });

    test('does not treat a bare bin directory as a binary', () {
      expect(
        InstallerService.chooseLaunchCommand(
          ['/usr/bin/', '/usr/share/doc/x/README'],
          const {},
        ),
        isNull,
      );
    });
  });

  group('InstallerService deb launch command', () {
    late InstallerService service;
    late Directory tmp;
    late Directory appData;

    setUp(() {
      service = InstallerService();
      tmp = Directory.systemTemp.createTempSync('autononext_launch_test_');
      appData = Directory(p.join(tmp.path, 'appdata'))..createSync();
      service.appSupportDirectory = () async => appData;
      service.privilegedProcessRunner =
          (executable, args, {workingDirectory}) async =>
              ProcessResult(0, 0, '', '');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    File makeDeb() => File(
          p.join(tmp.path, 'downloads', 'mq-x86_64-unknown-linux-gnu.deb'),
        )
      ..createSync(recursive: true)
      ..writeAsStringSync('not-really-a-deb');

    test('stores the launch command the installed package provides', () async {
      // The command recorded at add time is a guess from the repo name — for
      // FluxDown that was `fluxdown` for a deb shipping `fluxdown-desktop` — so
      // the install must read the answer from the package it just installed.
      service.packageLaunchCommandResolver =
          (packageName) async => '/usr/bin/mq';

      final result = await service.installPackage(makeDeb(), InstallType.deb);

      expect(result.launchCommand, '/usr/bin/mq');
    });

    test('leaves the launch command unset when the package name is unreadable',
        () async {
      // The default resolver must not invent a command, and must not shell out
      // to dpkg with a null name. The fixture is not a real .deb, so the name
      // cannot be read out of it.
      final result = await service.installPackage(makeDeb(), InstallType.deb);

      expect(result.launchCommand, isNull);
    });
  });
}
