import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autononext/models/release.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/ui/widgets/filter_preview.dart';

class _MockGh extends GitHubService {
  _MockGh(this._release);
  final Release _release;
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
    return _release;
  }
}

Release _release() => Release(
  tagName: 'v2.0.0',
  prerelease: false,
  draft: false,
  assets: [
    ReleaseAsset(name: 'app-2.0.0-linux-amd64.deb', browserDownloadUrl: 'https://x/app-2.0.0-linux-amd64.deb', contentType: 'application/octet-stream', size: 1000),
    ReleaseAsset(name: 'app-2.0.0-linux-arm64.deb', browserDownloadUrl: 'https://x/app-2.0.0-linux-arm64.deb', contentType: 'application/octet-stream', size: 1000),
    ReleaseAsset(name: 'app-2.0.0.tar.xz', browserDownloadUrl: 'https://x/app-2.0.0.tar.xz', contentType: 'application/octet-stream', size: 500),
  ],
);

Future<void> _pump(WidgetTester tester, GitHubService gh) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Provider<GitHubService>.value(
          value: gh,
          child: FilterPreview(
            owner: 'ninepointlabs',
            repo: 'autononext',
            assetFilterPattern: '*linux-amd64*',
            tagPrefix: 'v',
            architectures: const ['amd64', 'arm64'],
            includePrerelease: false,
          ),
        ),
      ),
    ),
  );
  // debounce + fetch
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

/// Ceiling for the fully-populated preview box. The aligned two-line layout
/// measures ~55 px; the ceiling leaves a little slack but still fails on a real
/// regression (the old stacked layout was 211 px).
const _maxPreviewHeight = 90.0;

/// The plain text of the line containing [needle].
String _lineContaining(WidgetTester tester, String needle) {
  final text = tester.widget<Text>(find.textContaining(needle));
  return text.textSpan?.toPlainText() ?? text.data ?? '';
}

void main() {
  testWidgets('the populated filter preview stays compact so it does not push the form down', (
    tester,
  ) async {
    final gh = _MockGh(_release());
    await _pump(tester, gh);

    // The widget must have rendered the release branch, not a loading/empty one.
    expect(find.textContaining('matching asset'), findsOneWidget);

    // The requested layout: title and every fact on ONE aligned line, bars
    // between them, with the filenames on a second line.
    expect(
      _lineContaining(tester, 'Filter Preview'),
      'Filter Preview  |  Will fetch  |  Release v2.0.0  |  X64/ARM64  |  3 matching asset(s)',
    );
    expect(
      _lineContaining(tester, 'filenames:'),
      'filenames: app-2.0.0-linux-amd64.deb, app-2.0.0-linux-arm64.deb, app-2.0.0.tar.xz',
    );

    final height = tester.getSize(find.byType(FilterPreview)).height;
    // ignore: avoid_print
    print('FILTER PREVIEW HEIGHT: $height');
    expect(
      height,
      lessThanOrEqualTo(_maxPreviewHeight),
      reason: 'the preview grew; check paddings, icon sizes and the text scale',
    );
  });
}
