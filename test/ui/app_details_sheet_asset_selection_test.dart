import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:autononext/models/release.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/database_service.dart';
import 'package:autononext/services/github_service.dart';
import 'package:autononext/services/install_location.dart';
import 'package:autononext/services/installer_service.dart';
import 'package:autononext/services/settings_service.dart';
import 'package:autononext/ui/home_screen.dart';
import '../mock_services.dart';
import '../mocks/mock_installer_service.dart';

TrackedApp _app() => TrackedApp(
      repoOwner: 'ninepointlabs',
      repoName: 'autononext',
      displayName: 'Autononext',
      createdAt: DateTime(2026, 1, 1),
    );

/// A release shipping three `.deb` variants with the amd64 build in the middle,
/// so neither "first listed wins" nor "last listed wins" picks the right one.
class _TwoVariantGitHubService extends GitHubService {
  @override
  Future<Release?> getLatestRelease(
    String owner,
    String repo, {
    String? assetFilterPattern,
    String? tagPrefix,
    List<String>? architectures,
    bool includePrerelease = false,
  }) async {
    ReleaseAsset variant(String arch) => ReleaseAsset(
          name: 'autononext_1.0.0_$arch.deb',
          browserDownloadUrl: 'https://example.com/autononext_1.0.0_$arch.deb',
          contentType: 'application/vnd.debian.binary-package',
          size: 1,
        );

    return Release(
      tagName: 'v1.0.0',
      prerelease: false,
      draft: false,
      assets: [variant('arm64'), variant('amd64'), variant('armhf')],
    );
  }
}

Future<void> _openSheet(
  WidgetTester tester,
  MockInstallerService installer,
) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<GitHubService>.value(value: _TwoVariantGitHubService()),
        Provider<InstallerService>.value(value: installer),
        Provider<DatabaseService>.value(value: MockDatabaseService()),
        Provider<SettingsService>.value(value: MockSettingsService()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => AppDetailsSheet(
                  app: _app(),
                  // A single, non-package-managed candidate means the target
                  // chooser resolves without a dialog and without probing the
                  // real filesystem (which would hang the fake-async zone).
                  candidatesOverride: const [
                    InstallLocation(
                      path: '/usr/local/bin/autononext',
                      source: 'PATH',
                      writable: true,
                      ownedByPackage: false,
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('AppDetailsSheet asset selection', () {
    testWidgets('picks the variant matching the host architecture, not the first or last listed',
        (tester) async {
      final installer = MockInstallerService();
      await _openSheet(tester, installer);

      await tester.tap(find.text('Install'));
      // `_isInstalling` drives an indeterminate LinearProgressIndicator, so
      // `pumpAndSettle` would never return here — pump a fixed number of frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('DEB'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // arm64 is listed first, amd64 in the middle and armhf last; the host
      // reports amd64, so only an architecture-aware pick is correct.
      expect(installer.downloadedUrls, hasLength(1));
      expect(
        installer.downloadedUrls.single,
        endsWith('autononext_1.0.0_amd64.deb'),
      );
    });
  });
}
