// ════════════════════════════════════════════════════════════════════════════
// FILE : lib/core/constants/app_colors.dart
// PURPOSE : Single source of truth for ALL colours used in the ISL app.
//
// WHY A CENTRAL COLOUR FILE?
//   • Change the entire app's theme by editing ONE file.
//   • No magic hex strings scattered across 20+ files.
//   • Designers and developers share the same named tokens.
//   • Easy to implement dark-mode later – just swap the colour values.
//
// ORGANISATION:
//   Colours are grouped by PURPOSE, not by value:
//     Primary Brand   – the ISL navy blue palette
//     Background      – page and surface fill colours
//     Text            – hierarchy of text colours
//     Border          – field, card, and divider stroke colours
//     Status          – success (green) and error (red) feedback
//     Misc            – one-off colours used in specific components
//
// IMPORTANT: The constructor is private (AppColors._()) to prevent
//   accidental instantiation. This class is used as a static namespace:
//     AppColors.primary   ✓
//     AppColors()         ✗  (compile error – good!)
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class AppColors {
  // Private constructor – this class must never be instantiated.
  // All colours are accessed as static constants: AppColors.primary
  AppColors._();

  // ── PRIMARY BRAND COLOURS ─────────────────────────────────────────────────
  // The ISL brand uses a deep navy blue as its primary colour.
  // Three tints provide flexibility for different UI needs.

  /// Deep Navy Blue – used for primary buttons, active states, headings.
  /// Hex: #1B3F7A
  static const Color primary      = Color(0xFF1B3F7A);

  /// Darker Navy – used for text that must read as "very dark blue" (not black).
  /// Hex: #0F2447
  static const Color primaryDark  = Color(0xFF0F2447);

  /// Lighter Accent Blue – used for borders, icon tints, secondary accents.
  /// Hex: #2E6FD9
  static const Color primaryLight = Color(0xFF2E6FD9);


  // ── BACKGROUND COLOURS ────────────────────────────────────────────────────

  /// Page header / top background – light blue-grey gradient base.
  /// Used as the top gradient stop on the login page background.
  static const Color bgTop     = Color(0xFFDAE8F7);

  /// Pure white – the bottom sheet / card background.
  static const Color bgBottom  = Color(0xFFFFFFFF);

  /// Light grey surface – fills input fields and role-toggle tracks.
  /// Slightly off-white to distinguish interactive surfaces from card white.
  static const Color bgSurface = Color(0xFFF7F9FC);


  // ── TEXT COLOURS ──────────────────────────────────────────────────────────
  // Four levels of text darkness create a clear visual hierarchy:
  //   textDark > textMedium > textLight > textWhite (reversed on dark bg)

  /// Primary text – headings and important labels. Nearly black navy.
  static const Color textDark   = Color(0xFF0F2447);

  /// Secondary text – sub-labels, body copy, button labels.
  static const Color textMedium = Color(0xFF4A5568);

  /// Tertiary text – placeholder / hint text, disabled labels.
  static const Color textLight  = Color(0xFF9CA3AF);

  /// White text – used on dark (primary blue) backgrounds, e.g. buttons.
  static const Color textWhite  = Color(0xFFFFFFFF);


  // ── BORDER COLOURS ────────────────────────────────────────────────────────

  /// Very subtle border – text field resting state, dividers.
  static const Color borderLight  = Color(0xFFE2E8F0);

  /// Slightly more visible border – social button outlines.
  static const Color borderMedium = Color(0xFFCBD5E0);


  // ── STATUS / FEEDBACK COLOURS ─────────────────────────────────────────────

  /// Green – success messages, check-marks, valid field indicators.
  static const Color success = Color(0xFF10B981);

  /// Red – error messages, invalid field borders.
  static const Color error   = Color(0xFFEF4444);


  // ── MISCELLANEOUS ─────────────────────────────────────────────────────────

  /// Very light sky blue – background of the security-note card.
  static const Color securityBg = Color(0xFFEFF6FF);

  /// Very light grey-blue – the 1px divider line between sections.
  static const Color divider    = Color(0xFFE9EFF8);
}