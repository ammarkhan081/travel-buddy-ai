import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/themeprovider.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    String selected;
    switch (themeProvider.themeMode) {
      case ThemeMode.light:
        selected = 'Light';
      case ThemeMode.dark:
        selected = 'Dark';
      case ThemeMode.system:
        selected = 'System';
    }

    void onChanged(String? value) {
      if (value == null) return;
      switch (value) {
        case 'Light':
          themeProvider.setThemeMode(ThemeMode.light);
        case 'Dark':
          themeProvider.setThemeMode(ThemeMode.dark);
        case 'System':
          themeProvider.setThemeMode(ThemeMode.system);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          IconButton(
            tooltip: 'Toggle light/dark',
            icon: Icon(
              themeProvider.themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            onPressed: themeProvider.toggleLightDark,
          ),
        ],
      ),
      body: Column(
        children: [
          RadioListTile<String>(
            title: const Text('Light'),
            subtitle: const Text('Default light theme'),
            value: 'Light',
            groupValue: selected,
            activeColor: theme.colorScheme.primary,
            onChanged: onChanged,
          ),
          const Divider(height: 1),
          RadioListTile<String>(
            title: const Text('Dark'),
            subtitle: const Text('Dark mode theme'),
            value: 'Dark',
            groupValue: selected,
            activeColor: theme.colorScheme.primary,
            onChanged: onChanged,
          ),
          const Divider(height: 1),
          RadioListTile<String>(
            title: const Text('System Default'),
            subtitle: const Text('Follow system theme'),
            value: 'System',
            groupValue: selected,
            activeColor: theme.colorScheme.primary,
            onChanged: onChanged,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
