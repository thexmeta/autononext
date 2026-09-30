import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Debug logger for tracking settings persistence issues
class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  static const String _logFileName = 'autononext_debug.log';
  /// Maximum on-disk log size before it is truncated to its newest half.
  static const int _maxLogBytes = 1024 * 1024; // 1 MB
  File? _logFile;
  final List<String> _buffer = [];
  bool _initialized = false;

  /// Whether logging is currently enabled. Defaults to `true` until
  /// [SettingsService] applies the `enable_debug_logging` preference.
  static bool _enabled = true;

  static bool get isEnabled => _enabled;

  /// Turns debug logging on/off. Called by [SettingsService]; the logger
  /// itself never reads settings back (that would recurse into logging).
  static void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      // Drop anything buffered so disabled logging leaves no trace.
      DebugLogger._instance._buffer.clear();
    }
  }

  /// Initialize the logger
  Future<void> _init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File(path.join(dir.path, _logFileName));
      _initialized = true;
      _flushBuffer();
    } catch (e) {
      // The logger cannot log its own failures (that would recurse), so report
      // to stderr directly.
      stderr.writeln('[DebugLogger] Failed to initialize: $e');
    }
  }

  /// Flush buffered logs, rotating the file first if it has grown too large.
  Future<void> _flushBuffer() async {
    if (_logFile == null || _buffer.isEmpty) return;
    try {
      final content = '${_buffer.join('\n')}\n';
      await _rotateIfNeeded(utf8.encode(content).length);
      await _logFile!.writeAsString(content, mode: FileMode.append);
      _buffer.clear();
    } catch (e) {
      // See _init(): logging a logging failure would recurse.
      stderr.writeln('[DebugLogger] Failed to write log: $e');
    }
  }

  /// Truncates the log to its most recent portion once appending
  /// [incomingBytes] would push it past [_maxLogBytes], so the file cannot
  /// grow without bound. The newest half of the cap is kept so rotation is
  /// not paid on every single write.
  Future<void> _rotateIfNeeded(int incomingBytes) async {
    final file = _logFile;
    if (file == null || !await file.exists()) return;
    final size = await file.length();
    if (size + incomingBytes <= _maxLogBytes) return;

    // Keep the newest bytes within half the cap so rotation is not paid on
    // every write. The slice is byte-bounded (not character-bounded) so a
    // multi-byte log cannot retain more than the intended budget.
    final keepBytes = _maxLogBytes ~/ 2;
    final text = await file.readAsString();
    final encoded = utf8.encode(text);
    var tail = encoded.length <= keepBytes
        ? text
        : utf8.decode(encoded.sublist(encoded.length - keepBytes),
            allowMalformed: true);
    // Drop a possibly partial first line left by cutting mid-file.
    final firstNewline = tail.indexOf('\n');
    if (firstNewline >= 0) {
      tail = tail.substring(firstNewline + 1);
    }
    await file.writeAsString(tail);
  }

  /// Log a message
  Future<void> log(String category, String message, {Map<String, dynamic>? data}) async {
    if (!_enabled) return;
    await _init();
    final timestamp = DateTime.now().toString().substring(0, 19);
    var logMsg = '[$timestamp] [$category] $message';
    if (data != null && data.isNotEmpty) {
      logMsg += ' | Data: ${data.map((k, v) => MapEntry(k, v.toString())).entries.map((e) => '${e.key}=${e.value}').join(', ')}';
    }
    
    // Add to buffer
    _buffer.add(logMsg);
    
    // Write immediately for critical debugging
    if (_logFile != null && _initialized) {
      await _flushBuffer();
    }
  }

  /// Clear the log file
  Future<void> clear() async {
    await _init();
    if (_logFile != null) {
      await _logFile!.writeAsString('');
    }
  }

  /// Get log file path
  Future<String?> getLogFilePath() async {
    await _init();
    return _logFile?.path;
  }
}

// Convenience functions
Future<void> dlog(String category, String message, {Map<String, dynamic>? data}) =>
    DebugLogger().log(category, message, data: data);

Future<void> dlogClear() => DebugLogger().clear();

Future<String?> dlogPath() => DebugLogger().getLogFilePath();
