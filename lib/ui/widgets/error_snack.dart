import 'package:flutter/material.dart';

/// Shows a persistent, dismissible error (or warning) snackbar.
///
/// The snackbar stays on screen until the user dismisses it, so long
/// diagnostic dumps (e.g. apt output with unmet dependencies) remain
/// readable and can be scrolled instead of overflowing or auto-dismissing.
void showErrorSnack(
  BuildContext context,
  String message, {
  bool isWarning = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(days: 1),
      backgroundColor:
          isWarning ? Colors.orange.shade700 : Colors.red.shade700,
      showCloseIcon: true,
      closeIconColor: Colors.white70,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  softWrap: true,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      action: SnackBarAction(
        label: 'Dismiss',
        textColor: Colors.white,
        onPressed: () => messenger.hideCurrentSnackBar(),
      ),
    ),
  );
}
