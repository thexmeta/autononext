import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/install_type.dart';
import '../models/release.dart';
import '../models/tracked_app.dart';
import '../services/database_service.dart';
import '../services/install_location.dart';
import '../services/installer_service.dart';
import '../utils/glob_pattern.dart';

/// Shared upgrade flow used by both the list-row action and the details sheet.
///
/// "Check for Updates" only fetches metadata; "Upgrade" actually downloads and
/// installs the newer release. These helpers implement the second half so the
/// two entry points cannot drift apart.
///
/// The executable name a release installs as: the basename of the first token
/// of the stored launch command, else the stored package name, else the repo
/// name lower-cased (matching the GitHub binary naming convention).
String _executableName(TrackedApp app) {
  final token = _firstToken(app.launchCommand);
  if (token != null && token.isNotEmpty) return p.basename(token);
  final packageName = app.packageName;
  if (packageName != null && packageName.isNotEmpty) return packageName;
  return app.repoName.toLowerCase();
}

String? _firstToken(String? command) {
  if (command == null) return null;
  final trimmed = command.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// Icon used to represent an [InstallType] in selection dialogs.
IconData installTypeIcon(InstallType type) {
  switch (type) {
    case InstallType.deb:
      return Icons.grid_view;
    case InstallType.rpm:
      return Icons.settings;
    case InstallType.appImage:
      return Icons.extension;
    case InstallType.flatpak:
      return Icons.layers;
    case InstallType.snap:
      return Icons.shopping_bag;
    default:
      return Icons.download;
  }
}

/// Dialog listing the install types available in [release]; null when the user
/// cancels or the release carries no installable asset.
Future<InstallType?> pickInstallType(
  BuildContext context,
  Release release, {
  TrackedApp? app,
}) async {
  final installer = context.read<InstallerService>();

  final types = <InstallType>[];
  for (final asset in release.assets) {
    final type = installer.identifyAssetType(asset.name, app: app);
    if (type != null && !types.contains(type)) types.add(type);
  }
  if (types.isEmpty) return null;

  return showDialog<InstallType>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Select Package Type'),
      children: types.map((type) {
        return SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(type),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(installTypeIcon(type)),
                const SizedBox(width: 12),
                Text(type.displayName),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}

/// Picks which release asset to install for [type].
///
/// Returns the only candidate without asking when the release ships exactly one
/// asset of that type. When it ships several — a release carrying both a GUI and
/// a CLI AppImage, for example — the user is asked rather than silently given
/// the first one (upstream issue #5).
///
/// [candidatesOverride] injects the asset list for tests.
Future<ReleaseAsset?> chooseAsset(
  BuildContext context,
  Release release,
  InstallType type, {
  TrackedApp? app,
  List<ReleaseAsset>? candidatesOverride,
  List<String>? preferredArchs,
}) async {
  final installer = context.read<InstallerService>();
  final candidates = (candidatesOverride ?? release.assets)
      .where((a) => installer.identifyAssetType(a.name, app: app) == type)
      .toList();

  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.single;

  final preferred = preferredArchs ?? app?.architectures ?? const [];
  String? matchingArch(ReleaseAsset asset) {
    for (final arch in preferred) {
      if (matchesArchitecture(asset.name, arch)) return arch.toUpperCase();
    }
    return null;
  }

  // Exactly one candidate satisfying the app's declared architectures is not a
  // real choice — the app already said which architecture it wants (this is the
  // usual "one .deb per architecture" release). Ask only when the choice stays
  // ambiguous: several matching, or none, as with a GUI and a CLI AppImage that
  // both match the host.
  final archMatches = candidates.where((a) => matchingArch(a) != null).toList();
  if (archMatches.length == 1) return archMatches.single;

  // Pair each asset with the architecture it satisfies, so the list can hint at
  // the likely choice without hiding the others.
  final entries = [
    for (final asset in candidates) (asset, matchingArch(asset)),
  ];

  return showDialog<ReleaseAsset>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('Select ${type.displayName} Asset'),
      children: [
        for (final (asset, arch) in entries)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(asset),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(installTypeIcon(type)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(asset.name, overflow: TextOverflow.ellipsis),
                  ),
                  if (arch != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        arch,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

/// Resolves where an app is currently installed and returns the absolute path
/// the upgrade should overwrite.
///
/// * 0 candidates — asks for a path, prefilled with `<home>/.local/bin/<name>`.
/// * 1 candidate — returns it without asking, but a package-managed target
///   requires an explicit confirmation first and yields null when declined.
/// * 2+ candidates — lists path + source so the user can pick.
///
/// [candidatesOverride] injects a candidate list for tests, avoiding real
/// filesystem probing inside the fake-async zone of widget tests.
Future<String?> chooseInstallTarget(
  BuildContext context,
  TrackedApp app, {
  List<InstallLocation>? candidatesOverride,
}) async {
  final candidates = candidatesOverride ??
      await const InstallLocationResolver().resolve(app);

  // The resolver may have taken real time; do not touch the context after it.
  if (!context.mounted) return null;

  if (candidates.isEmpty) {
    return _askForInstallPath(context, app);
  }

  if (candidates.length == 1) {
    final only = candidates.single;
    if (only.ownedByPackage) {
      final confirmed =
          await _confirmPackageManagedOverwrite(context, only.path);
      if (confirmed != true) return null;
    }
    return only.path;
  }

  return _pickFromCandidates(context, candidates);
}

Future<String?> _askForInstallPath(BuildContext context, TrackedApp app) {
  final home = Platform.environment['HOME'] ?? '';
  final defaultPath =
      p.join(home, '.local', 'bin', _executableName(app));
  return showDialog<String>(
    context: context,
    builder: (_) => _InstallPathDialog(defaultPath: defaultPath),
  );
}

/// Owns its [TextEditingController] so it is disposed after the dialog's exit
/// animation, not while the field is still on screen.
class _InstallPathDialog extends StatefulWidget {
  final String defaultPath;

  const _InstallPathDialog({required this.defaultPath});

  @override
  State<_InstallPathDialog> createState() => _InstallPathDialogState();
}

class _InstallPathDialogState extends State<_InstallPathDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultPath);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    // Reject unsafe paths here, before they can reach the installer, so the
    // user gets immediate feedback instead of a failure after downloading.
    final error = InstallerService.installTargetError(value);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Install Location'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Install path',
          helperText: 'Full path to install the executable to',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Install'),
        ),
      ],
    );
  }
}

