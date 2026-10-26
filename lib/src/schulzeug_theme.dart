import 'package:flutter/material.dart';

ThemeData schulzeugTheme() {
  const primary = Color(0xFF0066D6);
  const outline = Color(0xFF85858B);
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF5F5F7),
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF1D1D1F),
      onSurfaceVariant: Color(0xFF6E6E73),
      outline: outline,
      outlineVariant: Color(0xFFD9D9DF),
      secondaryContainer: Color(0xFFDCEEFF),
      onSecondaryContainer: Color(0xFF1D1D1F),
      error: Color(0xFFD93025),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, height: 20 / 14),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconTheme: const IconThemeData(size: 22, color: Color(0xFF515154)),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? const BorderSide(color: Color(0xFF007AFF), width: 2)
              : BorderSide.none,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F5F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFF007AFF), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFD9D9DF),
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFFAFAFA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
