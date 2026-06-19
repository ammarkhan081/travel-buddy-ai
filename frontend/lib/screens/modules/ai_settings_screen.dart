import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  static const String routeName = '/aiSettings';

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  String _provider = 'openai';
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _provider = prefs.getString('ai.provider') ?? 'openai';
    _baseUrlController.text =
        prefs.getString('ai.baseUrl') ?? AppConfig.baseUrl;
    _apiKeyController.text = prefs.getString('ai.apiKey') ?? '';
    _modelController.text =
        prefs.getString('ai.model') ??
        (_provider == 'gemini' ? 'gemini-1.5-flash' : 'gpt-4o-mini');

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai.provider', _provider);
      await prefs.setString('ai.baseUrl', _baseUrlController.text.trim());
      await prefs.setString('ai.apiKey', _apiKeyController.text.trim());
      await prefs.setString('ai.model', _modelController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI settings saved.')));
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'AI Settings',
            subtitle: 'Configure chat intelligence safely',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _infoCard(isDark),
                const SizedBox(height: 14),
                _settingsCard(
                  theme: theme,
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Connection mode', isDark),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _provider,
                        decoration: const InputDecoration(labelText: 'Mode'),
                        items: const [
                          DropdownMenuItem(
                            value: 'openai',
                            child: Text('Backend Server (recommended)'),
                          ),
                          DropdownMenuItem(
                            value: 'gemini',
                            child: Text('Google Gemini (direct)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _provider = v;
                            if (_provider == 'openai') {
                              if (_baseUrlController.text.trim().isEmpty) {
                                _baseUrlController.text = AppConfig.baseUrl;
                              }
                              if (_modelController.text.trim().isEmpty) {
                                _modelController.text = 'gpt-4o-mini';
                              }
                            } else if (_modelController.text.trim().isEmpty) {
                              _modelController.text = 'gemini-1.5-flash';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_provider == 'openai') ...[
                        TextField(
                          controller: _baseUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Backend URL',
                            hintText: 'http://localhost:8000',
                            helperText:
                                'Address of the Travel Buddy backend server.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _modelController,
                          decoration: const InputDecoration(
                            labelText: 'Model (optional)',
                            hintText: 'gpt-4o-mini',
                            helperText: 'Override the backend default model.',
                          ),
                        ),
                      ],
                      if (_provider == 'gemini') ...[
                        TextField(
                          controller: _modelController,
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            hintText: 'gemini-1.5-flash',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Gemini API Key',
                            hintText: 'Paste your Google AI Studio API key',
                            helperText: 'Stored locally on this device only.',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving...' : 'Save settings'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.primaryGlow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'The main Travel Buddy chat uses the backend server. AI keys stay server-side. These settings only adjust the backend URL or enable an optional direct Gemini connection.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({
    required ThemeData theme,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
      ),
    );
  }
}
