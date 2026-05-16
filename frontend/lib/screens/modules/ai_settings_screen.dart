import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

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
    _modelController.text = prefs.getString('ai.model') ??
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI settings saved.')),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info card explaining how AI is powered
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The main Travel Buddy chat uses the backend server — AI keys '
                    'are managed server-side. These settings let you configure the '
                    'backend URL or enable a direct Google Gemini connection.',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onPrimaryContainer,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          DropdownButtonFormField<String>(
            value: _provider,
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
                } else {
                  if (_modelController.text.trim().isEmpty) {
                    _modelController.text = 'gemini-1.5-flash';
                  }
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
                helperText: 'Address of the Travel Buddy backend server.',
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
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}
