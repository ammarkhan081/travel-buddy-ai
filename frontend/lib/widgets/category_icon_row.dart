import 'package:flutter/material.dart';

class CategoryIconRow extends StatelessWidget {
  final List<CategoryItem> categories;
  final void Function(int)? onTap;

  const CategoryIconRow({
    super.key,
    required this.categories,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(categories.length, (index) {
          final item = categories[index];
          return GestureDetector(
            onTap: () => onTap?.call(index),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: item.bgColor ?? Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Icon(item.icon, color: item.iconColor ?? Colors.blueAccent, size: 28),
                ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class CategoryItem {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final Color? bgColor;

  CategoryItem({
    required this.label,
    required this.icon,
    this.iconColor,
    this.bgColor,
  });
}

