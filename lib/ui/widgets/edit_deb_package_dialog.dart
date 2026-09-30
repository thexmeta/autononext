import 'package:flutter/material.dart';
import '../../models/tracked_deb_package.dart';

class EditDebPackageDialog extends StatefulWidget {
  final TrackedDebPackage package;

  const EditDebPackageDialog({super.key, required this.package});

  @override
  State<EditDebPackageDialog> createState() => _EditDebPackageDialogState();
}

class _EditDebPackageDialogState extends State<EditDebPackageDialog> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _displayNameController;
  bool _autoUpdate = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.package.name);
    _urlController = TextEditingController(text: widget.package.packageUrl);
    _displayNameController = TextEditingController(text: widget.package.displayName ?? '');
    _autoUpdate = widget.package.autoUpdate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final displayName = _displayNameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Internal name is required')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A valid http(s) package URL is required')),
      );
      return;
    }

    final updated = widget.package.copyWith(
      name: name,
      displayName: displayName.isEmpty ? null : displayName,
      packageUrl: url,
      autoUpdate: _autoUpdate,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    // Same compaction as the app edit dialog: slightly smaller text everywhere
    // plus denser text fields, so the form is shorter.
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.apply(fontSizeFactor: 0.85),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
      ),
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        title: const Text('Edit Deb Package'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Internal Name (Package ID)',
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'Package URL'),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: Text('Auto Update Check')),
                  Switch(
                    value: _autoUpdate,
                    onChanged: (v) => setState(() => _autoUpdate = v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
