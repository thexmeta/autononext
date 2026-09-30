import 'dart:io';
import 'dart:async';
import 'dart:convert';
import '../models/tracked_app.dart';
import '../models/tracked_deb_package.dart';
import 'debug_logger.dart';

typedef ExternalVersionProvider = Future<String?> Function(TrackedApp app);
typedef ExternalDebVersionProvider = Future<String?> Function(TrackedDebPackage pkg);

class ExternalAppChecker {
  /// Provider for app versions, can be overridden for testing
  static ExternalVersionProvider versionProvider = _defaultVersionProvider;
  
  /// Provider for deb package versions, can be overridden for testing
  static ExternalDebVersionProvider debVersionProvider = _defaultDebVersionProvider;

  static final RegExp _versionRegExp = RegExp(
    r'(?:v|version\s+)?(\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z0-9\.\-]+)?)',
    caseSensitive: false,
  );

  /// Checks if the application is installed externally and attempts to find its version.
  static Future<String?> getExternalVersion(TrackedApp app) async {
    return versionProvider(app);
  }

  /// Checks if the deb package is installed externally and attempts to find its version.
  static Future<String?> getExternalDebVersion(TrackedDebPackage pkg) async {
    return debVersionProvider(pkg);
  }

  static Future<String?> _defaultVersionProvider(TrackedApp app) async {
    final guesses = _generateAppGuesses(app);
    return _checkGuesses(app.repoName, guesses);
  }

  static Future<String?> _defaultDebVersionProvider(TrackedDebPackage pkg) async {
    final guesses = _generateDebGuesses(pkg);
    return _checkGuesses(pkg.name, guesses);
  }

  /// Looks up [guesses] against dpkg and PATH.
  ///
  /// Exact package-name matches are tried for every guess first; only if none
  /// of them hit do we fall back to the fuzzy `*$name*` wildcard, which can
  /// otherwise attribute an unrelated package's version to the app.
  static Future<String?> _checkGuesses(String identifier, List<String> guesses) async {
    dlog('ExternalAppChecker', 'Checking $identifier with guesses: $guesses');

    // 1. Exact dpkg-query match, then a PATH binary, per guess.
    for (final name in guesses) {
      final exact = await _dpkgExactVersion(name);
      if (exact != null) return exact;

      final fromPath = await _pathBinaryVersion(name);
      if (fromPath != null) return fromPath;
    }

    // 2. Wildcard fallback (last resort, only for reasonably long names).
    for (final name in guesses) {
      if (name.length < 4) continue;
      final wildcard = await _dpkgWildcardVersion(name);
      if (wildcard != null) return wildcard;
    }

    dlog('ExternalAppChecker', 'No version found for $identifier');
    return null;
  }

  static Future<String?> _dpkgExactVersion(String name) async {
    try {
      // Resolved through PATH: /usr/bin only exists on Debian-family systems.
      final dpkgRes = await Process.run('dpkg-query', ['-W', r'--showformat=${Version}', name])
          .timeout(const Duration(seconds: 2));
      if (dpkgRes.exitCode != 0) return null;
      final out = dpkgRes.stdout.toString().trim();
      if (out.isEmpty) return null;
      dlog('ExternalAppChecker', 'dpkg-query found match for $name: $out');
      final ver = extractVersion(out);
      if (ver != null) {
        dlog('ExternalAppChecker', 'Extracted version from dpkg for $name: $ver');
      }
      return ver;
    } catch (e) {
      dlog('ExternalAppChecker', 'Error in dpkg-query for $name: $e');
      return null;
    }
  }

