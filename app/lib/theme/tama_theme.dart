import 'package:flutter/material.dart';

/// Tama palette — the brand colors shared with the Tama-Tama app.
///
/// Values are copied verbatim from `tama-tama/app/globals.css`, so both apps in
/// the family render the exact same pink/purple/blue. The semantic mapping is
/// the one Tama-Tama uses on the web: `blue` is the page background, `purple`
/// is the primary accent, `pink` is the secondary, `white` is card fill, and
/// `ink` is text.
class TamaColors {
  const TamaColors._();

  static const Color pink = Color(0xFFFF8EAF);
  static const Color purple = Color(0xFFA855F7);
  static const Color blue = Color(0xFF7DD3FC);
  static const Color white = Color(0xFFFAFAFA);
  static const Color ink = Color(0xFF334155);

  /// Non-brand accents, also lifted from Tama-Tama: `rose` for cheeks/alerts,
  /// `amber` and `orange` for lesson tinting, `emerald` for a "correct" state.
  static const Color rose = Color(0xFFF43F5E);
  static const Color amber = Color(0xFFFBBF24);
  static const Color orange = Color(0xFFFB923C);
  static const Color emerald = Color(0xFF34D399);
  static const Color lavender = Color(0xFFC4B5FD);
}

/// Product name shown to the child (app bar, dialogs, permission copy).
const String kTamaMelodyAppName = 'Tama Melody';

/// The app-wide Tama theme.
///
/// [tamaColorScheme] is exposed separately so a widget test — or a future
/// platform-specific variant — can assert against the palette without pumping a
/// whole [MaterialApp].
ThemeData buildTamaTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: tamaColorScheme(),
    // A kids' app stays in light mode, matching Tama-Tama's
    // `color-scheme: only light`.
    brightness: Brightness.light,
    scaffoldBackgroundColor: TamaColors.blue,
    appBarTheme: const AppBarTheme(
      backgroundColor: TamaColors.purple,
      foregroundColor: TamaColors.white,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: TamaColors.purple,
      contentTextStyle: TextStyle(color: TamaColors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

ColorScheme tamaColorScheme() {
  return ColorScheme.fromSeed(
    // Purple, not the old `0xFF7C4DFF` violet: the seed drives every derived
    // surface, so seeding on the brand purple keeps tonal variants on-palette.
    seedColor: TamaColors.purple,
    primary: TamaColors.purple,
    secondary: TamaColors.pink,
    tertiary: TamaColors.blue,
    surface: TamaColors.white,
    onSurface: TamaColors.ink,
    onSurfaceVariant: TamaColors.ink,
    error: TamaColors.rose,
  );
}
