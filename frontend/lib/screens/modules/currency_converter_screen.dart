import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class CurrencyConverterScreen extends StatefulWidget {
  const CurrencyConverterScreen({super.key});

  @override
  State<CurrencyConverterScreen> createState() =>
      _CurrencyConverterScreenState();
}

class _CurrencyConverterScreenState extends State<CurrencyConverterScreen> {
  final _amountController = TextEditingController(text: '1000');
  String _from = 'PKR';
  String _to = 'USD';

  static const _ratesToUsd = <String, double>{
    'PKR': 1 / 280.0,
    'USD': 1.0,
    'EUR': 1.09,
    'GBP': 1.27,
    'AED': 0.272,
    'SAR': 0.267,
    'TRY': 0.031,
    'MYR': 0.213,
  };

  static const _labels = <String, String>{
    'PKR': 'Pakistani Rupee',
    'USD': 'US Dollar',
    'EUR': 'Euro',
    'GBP': 'British Pound',
    'AED': 'UAE Dirham',
    'SAR': 'Saudi Riyal',
    'TRY': 'Turkish Lira',
    'MYR': 'Malaysian Ringgit',
  };

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  double get _converted {
    final amountUsd = _amount * (_ratesToUsd[_from] ?? 1);
    return amountUsd / (_ratesToUsd[_to] ?? 1);
  }

  void _swap() {
    setState(() {
      final old = _from;
      _from = _to;
      _to = old;
    });
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
            title: 'Currency Converter',
            subtitle: 'Quick travel money estimate',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: isDark ? const [] : AppShadows.primaryGlow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estimated amount',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_converted.toStringAsFixed(2)} $_to',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_amount.toStringAsFixed(2)} $_from',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: isDark ? const [] : AppShadows.softCard,
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _currencyPicker(
                        label: 'From',
                        value: _from,
                        onChanged: (value) => setState(() => _from = value),
                      ),
                      const SizedBox(height: 10),
                      IconButton.filledTonal(
                        onPressed: _swap,
                        icon: const Icon(Icons.swap_vert_rounded),
                        tooltip: 'Swap currencies',
                      ),
                      const SizedBox(height: 10),
                      _currencyPicker(
                        label: 'To',
                        value: _to,
                        onChanged: (value) => setState(() => _to = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Rates are built-in estimates for trip planning. Confirm live exchange rates before payment.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _currencyPicker({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: _ratesToUsd.keys.map((code) {
        return DropdownMenuItem(
          value: code,
          child: Text('$code - ${_labels[code]}'),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
