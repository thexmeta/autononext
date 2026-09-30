import 'package:flutter/material.dart';
import '../../models/tracked_deb_package.dart';
import 'package:url_launcher/url_launcher.dart';
import 'error_snack.dart';

class DebPackageListItem extends StatelessWidget {
  final TrackedDebPackage package;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onUpdate;
  final bool isSelected;

  /// True while the list is in multi-select mode. Tapping a row then toggles
  /// its selection, so the inline "open URL" action is hidden — tapping it
  /// would open a browser instead of toggling the row.
  final bool isMultiSelectMode;

  const DebPackageListItem({
    super.key,
    required this.package,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onUpdate,
    this.isSelected = false,
    this.isMultiSelectMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasUpdate = package.hasUpdate;
    
    return ListTile(
      // Compact so more entries fit on screen, matching the app rows.
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: 0,
      // Every row shows a checkbox while multi-select is active, so the mode
      // is visible on unselected rows too — not only on already-selected ones.
      leading: isMultiSelectMode
          ? Checkbox(
              value: isSelected,
              onChanged: (value) => onTap(),
            )
          : null,
      title: Row(
        children: [
          Expanded(
            child: Text(
              package.effectiveDisplayName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: hasUpdate
                    ? Colors.orange.shade700
                    : (isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null),
              ),
            ),
          ),
          if (!isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.link, size: 16),
              onPressed: () => _openPackageUrl(context),
              tooltip: 'Open direct download URL',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(package.packageUrl, 
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          // Installed | Latest on one line, separated by a bar, matching the
          // app rows; the latest version keeps its own colour.
          if (package.installedVersion != null || package.latestVersion != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (package.installedVersion != null)
                      TextSpan(
                        text: 'Installed: ${package.installedVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (package.installedVersion != null &&
                        package.latestVersion != null)
                      TextSpan(
                        text: '  |  ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (package.latestVersion != null)
                      TextSpan(
                        text: 'Latest: ${package.latestVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUpdate
                              ? Colors.orange[600]
                              : Colors.grey[600],
                          fontWeight: hasUpdate ? FontWeight.w600 : null,
                        ),
                      ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (package.fileSize != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.storage, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Size: ${package.fileSize}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'DIRECT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(width: 4),
            // Compact hit boxes: the default IconButton reserves 48x48, which
            // alone sets a floor on the row height.
            if (hasUpdate)
              IconButton(
                icon: const Icon(Icons.system_update, size: 18),
                onPressed: onUpdate,
                tooltip: 'Check this package for updates',
                color: Colors.orange.shade700,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: onEdit,
                tooltip: 'Edit package',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
              tooltip: 'Remove from list',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 6),
            if (package.installedVersion != null)
              const Icon(Icons.check_circle, color: Colors.green, size: 18)
            else
              const Icon(Icons.circle_outlined, color: Colors.grey, size: 18),
        ],
      ),
      onTap: onTap,
      selected: isSelected,
    );
  }

  Future<void> _openPackageUrl(BuildContext context) async {
    final uri = Uri.parse(package.packageUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, 'Could not open URL: $e');
      }
    }
  }
}
