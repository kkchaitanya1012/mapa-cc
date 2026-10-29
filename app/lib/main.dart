import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'data/repo.dart';
import 'push/push_service.dart';
import 'router.dart';
import 'screens/landing.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/call_watcher.dart';

/// Draw the launch screen at once and load behind it, instead of showing nothing until loaded.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MapaApp());
}

class MapaApp extends StatefulWidget {
  const MapaApp({super.key});
  @override
  State<MapaApp> createState() => _MapaAppState();
}

class _MapaAppState extends State<MapaApp> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (Config.isSet) _load(); // nothing to load (or wait for) without server settings
  }

  Future<void> _load() async {
    // Long enough to read as a launch screen, short enough not to hold anyone up.
    final minimum = Future<void>.delayed(const Duration(milliseconds: 900));
    try {
      await repo.init();
    } catch (_) {
      repo.ready = true; // render anyway; screens show their own errors
    }
    try {
      await PushService.init();
    } catch (_) {} // push is a bonus: never stop the app starting
    try {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } catch (_) {}
    await minimum;
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (Config.isSet && !_loaded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: mapaTheme(Brightness.light),
        darkTheme: mapaTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const LandingScreen(splash: true),
      );
    }
    if (!Config.isSet) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: mapaTheme(Brightness.light),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Mapa needs its server settings.\n\nRun with --dart-define-from-file=config.local.json '
                '(copy config.example.json and fill it in).',
                style: TextStyle(fontSize: 18, height: 1.4, color: MapaColors.onPastel),
              ),
            ),
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: 'Mapa',
      debugShowCheckedModeBanner: false,
      theme: mapaTheme(Brightness.light),
      darkTheme: mapaTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) => CallWatcher(child: child ?? const SizedBox.shrink()),
    );
  }
}
