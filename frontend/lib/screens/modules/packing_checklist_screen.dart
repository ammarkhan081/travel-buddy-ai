import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class PackingChecklistScreen extends StatefulWidget {
  const PackingChecklistScreen({super.key});

  @override
  State<PackingChecklistScreen> createState() => _PackingChecklistScreenState();
}

class _PackingChecklistScreenState extends State<PackingChecklistScreen> {
  static const _prefKey = 'travel.packingChecklist';
  final _controller = TextEditingController();

  Map<String, List<_PackingItem>> _itemsByCategory = {};
  String? _selectedCategory;
  String _filter = 'All';

  static const _categories = [
    _PackingCategory(
      name: 'Mountain',
      subtitle: 'Hikes, valleys and high-altitude routes',
      icon: Icons.terrain_rounded,
      color: Color(0xFF34A853),
      starterItems: [
        'Warm layers',
        'Hiking shoes',
        'Water bottle',
        'Sunscreen',
        'First aid kit',
        'Power bank',
        'Trail snacks',
      ],
    ),
    _PackingCategory(
      name: 'Beach',
      subtitle: 'Sea breeze, sunscreen and relaxed days',
      icon: Icons.beach_access_rounded,
      color: Color(0xFF20B2C9),
      starterItems: [
        'Swimwear',
        'Beach towel',
        'Sunscreen',
        'Sunglasses',
        'Flip flops',
        'Waterproof pouch',
        'Extra clothes',
      ],
    ),
    _PackingCategory(
      name: 'Snowfall',
      subtitle: 'Cold weather trips and snowy stays',
      icon: Icons.ac_unit_rounded,
      color: Color(0xFF4F7AFF),
      starterItems: [
        'Thermal wear',
        'Winter jacket',
        'Gloves',
        'Wool socks',
        'Boots',
        'Moisturizer',
        'Medicines',
      ],
    ),
    _PackingCategory(
      name: 'City',
      subtitle: 'Hotels, markets and daily essentials',
      icon: Icons.location_city_rounded,
      color: Color(0xFF8E5DFF),
      starterItems: [
        'CNIC / Passport',
        'Phone charger',
        'Cash and cards',
        'Comfortable shoes',
        'Toiletries',
        'Medicines',
        'Travel documents',
      ],
    ),
    _PackingCategory(
      name: 'Camping',
      subtitle: 'Outdoor nights and simple camp comfort',
      icon: Icons.cabin_rounded,
      color: Color(0xFFE89B2C),
      starterItems: [
        'Tent',
        'Sleeping bag',
        'Torch',
        'Matchbox / lighter',
        'Insect repellent',
        'Reusable bottle',
        'First aid kit',
      ],
    ),
    _PackingCategory(
      name: 'Road Trip',
      subtitle: 'Long drives with everything in reach',
      icon: Icons.directions_car_filled_rounded,
      color: Color(0xFFE94E66),
      starterItems: [
        'Driving license',
        'Car documents',
        'Phone mount',
        'Charging cable',
        'Snacks',
        'Water bottles',
        'Emergency cash',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    final loaded = raw == null ? _starterItemsByCategory() : _decodeItems(raw);
    if (mounted) setState(() => _itemsByCategory = loaded);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(
        _itemsByCategory.map(
          (category, items) =>
              MapEntry(category, items.map((e) => e.toJson()).toList()),
        ),
      ),
    );
  }

  void _addItem() {
    final category = _selectedCategory;
    if (category == null) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _itemsByCategory
          .putIfAbsent(category, () => [])
          .insert(0, _PackingItem(title: text));
      _controller.clear();
    });
    _save();
  }

  void _toggle(int index, bool? value) {
    final category = _selectedCategory;
    if (category == null) return;
    final items = _itemsByCategory[category];
    if (items == null || index >= items.length) return;
    setState(
      () => _itemsByCategory[category]![index] =
          _itemsByCategory[category]![index].copyWith(done: value ?? false),
    );
    _save();
  }

  void _delete(int index) {
    final category = _selectedCategory;
    if (category == null) return;
    final items = _itemsByCategory[category];
    if (items == null || index >= items.length) return;
    setState(() => _itemsByCategory[category]!.removeAt(index));
    _save();
  }

  Map<String, List<_PackingItem>> _starterItemsByCategory() {
    return {
      for (final category in _categories)
        category.name: category.starterItems
            .map((title) => _PackingItem(title: title))
            .toList(),
    };
  }

  Map<String, List<_PackingItem>> _decodeItems(String raw) {
    final decoded = jsonDecode(raw);
    final starter = _starterItemsByCategory();

    if (decoded is List) {
      starter['City'] = decoded
          .map((e) => _PackingItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return starter;
    }

    if (decoded is Map<String, dynamic>) {
      return {
        for (final category in _categories)
          category.name:
              (decoded[category.name] as List?)
                  ?.map((e) => _PackingItem.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              starter[category.name]!,
      };
    }

    return starter;
  }

  void _openCategory(String category) {
    setState(() {
      _itemsByCategory.putIfAbsent(category, () => []);
      _selectedCategory = category;
      _filter = 'All';
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedItems = _selectedCategory == null
        ? const <_PackingItem>[]
        : _itemsByCategory[_selectedCategory] ?? const <_PackingItem>[];
    final done = selectedItems.where((item) => item.done).length;
    final visible = <MapEntry<int, _PackingItem>>[];
    for (var i = 0; i < selectedItems.length; i++) {
      final item = selectedItems[i];
      if (_filter == 'Packed' && !item.done) continue;
      if (_filter == 'Pending' && item.done) continue;
      visible.add(MapEntry(i, item));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: _selectedCategory ?? 'Packing Checklist',
            subtitle: _selectedCategory == null
                ? 'Choose your trip style'
                : 'Do not forget trip essentials',
            onBack: _selectedCategory == null
                ? () => Navigator.maybePop(context)
                : () => setState(() => _selectedCategory = null),
          ),
          Expanded(
            child: _selectedCategory == null
                ? _CategoryView(
                    categories: _categories,
                    itemsByCategory: _itemsByCategory,
                    isDark: isDark,
                    onSelect: _openCategory,
                  )
                : _ChecklistView(
                    controller: _controller,
                    done: done,
                    total: selectedItems.length,
                    visible: visible,
                    isDark: isDark,
                    filter: _filter,
                    onFilterChanged: (filter) =>
                        setState(() => _filter = filter),
                    onAddItem: _addItem,
                    onToggle: _toggle,
                    onDelete: _delete,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryView extends StatelessWidget {
  const _CategoryView({
    required this.categories,
    required this.itemsByCategory,
    required this.isDark,
    required this.onSelect,
  });

  final List<_PackingCategory> categories;
  final Map<String, List<_PackingItem>> itemsByCategory;
  final bool isDark;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppGradients.primary,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: isDark ? const [] : AppShadows.primaryGlow,
          ),
          child: const Row(
            children: [
              Icon(Icons.luggage_rounded, color: Colors.white, size: 34),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick a packing category',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Choose the trip type first, then check your items.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final category in categories)
          _CategoryTile(
            category: category,
            items: itemsByCategory[category.name] ?? const [],
            isDark: isDark,
            onTap: () => onSelect(category.name),
          ),
      ],
    );
  }
}

class _ChecklistView extends StatelessWidget {
  const _ChecklistView({
    required this.controller,
    required this.done,
    required this.total,
    required this.visible,
    required this.isDark,
    required this.filter,
    required this.onFilterChanged,
    required this.onAddItem,
    required this.onToggle,
    required this.onDelete,
  });

  final TextEditingController controller;
  final int done;
  final int total;
  final List<MapEntry<int, _PackingItem>> visible;
  final bool isDark;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onAddItem;
  final ValueChanged<int> onDelete;
  final void Function(int index, bool? value) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppGradients.primary,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: isDark ? const [] : AppShadows.primaryGlow,
          ),
          child: Row(
            children: [
              const Icon(Icons.luggage_rounded, color: Colors.white, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$done of $total packed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ready bags make calm departures.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: isDark ? const [] : AppShadows.softCard,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAddItem(),
                  decoration: const InputDecoration(
                    hintText: 'Add item',
                    prefixIcon: Icon(Icons.add_task_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: onAddItem,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: ['All', 'Pending', 'Packed'].map((value) {
            return ChoiceChip(
              label: Text(value),
              selected: filter == value,
              onSelected: (_) => onFilterChanged(value),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const AppEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Nothing here',
            subtitle: 'Switch filters or add a new packing item.',
          )
        else
          for (final entry in visible)
            _PackingTile(
              item: entry.value,
              isDark: isDark,
              onChanged: (value) => onToggle(entry.key, value),
              onDelete: () => onDelete(entry.key),
            ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.items,
    required this.isDark,
    required this.onTap,
  });

  final _PackingCategory category;
  final List<_PackingItem> items;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = items.where((item) => item.done).length;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(category.icon, color: category.color, size: 27),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      category.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$done/${items.length}',
                    style: TextStyle(
                      color: category.color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackingTile extends StatelessWidget {
  const _PackingTile({
    required this.item,
    required this.isDark,
    required this.onChanged,
    required this.onDelete,
  });

  final _PackingItem item;
  final bool isDark;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isPacked = item.done;
    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return GestureDetector(
      onTap: () => onChanged(!isPacked),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isPacked
              ? (isDark
                  ? AppColors.success.withValues(alpha: 0.08)
                  : AppColors.success.withValues(alpha: 0.06))
              : (isDark ? AppColors.surfaceDarkElevated : Colors.white),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: isPacked
                ? AppColors.success.withValues(alpha: 0.40)
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: isPacked ? 1.4 : 1.0,
          ),
          boxShadow: isDark ? const [] : AppShadows.softCard,
        ),
        child: Row(
          children: [
            // Custom circular checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPacked
                    ? AppColors.success
                    : Colors.transparent,
                border: Border.all(
                  color: isPacked
                      ? AppColors.success
                      : (isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary),
                  width: 2,
                ),
              ),
              child: isPacked
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Item title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isPacked ? secondaryText : primaryText,
                      decoration: isPacked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: secondaryText,
                    ),
                  ),
                  if (isPacked)
                    const SizedBox(height: 2),
                  if (isPacked)
                    Text(
                      'Packed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success.withValues(alpha: 0.80),
                      ),
                    ),
                ],
              ),
            ),

            // Delete button — subtle, only visible as an icon
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary,
              ),
              tooltip: 'Remove item',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _PackingItem {
  const _PackingItem({required this.title, this.done = false});

  final String title;
  final bool done;

  _PackingItem copyWith({bool? done}) {
    return _PackingItem(title: title, done: done ?? this.done);
  }

  Map<String, dynamic> toJson() => {'title': title, 'done': done};

  factory _PackingItem.fromJson(Map<String, dynamic> json) {
    return _PackingItem(
      title: json['title']?.toString() ?? '',
      done: json['done'] == true,
    );
  }
}

class _PackingCategory {
  const _PackingCategory({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.starterItems,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> starterItems;
}
