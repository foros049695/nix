import 'package:flutter/material.dart';

class NixTheme {
  static final ThemeData tacticalDarkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F0F10),
    primaryColor: const Color(0xFF1E88E5),
    cardColor: const Color(0xFF18181A),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00E676),
      secondary: Color(0xFF00B0FF),
      surface: Color(0xFF18181A),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF121214),
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