  /// Fuzzy `*$name*` lookup. An exact package-name row always wins over any
  /// other candidate the wildcard returned.
  static Future<String?> _dpkgWildcardVersion(String name) async {
    try {
      final dpkgWildRes = await Process.run('dpkg-query', ['-W', r'--showformat=${Package}|${Version}\n', '*$name*'])
          .timeout(const Duration(seconds: 2));
      if (dpkgWildRes.exitCode != 0) return null;

      final candidates = <MapEntry<String, String>>[];
      for (final line in dpkgWildRes.stdout.toString().trim().split('\n')) {
        final parts = line.split('|');
        if (parts.length != 2) continue;
        final pkg = parts[0].trim();
        final ver = extractVersion(parts[1]);
        if (ver == null) continue;
        dlog('ExternalAppChecker', 'dpkg wildcard match: $pkg -> ${parts[1]}');
        candidates.add(MapEntry(pkg, ver));
      }

      for (final candidate in candidates) {
        if (candidate.key.toLowerCase() == name.toLowerCase()) {
          dlog('ExternalAppChecker', 'Using exact wildcard row ${candidate.key} for $name');
          return candidate.value;
        }
      }
      if (candidates.isNotEmpty) {
        dlog('ExternalAppChecker', 'Extracted version from dpkg wildcard for $name: ${candidates.first.value}');
        return candidates.first.value;
      }
      return null;
    } catch (e) {
      dlog('ExternalAppChecker', 'Error in dpkg-query wildcard for $name: $e');
      return null;
    }
  }

  /// Runs `<name> --version` / `<name> -v` for a binary found on PATH.
  static Future<String?> _pathBinaryVersion(String name) async {
    try {
      final whichRes = await Process.run('which', [name])
          .timeout(const Duration(seconds: 1));
      if (whichRes.exitCode != 0) return null;
      final path = whichRes.stdout.toString().trim();
      if (path.isEmpty) return null;

      dlog('ExternalAppChecker', 'which found binary for $name at $path');
      final ver = await _runWithTimeout(path, ['--version']);
      if (ver != null) {
        dlog('ExternalAppChecker', 'Extracted version via --version for $name: $ver');
        return ver;
      }

      // Try -v if --version failed
      final verShort = await _runWithTimeout(path, ['-v']);
      if (verShort != null) {
        dlog('ExternalAppChecker', 'Extracted version via -v for $name: $verShort');
      }
      return verShort;
    } catch (e) {
      dlog('ExternalAppChecker', 'Error in which/run for $name: $e');
      return null;
    }
  }

  static List<String> _generateAppGuesses(TrackedApp app) {
    final guesses = <String>{};

    // 1. Explicit package name or launch command
    if (app.packageName != null && app.packageName!.isNotEmpty) {
      guesses.add(app.packageName!);
    }
    if (app.launchCommand != null && app.launchCommand!.isNotEmpty) {
      // If it's a full path, get the basename
      guesses.add(app.launchCommand!.split('/').last);
      // Also try the whole command if it's just a name
      if (!app.launchCommand!.contains('/')) {
        guesses.add(app.launchCommand!);
      }
    }

    // 2. Repo name and variations
    final repoLower = app.repoName.toLowerCase();
    guesses.add(repoLower);
    
    // 3. Repo owner (often the package name for multi-repo projects)
    final ownerLower = app.repoOwner.toLowerCase();
    guesses.add(ownerLower);
    guesses.add('$ownerLower.io');

    // Strip common suffixes like -go, -rust, -desktop
    final cleanRepo = repoLower
        .replaceAll(RegExp(r'-(?:go|rust|desktop|linux|app|cli|gui|client|server|bin|bundle)$'), '')
        .replaceAll(RegExp(r'\.(?:go|rust|desktop|linux|app|cli|gui|client|server|bin|bundle)$'), '');
    if (cleanRepo != repoLower) {
      guesses.add(cleanRepo);
    }
    
    // Also try adding .io (common for modern apps)
    guesses.add('$cleanRepo.io');

    // 4. Extract name from fetched package filename
    if (app.fetchedPackage != null && app.fetchedPackage!.isNotEmpty) {
      final fileName = app.fetchedPackage!.split('/').last;
      final guessesFromFilename = extractNameGuessesFromFilename(fileName);
      guesses.addAll(guessesFromFilename);
    }

    // 5. Display name variations (first word)
    final displayFirst = app.displayName
        .split(' ')[0]
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (displayFirst.length > 2) {
      guesses.add(displayFirst);
      guesses.add('$displayFirst.io');
    }

    return guesses.toList();
  }

