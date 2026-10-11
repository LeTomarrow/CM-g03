import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App color palette — dark military/bomb aesthetic.
class AppColors {
  AppColors._();

  // Core
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFF16213E);
  static const Color card = Color(0xFF1F1F38);

  // Accent
  static const Color danger = Color(0xFFFF1744);
  static const Color amber = Color(0xFFFFB300);
  static const Color success = Color(0xFF00E676);
  static const Color neonBlue = Color(0xFF00E5FF);

  // Text
  static const Color textPrimary = Color(0xFFE0E0E0);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textDim = Color(0xFF616161);

  // Misc
  static const Color metalGrey = Color(0xFF37474F);
  static const Color wire = Color(0xFF455A64);
  static const Color dangerGlow = Color(0x66FF1744);
  static const Color amberGlow = Color(0x66FFB300);
  static const Color successGlow = Color(0x6600E676);
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
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.metalGrey, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.shareTechMono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.amber,
          side: const BorderSide(color: AppColors.amber, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.shareTechMono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.metalGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.metalGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
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
    final mono = GoogleFonts.shareTechMono;
    final display = GoogleFonts.orbitron;

    return TextTheme(
      displayLarge: display(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        color: AppColors.danger,
        letterSpacing: 4,
      ),
      displayMedium: display(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: AppColors.danger,
        letterSpacing: 3,
      ),
      displaySmall: display(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: 2,
      ),
      headlineLarge: mono(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: 2,
      ),
      headlineMedium: mono(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: 1.5,
      ),
      headlineSmall: mono(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
      titleLarge: mono(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 2,
      ),
      titleMedium: mono(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      titleSmall: mono(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      bodyLarge: mono(fontSize: 16, color: AppColors.textPrimary),
      bodyMedium: mono(fontSize: 14, color: AppColors.textSecondary),
      bodySmall: mono(fontSize: 12, color: AppColors.textDim),
      labelLarge: mono(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppColors.amber,
        letterSpacing: 2,
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
    borderRadius: BorderRadius.circular(12),
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
