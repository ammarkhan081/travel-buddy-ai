import 'package:flutter/material.dart';

/// Central design tokens for Travio.
///
/// Every screen reads colors, gradients and shadows from this file (or via
/// `Theme.of(context)` which is built on top of it) so the visual language
/// stays consistent. If you want to tune the palette, do it here once.
class AppColors {
  AppColors._();

  // ── Travio Brand (New) ────────────────────────────────────────────────────
  static const Color travioBlue = Color(0xFF00A0FF);
  static const Color travioTeal = Color(0xFF00C9A7);
  static const Color travioNavy = Color(0xFF11102A);

  // ── Core brand ────────────────────────────────────────────────────────────
  /// The dashboard's primary purple — used for CTAs, accents and active state.
  static const Color primary = Color(0xFF00A0FF); // Updated to match logo

  /// Slightly deeper blue for gradients.
  static const Color primaryDark = Color(0xFF0077CC);

  /// Lighter cyan for secondary accents.
  static const Color primaryLight = Color(0xFF00E5FF);

  /// Pink/magenta accent (keeping for variety or updating if needed).
  static const Color accentPink = Color(0xFFE36DC4);

  /// Cool blue used for "Upcoming" pills, info cards.
  static const Color infoBlue = Color(0xFF4F7AFF);

  /// Success / completed.
  static const Color success = Color(0xFF34C77B);

  /// Warning / medium-severity alerts.
  static const Color warning = Color(0xFFE89B2C);

  /// Error / overdue / critical alerts.
  static const Color danger = Color(0xFFE94E66);

  // ── Backgrounds ───────────────────────────────────────────────────────────
  /// Light scaffold background.
  static const Color bgLight = Color(0xFFF6F4FB);

  /// Light header gradient — start (pale blue).
  static const Color headerLilac = Color(0xFFE2F5FF);

  /// Header top dark accent.
  static const Color headerNavyTop = Color(0xFF131434);
  static const Color headerNavyMid = Color(0xFF1A3B5C);

  /// Dark scaffold background.
  static const Color bgDark = Color(0xFF0E0B22);

  /// Dark surface (cards, sheets).
  static const Color surfaceDark = Color(0xFF1A1635);

  /// Dark elevated surface (drawer, popovers).
  static const Color surfaceDarkElevated = Color(0xFF231F40);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF11102A);
  static const Color textSecondary = Color(0xFF6B6480);
  static const Color textTertiary = Color(0xFF9A93B0);

  static const Color textPrimaryDark = Color(0xFFF3F1FF);
  static const Color textSecondaryDark = Color(0xFFB6B0D3);
  static const Color textTertiaryDark = Color(0xFF7E7896);

  // ── Border / divider ──────────────────────────────────────────────────────
  static const Color borderLight = Color(0xFFEAE5F7);
  static const Color borderDark = Color(0xFF332E55);
}

/// Reusable gradients.
class AppGradients {
  AppGradients._();

  /// The primary Travio blue → teal gradient used on CTAs and splash.
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.travioBlue,
      AppColors.travioTeal,
    ],
  );

  /// Simpler 2-stop blue gradient for buttons.
  static const LinearGradient blueButton = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.travioBlue, Color(0xFF0077CC)],
  );

  /// Light header — navy fade to blue to near-white.
  static const LinearGradient lightHeader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.12, 0.28, 1.0],
    colors: [
      AppColors.headerNavyTop,
      AppColors.headerNavyMid,
      AppColors.headerLilac,
      AppColors.bgLight,
    ],
  );

  /// Dark header — deep navy with blue tint.
  static const LinearGradient darkHeader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.6, 1.0],
    colors: [
      Color(0xFF0A0820),
      Color(0xFF0D253F),
      AppColors.surfaceDark,
    ],
  );
}

/// Reusable shadows.
class AppShadows {
  AppShadows._();

  /// Soft card shadow used on white cards in light mode.
  static List<BoxShadow> get softCard => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];

  /// Slightly stronger card shadow used on hero or featured cards.
  static List<BoxShadow> get raisedCard => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ];

  /// Glowing blue shadow used under CTAs.
  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.32),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Standardised radii.
class AppRadii {
  AppRadii._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}
