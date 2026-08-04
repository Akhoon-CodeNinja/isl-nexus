// ════════════════════════════════════════════════════════════════════════════
// FILE : lib/widgets/auth/auth_text_field.dart
// PURPOSE : A reusable, branded text-input widget used across all auth screens
//           (Login, Register, Forgot-Password, etc.).
//
// WHY A CUSTOM WIDGET?
//   Flutter's built-in TextFormField requires boilerplate InputDecoration
//   every time it is used. This widget centralises that decoration so:
//     1. Every field looks identical (consistent brand style).
//     2. Changing the brand style (border radius, colours) only requires
//        editing this ONE file — not every screen.
//     3. The optional [label] above the field is handled automatically.
//
// KEY FEATURES:
//   • Optional text label rendered ABOVE the field (not inside as a floating label)
//   • Prefix icon (e.g. person, lock) shown inside the field on the left
//   • Optional suffix widget (e.g. eye-toggle button) on the right
//   • obscureText support for password fields
//   • Focused, enabled, error and focusedError border states all pre-styled
//   • Pluggable [validator] for Form.validate() integration
//   • Pluggable [onChanged] for real-time updates
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:isl_app/core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthTextField  –  labelled, styled TextFormField
//
// EXTENDS: StatelessWidget – no internal state needed.
//   All mutable values (controller text, obscureText) are controlled by the
//   parent widget and passed in as constructor parameters.
// ─────────────────────────────────────────────────────────────────────────────
/// Shared widget — reusable styled text input used across the auth screens.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,  // REQUIRED: ties the field to a TextEditingController
    this.label,                // optional: text shown above the field
    this.hintText,             // optional: placeholder text inside the field
    this.prefixIcon,           // optional: icon on the left inside the field
    this.suffixWidget,         // optional: widget on the right (e.g. eye button)
    this.obscureText = false,  // default false – set true for password fields
    this.keyboardType = TextInputType.text, // default text keyboard
    this.textInputAction = TextInputAction.next, // default "Next" key on keyboard
    this.validator,            // optional: validation function for Form.validate()
    this.onChanged,            // optional: called on every keystroke
  });

  // ── Required props ────────────────────────────────────────────────────────

  /// TextEditingController – provides read/write access to the field's text.
  /// IMPORTANT: Must be created in the parent State and disposed in dispose().
  final TextEditingController controller;

  // ── Optional props ────────────────────────────────────────────────────────

  /// Text label rendered ABOVE the input box (not a floating Material label).
  /// Shown in medium-weight grey to separate it visually from the input value.
  final String? label;

  /// Placeholder text shown inside the field when it is empty.
  final String? hintText;

  /// Material icon displayed inside the field on the LEFT side.
  /// Helps users identify the field's purpose at a glance (e.g. person, lock).
  final IconData? prefixIcon;

  /// Optional widget placed on the RIGHT side inside the field.
  /// Most commonly used for an eye-toggle IconButton on password fields.
  final Widget? suffixWidget;

  /// When true: replaces typed characters with bullet dots (•••).
  /// Set to true for password fields; driven by parent state so the parent
  /// can toggle it with an eye button.
  final bool obscureText;

  /// Controls which keyboard layout is shown on mobile devices.
  /// Common values: TextInputType.text, .emailAddress, .number, .phone
  final TextInputType keyboardType;

  /// Controls the action button shown at the bottom-right of the mobile keyboard.
  /// Common values: TextInputAction.next (→), .done (✓), .search (🔍)
  final TextInputAction textInputAction;

  /// Validation function integrated with Flutter's Form widget.
  /// Return a String error message if invalid, or null if valid.
  /// Called automatically when the parent Form calls .validate().
  final String? Function(String?)? validator;

  /// Callback fired on every character change.
  /// Use for real-time validation, character counters, or search-as-you-type.
  final void Function(String)? onChanged;

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // label sits at left edge
      children: [

        // ── LABEL (above the field) ────────────────────────────────────────
        // Shown only when [label] is provided. Uses a spread operator (...)
        // to conditionally add widgets to the children list.
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,      // semi-bold label weight
              color: AppColors.textMedium,      // grey – softer than the input text
              letterSpacing: 0.2,
            ),
          ),
          // 8px gap between the label and the input box
          const SizedBox(height: 8),
        ],

        // ── TEXT INPUT FIELD ──────────────────────────────────────────────
        // TextFormField integrates with Form's GlobalKey for batch validation.
        // Plain TextField does not support Form.validate().
        TextFormField(
          controller:      controller,
          obscureText:     obscureText,
          keyboardType:    keyboardType,
          textInputAction: textInputAction,
          validator:       validator,
          onChanged:       onChanged,

          // Text style: dark colour, medium weight (readable)
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textDark,
            fontWeight: FontWeight.w500,
          ),

          decoration: InputDecoration(
            hintText: hintText,
            // Hint style: lighter colour + thinner weight (placeholder feel)
            hintStyle: const TextStyle(
              color: AppColors.textLight,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),

            // Prefix icon: only rendered when [prefixIcon] is provided
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: AppColors.textLight, size: 20)
                : null,

            // Suffix widget: anything – commonly an eye-toggle IconButton
            suffixIcon: suffixWidget,

            // filled + fillColor: gives the field a light grey background
            // that distinguishes it from the white card background
            filled:     true,
            fillColor:  AppColors.bgSurface,

            // Inner padding so text doesn't hug the border edge
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),

            // ── BORDER STATES ─────────────────────────────────────────────
            // Flutter requires separate border objects for each state.
            // All four use the same 12px radius for visual consistency.

            // Default / resting border
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.borderLight,
                width: 1.5,
              ),
            ),

            // Enabled (not focused) border
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.borderLight,
                width: 1.5,
              ),
            ),

            // Focused border: thicker + brand blue to signal active input
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.8, // slightly thicker than enabled border
              ),
            ),

            // Error border: red when validation fails
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 1.5,
              ),
            ),

            // Focused + error: field is focused AND has a validation error
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 1.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}