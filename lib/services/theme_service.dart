import 'dart:ui';
import 'package:flutter/material.dart';
import 'settings_service.dart';
import 'debug_logger.dart';

enum AppTheme {
  light,
  dark,
  system,
}

class ThemeService extends ChangeNotifier with WidgetsBindingObserver {
  AppTheme _theme = AppTheme.system;
  bool _isDarkMode = false;
  bool _isLoading = true;
  /// Set once the user picks a theme, so the async load cannot overwrite it.
  bool _userSetTheme = false;
  final SettingsService _settingsService;
  final DebugLogger _logger = DebugLogger();
  late final Future<void> initialization;

  AppTheme get theme => _theme;
  bool get isDarkMode => _isDarkMode;
  bool get isLoading => _isLoading;

  ThemeMode get themeMode {
    switch (_theme) {
      case AppTheme.light:
        return ThemeMode.light;
      case AppTheme.dark:
        return ThemeMode.dark;
      case AppTheme.system:
        return ThemeMode.system;
    }
  }

  ThemeService({required SettingsService settingsService})
      : _settingsService = settingsService {
    _logger.log('ThemeService', 'ThemeService created, starting initialization');
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (e) {
      _logger.log('ThemeService', 'Could not add observer (expected in unit tests)', data: {'error': e.toString()});
    }
    initialization = _loadTheme();
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _logger.log('ThemeService', 'didChangePlatformBrightness called');
    if (_theme == AppTheme.system) {
      _updateSystemTheme();
      notifyListeners();
    }
  }

  Future<void> _loadTheme() async {
    final stopwatch = Stopwatch()..start();
    await _logger.log('ThemeService', '=== START _loadTheme ===');
    try {
      await _logger.log('ThemeService', 'Calling _settingsService.getTheme()');
      final savedTheme = await _settingsService.getTheme();
      await _logger.log('ThemeService', 'getTheme() returned', data: {'value': savedTheme ?? 'null'});
      
      final themeStr = savedTheme ?? 'system';
      await _logger.log('ThemeService', 'Resolving theme string', data: {'themeStr': themeStr});

      // Only apply the persisted theme if the user has not already chosen one
      // while this load was in flight; otherwise the user's choice would be
      // silently reverted once initialization completes.
      if (!_userSetTheme) {
        _theme = AppTheme.values.firstWhere(
          (e) => e.name == themeStr,
          orElse: () => AppTheme.system,
        );
      }
      await _logger.log('ThemeService', 'Theme resolved', data: {'theme': _theme.name});
      
      _updateSystemTheme();
      await _logger.log('ThemeService', 'After _updateSystemTheme', data: {'isDarkMode': _isDarkMode.toString()});
      
      _isLoading = false;
      await _logger.log('ThemeService', 'About to notifyListeners, theme=$_theme, isDarkMode=$_isDarkMode');
      notifyListeners();
      await _logger.log('ThemeService', 'notifyListeners completed');
      
      stopwatch.stop();
      await _logger.log('ThemeService', '=== END _loadTheme (${stopwatch.elapsedMilliseconds}ms) ===');
    } catch (e) {
      await _logger.log('ThemeService', 'ERROR in _loadTheme: $e');
      _theme = AppTheme.system;
      _updateSystemTheme();
      _isLoading = false;
      notifyListeners();
      stopwatch.stop();
      await _logger.log('ThemeService', '=== END _loadTheme with ERROR (${stopwatch.elapsedMilliseconds}ms) ===');
    }
  }

  @override
  void notifyListeners() {
    _logger.log('ThemeService', 'notifyListeners called', data: {
      'theme': _theme.name,
      'isDarkMode': _isDarkMode.toString(),
      'isLoading': _isLoading.toString(),
      'listenerCount': 'unknown',
    });
    super.notifyListeners();
  }

  Future<void> _saveTheme() async {
    final stopwatch = Stopwatch()..start();
    await _logger.log('ThemeService', '=== START _saveTheme ===', data: {'theme': _theme.name});
    try {
      await _logger.log('ThemeService', 'Calling _settingsService.setTheme', data: {'theme': _theme.name});
      await _settingsService.setTheme(_theme.name);
      await _logger.log('ThemeService', 'setTheme completed successfully');
      stopwatch.stop();
      await _logger.log('ThemeService', '=== END _saveTheme (${stopwatch.elapsedMilliseconds}ms) ===');
    } catch (e) {
      await _logger.log('ThemeService', 'ERROR in _saveTheme: $e');
      stopwatch.stop();
      await _logger.log('ThemeService', '=== END _saveTheme with ERROR (${stopwatch.elapsedMilliseconds}ms) ===');
    }
  }

  void _updateSystemTheme() {
    // Update isDarkMode based on current theme
    if (_theme == AppTheme.system) {
      Brightness? brightness;
      try {
        brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      } catch (_) {
        try {
          brightness = PlatformDispatcher.instance.platformBrightness;
        } catch (_) {
          brightness = Brightness.light;
        }
      }
      _isDarkMode = brightness == Brightness.dark;
      _logger.log('ThemeService', '_updateSystemTheme (system)', data: {'brightness': brightness.name, 'isDarkMode': _isDarkMode});
    } else {
      _isDarkMode = _theme == AppTheme.dark;
      _logger.log('ThemeService', '_updateSystemTheme (manual)', data: {'theme': _theme.name, 'isDarkMode': _isDarkMode});
    }
  }

  Future<void> setTheme(AppTheme newTheme) async {
    _userSetTheme = true;
    if (_theme != newTheme) {
      _theme = newTheme;
      if (newTheme == AppTheme.system) {
        _updateSystemTheme();
      } else {
        _isDarkMode = newTheme == AppTheme.dark;
      }
      // Notify before persisting so the UI reflects the new theme immediately
      // instead of waiting on settings I/O (which may be slow or fail).
      notifyListeners();
      await _saveTheme();
    }
  }

  ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
  );

  ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
  );
}
