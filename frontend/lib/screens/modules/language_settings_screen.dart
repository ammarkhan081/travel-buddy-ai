import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  static const _prefKey = 'app.language';
  String _selected = 'English';

  static const _languages = <_LangOption>[
    _LangOption(
        code: 'English',
        flag: '🇬🇧',
        note: 'Fully supported',
        ready: true),
    _LangOption(
        code: 'Urdu',
        flag: '🇵🇰',
        note: 'Coming soon',
        ready: false),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && mounted) setState(() => _selected = saved);
  }

  Future<void> _select(String language) async {
    setState(() => _selected = language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, language);
    if (!mounted) return;
    if (language == 'Urdu') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Urdu localization is coming in a future update.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'Language',
            subtitle: 'Choose your app language',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                for (final lang in _languages) ...[
                  _langOptionCard(lang, isDark, theme),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _langOptionCard(_LangOption lang, bool isDark, ThemeData theme) {
    final active = _selected == lang.code;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: () => _select(lang.code),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: active
                  ? AppColors.primary
                  : (isDark
                      ? AppColors.borderDark
                      : AppColors.borderLight),
              width: active ? 1.8 : 1,
            ),
            boxShadow: isDark ? const [] : AppShadows.softCard,
            color: theme.colorScheme.surface,
          ),
          child: Row(
            children: [
              Text(lang.flag, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.code,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang.note,
                      style: TextStyle(
                        fontSize: 12,
                        color: lang.ready
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w700,
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
                  color: active ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: active
                        ? AppColors.primary
                        : (isDark
                            ? AppColors.borderDark
                            : AppColors.borderLight),
                    width: 2,
                  ),
                ),
                child: active
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

class _LangOption {
  final String code;
  final String flag;
  final String note;
  final bool ready;
  const _LangOption({
    required this.code,
    required this.flag,
    required this.note,
    required this.ready,
  });
}
