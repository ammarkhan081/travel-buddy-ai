import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  static const _prefKey = 'app.language';
  String _selected = 'English';

  static const _languages = [
    {'name': 'English', 'note': 'Fully supported'},
    {'name': 'Urdu', 'note': 'Coming soon'},
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Language'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          for (final lang in _languages) ...[
            RadioListTile<String>(
              title: Text(lang['name']!),
              subtitle: Text(
                lang['note']!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              value: lang['name']!,
              groupValue: _selected,
              activeColor: theme.colorScheme.primary,
              onChanged: (v) {
                if (v != null) _select(v);
              },
              secondary: _selected == lang['name']
                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                  : null,
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
