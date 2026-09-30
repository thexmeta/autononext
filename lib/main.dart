import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'ui/home_screen.dart';
import 'services/database_service.dart';
import 'services/github_service.dart';
import 'services/installer_service.dart';
import 'services/theme_service.dart';
import 'services/settings_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--version') || args.contains('-v')) {
    // Basic CLI support to prevent GUI launch on version check.
    // CLI contract: `--version` writes to stdout (not the debug log).
    final info = await PackageInfo.fromPlatform();
    stdout.writeln('Autononext ${info.version}');
    // The Linux runner creates and shows the GTK window before Dart runs, so
    // merely returning from main() would leave an invisible/black window alive
    // and the process hanging forever. Terminate explicitly.
    exit(0);
  }
  runApp(const AutononextApp());
}

class AutononextApp extends StatelessWidget {
  const AutononextApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = SettingsService();
    return MultiProvider(
      providers: [
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => settingsService),
        Provider(
          create: (context) => GitHubService(
            settingsService: settingsService,
          ),
        ),
        Provider(create: (_) => InstallerService()),
        ChangeNotifierProvider(
          create: (_) => ThemeService(
            settingsService: settingsService,
          ),
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          // Wait for the persisted theme before the first paint, otherwise the
          // app flashes the default theme before the saved one is applied.
          if (themeService.isLoading) {
            return const MaterialApp(
              home: Scaffold(body: SizedBox.shrink()),
            );
          }
          return MaterialApp(
            title: 'Autononext',
            theme: themeService.lightTheme,
            darkTheme: themeService.darkTheme,
            themeMode: themeService.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
