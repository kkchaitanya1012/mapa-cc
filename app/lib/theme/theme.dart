import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Inter is a variable font; the weight axis is set explicitly so every
/// platform renders the same weight.
TextStyle inter(double size, int weight,
    {Color? color, double? spacing, double? height, bool tabular = true}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
    letterSpacing: spacing == null ? null : size * spacing,
    height: height,
    color: color,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

class T {
  static TextStyle h1(Color c) => inter(34, 800, color: c, spacing: -.03, height: 1.05);
  static TextStyle h2(Color c) => inter(26, 800, color: c, spacing: -.03, height: 1.1);
  static TextStyle title(Color c) => inter(19, 700, color: c, spacing: -.01);
  static TextStyle body(Color c) => inter(16, 500, color: c, height: 1.4);
  static TextStyle row(Color c) => inter(16.5, 700, color: c, spacing: -.005);
  static TextStyle small(Color c) => inter(13.5, 500, color: c);
  static TextStyle label(Color c) => inter(14, 600, color: c);
  static TextStyle time(double size, Color c) =>
      inter(size, 800, color: c, spacing: -.045, height: 1);
}

ThemeData mapaTheme(Brightness b) {
  final c = b == Brightness.dark ? MapaColors.dark : MapaColors.light;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MapaColors.lilac,
      brightness: b,
      surface: c.bg,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: MapaColors.lilac,
      selectionColor: Color(0x66D9CCFF),
    ),
    extensions: [c],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

SystemUiOverlayStyle overlayFor(MapaColors c) => c.isDark
    ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
    : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent);
