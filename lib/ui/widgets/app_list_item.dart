import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/tracked_app.dart';
import 'error_snack.dart';

class AppListItem extends StatelessWidget {
  final TrackedApp app;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onUpdate;
  final bool isSelected;

  /// True while the list is in multi-select mode. Tapping a row then toggles
  /// its selection, so the inline "open repository" action is hidden — tapping
  /// it would open a browser instead of toggling the row.
  final bool isMultiSelectMode;

  const AppListItem({
    super.key,
    required this.app,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onUpdate,
    this.isSelected = false,
    this.isMultiSelectMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasUpdate = app.hasUpdate;
    // Inline separator between items that share a line.
    TextSpan bar() => TextSpan(
      text: '  |  ',
      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
    );
    
      return ListTile(
        // Compact so more entries fit on screen. Each row stacks several
        // metadata lines, so the default ListTile vertical padding is wasted
        // space.
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
              app.displayName,
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
          // The "open repository" action lives in `trailing` with the other
          // icons, so they all share one vertically-centred line instead of
          // this one floating up beside the title.
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Repository | asset filename on one line. A single Text so the whole
          // line ellipsises from the right, which drops the filename before the
          // repository when space runs out.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${app.repoOwner}/${app.repoName}'),
                if (app.fetchedPackage != null) ...[
                  bar(),
                  TextSpan(
                    text: app.fetchedPackage!,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
          // Installed | Latest | Released on one line, separated by bars. The
          // latest version keeps its own colour so an update still stands out.
          if (app.installedVersion != null ||
              app.latestVersion != null ||
              app.latestReleaseDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (app.installedVersion != null)
                      TextSpan(
                        text: 'Installed: ${app.installedVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (app.installedVersion != null &&
                        (app.latestVersion != null ||
                            app.latestReleaseDate != null))
                      bar(),
                    if (app.latestVersion != null)
                      TextSpan(
                        text: 'Latest: ${app.latestVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUpdate
                              ? Colors.orange[600]
                              : Colors.grey[600],
                          fontWeight: hasUpdate ? FontWeight.w600 : null,
                        ),
                      ),
                    if (app.latestVersion != null &&
                        app.latestReleaseDate != null)
                      bar(),
                    if (app.latestReleaseDate != null)
                      TextSpan(
                        text: 'Released: ${_formatDate(app.latestReleaseDate!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hidden in multi-select mode: tapping it would open a browser instead
          // of toggling the row.
          if (!isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => _openRepoUrl(context),
              tooltip: 'Open repository on GitHub',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          if (app.architectures.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                // All architectures, because the stacked line that used to list
                // them was removed.
                app.architectures.map((a) => a.toUpperCase()).join('/'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                tooltip: 'Upgrade this app',
                color: Colors.orange.shade700,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: onEdit,
                tooltip: 'Edit app',
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
            if (app.isInstalled)
              const Icon(Icons.check_circle, color: Colors.green, size: 18)
            else
              const Icon(Icons.circle_outlined, color: Colors.grey, size: 18),
        ],
      ),
      onTap: onTap,
      selected: isSelected,
    );
  }

  Future<void> _openRepoUrl(BuildContext context) async {
    final url = 'https://github.com/${app.repoOwner}/${app.repoName}';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, 'Could not open URL: $e');
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
