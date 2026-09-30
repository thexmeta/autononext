import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/install_type.dart';
import '../models/tracked_app.dart';
import '../models/tracked_deb_package.dart';
import 'debug_logger.dart';
import 'install_location.dart';

/// An install failure whose message is already written for the user to read.
///
/// `Exception('...')` renders as `Exception: ...`, so the UI would prefix a
/// sentence that is meant to be shown verbatim.
class InstallFailure implements Exception {
  const InstallFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class InstallerService {
  /// Where this user's application data lives.
  ///
  /// Overridable so tests can point it at a temp directory:
  /// `getApplicationSupportDirectory()` needs a registered path_provider
  /// plugin, which does not exist under `flutter test`, so without this seam
  /// the unwritable-target backup path — the one that writes as root — could
  /// not be tested at all.
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory;

  /// Executes the privileged helper.
  ///
  /// Overridable so tests can record the argv that would be handed to `pkexec`
  /// and assert on it, without ever running `pkexec`.
  Future<ProcessResult> Function(
    String executable,
    List<String> args, {
    String? workingDirectory,
  })
  privilegedProcessRunner = _runPrivilegedProcess;

  static Future<ProcessResult> _runPrivilegedProcess(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) => Process.run(executable, args, workingDirectory: workingDirectory);

  /// Builds the HTTP client used by [downloadFile]. Overridable so tests can
  /// drive redirects and oversized bodies deterministically instead of hitting
  /// the network.
  http.Client Function() httpClientFactory = http.Client.new;

  Future<Directory> get _downloadsDir async {
    final dataDir = await appSupportDirectory();
    final dir = Directory(p.join(dataDir.path, 'downloads'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> get _appImageDir async {
    final dataDir = await appSupportDirectory();
    final dir = Directory(p.join(dataDir.path, 'appimages'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Upper bound on a single downloaded asset.
  ///
  /// Desktop release assets run to tens of megabytes; 1 GiB is far above
  /// anything legitimate while still bounding a hostile or misconfigured
  /// release that would otherwise fill the disk. Overridable so tests can
  /// exercise the limit without streaming a gigabyte.
  int maxDownloadBytes = 1 << 30;

  Future<File> downloadFile(String url, String filename) async {
    final uri = Uri.parse(url);
    // The downloaded bytes become the user's binary, and on an unwritable
    // target they are installed as root, so plaintext transport is not
    // acceptable even when the caller supplies the URL.
    if (uri.scheme != 'https') {
      throw Exception('Refusing to download over ${uri.scheme}: $url');
    }

    final dir = await _downloadsDir;
    final file = File(p.join(dir.path, _sanitizeFilename(filename)));

    final client = httpClientFactory();
    var writing = false;
    try {
      final response = await _sendFollowingHttpsRedirects(client, uri)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('Failed to download file: ${response.statusCode}');
      }

      final declared = response.contentLength;
      if (declared != null && declared > maxDownloadBytes) {
        throw Exception(
          'Refusing to download $url: $declared bytes exceeds the '
          '$maxDownloadBytes byte limit',
        );
      }

      final sink = file.openWrite();
      writing = true;
      var written = 0;
      try {
        await for (final chunk in response.stream) {
          written += chunk.length;
          if (written > maxDownloadBytes) {
            throw Exception(
              'Aborting download of $url: exceeded the $maxDownloadBytes '
              'byte limit',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return file;
    } on TimeoutException {
      throw Exception('Timed out downloading file after 30s: $url');
    } catch (e) {
      // A truncated file must never be mistaken for a complete download.
      if (writing && await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Sends a GET, following redirects by hand so every hop can be required to
  /// be HTTPS.
  ///
  /// `http.get` follows redirects silently, so a URL that starts as HTTPS can
  /// be redirected to plaintext `http://` and the response would still be
  /// accepted.
  Future<http.StreamedResponse> _sendFollowingHttpsRedirects(
    http.Client client,
    Uri uri,
  ) async {
    var current = uri;
    for (var hop = 0; hop <= 5; hop++) {
      final request = http.Request('GET', current)..followRedirects = false;
      final response = await client.send(request);
      if (!response.isRedirect) return response;

      final location = response.headers['location'];
      if (location == null) {
        throw Exception('Redirect without a Location header from $current');
      }
      final next = current.resolve(location);
      if (next.scheme != 'https') {
        throw Exception(
          'Refusing to download over ${next.scheme}: redirect from $current '
          'downgraded to $next',
        );
      }
      current = next;
    }
    throw Exception('Too many redirects downloading $uri');
  }

  /// Reduces [filename] to a single, safe path component.
  ///
  /// The name can be derived from user-controlled package metadata, so a value
  /// such as `../../etc/passwd` must not be allowed to escape the downloads
  /// directory. Directory components (both `/` and `\`) are stripped and a
  /// name that reduces to nothing, `.` or `..` is rejected.
  String _sanitizeFilename(String filename) {
    final base = p.basename(filename.replaceAll('\\', '/'));
    final cleaned = base.replaceAll(RegExp(r'[/\\]'), '').trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      throw Exception('Invalid download filename: "$filename"');
    }
    return cleaned;
  }

  Future<({String? launchCommand, String? packageName})> installPackage(
    File file,
    InstallType type, {
    String? targetPath,
    String? binaryName,
  }) async {
    switch (type) {
      case InstallType.deb:
        String? pkgName;
        try {
          final res = await Process.run('dpkg-deb', ['-f', file.path, 'Package']);
          if (res.exitCode == 0) pkgName = res.stdout.toString().trim();
        } catch (_) {}

        // Pass the ABSOLUTE path. `pkexec` resets the working directory to the
        // target user's home (/root) regardless of the caller's cwd, so a
        // relative "./<basename>" path never resolves and apt-get fails with
        // "E: Unsupported file ./<name>.deb given on commandline" (exit 100).
        // apt-get accepts absolute paths for local .deb files.
        await _runPrivileged(
          'apt-get',
          ['install', '-y', file.path],
        );
        await _deleteTempDownload(file);
        return (launchCommand: null, packageName: pkgName);

      case InstallType.rpm:
        String? pkgName;
        try {
          final res = await Process.run('rpm', ['-qp', '--queryformat', '%{NAME}', file.path]);
          if (res.exitCode == 0) pkgName = res.stdout.toString().trim();
        } catch (_) {}

        await _runPrivileged('rpm', ['-i', file.path]);
        await _deleteTempDownload(file);
        return (launchCommand: null, packageName: pkgName);

      case InstallType.flatpak:
        final flatpakResult = await Process.run('flatpak', ['install', '-y', file.path]);
        if (flatpakResult.exitCode != 0) {
          throw Exception(
            'flatpak install failed (exit code ${flatpakResult.exitCode}): ${flatpakResult.stderr}'.trim(),
          );
        }
        await _deleteTempDownload(file);
        return (launchCommand: null, packageName: null);

      case InstallType.appImage:
        final appImageDir = await _appImageDir;
        final target = File(p.join(appImageDir.path, p.basename(file.path)));
        await file.copy(target.path);
        final chmodResult = await Process.run('chmod', ['+x', target.path]);
        if (chmodResult.exitCode != 0) {
          throw Exception(
            'chmod +x failed (exit code ${chmodResult.exitCode}): ${chmodResult.stderr}'.trim(),
          );
        }
        await _deleteTempDownload(file);
        return (launchCommand: target.path, packageName: null);

      case InstallType.binary:
        return _installBinary(file, targetPath: targetPath, binaryName: binaryName);

      default:
        throw Exception('Installation not supported for ${type.name}');
    }
  }

  /// Installs a raw or archived binary.
  ///
  /// Archives are extracted into a throwaway temp directory; a raw download is
  /// validated as ELF so a filter pattern that matched a script or JSON cannot
  /// be installed as an executable. The payload selected out of an archive is
  /// ELF-validated too — otherwise an archive whose only non-documentation
  /// file is a README would install the README. The payload is staged next to
  /// the target and atomically renamed into place, with the previous file
  /// preserved as `<target>.bak` first so the install is always reversible.
  Future<({String? launchCommand, String? packageName})> _installBinary(
    File file, {
    String? targetPath,
    String? binaryName,
  }) async {
    // A caller-supplied target is rejected before extracting or writing
    // anything, so a `-`-prefixed or otherwise unsafe path cannot reach the
    // privileged `install` call.
    if (targetPath != null) {
      final error = installTargetError(targetPath);
      if (error != null) throw Exception(error);
    }

    final isArchive = _binaryArchiveSuffixes.any(file.path.toLowerCase().endsWith);
    Directory? tempDir;
    try {
      final File payload;
      final String effectiveName;
      if (isArchive) {
        tempDir = await Directory.systemTemp.createTemp('autononext_binary_');
        await _extractArchive(file, tempDir);
        payload = await _locatePayload(tempDir, binaryName, file);
        // Archives get the same ELF guarantee raw downloads already have: an
        // archive with no executable in it must never be installed.
        await _verifyExtractedPayload(payload);
        effectiveName = binaryName ?? p.basename(payload.path);
      } else {
        await _verifyElf(file);
        payload = file;
        effectiveName = binaryName ?? p.basename(file.path);
      }

      final target = targetPath ?? _defaultBinaryTarget(effectiveName);
      final targetError = installTargetError(target);
      if (targetError != null) throw Exception(targetError);
      await _stageAndInstallBinary(payload, target);

      await _deleteTempDownload(file);
      return (launchCommand: target, packageName: effectiveName);
    } finally {
      if (tempDir != null) {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } catch (e) {
          // Cleanup is best effort: never fail an install that already
          // succeeded because a temp dir could not be removed.
          dlog('InstallerService', 'Could not remove temp dir ${tempDir.path}: $e');
        }
      }
    }
  }

  Future<void> _extractArchive(File archive, Directory destination) async {
    final isZip = archive.path.toLowerCase().endsWith('.zip');
    final ProcessResult result;
    if (isZip) {
      result = await Process.run('unzip', ['-q', archive.path, '-d', destination.path]);
    } else {
      // GNU tar auto-detects gzip/xz/bzip2/zstd when extracting.
      result = await Process.run('tar', ['-xf', archive.path, '-C', destination.path]);
    }
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw Exception(
        'Failed to extract ${p.basename(archive.path)}'
        '${stderr.isNotEmpty ? ': $stderr' : ' (exit code ${result.exitCode})'}',
      );
    }
  }

  /// Whether [file] starts with the ELF magic bytes.
  Future<bool> _isElf(File file) async {
    final raf = await file.open();
    try {
      final bytes = await raf.read(4);
      return bytes.length >= 4 &&
          bytes[0] == 0x7F &&
          bytes[1] == 0x45 &&
          bytes[2] == 0x4C &&
          bytes[3] == 0x46;
    } finally {
      await raf.close();
    }
  }

  /// Verifies that [file] starts with the ELF magic bytes.
  Future<void> _verifyElf(File file) async {
    if (await _isElf(file)) return;
    throw Exception(
      'Refusing to install ${p.basename(file.path)}: not an ELF executable',
    );
  }

  /// Fails when an extracted archive contains no executable.
  ///
  /// An archive can legitimately carry only source or documentation. Real case:
  /// `Anselmoo/mcp-server-analyzer` publishes a `.mcpb`, a Python wheel and a
  /// Python sdist, so a `*tar.gz` filter matches something that can never be
  /// installed here.
  Future<void> _verifyExtractedPayload(File payload) async {
    if (await _isElf(payload)) return;
    throw const InstallFailure(
      'This entry cant be installable. It doesnt include binary/executable.',
    );
  }

  /// Finds the executable inside the archive extracted into [dir].
  ///
  /// Only two signals are trusted: an exact [binaryName] match, then the first
  /// regular file carrying an execute bit. The previous "largest file that is
  /// not .txt/.md/.json" fallback is deliberately gone — it installed a
  /// 5000-byte README over the real 22-byte binary. Candidates are sorted so
  /// the choice does not depend on filesystem listing order. Only the first 3
  /// directory levels are searched.
  Future<File> _locatePayload(
    Directory dir,
    String? binaryName,
    File archive,
  ) async {
    final candidates = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: dir.path);
      if (p.split(relative).length > 3) continue;
      candidates.add(entity);
    }
    // dir.list() order is filesystem-dependent; sort so the pick is stable.
    candidates.sort((a, b) => a.path.compareTo(b.path));

    if (binaryName != null && binaryName.isNotEmpty) {
      for (final candidate in candidates) {
        if (p.basename(candidate.path) == binaryName) return candidate;
      }
    }

    for (final candidate in candidates) {
      final stat = await candidate.stat();
      if (stat.mode & 0x49 != 0) return candidate;
    }

    final names = candidates
        .map((f) => p.relative(f.path, from: dir.path))
        .join(', ');
    throw Exception(
      'No installable executable found in ${p.basename(archive.path)}'
      '${names.isEmpty ? '' : ' (candidates: $names)'}',
    );
  }

  /// Default install location when the caller does not choose one.
  String _defaultBinaryTarget(String binaryName) {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw Exception(
        'Cannot determine install location: HOME is not set. '
        'Pass an explicit target path.',
      );
    }
    return p.join(home, '.local', 'bin', binaryName);
  }

  /// Stages [payload] beside [target] and moves it into place.
  ///
  /// The existing target is copied to `<target>.bak` before it is replaced. If
  /// the target directory is not writable the backup is made beside the target
  /// with a privileged copy and the install falls back to a privileged
  /// `install` call.
  Future<void> _stageAndInstallBinary(File payload, String target) async {
    final targetDir = p.dirname(target);
    var writable = await _isDirWritable(targetDir);
    if (!writable) {
      // A missing directory (e.g. ~/.local/bin) may still be creatable.
      try {
        await Directory(targetDir).create(recursive: true);
        writable = await _isDirWritable(targetDir);
      } catch (_) {
        writable = false;
      }
    }

    if (writable) {
      final staging = File('$target.tmp');
      try {
        await payload.copy(staging.path);
        final chmodResult = await Process.run('chmod', ['755', staging.path]);
        if (chmodResult.exitCode != 0) {
          final stderr = chmodResult.stderr.toString().trim();
          throw Exception(
            'chmod 755 failed on ${staging.path}'
            '${stderr.isNotEmpty ? ': $stderr' : ' (exit code ${chmodResult.exitCode})'}',
          );
        }
        // The new payload is safely staged; only now is the old file backed up.
        await _backupExistingTarget(target, targetDirWritable: true);
        // rename(2) replaces the destination atomically on Linux.
        await staging.rename(target);
      } finally {
        // A successful rename consumed the staging path; on any failure this
        // removes the half-written file so nothing is left behind.
        await _removeIfPresent(staging);
      }
    } else {
      final backup = await _backupExistingTarget(target, targetDirWritable: false);
      if (backup != null) {
        // Record where the backup went; the user needs this path to restore.
        await dlog(
          'InstallerService',
          'Target $target not writable; backed it up to ${backup.path}',
        );
      }
      // ONE privileged invocation stages then renames, so the target is either
      // the old binary or the new one — never absent, never half-written.
      //
      // `install` alone is NOT atomic: it unlinks the destination and creates a
      // new file (the inode changes), so a failure in between destroys the
      // original. `mv` within the same directory is an atomic `rename(2)`.
      // The paths travel as positional parameters ($1/$2) and are therefore
      // never parsed as shell source, so a target containing spaces, quotes or
      // `$(...)` cannot inject a command; `--` keeps a leading `-` from being
      // read as an option.
      final staging = '$target.autononext-new';
      try {
        await _runPrivileged('sh', [
          '-c',
          'install -m 755 -- "\$1" "\$2.autononext-new" && '
              'mv -f -- "\$2.autononext-new" "\$2"',
          'sh',
          payload.path,
          target,
        ]);
      } finally {
        // `mv` consumes the staging path on success; a failed run can leave it
        // behind. The target directory is not writable, so the removal itself
        // must go through the privileged runner. Best effort — never mask the
        // original failure.
        await _removePrivilegedStagingIfPresent(staging);
      }
    }
  }

  Future<void> _removeIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      dlog('InstallerService', 'Could not remove temporary file ${file.path}: $e');
    }
  }

  /// Removes a privileged staging file left by a failed atomic install.
  ///
  /// The staging file lives in a directory the user cannot write, so `delete()`
  /// would fail; only attempt the privileged `rm` when the file actually
  /// survived, so the happy path needs no second authorization prompt.
  Future<void> _removePrivilegedStagingIfPresent(String stagingPath) async {
    try {
      if (!await File(stagingPath).exists()) return;
    } catch (_) {
      return;
    }
    try {
      await _runPrivileged('rm', ['-f', '--', stagingPath]);
    } catch (e) {
      dlog(
        'InstallerService',
        'Could not remove privileged staging file $stagingPath: $e',
      );
    }
  }

  /// Returns a human-readable reason why [target] is not a valid install
  /// destination, or null when it is acceptable.
  ///
  /// Shared by [installPackage] (before any write) and the UI dialog, so both
  /// reject the same paths. An absent path inside a writable directory is
  /// valid; the target must not already be a directory, symlink or special
  /// file, because overwriting any of those is destructive or undefined.
  static String? installTargetError(String target) {
    if (!p.isAbsolute(target)) {
      return 'Install path must be absolute: $target';
    }
    final normalized = p.normalize(target);
    for (final forbidden in const ['/dev', '/proc', '/sys']) {
      if (normalized == forbidden || normalized.startsWith('$forbidden/')) {
        return 'Refusing to install into $forbidden: $target';
      }
    }
    if (p.basename(target).startsWith('-')) {
      return 'Install path must not start with "-": $target';
    }
    // isLinkSync does not follow, so a symlink is detected even when it points
    // at a regular file (which we would otherwise happily replace).
    if (FileSystemEntity.isLinkSync(target)) {
      return 'Install path is a symbolic link: $target';
    }
    final stat = FileStat.statSync(target);
    switch (stat.type) {
      case FileSystemEntityType.notFound:
        return null;
      case FileSystemEntityType.file:
        return null;
      case FileSystemEntityType.directory:
        return 'Install path is a directory: $target';
      default:
        return 'Install path is not a regular file: $target';
    }
  }

  /// Backup filename used when the target directory is not writable and even a
  /// privileged copy beside the target failed.
  ///
  /// Keyed by a hash of the full path, not just the basename, so two targets
  /// with the same name in different directories cannot clobber each other.
  static String appDataBackupName(String target) {
    final absolute = p.absolute(target);
    // FNV-1a 32-bit over the absolute path: deterministic and stable.
    var hash = 0x811c9dc5;
    for (final unit in absolute.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final hex = hash.toRadixString(16).padLeft(8, '0');
    return '${p.basename(target)}.$hex.bak';
  }

  /// Copies an existing [target] to a backup, or returns null when there is
  /// nothing to back up.
  ///
  /// On the writable path the backup sits beside the target. When the target
  /// directory is not writable the backup is still created beside the target
  /// via a privileged `cp`, so it stays discoverable at a predictable path;
  /// only if that fails does it fall back to the app data directory.
  Future<File?> _backupExistingTarget(
    String target, {
    required bool targetDirWritable,
  }) async {
    final existing = File(target);
    if (!await existing.exists()) return null;

    if (targetDirWritable) {
      final backupPath = '$target.bak';
      await existing.copy(backupPath);
      return File(backupPath);
    }

    final besidePath = '$target.bak';
    try {
      await _runPrivileged('cp', ['-p', '--', target, besidePath]);
      return File(besidePath);
    } catch (e) {
      dlog(
        'InstallerService',
        'Privileged backup of $target failed ($e); using app data directory',
      );
    }

    final dataDir = await appSupportDirectory();
    final backupDir = Directory(p.join(dataDir.path, 'binary_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    final backupPath = p.join(backupDir.path, appDataBackupName(target));
    await existing.copy(backupPath);
    return File(backupPath);
  }

  Future<bool> _isDirWritable(String dir) =>
      InstallLocationResolver.isDirWritable(dir);

  Future<void> uninstallPackage(TrackedApp app) async {
    final type = app.installType;
    if (type == InstallType.appImage && app.launchCommand != null) {
      final file = File(app.launchCommand!);
      if (await file.exists()) await file.delete();
    } else if (type == InstallType.deb && app.packageName != null) {
      await _runPrivileged('dpkg', ['-r', app.packageName!]);
    } else if (type == InstallType.rpm && app.packageName != null) {
      await _runPrivileged('rpm', ['-e', app.packageName!]);
    } else if (type == InstallType.flatpak) {
      final ref = app.packageName;
      if (ref == null || ref.isEmpty) {
        throw Exception(
          'Cannot uninstall Flatpak: no application ID is stored for this app. '
          'Set it in the app settings or remove it manually with '
          '"flatpak uninstall <app-id>".',
        );
      }
      final result = await Process.run('flatpak', ['uninstall', '-y', ref]);
      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        throw Exception(
          'flatpak uninstall failed (exit code ${result.exitCode})'
          '${stderr.isNotEmpty ? ': $stderr' : ''}',
        );
      }
    } else if (type == InstallType.snap) {
      final pkg = app.packageName;
      throw Exception(
        'Uninstall is not supported for snap; remove it with '
        '"snap remove ${pkg ?? '<package-name>'}".',
      );
    } else if (type == InstallType.binary || type == InstallType.source) {
      throw Exception(
        'Uninstall is not supported for ${type!.name}; remove it with the '
        'same method used to install it.',
      );
    } else {
      throw Exception('Uninstall not supported for this app (missing package info)');
    }
  }

  Future<void> uninstallDebPackage(TrackedDebPackage pkg) async {
    if (pkg.packageName != null) {
      await _runPrivileged('dpkg', ['-r', pkg.packageName!]);
    } else {
      throw Exception('Uninstall not supported for this package (missing package name)');
    }
  }

  Future<void> launchApp(TrackedApp app) async {
    if (app.launchCommand != null) {
      // If we have a stored command/path, use it (may include arguments).
      await _startDetached(app.launchCommand!);
      return;
    }

    if (app.installType == InstallType.appImage && app.installedVersion != null) {
       // Fallback for old AppImages without stored path
       final appImageDir = await _appImageDir;
       await for (final entity in appImageDir.list()) {
         if (entity is File && entity.path.toLowerCase().contains(app.repoName.toLowerCase())) {
           await _startDetached(entity.path);
           return;
         }
       }
       throw Exception('Could not find AppImage to launch');
    } else {
      // For system installs, try running the repo name as command
      try {
        await _startDetached(app.repoName);
      } catch (e) {
        // Try lowercase as fallback (common for Linux binaries)
        if (app.repoName != app.repoName.toLowerCase()) {
          try {
            await _startDetached(app.repoName.toLowerCase());
            return;
          } catch (_) {
            // Ignore and throw original error
          }
        }
        throw Exception('Could not launch ${app.repoName}: $e');
      }
    }
  }

  Future<void> launchDebPackage(TrackedDebPackage pkg) async {
    if (pkg.launchCommand != null) {
      await _startDetached(pkg.launchCommand!);
    } else {
      // Try running the name as command
      try {
        await _startDetached(pkg.name);
      } catch (e) {
        throw Exception('Could not launch ${pkg.name}: $e');
      }
    }
  }

  /// Starts [command] without waiting for it.
  ///
  /// A launch command may be a bare executable path that itself contains
  /// spaces (e.g. `/opt/My App/bin/app`), or a command with arguments (e.g.
  /// `code --no-sandbox`). Splitting on whitespace would corrupt the former,
  /// so the whole string is used verbatim when it resolves to an existing
  /// file; otherwise it is split into executable + arguments. Both output
  /// streams are drained so a chatty child cannot deadlock once the pipe
  /// buffer fills up.
  Future<void> _startDetached(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      throw Exception('Cannot launch: empty launch command');
    }
    final String executable;
    final List<String> args;
    if (await File(trimmed).exists()) {
      executable = trimmed;
      args = const [];
    } else {
      final parts = trimmed.split(RegExp(r'\s+'));
      executable = parts.first;
      args = parts.sublist(1);
    }
    final process = await Process.start(executable, args);
    process.stdout.listen((_) {});
    process.stderr.listen((_) {});
  }

  /// Archive suffixes that carry an extractable binary payload.
  static const _binaryArchiveSuffixes = [
    '.tar.gz',
    '.tgz',
    '.tar.xz',
    '.txz',
    '.tar.bz2',
    '.tbz2',
    '.tar.zst',
    '.zip',
  ];

  /// Basenames that are documentation or release metadata, not executables.
  ///
  /// An extension-less name is normally a raw binary, but release pages also
  /// carry extension-less files such as `LICENSE` and `SHA256SUMS`. Treating
  /// those as binaries offered them for installation; this denylist keeps them
  /// out. Matched case-insensitively against the basename.
  static const _nonBinaryBasenames = {
    'license',
    'licence',
    'copying',
    'notice',
    'readme',
    'changelog',
    'changes',
    'contributing',
    'authors',
    'install',
    'makefile',
    'sha256sums',
    'sha512sums',
    'checksums',
    'checksum',
    'latest',
    'version',
    'manifest',
  };

  /// Returns the install type for [filename], or null when it is not something
  /// this app can install.
  ///
  /// [app] supplies the executable names to expect, which is what lets an
  /// extension-less asset be recognised as the app's own binary. Without it an
  /// extension-less name must carry a platform token of its own.
  InstallType? identifyAssetType(String filename, {TrackedApp? app}) {
    final lower = filename.toLowerCase();
    // Package formats are checked first so they keep winning over the
    // generic binary fallback below.
    if (lower.endsWith('.deb')) return InstallType.deb;
    if (lower.endsWith('.rpm')) return InstallType.rpm;
    if (lower.endsWith('.appimage')) return InstallType.appImage;
    if (lower.endsWith('.flatpak')) return InstallType.flatpak;
    if (lower.endsWith('.snap')) return InstallType.snap;
    if (_binaryArchiveSuffixes.any(lower.endsWith)) return InstallType.binary;
    // An extension-less asset name carries no format information, so "has no
    // dot" is not evidence of anything. Require positive evidence instead: a
    // platform token in the name, or the name being the executable we expect
    // for this app. A name with an unrecognised extension (`download_cli.sh`,
    // `latest.json`) is never a binary.
    final basename = lower.split('/').last;
    // Hidden files and documentation/metadata names are never binaries, even
    // without an extension.
    if (basename.startsWith('.')) return null;
    if (_nonBinaryBasenames.contains(basename)) return null;
    if (!basename.contains('.')) {
      return _hasBinaryNameSignal(basename, app) ? InstallType.binary : null;
    }
    return null;
  }

  /// Tokens that affirmatively mark a name as a platform-specific binary.
  ///
  /// Names are split on non-alphanumerics, so `x86_64` yields `x86` and `64`.
  /// `linux` is included deliberately: in a release asset it is the strongest
  /// single marker of a Linux build. It is weak evidence on its own — which is
  /// why the payload is still verified as ELF before anything is installed.
  static const _binaryPlatformTokens = {
    // architectures
    'amd64', 'x86', 'x64', 'i386', 'i686', 'aarch64', 'arm64', 'armv7',
    'armhf', 'riscv64', 'ppc64le', 's390x',
    // platform / libc
    'linux', 'musl',
  };

  /// True when [basename] affirmatively looks like a raw binary.
  ///
  /// This is a positive rule on purpose. The previous rule treated any
  /// extension-less name as a binary unless it appeared in
  /// [_nonBinaryBasenames], so a metadata name nobody had anticipated — e.g.
  /// `checksums-2026` — was offered for installation as an executable.
  bool _hasBinaryNameSignal(String basename, TrackedApp? app) {
    final tokens = basename.split(RegExp(r'[^a-z0-9]+'));
    if (tokens.any(_binaryPlatformTokens.contains)) return true;
    if (app == null) return false;
    return _expectedExecutableNames(app).contains(basename);
  }

  /// The names this app's own executable could plausibly be shipped under.
  static Set<String> _expectedExecutableNames(TrackedApp app) {
    final names = <String>{
      app.repoName.toLowerCase(),
      app.displayName.toLowerCase(),
    };
    final pkg = app.packageName;
    if (pkg != null && pkg.isNotEmpty) {
      names.add(p.basename(pkg.toLowerCase()));
    }
    final launch = app.launchCommand;
    if (launch != null && launch.trim().isNotEmpty) {
      final first = launch.trim().split(RegExp(r'\s+')).first;
      names.add(p.basename(first).toLowerCase());
    }
    names.removeWhere((name) => name.isEmpty);
    return names;
  }

  Future<void> _runPrivileged(
    String command,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final printable = 'pkexec $command ${args.join(' ')}';

    // Log the command before it runs, so the in-app log viewer shows what was
    // attempted even if the command then fails.
    dlog('InstallerService', 'Running privileged command: $printable');

    // Try pkexec first
    final ProcessResult result;
    try {
      result = await privilegedProcessRunner(
        'pkexec',
        [command, ...args],
        workingDirectory: workingDirectory,
      );
    } catch (e) {
      dlog('InstallerService', 'Failed to run privileged command: $e');
      throw Exception('Failed to run privileged command: $e');
    }

    // Checked outside the try so a failing command is not wrapped twice.
    if (result.exitCode != 0) {
      // apt writes the actionable diagnosis ("Reading package lists...",
      // "The following packages have unmet dependencies: ...") to stdout and
      // only terse "E:" lines to stderr. Surface both, stdout first, so the
      // message reads in the same order the command actually produced it.
      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();
      final details = [
        if (stdout.isNotEmpty) stdout,
        if (stderr.isNotEmpty) stderr,
      ].join('\n');
      dlog(
        'InstallerService',
        'Privileged command failed (exit code ${result.exitCode}): $printable',
        data: {'stdout': stdout, 'stderr': stderr},
      );
      throw Exception(
        'Command failed (exit code ${result.exitCode})${details.isNotEmpty ? ': $details' : ''}',
      );
    }

    dlog('InstallerService', 'Privileged command succeeded: $printable');
  }

  /// Removes the downloaded file once it has been installed successfully.
  Future<void> _deleteTempDownload(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Cleanup is best effort: never fail an install that already succeeded.
      dlog('InstallerService', 'Could not remove temporary download ${file.path}: $e');
    }
  }
}
