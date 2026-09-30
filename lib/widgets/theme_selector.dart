import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class ThemeSelector extends StatelessWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Theme',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<AppTheme>(
                  segments: const [
                    ButtonSegment(
                      value: AppTheme.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: AppTheme.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                    ButtonSegment(
                      value: AppTheme.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                  ],
                  selected: {themeService.theme},
                  onSelectionChanged: (selected) async {
                    try {
                      await themeService.setTheme(selected.first);
                    } catch (e) {
                      // Do not silently drop the persistence future: surface a
                      // failed save so the user knows the choice was not stored.
                      debugPrint('Failed to persist theme: $e');
                    }
                  },
                  showSelectedIcon: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'Current: ${themeService.isDarkMode ? 'Dark' : 'Light'} mode',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
