import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminTheme {
  // ── Primary Color System (Matching Gym OS) ──
  static const Color primary = Color(0xFF6C3AED);       // Violet-700
  static const Color primaryLight = Color(0xFFEDE9FE);   // Violet-100
  static const Color primaryDark = Color(0xFF5B21B6);    // Violet-800
  static const Color primarySurface = Color(0xFFF5F3FF); // Violet-50

  // ── Light Mode Surfaces ──
  static const Color lightBackground = Color(0xFFF8F8FA);
  static const Color lightCard = Colors.white;
  static const Color lightSurface = Color(0xFFF3F4F6);
  static const Color lightSidebar = Colors.white;

  // ── Dark Mode Surfaces ──
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkSurface = Color(0xFF334155);
  static const Color darkSidebar = Color(0xFF1E293B);

  // ── Text Colors ──
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  // ── Borders ──
  static const Color lightBorder = Color(0xFFF0F0F2);
  static const Color darkBorder = Color(0xFF334155);

  // ── Semantic Colors ──
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color orange = Color(0xFFF97316);
  static const Color orangeLight = Color(0xFFFFF7ED);
  static const Color teal = Color(0xFF14B8A6);
  static const Color tealLight = Color(0xFFCCFBF1);
  static const Color pink = Color(0xFFEC4899);
  static const Color pinkLight = Color(0xFFFCE7F3);
  static const Color indigo = Color(0xFF6366F1);
  static const Color indigoLight = Color(0xFFE0E7FF);

  // ── Radius ──
  static const double radiusXs = 6.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 10.0;
  static const double radiusCard = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusSheet = 24.0;

  // ── Spacing ──
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;
  static const double spacingXxl = 24.0;
  static const double spacing3xl = 32.0;
  static const double spacing4xl = 40.0;

  // ── Sidebar ──
  static const double sidebarExpanded = 260.0;
  static const double sidebarCollapsed = 72.0;

  // ── Shadows ──
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get sidebarShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 20,
      offset: const Offset(2, 0),
    ),
  ];

  // ── Gradient ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C3AED), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Animation Durations ──
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);
  static const Duration animPage = Duration(milliseconds: 300);

  // ── Curves ──
  static const Curve animCurve = Curves.easeInOutCubic;

  // ══════════════════════════════════════
  //  LIGHT THEME
  // ══════════════════════════════════════
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primaryDark,
        surface: lightCard,
        error: danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      scaffoldBackgroundColor: lightBackground,
      dividerColor: lightBorder,
      textTheme: _buildTextTheme(Brightness.light),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: _buildInputTheme(Brightness.light),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(Brightness.light),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightCard,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary, fontSize: 17, fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        elevation: 0,
        backgroundColor: lightCard,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        elevation: 4,
        color: lightCard,
        textStyle: GoogleFonts.inter(fontSize: 14, color: textPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(radiusXs),
        ),
        textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // ══════════════════════════════════════
  //  DARK THEME
  // ══════════════════════════════════════
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: Color(0xFF8B5CF6),
        surface: darkCard,
        error: danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
      ),
      scaffoldBackgroundColor: darkBackground,
      dividerColor: darkBorder,
      textTheme: _buildTextTheme(Brightness.dark),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: _buildInputTheme(Brightness.dark),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(Brightness.dark),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkCard,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: darkTextPrimary, size: 22),
        titleTextStyle: GoogleFonts.inter(
          color: darkTextPrimary, fontSize: 17, fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        elevation: 0,
        backgroundColor: darkCard,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        elevation: 4,
        color: darkCard,
        textStyle: GoogleFonts.inter(fontSize: 14, color: darkTextPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF475569),
          borderRadius: BorderRadius.circular(radiusXs),
        ),
        textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // ── Typography Builder ──
  static TextTheme _buildTextTheme(Brightness brightness) {
    final primary = brightness == Brightness.light ? textPrimary : darkTextPrimary;
    final secondary = brightness == Brightness.light ? textSecondary : darkTextSecondary;
    final muted = brightness == Brightness.light ? textMuted : darkTextMuted;

    return GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: primary, letterSpacing: -0.5),
      displayMedium: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: primary, letterSpacing: -0.3),
      displaySmall: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: primary),
      headlineLarge: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: primary),
      headlineMedium: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: primary),
      headlineSmall: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
      titleLarge: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: primary),
      titleMedium: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: primary),
      titleSmall: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.normal, color: secondary),
      bodyMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.normal, color: secondary),
      bodySmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.normal, color: muted),
      labelLarge: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
      labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
    );
  }

  // ── Input Decoration Builder ──
  static InputDecorationTheme _buildInputTheme(Brightness brightness) {
    final border = brightness == Brightness.light ? lightBorder : darkBorder;
    final hint = brightness == Brightness.light ? textMuted : darkTextMuted;
    final label = brightness == Brightness.light ? textSecondary : darkTextSecondary;

    return InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: danger, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: danger, width: 1.5),
      ),
      hintStyle: GoogleFonts.inter(color: hint, fontSize: 14),
      labelStyle: GoogleFonts.inter(color: label, fontSize: 14),
      floatingLabelStyle: GoogleFonts.inter(color: primary, fontSize: 14, fontWeight: FontWeight.w500),
      prefixIconColor: hint,
      suffixIconColor: hint,
    );
  }

  // ── Button Themes ──
  static ElevatedButtonThemeData _buildElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        minimumSize: const Size(120, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme(Brightness brightness) {
    final border = brightness == Brightness.light ? lightBorder : darkBorder;
    final fg = brightness == Brightness.light ? textPrimary : darkTextPrimary;

    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: border, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        minimumSize: const Size(120, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ══════════════════════════════════════
  //  HELPER METHODS
  // ══════════════════════════════════════

  /// Get adaptive color based on current theme brightness
  static Color cardColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkCard : lightCard;

  static Color backgroundColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkBackground : lightBackground;

  static Color borderColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkBorder : lightBorder;

  static Color surfaceColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkSurface : lightSurface;

  static Color sidebarColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkSidebar : lightSidebar;

  static Color textColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTextPrimary : textPrimary;

  static Color secondaryTextColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTextSecondary : textSecondary;

  static Color mutedTextColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTextMuted : textMuted;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}
