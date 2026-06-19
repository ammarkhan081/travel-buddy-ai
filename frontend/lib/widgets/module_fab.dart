import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ModuleFab extends StatelessWidget {
  const ModuleFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.minWidth = 132,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(28),
      elevation: 6,
      shadowColor: AppColors.primary.withValues(alpha: 0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth, minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
