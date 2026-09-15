import 'package:flutter/material.dart';

const Color kPrimary = Color.fromARGB(255, 14, 111, 103);
const Color kTertiary = Color.fromARGB(255, 122, 69, 69);
const Color kBackground = Color(0xFFF5F5F5);
const Color kSurface = Color(0xFFFFFFFF);

ThemeData liquidGlassTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: kPrimary,
    scaffoldBackgroundColor: kBackground,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
  );
}
