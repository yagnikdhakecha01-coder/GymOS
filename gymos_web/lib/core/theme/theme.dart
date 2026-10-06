import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Primary Color System ──
  static const Color primary = Color(0xFF6C3AED);       // Violet-700
  static const Color primaryLight = Color(0xFFEDE9FE);   // Violet-100
  static const Color primaryDark = Color(0xFF5B21B6);    // Violet-800

  // ── Surfaces ──
  static const Color background = Color(0xFFF8F8FA);
  static const Color cardBackground = Colors.white;
  static const Color surfaceGray = Color(0xFFF3F4F6);   // Gray-100

  // ── Text ──
  static const Color textPrimary = Color(0xFF111827);    // Gray-900
  static const Color textSecondary = Color(0xFF6B7280);  // Gray-500
  static const Color textMuted = Color(0xFF9CA3AF);      // Gray-400

  // ── Borders & Dividers ──
  static const Color border = Color(0xFFF0F0F2);
  static const Color divider = Color(0xFFF3F4F6);

  // ── Semantic Colors ──
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  // ── Shadows ──
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get bottomNavShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 1,
      offset: const Offset(0, -1),
    ),
  ];

  // ── Radius Constants ──
  static const double radiusCard = 12.0;
  static const double radiusButton = 12.0;
  static const double radiusInput = 10.0;
  static const double radiusChip = 20.0;
  static const double radiusBadge = 6.0;
  static const double radiusIconContainer = 10.0;
  static const double radiusSheet = 24.0;
  static const double radiusThumbnail = 12.0;

  // ── Spacing Constants ──
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;
  static const double spacingXxl = 24.0;
  static const double pagePadding = 16.0;

  // ── Component Sizes ──
  static const double buttonHeight = 52.0;
  static const double iconContainerSize = 36.0;
  static const double avatarRadiusLg = 40.0;
  static const double avatarRadiusMd = 22.0;
  static const double avatarRadiusSm = 18.0;
  static const double thumbnailSize = 80.0;

  // ── Theme Data ──
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primaryDark,
        surface: cardBackground,
        error: danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      scaffoldBackgroundColor: background,
      dividerColor: divider,

      // ── Typography (Inter) ──
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.bold, color: textPrimary, letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 24, fontWeight: FontWeight.bold, color: textPrimary, letterSpacing: -0.3,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.normal, color: textSecondary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.normal, color: textSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 11, fontWeight: FontWeight.normal, color: textMuted,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w600, color: textMuted,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11, fontWeight: FontWeight.w500, color: textMuted,
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 14),
        floatingLabelStyle: GoogleFonts.inter(color: primary, fontSize: 14, fontWeight: FontWeight.w500),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
      ),

      // ── Elevated Button ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          minimumSize: const Size(double.infinity, buttonHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Outlined Button ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border, width: 1),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          minimumSize: const Size(double.infinity, buttonHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Text Button ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Bottom Navigation ──
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.normal),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary, fontSize: 17, fontWeight: FontWeight.w600,
        ),
      ),

      // ── Tab Bar ──
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.normal),
        dividerColor: border,
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primary,
        disabledColor: surfaceGray,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        secondaryLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusChip)),
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        showCheckmark: false,
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        elevation: 0,
        backgroundColor: Colors.white,
      ),

      // ── Bottom Sheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: false,
      ),

      // ── Popup Menu ──
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
        elevation: 4,
        color: Colors.white,
        textStyle: GoogleFonts.inter(fontSize: 14, color: textPrimary),
      ),
    );
  }
}
