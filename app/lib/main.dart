import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers.dart';
import 'screens/adventure_map_screen.dart';
import 'theme/tama_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const TamaMelodyApp(),
    ),
  );
}

class TamaMelodyApp extends StatelessWidget {
  const TamaMelodyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kTamaMelodyAppName,
      theme: buildTamaTheme(),
      home: const AdventureMapScreen(),
    );
  }
}
