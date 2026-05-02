import 'package:flutter/material.dart';

/// Central light / dark themes with tuned surfaces, contrast, and component defaults.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF1565C0);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFF5F7FA),
      surfaceContainerLowest: const Color(0xFFF0F3F8),
      surfaceContainerLow: const Color(0xFFF7F8FC),
      surfaceContainer: const Color(0xFFFFFFFF),
      surfaceContainerHigh: const Color(0xFFEEF1F7),
      surfaceContainerHighest: const Color(0xFFE4E9F2),
    );
    return _buildTheme(brightness: Brightness.light, colorScheme: scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF0F1419),
      surfaceContainerLowest: const Color(0xFF0A0D12),
      surfaceContainerLow: const Color(0xFF131920),
      surfaceContainer: const Color(0xFF181F28),
      surfaceContainerHigh: const Color(0xFF212A35),
      surfaceContainerHighest: const Color(0xFF2A3442),
      onSurface: const Color(0xFFE8EDF4),
      onSurfaceVariant: const Color(0xFFB0BBC9),
      outline: const Color(0xFF3D4C5F),
      outlineVariant: const Color(0xFF2A3544),
      // Primary / onPrimary tuned for light icons on saturated blue (AppBar, FAB).
      primary: const Color(0xFF5B9CF5),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFF1E4272),
      onPrimaryContainer: const Color(0xFFD4E4FF),
      secondary: const Color(0xFF9ECAFF),
      onSecondary: const Color(0xFF001634),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      inverseSurface: const Color(0xFFE8EDF4),
      onInverseSurface: const Color(0xFF0F1419),
      shadow: Colors.black,
      scrim: const Color(0xCC000000),
    );
    return _buildTheme(brightness: Brightness.dark, colorScheme: scheme);
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme colorScheme,
  }) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.75 : 1),
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: isDark ? 2 : 1,
        backgroundColor: colorScheme.surfaceContainerLow,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: isDark ? 0 : 1,
        shadowColor: isDark ? Colors.transparent : const Color(0x33000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: EdgeInsets.zero,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: colorScheme.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: isDark ? 3 : 4,
        focusElevation: isDark ? 4 : 6,
        hoverElevation: isDark ? 5 : 8,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        subtitleTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: colorScheme.onSurface),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(
            colorScheme.surfaceContainerHigh,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.55 : 0.75,
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        deleteIconColor: colorScheme.onSurface,
        disabledColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        secondarySelectedColor: colorScheme.secondaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: colorScheme.primary, width: 1.5);
            }
            return BorderSide(color: colorScheme.outline);
          }),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.surfaceContainerHigh,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
    );
  }

  /// Soft page gradient stops for auth / marketing-style screens.
  static List<Color> authBackgroundGradient(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return [
        Color.lerp(cs.surfaceContainerLowest, cs.primary, 0.08)!,
        cs.surface,
        Color.lerp(cs.surface, cs.surfaceContainerLow, 0.5)!,
      ];
    }
    return const [
      Color(0xFFEEF3FB),
      Color(0xFFF7F9FD),
      Color(0xFFFFFFFF),
    ];
  }

  /// Standard “tool” screen scaffold tone (PDF tools, scanner, etc.).
  static Color toolScaffoldBackground(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
}
