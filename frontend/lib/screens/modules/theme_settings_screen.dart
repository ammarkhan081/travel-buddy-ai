import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_colors.dart';
import '../../theme/themeprovider.dart';
import '../../widgets/app_header.dart';

/// Theme settings — pick between Light, Dark and System.
/// Re-uses ThemeProvider so any change propagates app-wide instantly.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);

    final selected = switch (themeProvider.themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };

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
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'Theme',
            subtitle: 'Pick light, dark, or follow your device',
            onBack: () => Navigator.maybePop(context),
            trailing: AppHeaderIconButton(
              icon: themeProvider.themeMode == ThemeMode.dark
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              onTap: themeProvider.toggleLightDark,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _themeOption(
                  context: context,
                  icon: Icons.light_mode_rounded,
                  iconColor: AppColors.warning,
                  title: 'Light',
                  subtitle: 'Bright, airy lilac surfaces',
                  isSelected: selected == 'Light',
                  onTap: () => onChanged('Light'),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _themeOption(
                  context: context,
                  icon: Icons.dark_mode_rounded,
                  iconColor: AppColors.primary,
                  title: 'Dark',
                  subtitle: 'Deep navy with purple highlights',
                  isSelected: selected == 'Dark',
                  onTap: () => onChanged('Dark'),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _themeOption(
                  context: context,
                  icon: Icons.brightness_auto_rounded,
                  iconColor: AppColors.success,
                  title: 'System default',
                  subtitle: 'Follow your phone\'s setting',
                  isSelected: selected == 'System',
                  onTap: () => onChanged('System'),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeOption({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                      ? AppColors.borderDark
                      : AppColors.borderLight),
              width: isSelected ? 1.8 : 1,
            ),
            boxShadow: isDark ? const [] : AppShadows.softCard,
            color: theme.colorScheme.surface,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? AppColors.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark
                            ? AppColors.borderDark
                            : AppColors.borderLight),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
