import 'package:flutter/material.dart';

/// WishHive theme.
///
/// Brand blue from the splash and icon, four soft card tints taken from the
/// blocks in the logo, and nothing else. Figtree carries every piece of text;
/// Instrument Serif italic is reserved for one accent word in a title.
class AppTheme {
  // ─── Brand ────────────────────────────────────────────────────────
  static const Color brandBlue = Color(0xFF1769FF);
  static const Color brandBlueText = Color(0xFF1459D9);

  // ─── Card tints ───────────────────────────────────────────────────
  static const Color tintSky = Color(0xFFC7DBFF);
  static const Color tintLilac = Color(0xFFDCD1FF);
  static const Color tintButter = Color(0xFFFFE9A3);
  static const Color tintBlush = Color(0xFFFFD0E3);
  static const List<Color> cardTints = [tintSky, tintLilac, tintButter, tintBlush];

  // ─── Neutrals ─────────────────────────────────────────────────────
  static const Color background = Color(0xFFF4F5F8);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF111318);
  static const Color muted = Color(0xFF5F6573);
  static const Color divider = Color(0xFFE6E8EE);
  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFE53935);

  // ─── Dark ─────────────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF0E1016);
  static const Color darkSurface = Color(0xFF161922);
  static const Color darkCard = Color(0xFF1C2029);
  static const Color darkDivider = Color(0xFF262B36);
  static const Color darkTextPrimary = Color(0xFFF2F3F7);
  static const Color darkTextSecondary = Color(0xFF9AA1B1);

  static const String fontFamily = 'Figtree';
  static const String serifFamily = 'InstrumentSerif';

  // ─── Shape ────────────────────────────────────────────────────────
  static const double rHive = 26;
  static const double rRow = 22;
  static const double rButton = 18;
  static const double screenMargin = 16;

  /// The colours a hive can be given, stored on the document by key so the
  /// choice survives independently of however the palette is defined here.
  static const Map<String, Color> namedTints = {
    'sky': tintSky,
    'lilac': tintLilac,
    'butter': tintButter,
    'blush': tintBlush,
    'blue': brandBlue,
  };

  /// The colour a hive shows: the one its owner picked, or a tint derived from
  /// its id when they never picked one.
  ///
  /// A pick is stored either as one of the [namedTints] keys or as a plain
  /// "#RRGGBB" string, so a free choice from the wheel survives alongside the
  /// presets without a second field.
  static Color colorFor(String? key, String seed) {
    if (key == null || key.isEmpty) return tintFor(seed);

    final named = namedTints[key];
    if (named != null) return named;

    final hex = parseHex(key);
    return hex ?? tintFor(seed);
  }

  /// Parses "#RRGGBB" or "RRGGBB". Returns null for anything else, so a
  /// malformed value falls back rather than throwing on a card.
  static Color? parseHex(String value) {
    final cleaned = value.startsWith('#') ? value.substring(1) : value;
    if (cleaned.length != 6) return null;
    final rgb = int.tryParse(cleaned, radix: 16);
    if (rgb == null) return null;
    return Color(0xFF000000 | rgb);
  }

  /// The storage form of a colour: a named key when it is one of the presets,
  /// otherwise a hex string.
  static String keyForColor(Color color) {
    for (final entry in namedTints.entries) {
      if (entry.value.toARGB32() == color.toARGB32()) return entry.key;
    }
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  /// Text and icons that sit on a card colour. Blue needs white; every tint
  /// takes ink.
  static Color onColor(Color background) =>
      background.computeLuminance() > 0.5 ? ink : Colors.white;

  /// The tint a hive shows, derived from its id so a given hive always looks
  /// the same on every device without storing a colour on the document.
  static Color tintFor(String seed) {
    if (seed.isEmpty) return tintSky;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return cardTints[hash % cardTints.length];
  }

  /// Amounts line up column-wise, and stay ink rather than taking an accent.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle money({double size = 17, Color color = ink}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
        color: color,
      );

  /// The one accent face, for a single word inside a title.
  static TextStyle serif({required double size, Color color = ink}) => TextStyle(
        fontFamily: serifFamily,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: size,
        height: 1.05,
        color: color,
      );

  static TextTheme _text(Color primary, Color secondary) => TextTheme(
        displayLarge: TextStyle(fontFamily: fontFamily, fontSize: 48, fontWeight: FontWeight.w300, height: 1.05, letterSpacing: -1.8, color: primary),
        headlineLarge: TextStyle(fontFamily: fontFamily, fontSize: 34, fontWeight: FontWeight.w300, height: 1.1, letterSpacing: -1.2, color: primary),
        headlineMedium: TextStyle(fontFamily: fontFamily, fontSize: 24, fontWeight: FontWeight.w400, height: 1.15, letterSpacing: -0.6, color: primary),
        titleLarge: TextStyle(fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w500, color: primary),
        titleMedium: TextStyle(fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w500, color: primary),
        titleSmall: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w500, color: primary),
        bodyLarge: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w400, color: primary),
        bodyMedium: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w400, color: secondary),
        bodySmall: TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w400, color: secondary),
        labelLarge: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600, color: primary),
        labelMedium: TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: secondary),
        labelSmall: TextStyle(fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w400, color: secondary),
      );

  // ─── Light ────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final text = _text(ink, muted);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      primaryColor: brandBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandBlue,
        brightness: Brightness.light,
        primary: brandBlue,
        secondary: brandBlueText,
        surface: surfaceWhite,
        error: error,
      ).copyWith(onSurface: ink),
      scaffoldBackgroundColor: background,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: text.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: divider, width: 1.2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: divider, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: brandBlue, width: 1.8)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: error, width: 1.2)),
        labelStyle: text.bodyMedium,
        hintStyle: text.bodyMedium,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rButton)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandBlueText,
          textStyle: text.labelLarge,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rHive)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: screenMargin),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceWhite,
        selectedColor: ink,
        side: const BorderSide(color: divider),
        labelStyle: text.labelMedium,
        shape: const StadiumBorder(),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        elevation: 3,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // ─── Dark ─────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final text = _text(darkTextPrimary, darkTextSecondary);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      primaryColor: brandBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandBlue,
        brightness: Brightness.dark,
        primary: brandBlue,
        secondary: tintSky,
        surface: darkSurface,
        error: error,
      ).copyWith(
        surface: darkSurface,
        onSurface: darkTextPrimary,
        surfaceContainerHighest: darkCard,
        primaryContainer: const Color(0xFF10306E),
        onPrimaryContainer: tintSky,
      ),
      scaffoldBackgroundColor: darkBackground,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: darkDivider, width: 1.2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: darkDivider, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: brandBlue, width: 1.8)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(rRow), borderSide: const BorderSide(color: error, width: 1.2)),
        labelStyle: text.bodyMedium,
        hintStyle: text.bodyMedium,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rButton)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tintSky,
          textStyle: text.labelLarge,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rHive),
          side: const BorderSide(color: darkDivider, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: screenMargin),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: brandBlue,
        side: const BorderSide(color: darkDivider),
        labelStyle: text.labelMedium,
        shape: const StadiumBorder(),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        elevation: 3,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dividerTheme: const DividerThemeData(color: darkDivider, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkCard,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, color: darkTextPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      listTileTheme: const ListTileThemeData(iconColor: darkTextSecondary),
      dialogTheme: const DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? brandBlue : darkTextSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? brandBlue.withValues(alpha: 0.4) : darkDivider),
      ),
    );
  }
}
