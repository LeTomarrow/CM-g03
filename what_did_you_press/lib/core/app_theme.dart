import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App color palette: an improvised device in an olive equipment case, with
/// label-maker tape and an LED clock.
class AppColors {
  AppColors._();

  // Core: the painted casing.
  static const Color background = Color(0xFF1B1E18);
  static const Color surface = Color(0xFF252A21);
  static const Color surfaceLight = Color(0xFF2F352A);
  static const Color card = Color(0xFF2A2F25);

  // Accent
  static const Color danger = Color(0xFFE2483D);
  static const Color amber = Color(0xFFE9AE3B);
  static const Color success = Color(0xFF6CC071);
  static const Color neonBlue = Color(0xFF4AA3DF);
  static const Color neonPurple = Color(0xFFB477D9);

  // Text
  static const Color textPrimary = Color(0xFFECE7D9);
  static const Color textSecondary = Color(0xFFA7AB98);
  static const Color textDim = Color(0xFF7A7F6F);

  // Hardware
  static const Color metalGrey = Color(0xFF474E40);
  static const Color wire = Color(0xFF5A6150);
  static const Color tape = Color(0xFFECE7D9);
  static const Color led = Color(0xFFFF4A3D);
  static const Color copper = Color(0xFFD08A4E);
  static const Color dangerGlow = Color(0x66E2483D);
  static const Color amberGlow = Color(0x66E9AE3B);
  static const Color successGlow = Color(0x666CC071);
}

/// The classic bomb wire colours.
class WireColors {
  WireColors._();

  static const Color red = Color(0xFFC8332B);
  static const Color blue = Color(0xFF2F62B0);
  static const Color yellow = Color(0xFFE3B530);
  static const Color white = Color(0xFFE6E2D6);
  static const Color black = Color(0xFF0C0D0B);
}

/// App-wide theme configuration.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.danger,
        secondary: AppColors.amber,
        tertiary: AppColors.success,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      textTheme: _textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.danger,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: AppColors.metalGrey, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: GoogleFonts.barlowCondensed(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.amber,
          side: const BorderSide(color: AppColors.amber, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: GoogleFonts.barlowCondensed(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.metalGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.metalGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.amber, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textDim),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.amber,
        inactiveTrackColor: AppColors.metalGrey,
        thumbColor: AppColors.amber,
        overlayColor: AppColors.amberGlow,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    );
  }

  static TextTheme get _textTheme {
    // Condensed for headings and controls, like stencilled equipment labels;
    // regular Barlow for anything read as sentences.
    final condensed = GoogleFonts.barlowCondensed;
    final body = GoogleFonts.barlow;

    return TextTheme(
      displayLarge: condensed(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        color: AppColors.danger,
        letterSpacing: 0.5,
      ),
      displayMedium: condensed(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: AppColors.danger,
        letterSpacing: 0.5,
      ),
      displaySmall: condensed(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: 0.5,
      ),
      headlineLarge: condensed(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: 0.5,
      ),
      headlineMedium: condensed(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: 1.5,
      ),
      headlineSmall: condensed(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
      titleLarge: condensed(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.5,
      ),
      titleMedium: condensed(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      titleSmall: condensed(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      bodyLarge: body(fontSize: 16, height: 1.45, color: AppColors.textPrimary),
      bodyMedium: body(
        fontSize: 14,
        height: 1.45,
        color: AppColors.textSecondary,
      ),
      bodySmall: body(fontSize: 13, color: AppColors.textDim),
      labelLarge: condensed(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.amber,
        letterSpacing: 1,
      ),
    );
  }
}

/// Shared box decoration for cards with a subtle glow.
BoxDecoration glowingCardDecoration({
  Color glowColor = AppColors.dangerGlow,
  Color borderColor = AppColors.metalGrey,
}) {
  return BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderColor, width: 1),
    boxShadow: [BoxShadow(color: glowColor, blurRadius: 20, spreadRadius: -5)],
  );
}

/// Scan-line overlay for retro CRT look.
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({super.key, this.opacity = 0.03});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanlinePainter(opacity: opacity),
        size: Size.infinite,
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter({required this.opacity});
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: opacity)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
