/// Result of a single batch operation item
class BatchOperationResult {
  final String appName;
  final bool success;
  final String? error;
  final String? newVersion;

  const BatchOperationResult({
    required this.appName,
    required this.success,
    this.error,
    this.newVersion,
  });
}

/// Progress tracker for batch operations
class BatchProgress {
  final int total;
  int completed;
  int successful;
  int failed;
  String currentOperation;
  final DateTime startTime;

  BatchProgress({
    required this.total,
    this.completed = 0,
    this.successful = 0,
    this.failed = 0,
    this.currentOperation = '',
    required this.startTime,
  });

  double get progressPercentage => total > 0 ? (completed / total) * 100 : 0;
  Duration get elapsed => DateTime.now().difference(startTime);
}
