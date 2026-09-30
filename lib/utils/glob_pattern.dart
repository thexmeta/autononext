bool matchesGlobPattern(String input, String pattern) {
  if (pattern.isEmpty) return true;
  if (input.isEmpty) return pattern == '*';

  final patterns = pattern.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);
  
  for (final p in patterns) {
    final regexPattern = _globToRegex(p);
    RegExp? regex;
    try {
      regex = RegExp(regexPattern, caseSensitive: false);
    } catch (_) {
      // A pattern can never be trusted to compile: fall back to a literal
      // case-insensitive substring match instead of throwing.
      regex = null;
    }
    if (regex != null) {
      if (regex.hasMatch(input)) return true;
    } else if (input.toLowerCase().contains(p.toLowerCase())) {
      return true;
    }
  }
  return false;
}

/// Converts a glob pattern into an anchored, case-insensitive regex source.
///
/// Every regex metacharacter is escaped; only `*` and `?` keep their glob
/// meaning.
String _globToRegex(String pattern) {
  final buffer = StringBuffer();
  final trimmed = pattern.trim();

  for (var i = 0; i < trimmed.length; i++) {
    final char = trimmed[i];
    if (char == '*') {
      buffer.write('.*');
    } else if (char == '?') {
      buffer.write('.');
    } else {
      buffer.write(RegExp.escape(char));
    }
  }

  return '^${buffer.toString()}\$';
}

/// OS tokens that identify an asset built for a platform other than Linux.
///
/// Deliberately excludes `android`, `ios` and `apple`: those words appear in
/// product names far more often than they mark a build target, and a whole-token
/// match on them rejects legitimate Linux artifacts. `Android-Messages-v6.1.1-linux-amd64.deb`
/// is the real case — the app's own name contains "Android", so the asset was
/// dropped and the selector fell back to a 2022 release. Mobile artifacts are
/// caught by extension instead.
const Set<String> _foreignOsTokens = {
  'darwin', 'macos', 'osx', 'win32', 'win64', 'windows',
  'mingw', 'msvc', 'cygwin', 'freebsd',
};

/// Extensions that mark an artifact as unusable on Linux, whatever the name.
const List<String> _foreignOsSuffixes = [
  '.exe', '.msi', '.dmg', '.pkg', '.app', // desktop, other OS
  '.apk', '.aab', '.ipa', // mobile
];

/// Returns `true` when [fileName] names an artifact built for an OS other than
/// Linux.
///
/// A filename is foreign when any whole alphanumeric token is a known
/// non-Linux OS marker, or when it carries a platform-specific extension.
/// Comparison is done on a lowercased, punctuation-split form so
/// `br-0.7.3-darwin_amd64.tar.gz` is recognised as a macOS build even though
/// its architecture token (`amd64`) matches the host.
bool isForeignOsAsset(String fileName) {
  final lower = fileName.toLowerCase();
  if (_foreignOsSuffixes.any(lower.endsWith)) {
    return true;
  }
  final tokens = lower.split(RegExp(r'[^a-z0-9]+'));
  return tokens.any(_foreignOsTokens.contains);
}

bool matchesArchitecture(String fileName, String architecture) {
  // This app targets Linux, so an architecture match on a macOS/Windows (or
  // any other non-Linux) asset is never actionable. Reject foreign-OS
  // artifacts before the architecture switch so a macOS build such as
  // `br-0.7.3-darwin_amd64.tar.gz` is never selected for `amd64`.
  if (isForeignOsAsset(fileName)) return false;

  final lowerName = fileName.toLowerCase();
  final lowerArch = architecture.toLowerCase();

  switch (lowerArch) {
    case 'amd64':
    case 'x86_64':
      return lowerName.contains('amd64') ||
          lowerName.contains('x86_64') ||
          lowerName.contains('x64') ||
          lowerName.contains('64-bit');
    case 'arm64':
    case 'aarch64':
      return lowerName.contains('arm64') ||
          lowerName.contains('aarch64') ||
          lowerName.contains('armv8');
    case 'arm':
    case 'armhf':
    case 'armv7':
      return lowerName.contains('armhf') ||
          lowerName.contains('armv7') ||
          lowerName.contains('arm-');
    case 'i386':
    case 'x86':
      return lowerName.contains('i386') ||
          lowerName.contains('x86') ||
          lowerName.contains('32-bit');
    default:
      return lowerName.contains(lowerArch);
  }
}

List<String> findMatchingArchitectures(
  String fileName,
  List<String> architectures,
) {
  return architectures
      .where((arch) => matchesArchitecture(fileName, arch))
      .toList();
}
