import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/tracked_app.dart';

/// A single candidate location where an app's executable may live.
///
/// [path] is absolute with symlinks resolved so that two entries pointing at
/// the same file (via different PATH entries or a symlink) compare equal.
class InstallLocation {
  final String path;
  final String source;
  final bool writable;
  final bool ownedByPackage;

  const InstallLocation({
    required this.path,
    required this.source,
    required this.writable,
    required this.ownedByPackage,
  });
}

/// Discovers where an already-installed binary for [TrackedApp] lives.
///
/// Detection never guesses a fixed directory: it returns every candidate it
/// can prove exists so the UI can ask the user when there is more than one.
class InstallLocationResolver {
  const InstallLocationResolver();

  /// [pathDirs] and [home] are injectable for tests; they default to the real
  /// `PATH` and `HOME`, so production callers pass nothing.
  Future<List<InstallLocation>> resolve(
    TrackedApp app, {
    List<String>? pathDirs,
    String? home,
  }) async {
    final dirs = pathDirs ??
        (Platform.environment['PATH'] ?? '')
            .split(':')
            .where((d) => d.isNotEmpty)
            .toList();
    final homeDir = home ?? Platform.environment['HOME'];

    final results = <InstallLocation>[];
    final seen = <String>{};

    final launchToken = _firstToken(app.launchCommand);

    // 1. An explicit launch command is the strongest signal: if it is an
    //    absolute path to a real file, that is where the app runs from.
    if (launchToken != null && p.isAbsolute(launchToken)) {
      if (await _isRegularFile(launchToken)) {
        final loc = await _build(launchToken, 'launch command', seen);
        if (loc != null) results.add(loc);
      }
    }

    // 2. Derive the executable name we should look for.
    final name = _executableName(app, launchToken);

    // 3. Walk PATH in order.
    for (final dir in dirs) {
      final candidate = p.join(dir, name);
      if (await _isExecutableFile(candidate)) {
        final loc = await _build(candidate, 'PATH', seen);
        if (loc != null) results.add(loc);
      }
    }

    // 4. Probe well-known install directories not already covered.
    for (final dir in await _wellKnownDirs(homeDir)) {
      final candidate = p.join(dir, name);
      if (await _isExecutableFile(candidate)) {
        final loc = await _build(candidate, 'well-known', seen);
        if (loc != null) results.add(loc);
      }
    }

    return results;
  }

