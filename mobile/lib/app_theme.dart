import 'package:flutter/material.dart';

abstract final class WesbarPalette {
  static const royal = Color(0xFF334EAC);
  static const moon = Color(0xFFF7F2EB);
  static const china = Color(0xFF7096D1);

  static const ink = Color(0xFF202A3B);
  static const mutedInk = Color(0xFF566174);
  static const outline = Color(0xFFD7DDE7);
  static const inputBorder = Color(0xFF8792A6);
  static const chinaBorder = Color(0xFF6688C4);
  static const card = Color(0xFFFFFEFC);
  static const emergency = Color(0xFFB42318);
}

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.pending,
    required this.progress,
    required this.done,
    required this.escalated,
  });

  static const light = StatusColors(
    pending: Color(0xFFB54708),
    progress: Color(0xFF334EAC),
    done: Color(0xFF067647),
    escalated: WesbarPalette.emergency,
  );

  final Color pending;
  final Color progress;
  final Color done;
  final Color escalated;

  @override
  StatusColors copyWith({
    Color? pending,
    Color? progress,
    Color? done,
    Color? escalated,
  }) =>
      StatusColors(
        pending: pending ?? this.pending,
        progress: progress ?? this.progress,
        done: done ?? this.done,
        escalated: escalated ?? this.escalated,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      pending: Color.lerp(pending, other.pending, t)!,
      progress: Color.lerp(progress, other.progress, t)!,
      done: Color.lerp(done, other.done, t)!,
      escalated: Color.lerp(escalated, other.escalated, t)!,
    );
  }
}

abstract final class WesbarTheme {
  static final panicButton = FilledButton.styleFrom(
    backgroundColor: WesbarPalette.emergency,
    foregroundColor: Colors.white,
    minimumSize: const Size(160, 160),
    shape: const CircleBorder(),
  );

  static final light = ThemeData(
    useMaterial3: true,
    extensions: const <ThemeExtension<dynamic>>[StatusColors.light],
    colorScheme: ColorScheme.fromSeed(
      seedColor: WesbarPalette.royal,
      brightness: Brightness.light,
    ).copyWith(
      primary: WesbarPalette.royal,
      onPrimary: Colors.white,
      secondary: WesbarPalette.china,
      onSecondary: const Color(0xFF17264A),
      secondaryContainer: const Color(0xFFE5EDF9),
      onSecondaryContainer: const Color(0xFF1F3458),
      surface: WesbarPalette.moon,
      onSurface: WesbarPalette.ink,
      error: WesbarPalette.emergency,
      onError: Colors.white,
      errorContainer: const Color(0xFFFFE8E5),
      onErrorContainer: const Color(0xFF681D18),
      outline: WesbarPalette.outline,
    ),
    scaffoldBackgroundColor: WesbarPalette.moon,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: Typography.material2021()
        .black
        .apply(bodyColor: WesbarPalette.ink, displayColor: WesbarPalette.ink)
        .copyWith(
          headlineSmall: const TextStyle(
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.45),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: WesbarPalette.moon,
      foregroundColor: WesbarPalette.royal,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: WesbarPalette.royal,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: WesbarPalette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: WesbarPalette.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WesbarPalette.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: WesbarPalette.mutedInk),
      hintStyle: const TextStyle(color: WesbarPalette.mutedInk),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WesbarPalette.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WesbarPalette.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WesbarPalette.royal, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WesbarPalette.emergency),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WesbarPalette.emergency, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WesbarPalette.royal,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WesbarPalette.royal,
        side: const BorderSide(color: WesbarPalette.chinaBorder, width: 1.2),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: WesbarPalette.royal,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: WesbarPalette.royal,
        minimumSize: const Size(48, 48),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: WesbarPalette.card,
      indicatorColor: const Color(0xFFE5EDF9),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: WesbarPalette.royal,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: WesbarPalette.royal,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: WesbarPalette.ink,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
    ),
  );
}
