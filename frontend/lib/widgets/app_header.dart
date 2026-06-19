import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Lightweight gradient header used by every module screen.
///
/// Mirrors the look of the dashboard header (navy fade → lilac) but compact —
/// designed to sit at the very top of a screen above the regular content.
/// Status-bar icons are forced to white so the dark band reads cleanly.
///
/// Usage:
/// ```dart
/// Scaffold(
///   body: Column(
///     children: [
///       AppHeader(
///         title: 'Reminders',
///         subtitle: 'Stay on track for every trip',
///         onBack: () => Navigator.pop(context),
///         trailing: IconButton(icon: Icon(Icons.add), onPressed: ...),
///       ),
///       Expanded(child: ...),
///     ],
///   ),
/// );
/// ```
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leading,
    this.trailing,
    this.actions,
  });

  /// Big header title.
  final String title;

  /// Optional one-line subtitle under the title.
  final String? subtitle;

  /// If supplied, shows a back-arrow leading icon that triggers this callback.
  final VoidCallback? onBack;

  /// Custom leading widget (takes precedence over [onBack]).
  final Widget? leading;

  /// Single trailing action (right of title). Use [actions] for multiple.
  final Widget? trailing;

  /// Multiple right-side actions, displayed as a horizontal row.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: isDark ? AppGradients.darkHeader : AppGradients.lightHeader,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadii.xxl),
          bottomRight: Radius.circular(AppRadii.xxl),
        ),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                leading ?? (onBack != null ? _backButton(context) : const _Spacer46()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          height: 1.15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions != null && actions!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final w in actions!) ...[
                        const SizedBox(width: 8),
                        w,
                      ],
                    ],
                  )
                else if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context) {
    return _HeaderIconButton(
      icon: Icons.arrow_back_ios_new_rounded,
      onTap: onBack ?? () => Navigator.maybePop(context),
    );
  }
}

class _Spacer46 extends StatelessWidget {
  const _Spacer46();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 46, height: 46);
}

/// A small white pill icon button matching the dashboard header style.
/// Use this for trailing actions on [AppHeader].
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppHeaderIconButton(icon: icon, onTap: onTap);
  }
}

/// Public version — let callers add their own trailing icons.
class AppHeaderIconButton extends StatelessWidget {
  const AppHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount,
  });
  final IconData icon;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, color: AppColors.textPrimary, size: 20),
            ),
          ),
        ),
        if (badgeCount != null && badgeCount! > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              alignment: Alignment.center,
              child: Text(
                badgeCount! > 9 ? '9+' : '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small section title with optional "See all" trailing button — used at the
/// top of horizontally-scrolling rows on module screens.
class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.onSeeAll,
    this.seeAllLabel = 'See All',
  });
  final String title;
  final IconData? icon;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
        ),
        if (onSeeAll != null)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.xs),
            onTap: onSeeAll,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Text(
                    seeAllLabel,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.primary, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A simple empty-state card used inside modules when there's nothing yet.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onCta,
              icon: const Icon(Icons.add, size: 18),
              label: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
