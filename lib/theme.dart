import 'package:flutter/material.dart';

abstract final class ThreadTheme {
  static const ink = Color(0xFF243D30);
  static const green = Color(0xFF36533E);
  static const canvas = Color(0xFFF8F8F3);
  static const line = Color(0xFFE4E7DD);
  static const muted = Color(0xFF657060);
  static const lime = Color(0xFFDDE9B3);
  static const softGreen = Color(0xFFEEF1E7);

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: 'ThreadSans',
    scaffoldBackgroundColor: canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      primary: green,
      secondary: const Color(0xFFB6C78D),
      surface: canvas,
      onSurface: ink,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 56,
        height: 1.04,
        letterSpacing: -2.5,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      displayMedium: TextStyle(
        fontSize: 40,
        height: 1.1,
        letterSpacing: -1.7,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        letterSpacing: -1,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        letterSpacing: -.6,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.6, color: ink),
      bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: 'ThreadSans',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(48, 46),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
    ),
    dividerColor: line,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = ThreadTheme.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      letterSpacing: 1.7,
      fontWeight: FontWeight.w700,
      color: color,
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: ThreadTheme.line),
    ),
    child: child,
  );
}
