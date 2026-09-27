import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_app/theme/tama_theme.dart';

void main() {
  group('TamaColors', () {
    test('matches the Tama-Tama palette verbatim', () {
      // Guarded against drift: these are the --color-tama-* values in
      // tama-tama/app/globals.css. Change them there first, or not at all.
      expect(TamaColors.pink.value, 0xFFFF8EAF);
      expect(TamaColors.purple.value, 0xFFA855F7);
      expect(TamaColors.blue.value, 0xFF7DD3FC);
      expect(TamaColors.white.value, 0xFFFAFAFA);
      expect(TamaColors.ink.value, 0xFF334155);
    });
  });

  group('buildTamaTheme', () {
    final theme = buildTamaTheme();

    test('paints the scaffold with tama blue and the app bar with purple', () {
      expect(theme.scaffoldBackgroundColor, TamaColors.blue);
      expect(theme.appBarTheme.backgroundColor, TamaColors.purple);
      expect(theme.appBarTheme.foregroundColor, TamaColors.white);
    });

    test('stays light, like a kids app should', () {
      expect(theme.brightness, Brightness.light);
    });

    test('drives Material from the palette, not the old violet seed', () {
      expect(theme.colorScheme.primary, TamaColors.purple);
      expect(theme.colorScheme.secondary, TamaColors.pink);
      expect(theme.colorScheme.surface, TamaColors.white);
      expect(theme.colorScheme.onSurface, TamaColors.ink);
    });
  });

  test('app name is the Tama Melody brand', () {
    expect(kTamaMelodyAppName, 'Tama Melody');
  });
}