Future<bool?> _confirmPackageManagedOverwrite(
  BuildContext context,
  String path,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Package-managed file'),
      content: Text(
        '$path is managed by your system package manager.\n\n'
        'Overwriting it directly desynchronises the package database, so a '
        'later system update may undo this upgrade or fail. Continue only if '
        'you are sure.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: const Text('Overwrite anyway'),
        ),
      ],
    ),
  );
}

Future<String?> _pickFromCandidates(
  BuildContext context,
  List<InstallLocation> candidates,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Choose Install Location'),
      children: candidates.map((candidate) {
        return SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(candidate.path),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(candidate.path),
              Text(
                candidate.ownedByPackage
                    ? '${candidate.source} · package-managed'
                    : candidate.source,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      }).toList(),
    ),
  );
}

/// Downloads [assetName] from [downloadUrl], installs it into [targetPath] as
/// [type], and persists the result. Returns true only when every step
/// succeeded; the success message is never shown on a failure path.
Future<bool> performUpgrade({
  required BuildContext context,
  required TrackedApp app,
  required Release release,
  required InstallType type,
  required String assetName,
  required String downloadUrl,
  required String targetPath,
}) async {
  final installer = context.read<InstallerService>();
  final db = context.read<DatabaseService>();

  // Never downgrade: if something is already installed and the release is not
  // strictly newer, refuse and say so instead of overwriting with an older
  // build. A null installed version means this is a first-time install.
  final installed = app.installedVersion;
  if (installed != null && !isNewerVersion(release.tagName, installed)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${app.displayName} is already at $installed; '
            '${release.tagName} is not newer',
          ),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
    return false;
  }

  try {
    final file = await installer.downloadFile(downloadUrl, assetName);
    final result = await installer.installPackage(
      file,
      type,
      targetPath: targetPath,
      binaryName: _executableName(app),
    );

      var updatedApp = app.copyWith(
        installedVersion: release.tagName,
        installType: type,
        packageName: result.packageName,
        // Record the asset actually installed, so the row shows the file that is
        // now on disk instead of whatever the previous check happened to pick.
        fetchedPackage: assetName,
        lastChecked: DateTime.now(),
      );
    // copyWith uses sentinel semantics, so passing a null launchCommand would
    // CLEAR a stored one. Only overwrite it when the install produced one.
    if (result.launchCommand != null) {
      updatedApp = updatedApp.copyWith(launchCommand: result.launchCommand);
    }
    await db.updateApp(updatedApp);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upgraded ${app.displayName} to ${release.tagName}'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upgrade failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    return false;
  }
}
