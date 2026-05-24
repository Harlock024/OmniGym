import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

// Widgets compartidos entre las pantallas de autenticación.

class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF06080F), Color(0xFF0D1428)],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OmniGymColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OmniGymColors.border),
        boxShadow: [
          BoxShadow(
            color: OmniGymColors.primary.withAlpha(25),
            blurRadius: 80,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      padding: const EdgeInsets.all(36),
      child: child,
    );
  }
}

class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: OmniGymColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: OmniGymColors.primary.withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.fitness_center, color: Colors.white, size: 26),
      ),
    );
  }
}

class AuthDarkField extends StatelessWidget {
  const AuthDarkField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.onSubmitted,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final TextCapitalization textCapitalization;

  static const _borderSide = BorderSide(color: OmniGymColors.border);
  static const _focusBorder = BorderSide(color: OmniGymColors.primary, width: 1.5);

  InputDecoration get _decoration => InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
        prefixIcon:
            Icon(prefixIcon, color: OmniGymColors.textSecondary, size: 18),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: OmniGymColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: _borderSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: _borderSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: _focusBorder,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OmniGymColors.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
              color: OmniGymColors.errorRed, width: 1.5),
        ),
        errorStyle: const TextStyle(
          color: OmniGymColors.errorRed,
          fontSize: 11,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 14),
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: _decoration,
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: OmniGymColors.errorRed.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OmniGymColors.errorRed.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: OmniGymColors.errorRed, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: OmniGymColors.errorRed, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: OmniGymColors.border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'o',
            style:
                TextStyle(color: OmniGymColors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: OmniGymColors.border)),
      ],
    );
  }
}
