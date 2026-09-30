import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tracked_deb_package.dart';
import '../../models/install_type.dart';
import '../../services/database_service.dart';
import '../../services/installer_service.dart';
import 'error_snack.dart';

class DebPackageDetailsSheet extends StatefulWidget {
  final TrackedDebPackage package;

  const DebPackageDetailsSheet({super.key, required this.package});

  @override
  State<DebPackageDetailsSheet> createState() => _DebPackageDetailsSheetState();
}

class _DebPackageDetailsSheetState extends State<DebPackageDetailsSheet> {
  bool _isInstalling = false;
  bool _isUninstalling = false;

  /// Human-readable description of the operation in flight. A bare spinner
  /// gives no indication of whether the app is downloading or installing.
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final pkg = widget.package;
    
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, size: 48, color: Colors.blue),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pkg.effectiveDisplayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      pkg.name,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildInfoRow('URL', pkg.packageUrl),
          _buildInfoRow('Installed Version', pkg.installedVersion ?? 'Not installed'),
          _buildInfoRow('Latest Version', pkg.latestVersion ?? 'Unknown'),
          // Only render file metadata when the service actually populated it;
          // never show a placeholder for a genuinely-null value.
          if (pkg.fileSize != null) _buildInfoRow('File Size', pkg.fileSize!),
          if (pkg.fileDate != null)
            _buildInfoRow(
              'File Date',
              pkg.fileDate!.toLocal().toString().split('.').first,
            ),
          if (pkg.lastChecked != null)
            _buildInfoRow('Last Checked', pkg.lastChecked!.toLocal().toString().split('.').first),
          // `autoUpdate` is a stored preference only — no scheduler consumes
          // it yet, so the label must not imply automatic updates actually run.
          _buildInfoRow(
            'Auto-update check',
            pkg.autoUpdate ? 'On (preference only, no scheduler)' : 'Off',
          ),
          
          const SizedBox(height: 32),
          if (_statusMessage != null) ...[
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              if (pkg.installedVersion != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isUninstalling ? null : _uninstall,
                    icon: _isUninstalling 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_outline),
                    label: const Text('Uninstall'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _launch,
                    icon: const Icon(Icons.launch),
                    label: const Text('Launch'),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isInstalling ? null : _installUpdate,
                    icon: _isInstalling 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download),
                    label: const Text('Install'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (pkg.hasUpdate && pkg.installedVersion != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isInstalling ? null : _installUpdate,
                icon: const Icon(Icons.update),
                label: const Text('Upgrade to Latest'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Future<void> _uninstall() async {
    setState(() {
      _isUninstalling = true;
      _statusMessage = 'Uninstalling ${widget.package.effectiveDisplayName}...';
    });
    try {
      final installer = context.read<InstallerService>();
      final db = context.read<DatabaseService>();
      
      await installer.uninstallDebPackage(widget.package);
      
      final updatedPkg = widget.package.copyWith(installedVersion: null);
      await db.updateDebPackage(updatedPkg);
      
      if (mounted) {
        setState(() {
          _isUninstalling = false;
          _statusMessage = null;
        });
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUninstalling = false;
          _statusMessage = null;
        });
        showErrorSnack(context, 'Uninstallation failed: $e');
      }
    }
  }

  Future<void> _launch() async {
    try {
      final installer = context.read<InstallerService>();
      setState(() => _statusMessage = 'Launching...');
      await installer.launchDebPackage(widget.package);
      // Dismiss the sheet so the dispatch is visible; leaving it open made a
      // successful launch look like nothing happened.
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = null);
        showErrorSnack(context, 'Launch failed: $e');
      }
    }
  }

  Future<void> _installUpdate() async {
    final filename = widget.package.name.endsWith('.deb') ? widget.package.name : '${widget.package.name}.deb';
    setState(() {
      _isInstalling = true;
      _statusMessage = 'Downloading $filename...';
    });
    try {
      final installer = context.read<InstallerService>();
      final db = context.read<DatabaseService>();
      
      final file = await installer.downloadFile(widget.package.packageUrl, filename);
      
      if (mounted) setState(() => _statusMessage = 'Installing $filename...');
      final result = await installer.installPackage(file, InstallType.deb);
      
      final version = TrackedDebPackage.extractVersionFromFilename(file.path.split('/').last);

      final updatedPkg = widget.package.copyWith(
        installedVersion: version ?? widget.package.latestVersion,
        packageName: result.packageName,
        launchCommand: result.launchCommand,
        lastChecked: DateTime.now(),
      );
      await db.updateDebPackage(updatedPkg);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Installation successful'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, 'Installation failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _statusMessage = null;
        });
      }
    }
  }
}
