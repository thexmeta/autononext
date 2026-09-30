import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/utils/glob_pattern.dart';

void main() {
  group('matchesGlobPattern', () {
    test('exact match', () {
      expect(matchesGlobPattern('app.deb', 'app.deb'), isTrue);
      expect(matchesGlobPattern('MyApp.tar.gz', 'MyApp.tar.gz'), isTrue);
    });

    test('wildcard at end', () {
      expect(matchesGlobPattern('app.deb', 'app*'), isTrue);
      expect(matchesGlobPattern('application.deb', 'app*'), isTrue);
      expect(matchesGlobPattern('app', 'app*'), isTrue);
    });

    test('wildcard at start', () {
      expect(matchesGlobPattern('app.deb', '*.deb'), isTrue);
      expect(matchesGlobPattern('MyApp.deb', '*.deb'), isTrue);
      expect(matchesGlobPattern('app.tar.gz', '*.tar.gz'), isTrue);
    });

    test('wildcard in middle', () {
      expect(matchesGlobPattern('app.deb', 'app*.deb'), isTrue);
      expect(matchesGlobPattern('application.deb', 'app*.deb'), isTrue);
      expect(matchesGlobPattern('app.deb', 'app.*'), isTrue);
    });

    test('multiple wildcards', () {
      expect(matchesGlobPattern('app.deb', '*.*'), isTrue);
      expect(matchesGlobPattern('MyApp.tar.gz', '*.*.*'), isTrue);
      expect(matchesGlobPattern('anything', '*'), isTrue);
    });

    test('question mark single char', () {
      expect(matchesGlobPattern('app1.deb', 'app?.deb'), isTrue);
      expect(matchesGlobPattern('appA.deb', 'app?.deb'), isTrue);
      expect(matchesGlobPattern('app.deb', 'app?.deb'), isFalse);
    });

    test('question mark multiple', () {
      expect(matchesGlobPattern('app12.deb', 'app??.deb'), isTrue);
      expect(matchesGlobPattern('app1.deb', 'app??.deb'), isFalse);
    });

    test('case insensitive', () {
      expect(matchesGlobPattern('APP.DEB', 'app.deb'), isTrue);
      expect(matchesGlobPattern('app.deb', 'APP.DEB'), isTrue);
      expect(matchesGlobPattern('App.Deb', 'app.deb'), isTrue);
    });

    test('empty pattern matches everything', () {
      expect(matchesGlobPattern('anything', ''), isTrue);
      expect(matchesGlobPattern('app.deb', ''), isTrue);
    });

    test('empty input handling', () {
      expect(matchesGlobPattern('', ''), isTrue);
      expect(matchesGlobPattern('', '*'), isTrue);
      expect(matchesGlobPattern('', 'app'), isFalse);
    });

    test('special characters in filename', () {
      expect(matchesGlobPattern('my-app_v1.0.deb', 'my-app_v*.deb'), isTrue);
      expect(matchesGlobPattern('app-name.deb', 'app-*.deb'), isTrue);
    });

    test('no match cases', () {
      expect(matchesGlobPattern('app.deb', 'other.deb'), isFalse);
      expect(matchesGlobPattern('app.deb', '*.rpm'), isFalse);
      expect(matchesGlobPattern('app.deb', 'app*.rpm'), isFalse);
    });

    test('regex metacharacters are matched literally', () {
      expect(matchesGlobPattern('app+1.deb', 'app+1.deb'), isTrue);
      expect(matchesGlobPattern('app(1).deb', 'app(1).deb'), isTrue);
      expect(matchesGlobPattern('app[1].deb', 'app[1].deb'), isTrue);
      expect(matchesGlobPattern('app{1}.deb', 'app{1}.deb'), isTrue);
      expect(matchesGlobPattern('app|1.deb', 'app|1.deb'), isTrue);
      expect(matchesGlobPattern('^app.deb', '^app.deb'), isTrue);
      expect(matchesGlobPattern('app\$.deb', 'app\$.deb'), isTrue);
      expect(matchesGlobPattern(r'app\1.deb', r'app\1.deb'), isTrue);
    });

    test('regex metacharacters combined with wildcards', () {
      expect(matchesGlobPattern('app+1.deb', 'app+*'), isTrue);
      expect(matchesGlobPattern('app(1).deb', 'app(*.deb'), isTrue);
      expect(matchesGlobPattern('app[1].deb', 'app[?]*'), isTrue);
      expect(matchesGlobPattern('app{1}.deb', 'app{*}*'), isTrue);
      expect(matchesGlobPattern('app|1.deb', 'app|?.deb'), isTrue);
      expect(matchesGlobPattern('^app.deb', '^*'), isTrue);
      expect(matchesGlobPattern('app\$.deb', '*\$*'), isTrue);
    });

    test('metacharacters do not match other strings', () {
      expect(matchesGlobPattern('app.deb', 'app+.deb'), isFalse);
      expect(matchesGlobPattern('app.deb', 'app(1)*'), isFalse);
      expect(matchesGlobPattern('app.deb', '*|*'), isFalse);
    });

    test('metacharacters in comma separated patterns', () {
      expect(matchesGlobPattern('app.deb', '*.rpm, app(1)*'), isFalse);
      expect(matchesGlobPattern('app(1).deb', '*.rpm, app(*'), isTrue);
    });

    test('malformed patterns never throw', () {
      expect(() => matchesGlobPattern('app.deb', 'app+(['), returnsNormally);
      expect(() => matchesGlobPattern('app.deb', '[a-'), returnsNormally);
      expect(() => matchesGlobPattern('app.deb', '***(unclosed'), returnsNormally);
      expect(matchesGlobPattern('app.deb', 'app+(['), isFalse);
      expect(matchesGlobPattern('app.deb', '[a-'), isFalse);
    });
  });

  group('matchesArchitecture', () {
    test('amd64 detection', () {
      expect(matchesArchitecture('app-amd64.deb', 'amd64'), isTrue);
      expect(matchesArchitecture('app-x86_64.deb', 'x86_64'), isTrue);
      expect(matchesArchitecture('app-x64.deb', 'x64'), isTrue);
      expect(matchesArchitecture('app-64-bit.deb', '64-bit'), isTrue);
    });

    test('amd64 cross detection', () {
      expect(matchesArchitecture('app-x86_64.deb', 'amd64'), isTrue);
      expect(matchesArchitecture('app-amd64.deb', 'x86_64'), isTrue);
      expect(matchesArchitecture('app-x64.deb', 'amd64'), isTrue);
      expect(matchesArchitecture('app-64-bit.deb', 'amd64'), isTrue);
    });

    test('arm64 detection', () {
      expect(matchesArchitecture('app-arm64.deb', 'arm64'), isTrue);
      expect(matchesArchitecture('app-aarch64.deb', 'aarch64'), isTrue);
      expect(matchesArchitecture('app-armv8.deb', 'armv8'), isTrue);
    });

    test('arm64 cross detection', () {
      expect(matchesArchitecture('app-arm64.deb', 'aarch64'), isTrue);
      expect(matchesArchitecture('app-aarch64.deb', 'arm64'), isTrue);
    });

    test('arm detection', () {
      expect(matchesArchitecture('app-armhf.deb', 'armhf'), isTrue);
      expect(matchesArchitecture('app-armv7.deb', 'armv7'), isTrue);
      expect(matchesArchitecture('app-arm-.deb', 'arm'), isTrue);
    });

    test('i386 detection', () {
      expect(matchesArchitecture('app-i386.deb', 'i386'), isTrue);
      expect(matchesArchitecture('app-x86.deb', 'x86'), isTrue);
      expect(matchesArchitecture('app-32-bit.deb', '32-bit'), isTrue);
    });

    test('i386 cross detection', () {
      expect(matchesArchitecture('app-i386.deb', 'x86'), isTrue);
      expect(matchesArchitecture('app-x86.deb', 'i386'), isTrue);
    });

    test('case insensitive', () {
      expect(matchesArchitecture('app-AMD64.deb', 'amd64'), isTrue);
      expect(matchesArchitecture('app-ARM64.deb', 'arm64'), isTrue);
      expect(matchesArchitecture('app-Amd64.deb', 'amd64'), isTrue);
    });

    test('custom architecture string', () {
      expect(matchesArchitecture('app-linux-musl-x64.deb', 'musl'), isTrue);
      // FreeBSD is not Linux, so a `freebsd`-tagged asset is rejected as a
      // foreign-OS build even when `freebsd` is the requested architecture.
      expect(matchesArchitecture('app-freebsd.deb', 'freebsd'), isFalse);
    });

    test('no match', () {
      expect(matchesArchitecture('app-amd64.deb', 'arm64'), isFalse);
      expect(matchesArchitecture('app-arm64.deb', 'amd64'), isFalse);
      expect(matchesArchitecture('app.deb', 'amd64'), isFalse);
    });

    test('rejects a macOS asset even when its architecture token matches', () {
      expect(matchesArchitecture('br-0.7.3-darwin_amd64.tar.gz', 'amd64'), isFalse);
    });

    test('accepts a Linux asset when its architecture token matches', () {
      expect(matchesArchitecture('ty-x86_64-unknown-linux-musl.tar.gz', 'amd64'), isTrue);
    });

    test('keeps matching an OS-neutral Linux package name', () {
      expect(matchesArchitecture('app-amd64.deb', 'amd64'), isTrue);
    });
  });

  group('isForeignOsAsset', () {
    test('flags a macOS asset so a Linux host never selects it', () {
      expect(isForeignOsAsset('br-0.7.3-darwin_amd64.tar.gz'), isTrue);
    });

    test('leaves Linux assets selectable because no token marks a foreign OS', () {
      expect(isForeignOsAsset('ty-x86_64-unknown-linux-musl.tar.gz'), isFalse);
      expect(isForeignOsAsset('computer-use-linux-x86_64-unknown-linux-gnu'), isFalse);
      expect(isForeignOsAsset('waza-linux-amd64'), isFalse);
      expect(isForeignOsAsset('biome-linux-x64-musl'), isFalse);
      expect(isForeignOsAsset('PromptOptimizer-2.11.10-linux-x64.zip'), isFalse);
      expect(isForeignOsAsset('ruff-x86_64-unknown-linux-musl.tar.gz'), isFalse);
      expect(isForeignOsAsset('nub-linux-x64-musl.tar.gz'), isFalse);
      expect(isForeignOsAsset('app-amd64.deb'), isFalse);
    });

    test('keeps a Linux asset whose PRODUCT NAME contains android or ios, so a hyphenated name does not downgrade the app', () {
      // Regression: `android` used to be a foreign-OS token, so this real asset
      // was rejected and the selector fell back to a 2022 release.
      expect(
        isForeignOsAsset('Android-Messages-v6.1.1-linux-amd64.deb'),
        isFalse,
      );
      expect(matchesArchitecture('Android-Messages-v6.1.1-linux-amd64.deb', 'amd64'), isTrue);
      expect(isForeignOsAsset('apple-music-linux-x64.tar.gz'), isFalse);
      expect(isForeignOsAsset('ios-remote-linux-amd64'), isFalse);
    });

    test('rejects mobile artifacts by extension so android/ios builds still never install', () {
      expect(isForeignOsAsset('app-android-arm64.apk'), isTrue);
      expect(isForeignOsAsset('app-release.aab'), isTrue);
      expect(isForeignOsAsset('app-ios-arm64.ipa'), isTrue);
    });
  });

  group('findMatchingArchitectures', () {
    test('finds matching architectures', () {
      final result = findMatchingArchitectures(
        'app-amd64-arm64.deb',
        ['amd64', 'arm64', 'armhf'],
      );
      expect(result, contains('amd64'));
      expect(result, contains('arm64'));
      expect(result.length, equals(2));
    });

    test('returns empty for no matches', () {
      final result = findMatchingArchitectures(
        'app.deb',
        ['amd64', 'arm64'],
      );
      expect(result, isEmpty);
    });

    test('returns all matching', () {
      final result = findMatchingArchitectures(
        'app-amd64-x86_64.deb',
        ['amd64', 'x86_64', 'arm64'],
      );
      expect(result, contains('amd64'));
      expect(result, contains('x86_64'));
      expect(result.length, equals(2));
    });
  });

  group('Release Filtering logic', () {
    test('tag prefix filtering', () {
      // Logic from GitHubService: lowerTag.contains(searchPrefix)
      bool matchesTag(String tagName, String prefix) {
        if (prefix.trim().isEmpty) return true;
        return tagName.toLowerCase().contains(prefix.trim().toLowerCase());
      }

      expect(matchesTag('v1.0.0', 'v'), isTrue);
      expect(matchesTag('v1.0.0', '1.0'), isTrue);
      expect(matchesTag('v1.0.0', 'V'), isTrue);
      expect(matchesTag('v1.0.0', '2.0'), isFalse);
      expect(matchesTag('app-v1.0.0', 'v1'), isTrue);
    });

    test('prerelease filtering', () {
      bool shouldInclude(bool isPrerelease, bool includePrerelease) {
        if (!includePrerelease && isPrerelease) return false;
        return true;
      }

      expect(shouldInclude(true, false), isFalse);
      expect(shouldInclude(true, true), isTrue);
      expect(shouldInclude(false, false), isTrue);
      expect(shouldInclude(false, true), isTrue);
    });
  });
}