  /// Returns the first whitespace-separated token of [command], or null.
  String? _firstToken(String? command) {
    if (command == null) return null;
    final trimmed = command.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  String _executableName(TrackedApp app, String? launchToken) {
    if (launchToken != null && launchToken.isNotEmpty) {
      return p.basename(launchToken);
    }
    final packageName = app.packageName;
    if (packageName != null && packageName.isNotEmpty) {
      return packageName;
    }
    if (app.repoName.isNotEmpty) {
      return app.repoName.toLowerCase();
    }
    return app.displayName.toLowerCase();
  }

  /// Well-known directories, in probe order. Home-relative probes are skipped
  /// when [home] is null.
  Future<List<String>> _wellKnownDirs(String? home) async {
    final dirs = <String>[];
    if (home != null && home.isNotEmpty) {
      dirs.add(p.join(home, '.local', 'bin'));
    }
    dirs.add('/usr/local/bin');
    dirs.add('/usr/bin');

    // Each `/opt/<app>/bin` is a common layout for self-contained bundles.
    try {
      final opt = Directory('/opt');
      if (await opt.exists()) {
        await for (final entity in opt.list()) {
          if (entity is Directory) {
            dirs.add(p.join(entity.path, 'bin'));
          }
        }
      }
    } catch (_) {
      // A missing or unreadable /opt simply yields no extra candidates.
    }
    return dirs;
  }

  /// Builds an [InstallLocation] for a path already confirmed to exist,
  /// returning null when an equivalent location was seen before.
  Future<InstallLocation?> _build(
    String path,
    String source,
    Set<String> seen,
  ) async {
    // resolveSymbolicLinksSync() throws for a missing path; callers only pass
    // confirmed-existing paths, and we fall back to the absolute path on any
    // other failure.
    String key;
    try {
      key = File(path).resolveSymbolicLinksSync();
    } catch (_) {
      key = p.absolute(path);
    }
    if (!seen.add(key)) return null;

    return InstallLocation(
      path: key,
      source: source,
      writable: await isDirWritable(p.dirname(path)),
      ownedByPackage: await _ownedByPackage(path),
    );
  }

  Future<bool> _isRegularFile(String path) async {
    return await FileSystemEntity.type(path) == FileSystemEntityType.file;
  }

  Future<bool> _isExecutableFile(String path) async {
    if (!await _isRegularFile(path)) return false;
    // Any execute bit (owner/group/other) is enough. The mode check is only
    // used to decide *whether the file looks like a program*; the real
    // writability question is answered by an actual write probe below.
    final stat = await File(path).stat();
    return stat.mode & 0x49 != 0;
  }

  /// Whether the current user can create files in [dirPath].
  ///
  /// This is a pure read. It replaced a create-then-delete probe that wrote a
  /// dotfile into system directories: because the user is in group `root`,
  /// resolving an ordinary app briefly created and removed a file inside the
  /// real `/usr/bin`, and a crash in that window would leave it behind.
  ///
  /// Ownership and mode come from `stat`; the effective uid/gid and the
  /// supplementary group set come from `/proc/self/status`. A directory is
  /// writable when the effective uid is 0, or the owner uid matches and the
  /// owner-write bit is set, or the owning gid is one of our groups and the
  /// group-write bit is set, or the other-write bit is set.
  ///
  /// POSIX ACLs are not considered: evaluating them needs libacl, which this
  /// app does not link, so a directory granted write access only through an
  /// ACL reports false. The computation is conservative (it never reports
  /// writable for a directory we cannot write), which is the safe direction.
  ///
  /// Returns false when the path is missing or any lookup fails.
  static Future<bool> isDirWritable(String dirPath) async {
    try {
      final stat = await Process.run('stat', ['-c', '%u %g %a', dirPath]);
      if (stat.exitCode != 0) return false;
      final fields = stat.stdout.toString().trim().split(RegExp(r'\s+'));
      if (fields.length < 3) return false;
      final ownerUid = int.tryParse(fields[0]);
      final ownerGid = int.tryParse(fields[1]);
      final mode = int.tryParse(fields[2], radix: 8);
      if (ownerUid == null || ownerGid == null || mode == null) return false;

      final ids = await _processIds();
      if (ids == null) return false;
      if (ids.uid == 0) return true;
      if (ownerUid == ids.uid && mode & 0x80 != 0) return true;
      if (ids.groups.contains(ownerGid) && mode & 0x10 != 0) return true;
      if (mode & 0x02 != 0) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// The process's effective uid and its group set (effective gid plus the
  /// supplementary groups), read from `/proc/self/status`. Null when the file
  /// is unreadable or malformed.
  static Future<({int uid, Set<int> groups})?> _processIds() async {
    try {
      final status = await File('/proc/self/status').readAsString();
      int? uid;
      int? gid;
      final groups = <int>{};
      for (final line in status.split('\n')) {
        if (line.startsWith('Uid:')) {
          // real, effective, saved, filesystem — effective is the second.
          final fields = line.substring(4).trim().split(RegExp(r'\s+'));
          if (fields.length >= 2) uid = int.tryParse(fields[1]);
        } else if (line.startsWith('Gid:')) {
          final fields = line.substring(4).trim().split(RegExp(r'\s+'));
          if (fields.length >= 2) gid = int.tryParse(fields[1]);
        } else if (line.startsWith('Groups:')) {
          for (final group in line.substring(7).trim().split(RegExp(r'\s+'))) {
            final value = int.tryParse(group);
            if (value != null) groups.add(value);
          }
        }
      }
      if (uid == null) return null;
      // The effective gid is itself one of the groups the process holds.
      if (gid != null) groups.add(gid);
      return (uid: uid, groups: groups);
    } catch (_) {
      return null;
    }
  }

  /// Whether [path] belongs to an installed package, via `dpkg -S` (Debian)
  /// falling back to `rpm -qf` (RPM). Never throws: a missing package tool or
  /// a non-zero exit simply means "not known to be package-owned".
  Future<bool> _ownedByPackage(String path) async {
    try {
      final res = await Process.run('dpkg', ['-S', path]);
      return res.exitCode == 0;
    } catch (_) {
      // dpkg is unavailable — fall through to rpm.
    }
    try {
      final res = await Process.run('rpm', ['-qf', path]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
