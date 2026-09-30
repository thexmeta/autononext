import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/models/release.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/ui/widgets/filter_preview.dart';

class _CountingGitHubService extends GitHubService {
  int calls = 0;

  @override
  Future<Release?> getLatestRelease(
    String owner,
    String repo, {
    String? assetFilterPattern,
    String? tagPrefix,
    List<String>? architectures,
    bool includePrerelease = false,
  }) async {
    calls++;
    return Release(
      tagName: 'v1.0.0',
      prerelease: false,
      draft: false,
      assets: const [],
    );
  }
}

void main() {
  testWidgets('an equal-but-distinct architecture list does not refetch', (tester) async {
    final gh = _CountingGitHubService();

    Widget build(List<String> architectures) => Provider<GitHubService>.value(
          value: gh,
          child: MaterialApp(
            home: Scaffold(
              body: FilterPreview(
                owner: 'ninepointlabs',
                repo: 'autononext',
                architectures: architectures,
              ),
            ),
          ),
        );

    // Deliberately non-const literals: a `const` list is canonicalised, so two
    // `const ['amd64']` literals would be the same instance and identity
    // comparison would appear to work.
    await tester.pumpWidget(build(['amd64']));
    // The preview debounces for 500ms before fetching.
    await tester.pump(const Duration(milliseconds: 600));
    expect(gh.calls, 1);

    // A parent rebuild hands over a new List instance with the same contents.
    // Identity comparison treated that as a filter change and refetched on every
    // single rebuild.
    await tester.pumpWidget(build(['amd64']));
    await tester.pump(const Duration(milliseconds: 600));
    expect(gh.calls, 1);

    // A genuinely different list must still refetch.
    await tester.pumpWidget(build(['arm64']));
    await tester.pump(const Duration(milliseconds: 600));
    expect(gh.calls, 2);
  });
}
