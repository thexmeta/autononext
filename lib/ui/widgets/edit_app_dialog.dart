import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tracked_app.dart';
import '../../services/github_service.dart';
import 'error_snack.dart';
import 'filter_preview.dart';

class EditAppDialog extends StatefulWidget {
  final TrackedApp app;

  const EditAppDialog({super.key, required this.app});

  @override
  State<EditAppDialog> createState() => _EditAppDialogState();
}

class _EditAppDialogState extends State<EditAppDialog> {
  late TextEditingController _nameController;
  late TextEditingController _ownerController;
  late TextEditingController _repoController;
  late TextEditingController _assetFilterController;
  late TextEditingController _tagPrefixController;
  late TextEditingController _architecturesController;
  late TextEditingController _launchCommandController;
  late TextEditingController _packageNameController;
  bool _includePrerelease = false;
  bool _showPreview = false;
  bool _isFetching = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.app.displayName);
    _ownerController = TextEditingController(text: widget.app.repoOwner);
    _repoController = TextEditingController(text: widget.app.repoName);
    _assetFilterController = TextEditingController(text: widget.app.assetFilterPattern ?? '');
    _tagPrefixController = TextEditingController(text: widget.app.tagPrefix ?? '');
    _architecturesController = TextEditingController(
      text: widget.app.architectures.join(', '),
    );
    _launchCommandController = TextEditingController(text: widget.app.launchCommand ?? '');
    _packageNameController = TextEditingController(text: widget.app.packageName ?? '');
    _includePrerelease = widget.app.includePrerelease;

    for (final controller in _previewControllers) {
      controller.addListener(_onPreviewInputChanged);
    }
  }

  /// Controllers whose text feeds [FilterPreview]. Listening to them rebuilds
  /// the dialog on each keystroke so the preview's 500 ms debounce re-arms.
  List<TextEditingController> get _previewControllers => [
        _ownerController,
        _repoController,
        _assetFilterController,
        _tagPrefixController,
        _architecturesController,
      ];

  void _onPreviewInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _previewControllers) {
      controller.removeListener(_onPreviewInputChanged);
    }
    _nameController.dispose();
    _ownerController.dispose();
    _repoController.dispose();
    _assetFilterController.dispose();
    _tagPrefixController.dispose();
    _architecturesController.dispose();
    _launchCommandController.dispose();
    _packageNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    
    if (owner.isEmpty || repo.isEmpty) {
      setState(() {
        _fetchError = 'Owner and repo are required';
      });
      return;
    }

    setState(() {
      _isFetching = true;
      _fetchError = null;
    });

    try {
      final gh = context.read<GitHubService>();
      final info = await gh.getRepository(owner, repo);

      if (!mounted) return;
      setState(() {
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = info['description'] ?? info['name'];
        }
        if (_packageNameController.text.trim().isEmpty) {
          _packageNameController.text = info['name'].toLowerCase();
        }
        if (_launchCommandController.text.trim().isEmpty) {
          _launchCommandController.text = info['name'].toLowerCase();
        }
        _isFetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = e.toString();
        _isFetching = false;
      });
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty ||
        _ownerController.text.trim().isEmpty ||
        _repoController.text.trim().isEmpty) {
      showErrorSnack(context, 'Please fill all required fields', isWarning: true);
      return;
    }

    final filterError = TrackedApp.validateFilterSettings(
      assetFilterPattern: _assetFilterController.text.isEmpty ? null : _assetFilterController.text,
      tagPrefix: _tagPrefixController.text.isEmpty ? null : _tagPrefixController.text,
    );
    if (filterError != null) {
      showErrorSnack(context, filterError, isWarning: true);
      return;
    }

    try {
      final architectures = _architecturesController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final updatedApp = widget.app.copyWith(
        displayName: _nameController.text.trim(),
        repoOwner: _ownerController.text.trim(),
        repoName: _repoController.text.trim(),
        assetFilterPattern: _assetFilterController.text.trim().isEmpty ? null : _assetFilterController.text.trim(),
        tagPrefix: _tagPrefixController.text.trim().isEmpty ? null : _tagPrefixController.text.trim(),
        architectures: architectures,
        includePrerelease: _includePrerelease,
        launchCommand: _launchCommandController.text.trim().isEmpty ? null : _launchCommandController.text.trim(),
        packageName: _packageNameController.text.trim().isEmpty ? null : _packageNameController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, updatedApp);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, 'Error preparing app update: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Compact the whole form: slightly smaller text everywhere plus denser text
    // fields, so the dialog is shorter and needs less scrolling.
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.apply(fontSizeFactor: 0.9),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          isDense: true,
          // Compact but still legible: the labels and helpers stay readable
          // while the field boxes and gaps carry most of the saving.
          labelStyle: const TextStyle(fontSize: 12),
          hintStyle: const TextStyle(fontSize: 12),
          helperStyle: const TextStyle(fontSize: 11),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
        ),
      ),
      child: AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      title: const Text('Edit Tracked App'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ownerController,
              decoration: const InputDecoration(
                labelText: 'Repository Owner',
                hintText: 'e.g., flutter',
                prefixText: 'https://github.com/',
                suffixText: '/repo-name',
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _repoController,
              decoration: const InputDecoration(
                labelText: 'Repository Name',
                hintText: 'e.g., flutter',
              ),
            ),
            const SizedBox(height: 6),
            // Asset Filter Pattern - Always visible
            TextField(
              controller: _assetFilterController,
              decoration: const InputDecoration(
                labelText: 'Asset Filter Pattern',
                hintText: '*.deb, *amd64*, *linux*',
                helperText: 'Filter release assets by filename (e.g., *.deb)',
                prefixIcon: Icon(Icons.filter_alt, size: 18),
              ),
            ),
            const SizedBox(height: 6),
            // Tag Prefix
            TextField(
              controller: _tagPrefixController,
              decoration: const InputDecoration(
                labelText: 'Tag Prefix',
                hintText: 'v, release-, app-v',
                helperText: 'Only consider releases with this tag prefix',
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _architecturesController,
              decoration: const InputDecoration(
                labelText: 'Architectures',
                hintText: 'e.g., x64, arm64 (comma-separated)',
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Include Pre-releases'),
              value: _includePrerelease,
              onChanged: (value) {
                setState(() => _includePrerelease = value);
              },
            ),
            const SizedBox(height: 6),
            const Divider(),
            const Text('System Detection (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _launchCommandController,
              decoration: const InputDecoration(
                labelText: 'Custom Binary/Launch Command',
                hintText: 'e.g., code, discord, br',
                helperText: 'Command name to check with "which"',
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _packageNameController,
              decoration: const InputDecoration(
                labelText: 'Custom Package Name',
                hintText: 'e.g., code-insiders, discord-canary',
                helperText: 'Package name to check with "dpkg"',
              ),
            ),
            const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() => _showPreview = !_showPreview);
              },
              icon: Icon(
                _showPreview ? Icons.visibility_off : Icons.visibility,
                size: 16,
              ),
              label: Text(_showPreview ? 'Hide Preview' : 'Show Preview'),
            ),
            IconButton(
              icon: _isFetching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              onPressed: _isFetching ? null : _fetchDetails,
              tooltip: 'Fetch repository details',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        if (_fetchError != null)
          Text(
            _fetchError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
            if (_showPreview)
              FilterPreview(
                owner: _ownerController.text.trim(),
                repo: _repoController.text.trim(),
                assetFilterPattern: _assetFilterController.text.isEmpty ? null : _assetFilterController.text,
                tagPrefix: _tagPrefixController.text.isEmpty ? null : _tagPrefixController.text,
                architectures: _architecturesController.text
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
                includePrerelease: _includePrerelease,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save Changes'),
        ),
      ],
      ),
    );
  }
}
