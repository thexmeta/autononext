import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'debug_logger.dart';

class SettingsService {
  final DebugLogger _logger = DebugLogger();
  static const String _settingsFileName = 'settings.json';
  File? _settingsFile;

  Future<File> get _file async {
    if (_settingsFile != null) return _settingsFile!;
    final configDir = await getApplicationSupportDirectory();
    await Directory(configDir.path).create(recursive: true);
    _settingsFile = File(join(configDir.path, _settingsFileName));
    return _settingsFile!;
  }

  @protected
  Future<Map<String, dynamic>> loadSettings() async {
    final stopwatch = Stopwatch()..start();
    await _logger.log('SettingsService', '=== START loadSettings ===');
    try {
      final file = await _file;
      final exists = await file.exists();
      await _logger.log('SettingsService', 'File exists: $exists', data: {'path': file.path});
      
      if (!exists) {
        DebugLogger.setEnabled(true);
        await _logger.log('SettingsService', 'File does not exist, returning empty');
        return {};
      }
      
      final content = await file.readAsString();
      await _logger.log('SettingsService', 'File content length: ${content.length}', data: {'length': content.length.toString()});
      
      if (content.isEmpty) {
        DebugLogger.setEnabled(true);
        await _logger.log('SettingsService', 'File content is empty');
        return {};
      }
      
      final result = jsonDecode(content) as Map<String, dynamic>;
      // Keep DebugLogger in sync with the stored preference (enabled by
      // default while unset). Done here — rather than inside DebugLogger — so
      // that logging never triggers a settings read (which would recurse).
      DebugLogger.setEnabled(result['enable_debug_logging'] is bool
          ? result['enable_debug_logging'] as bool
          : true);
      await _logger.log('SettingsService', 'Decoded JSON', data: {
        'keys': result.keys.join(', '),
        'theme': result['theme']?.toString() ?? 'null',
        'github_token': result['github_token'] != null ? '***' : 'null',
      });
      
      stopwatch.stop();
      await _logger.log('SettingsService', '=== END loadSettings (${stopwatch.elapsedMilliseconds}ms) ===');
      return result;
    } catch (e) {
      await _logger.log('SettingsService', 'ERROR in loadSettings: $e');
      stopwatch.stop();
      await _logger.log('SettingsService', '=== END loadSettings with ERROR (${stopwatch.elapsedMilliseconds}ms) ===');
      return {};
    }
  }

  @protected
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final stopwatch = Stopwatch()..start();
    await _logger.log('SettingsService', '=== START saveSettings ===', data: {
      'keys': settings.keys.join(', '),
      'theme': settings['theme']?.toString() ?? 'null',
    });
    try {
      final file = await _file;
      await _logger.log('SettingsService', 'Writing to file', data: {'path': file.path});
      
      final encoded = jsonEncode(settings);
      await _logger.log('SettingsService', 'Encoded JSON', data: {'length': encoded.length.toString()});

      // Write to a temp file then rename, so a crash mid-write can never
      // leave a truncated settings.json (which also holds the GitHub token).
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(encoded);
      try {
        await tmp.rename(file.path);
      } catch (e) {
        try {
          await tmp.delete();
        } catch (_) {
          // Best effort: nothing else to do while already failing.
        }
        rethrow;
      }
      await _logger.log('SettingsService', 'File written successfully');
      
      // Verify by reading back. Only the settings KEYS are logged — the file
      // contains the GitHub PAT, which must never reach the debug log.
      final verifySettings = jsonDecode(await file.readAsString());
      final verifyKeys = verifySettings is Map
          ? verifySettings.keys.map((k) => k.toString()).join(', ')
          : '(not a JSON object)';
      await _logger.log('SettingsService', 'Verification read', data: {'keys': verifyKeys});
      
      stopwatch.stop();
      await _logger.log('SettingsService', '=== END saveSettings (${stopwatch.elapsedMilliseconds}ms) ===');
    } catch (e) {
      await _logger.log('SettingsService', 'ERROR in saveSettings: $e');
      stopwatch.stop();
      await _logger.log('SettingsService', '=== END saveSettings with ERROR (${stopwatch.elapsedMilliseconds}ms) ===');
      rethrow;
    }
  }

  Future<String?> getGithubToken() async {
    final settings = await loadSettings();
    return settings['github_token'] as String?;
  }

  Future<void> setGithubToken(String? token) async {
    final settings = await loadSettings();
    if (token == null || token.isEmpty) {
      settings.remove('github_token');
    } else {
      settings['github_token'] = token;
    }
    await saveSettings(settings);
  }

  Future<bool> hasGithubToken() async {
    final token = await getGithubToken();
    return token != null && token.isNotEmpty;
  }

  Future<int?> getReleasesPerPage() async {
    final settings = await loadSettings();
    // Values may have been hand-edited into the settings file as strings.
    return int.tryParse(settings['github_releases_per_page']?.toString() ?? '');
  }

  Future<void> setReleasesPerPage(int? count) async {
    final settings = await loadSettings();
    if (count == null) {
      settings.remove('github_releases_per_page');
    } else {
      settings['github_releases_per_page'] = count.clamp(1, 100);
    }
    await saveSettings(settings);
  }

  Future<int> getEffectiveReleasesPerPage() async {
    final count = await getReleasesPerPage();
    return count ?? 100; // Default to 100 if not set
  }

  Future<String?> getDefaultArchitecture() async {
    final settings = await loadSettings();
    return settings['default_architecture'] as String?;
  }

  Future<void> setDefaultArchitecture(String? arch) async {
    final settings = await loadSettings();
    if (arch == null || arch.isEmpty) {
      settings.remove('default_architecture');
    } else {
      settings['default_architecture'] = arch;
    }
    await saveSettings(settings);
  }

  Future<String> getEffectiveDefaultArchitecture() async {
    final arch = await getDefaultArchitecture();
    return arch ?? 'amd64'; // Default to amd64 if not set
  }

  Future<String?> getTheme() async {
    final settings = await loadSettings();
    return settings['theme'] as String?;
  }

  Future<void> setTheme(String? theme) async {
    final settings = await loadSettings();
    if (theme == null || theme.isEmpty) {
      settings.remove('theme');
    } else {
      settings['theme'] = theme;
    }
    await saveSettings(settings);
  }

  Future<bool> hasTheme() async {
    final theme = await getTheme();
    return theme != null && theme.isNotEmpty;
  }

  // Debug logging settings
  Future<bool> isDebugLoggingEnabled() async {
    final settings = await loadSettings();
    return settings['enable_debug_logging'] as bool? ?? false;
  }

  Future<void> setDebugLoggingEnabled(bool enabled) async {
    final settings = await loadSettings();
    settings['enable_debug_logging'] = enabled;
    await saveSettings(settings);
    DebugLogger.setEnabled(enabled);
  }
}
