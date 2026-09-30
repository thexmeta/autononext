import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/github_service.dart';
import '../../models/release.dart';

class FilterPreview extends StatefulWidget {
  final String owner;
  final String repo;
  final String? assetFilterPattern;
  final String? tagPrefix;
  final List<String> architectures;
  final bool includePrerelease;

  const FilterPreview({
    super.key,
    required this.owner,
    required this.repo,
    this.assetFilterPattern,
    this.tagPrefix,
    this.architectures = const [],
    this.includePrerelease = false,
  });

  @override
  State<FilterPreview> createState() => _FilterPreviewState();
}

class _FilterPreviewState extends State<FilterPreview> {
  Release? _latestRelease;
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _debounceFetch();
  }

  @override
  void didUpdateWidget(FilterPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.owner != oldWidget.owner ||
        widget.repo != oldWidget.repo ||
        widget.assetFilterPattern != oldWidget.assetFilterPattern ||
        widget.tagPrefix != oldWidget.tagPrefix ||
        // `architectures` is rebuilt from a controller on every parent build,
        // so identity comparison fired a refetch on every rebuild. Compare
        // contents instead.
        !listEquals(widget.architectures, oldWidget.architectures) ||
        widget.includePrerelease != oldWidget.includePrerelease) {
      _debounceFetch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _debounceFetch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _fetchPreview();
      }
    });
  }

  Future<void> _fetchPreview() async {
    if (widget.owner.isEmpty || widget.repo.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final gh = context.read<GitHubService>();
      
      // Fetch latest release with filters
      final release = await gh.getLatestRelease(
        widget.owner,
        widget.repo,
        assetFilterPattern: widget.assetFilterPattern,
        tagPrefix: widget.tagPrefix,
        architectures: widget.architectures,
        includePrerelease: widget.includePrerelease,
      );

      if (mounted) {
        setState(() {
          _latestRelease = release;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // No text-scale wrapper here: `Theme.of(context)` inside this widget's own
    // build resolves to the ANCESTOR theme, so a wrapper added here would only
    // shrink the few Texts that carry no explicit size, leaving the rest at the
    // host's scale. The preview instead inherits whatever scale its host applies
    // (the edit dialog uses 0.9), which keeps every line consistent.
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // In the release state the title leads the single aligned data line,
          // so the standalone header is only drawn for the other states.
          if (!(_latestRelease != null && !_isLoading && _error == null)) ...[
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Filter Preview',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Error: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
          else if (_latestRelease != null)
            _buildPreviewContent()
          else
            _buildNoResults(),
        ],
      ),
    );
  }

  Widget _buildPreviewContent() {
    final assets = _latestRelease!.assets;
    final assetCount = assets.length;
    final archLabels = _getArchitectureLabels();
    final names = assets.take(3).map((a) => a.name).toList();
    final remaining = assetCount - names.length;

    final scheme = Theme.of(context).colorScheme;
    final bold = TextStyle(fontWeight: FontWeight.bold);
    final muted = TextStyle(color: scheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Everything on one aligned line, bars between the parts:
        // Filter Preview | Will fetch | Release <tag> | <ARCH> | N matching asset(s)
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Filter Preview',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              bar(),
              TextSpan(text: 'Will fetch', style: bold),
              bar(),
              TextSpan(
                text: _latestRelease!.tagName.isNotEmpty
                    ? 'Release ${_latestRelease!.tagName}'
                    : 'Latest release',
              ),
              if (archLabels.isNotEmpty) ...[
                bar(),
                TextSpan(
                  text: archLabels.join('/').toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
              ],
              bar(),
              TextSpan(
                text: assetCount > 0
                    ? '$assetCount matching asset(s)'
                    : 'No matching assets',
                style: TextStyle(
                  color: assetCount > 0 ? scheme.primary : scheme.error,
                ),
              ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
        ),
        // Second line: the filenames themselves, comma separated.
        if (assetCount > 0) ...[
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'filenames: ', style: bold),
                TextSpan(
                  text:
                      names.join(', ') +
                      (remaining > 0 ? ' (+$remaining more)' : ''),
                  style: muted,
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  /// The inline separator used between items that share a line.
  TextSpan bar() => TextSpan(
    text: '  |  ',
    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );

  Widget _buildNoResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.warning,
              size: 15,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              'No releases found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Try adjusting your filters or check if the repository has releases.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  List<String> _getArchitectureLabels() {
    final labels = <String>[];
    final assetNames = _latestRelease?.assets.map((a) => a.name).join(' ') ?? '';
    
    if (widget.architectures.any((a) => a.toLowerCase().contains('x64') || a.toLowerCase().contains('amd64'))) {
      if (assetNames.toLowerCase().contains('x64') || assetNames.toLowerCase().contains('amd64')) {
        labels.add('x64');
      }
    }
    if (widget.architectures.any((a) => a.toLowerCase().contains('arm64') || a.toLowerCase().contains('aarch64'))) {
      if (assetNames.toLowerCase().contains('arm64') || assetNames.toLowerCase().contains('aarch64')) {
        labels.add('arm64');
      }
    }
    if (widget.architectures.any((a) => a.toLowerCase().contains('arm'))) {
      if (assetNames.toLowerCase().contains('armhf') || assetNames.toLowerCase().contains('armv7')) {
        labels.add('arm');
      }
    }
    
    return labels;
  }
}
