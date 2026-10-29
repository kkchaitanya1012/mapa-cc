import 'package:flutter/material.dart';

/// Mapa colour tokens. "The Call Home": pastel push-button landline phones,
/// one phone colour per person, plum ink. Light is a day sky, dark a night ink.
@immutable
class MapaColors extends ThemeExtension<MapaColors> {
  const MapaColors({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.ink2,
    required this.line,
    required this.edge,
    required this.shadow,
    required this.ok,
    required this.okBg,
    required this.bad,
    required this.badBg,
    required this.frost,
    required this.frostLine,
    required this.landTop,
    required this.landMid,
    required this.landBot,
    required this.isDark,
  });

  final Color bg, surface, raised, ink, ink2, line, edge, shadow;
  final Color ok, okBg, bad, badBg;
  final Color frost, frostLine;
  final Color landTop, landMid, landBot;
  final bool isDark;

  // Phones are the same pastel in both modes; text on them is always plum.
  static const peach = Color(0xFFFFC9B0);
  static const mint = Color(0xFFBFE8D6);
  static const butter = Color(0xFFFFE7A3);
  static const lilac = Color(0xFFD9CCFF);
  static const onPastel = Color(0xFF2D2A3E);
  static const onPastel2 = Color(0xFF4A4660);
  static const nextText = Color(0xFF4A3600);
  static const answer = Color(0xFF33C58A);
  static const hangUp = Color(0xFFFF7A66);

  static const light = MapaColors(
    bg: Color(0xFFF7F7FB),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEFEEF6),
    ink: Color(0xFF2D2A3E),
    ink2: Color(0xFF625E7A),
    line: Color(0xFFE6E4EF),
    edge: Color(0x57000000),
    shadow: Color(0x242D2A3E),
    ok: Color(0xFF1B6E45),
    okBg: Color(0xFFDDF3E7),
    bad: Color(0xFFB93E26),
    badBg: Color(0xFFFFE3DA),
    frost: Color(0x85FFFFFF),
    frostLine: Color(0xB3FFFFFF),
    landTop: Color(0xFFFFDCCB),
    landMid: Color(0xFFFFC9B0),
    landBot: Color(0xFFFFE7A3),
    isDark: false,
  );

  static const dark = MapaColors(
    bg: Color(0xFF14121D),
    surface: Color(0xFF1F1C2D),
    raised: Color(0xFF2A2640),
    ink: Color(0xFFF3F1FA),
    ink2: Color(0xFFB0ABC8),
    line: Color(0xFF322E48),
    edge: Color(0x472D2A3E),
    shadow: Color(0x80000000),
    ok: Color(0xFF7FE0B0),
    okBg: Color(0xFF1E3B2E),
    bad: Color(0xFFFFA48E),
    badBg: Color(0xFF43251F),
    frost: Color(0x8C28243E),
    frostLine: Color(0x1FFFFFFF),
    landTop: Color(0xFF2B2036),
    landMid: Color(0xFF1B1626),
    landBot: Color(0xFF14121D),
    isDark: true,
  );

  @override
  MapaColors copyWith() => this;

  @override
  MapaColors lerp(ThemeExtension<MapaColors>? other, double t) =>
      t < .5 ? this : (other as MapaColors? ?? this);
}

extension MapaTheme on BuildContext {
  MapaColors get c => Theme.of(this).extension<MapaColors>()!;
}

/// One phone colour per person, used everywhere as that person's code.
enum Tone {
  peach(MapaColors.peach),
  mint(MapaColors.mint),
  butter(MapaColors.butter),
  lilac(MapaColors.lilac);

  const Tone(this.color);
  final Color color;
}
