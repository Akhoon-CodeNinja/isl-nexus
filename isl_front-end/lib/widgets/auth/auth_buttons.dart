// ════════════════════════════════════════════════════════════════════════════
// FILE : lib/widgets/auth/auth_buttons.dart
// PURPOSE : Reusable button widgets for authentication screens.
//
// CONTAINS:
//   1. PrimaryButton        – full-width deep-blue action button
//                            (Sign In, Continue, Submit, etc.)
//   2. OutlinedActionButton – full-width outlined secondary button
//                            (Google, Microsoft, Apple, etc.)
//
// WHY SEPARATE WIDGETS?
//   • Eliminates copy-paste of the same ElevatedButton / OutlinedButton
//     decoration across every screen.
//   • One place to update brand colours, border radius, heights.
//   • PrimaryButton also encapsulates the loading-spinner state, keeping
//     each screen's build() method clean.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:isl_app/core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PrimaryButton  –  the main call-to-action button
//
// PURPOSE : Used for the primary action on every auth screen (e.g. "Sign In",
//           "Create Account", "Reset Password").
//
// IMPORTANT FEATURES:
//   • Always full-width (SizedBox(width: double.infinity))
//   • Fixed height 54px – tall enough for comfortable tapping on mobile
//   • Shows a CircularProgressIndicator when [isLoading] is true
//     (button also becomes un-tappable during loading to prevent double-submit)
//   • Optional trailing [icon] placed to the right of the label text
//   • elevation: 0 + shadowColor: transparent → flat design (no drop-shadow)
//     The button relies on its solid background colour for visual weight.
// ─────────────────────────────────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label, // REQUIRED: button text (e.g. "Sign In")
    this.icon, // optional: trailing icon (e.g. arrow_forward)
    this.onPressed, // optional: tap callback; null disables the button
    this.isLoading = false, // default false; set true to show spinner
  });

  // ── Props ─────────────────────────────────────────────────────────────────

  /// The text displayed on the button (e.g. "Sign In", "Continue").
  final String label;

  /// Optional trailing icon displayed to the right of [label].
  /// Shown only when [isLoading] is false.
  final IconData? icon;

  /// Tap handler. When null the button is automatically disabled
  /// (ElevatedButton.styleFrom disabledBackgroundColor applies).
  final VoidCallback? onPressed;

  /// When true:
  ///   • Replaces the label + icon with a CircularProgressIndicator
  ///   • Passes null to onPressed → button is un-tappable (prevents double-tap)
  ///   • Background uses a semi-transparent version of AppColors.primary
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, // stretch to fill parent width
      height: 54, // comfortable tap height on mobile / web

      child: ElevatedButton(
        // IMPORTANT: null onPressed = disabled state (no tap response)
        // We set it to null during loading to block accidental re-submission.
        onPressed: isLoading ? null : onPressed,

        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary, // ISL deep navy blue
          foregroundColor: AppColors.textWhite, // white text + icon tint
          // Disabled background: 60% opacity of the primary colour
          // Applied automatically when onPressed is null (loading state)
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),

          elevation: 0, // flat design – no raised shadow
          shadowColor: Colors.transparent, // explicitly disable shadow

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), // rounded pill-ish corners
          ),
        ),

        // ── Button content ────────────────────────────────────────────────
        // Switches between loading spinner and label+icon based on [isLoading].
        child: isLoading
            // Loading state: centred spinner (same white colour as text)
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth:
                      2.4, // thin stroke looks more elegant than default 4.0
                ),
              )
            // Normal state: label text + optional trailing icon
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700, // bold for prominence
                      letterSpacing: 0.5, // slight spacing for readability
                    ),
                  ),
                  // Only render the icon and gap if [icon] was provided
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 20),
                  ],
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OutlinedActionButton  –  secondary / social login button
//
// PURPOSE : Used for alternative login methods (Google, Microsoft, etc.)
//           and any secondary action that should not compete visually with
//           the primary PrimaryButton.
//
// DESIGN DIFFERENCES from PrimaryButton:
//   • White / transparent background (not solid blue)
//   • Border instead of fill (OutlinedButton)
//   • Grey text instead of white
//   • 50px height (slightly shorter than primary – lower visual hierarchy)
//   • Accepts a [leadingWidget] (e.g. a brand icon) instead of a trailing icon
//
// IMPORTANT: The [leadingWidget] is expected to be a small icon widget
//   (e.g. _GoogleIcon or _MicrosoftIcon drawn with CustomPainter).
//   If null, only the [label] text is shown.
// ─────────────────────────────────────────────────────────────────────────────
class OutlinedActionButton extends StatelessWidget {
  const OutlinedActionButton({
    super.key,
    required this.label, // REQUIRED: button text
    this.leadingWidget, // optional: brand icon shown BEFORE the label
    this.onPressed, // optional: tap callback
  });

  // ── Props ─────────────────────────────────────────────────────────────────

  /// Button label text (e.g. "Continue with Google").
  final String label;

  /// Widget displayed to the LEFT of [label].
  /// Intended for small brand icons (16–24px).
  final Widget? leadingWidget;

  /// Tap handler. null = button disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, // full-width like PrimaryButton
      height: 50, // slightly shorter than primary (50 vs 54)

      child: OutlinedButton(
        onPressed: onPressed,

        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textDark, // dark text on white background
          // Border: medium grey, 1.4px – visible but not aggressive
          side: const BorderSide(color: AppColors.borderMedium, width: 1.4),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              12,
            ), // consistent with text fields
          ),

          // White background so the button stands out against the card
          backgroundColor: AppColors.bgBottom,
        ),

        // ── Button content ────────────────────────────────────────────────
        // Row: [leadingWidget] [10px gap] [label]
        // Both are centred horizontally inside the button.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Render the brand icon only when provided
              if (leadingWidget != null) ...[
                leadingWidget!,
                const SizedBox(width: 10), // gap between icon and label
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight:
                      FontWeight.w600, // semi-bold to match PrimaryButton feel
                  color: AppColors.textMedium, // grey (secondary importance)
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}