  /// Extracts potential package/app names from a filename
  static List<String> extractNameGuessesFromFilename(String fileName) {
    final guesses = <String>{};
    
    // Extract everything before first version-like part or first -/_
    final namePart = fileName.split(RegExp(r'[-_1-9]'))[0].toLowerCase();
    if (namePart.length > 1) {
      guesses.add(namePart);
      guesses.add('$namePart.io');
    }
    
    final firstSegment = fileName.split(RegExp(r'[-_]'))[0].toLowerCase();
    if (firstSegment.length > 1) {
      guesses.add(firstSegment);
    }
    
    return guesses.toList();
  }

  static List<String> _generateDebGuesses(TrackedDebPackage pkg) {
    final guesses = <String>{};

    // 1. The package's own name first — an exact match on it is the most
    //    trustworthy answer.
    guesses.add(pkg.name.toLowerCase());

    // 2. Explicit package name or launch command
    if (pkg.packageName != null && pkg.packageName!.isNotEmpty) {
      guesses.add(pkg.packageName!);
    }
    if (pkg.launchCommand != null && pkg.launchCommand!.isNotEmpty) {
      guesses.add(pkg.launchCommand!.split('/').last);
      if (!pkg.launchCommand!.contains('/')) {
        guesses.add(pkg.launchCommand!);
      }
    }
    
    // Strip common suffixes
    final cleanName = pkg.name.toLowerCase()
        .replaceAll(RegExp(r'-(?:go|rust|desktop|linux|app|cli|gui|client|server|bin|bundle)$'), '');
    if (cleanName != pkg.name.toLowerCase()) {
      guesses.add(cleanName);
    }

    // 3. Display name variations
    if (pkg.displayName != null) {
      final displayFirst = pkg.displayName!
          .split(' ')[0]
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (displayFirst.length > 2) {
        guesses.add(displayFirst);
      }
    }

    return guesses.toList();
  }

  static Future<String?> _runWithTimeout(String cmd, List<String> args) async {
    Process? process;
    Timer? timer;
    try {
      process = await Process.start(cmd, args);
      final output = StringBuffer();
      
      // Safety timer to kill process if it hangs (e.g. GUI launches)
      timer = Timer(const Duration(seconds: 2), () {
        process?.kill();
      });

      // Both streams must be drained: a child writing more than the pipe
      // buffer holds would otherwise block forever.
      final stdoutFuture = process.stdout.transform(utf8.decoder).listen((data) {
        output.write(data);
      }).asFuture();
      final stderrFuture = process.stderr.listen((_) {}).asFuture();

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5), // Increased timeout for slow Electron apps
        onTimeout: () {
          process?.kill();
          return -1;
        },
      );

      // Ensure we don't leak resources
      await stdoutFuture.catchError((_) => null);
      await stderrFuture.catchError((_) => null);

      if (exitCode == 0) {
        return extractVersion(output.toString());
      }
    } catch (_) {
      return null;
    } finally {
      timer?.cancel();
    }
    return null;
  }

  static String? extractVersion(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return null;
    
    // Use regex to find the version string
    final match = _versionRegExp.firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      final ver = match.group(1);
      if (ver != null && ver.isNotEmpty) return ver;
    }
    
    // Fallback: accept only output that is itself a plausible version, e.g.
    // "1.2.3" or "1.2.3-rc1". This avoids mistaking a bare year or build
    // number (e.g. "2024") for a version.
    final fallback =
        RegExp(r'^v?(\d+(?:\.\d+){1,3}(?:-[0-9A-Za-z.\-]+)?)$').firstMatch(trimmed);
    if (fallback != null) {
      return fallback.group(1);
    }

    return null;
  }
}
