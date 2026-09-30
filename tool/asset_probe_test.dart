// LIVE network probe — NOT part of the test suite (it lives outside `test/`).
// Run explicitly:  flutter test tool/asset_probe_test.dart
// Proves which release asset the app would actually download, for the exact
// filters stored in the live profile.
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/services/github_service.dart';

/// `(repo, assetFilterPattern, architectures)` copied verbatim from
/// `~/.local/share/com.autononext/apps.json`.
const _cases = <(String, String, List<String>)>[
  ('Dicklesworthstone/beads_rust', '*tar.gz', ['amd64']),
  ('astral-sh/ty', '*linux-musl*tar.gz', ['amd64']),
  ('agent-sh/computer-use-linux', '*linux-x*gnu', ['amd64']),
  ('Dicklesworthstone/fastmcp_rust', '*linux-amd64*tar.xz', ['amd64']),
  ('Anselmoo/mcp-server-analyzer', '*tar.gz', <String>[]),
];

void main() {
  for (final (repo, filter, archs) in _cases) {
    test('selects a Linux asset for $repo', () async {
      final parts = repo.split('/');
      final info = await GitHubService().getLatestReleaseWithPackageInfo(
        parts[0],
        parts[1],
        assetFilterPattern: filter,
        architectures: archs,
      );
      final selected = info?['packageName'] as String?;
      // ignore: avoid_print
      print('PROBE $repo -> tag=${(info?['release'] as dynamic)?.tagName} '
          'asset=$selected url=${info?['downloadUrl']}');
      expect(info, isNotNull, reason: '$repo: no release matched $filter');
      expect(selected, isNotNull, reason: '$repo: no asset selected');
    });
  }
}
