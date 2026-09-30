import 'package:flutter/material.dart';

class BatchActionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback? onSelectAll;
  final VoidCallback? onDeselectAll;
  final VoidCallback? onUpdateAll;
  final VoidCallback? onInstallAll;
  final VoidCallback? onDeleteAll;

  const BatchActionBar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    this.onSelectAll,
    this.onDeselectAll,
    this.onUpdateAll,
    this.onInstallAll,
    this.onDeleteAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selection info
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                '$selectedCount of $totalCount selected',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            children: [
              // Select All / Deselect All
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selectedCount == totalCount
                      ? onDeselectAll
                      : onSelectAll,
                  icon: const Icon(Icons.select_all),
                  label: Text(
                    selectedCount == totalCount ? 'Deselect All' : 'Select All',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Check for Updates (metadata only — does not install)
              Expanded(
                child: FilledButton.icon(
                  onPressed: selectedCount > 0 ? onUpdateAll : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check for Updates'),
                ),
              ),
        const SizedBox(width: 8),
        // Install All
        Expanded(
          child: FilledButton.icon(
            onPressed: selectedCount > 0 ? onInstallAll : null,
            icon: const Icon(Icons.download),
            label: const Text('Install'),
          ),
        ),
        const SizedBox(width: 8),
        // Delete All
        Expanded(
          child: FilledButton.icon(
            onPressed: selectedCount > 0 ? onDeleteAll : null,
            icon: const Icon(Icons.delete),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
          ),
        ),
        ],
      ),
        ],
      ),
    );
  }
}
