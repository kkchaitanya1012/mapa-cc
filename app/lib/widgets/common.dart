import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

enum KeyKind { primary, secondary, danger, quiet, pastel }

/// A chunky keypad button: a soft base edge and a small press-down.
class KeyButton extends StatefulWidget {
  const KeyButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.kind = KeyKind.primary,
    this.tone,
    this.height = 58,
    this.fontSize = 17,
    this.expand = true,
    this.radius = 20,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final KeyKind kind;
  final Tone? tone;
  final double height, fontSize, radius;
  final bool expand;

  @override
  State<KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<KeyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    late Color bg, fg, base;
    bool shadow = true;
    BoxBorder? border;
    switch (widget.kind) {
      case KeyKind.primary:
        bg = c.ink; fg = c.bg; base = c.edge;
      case KeyKind.secondary:
        bg = c.surface; fg = c.ink; base = c.line;
      case KeyKind.pastel:
        bg = (widget.tone ?? Tone.peach).color; fg = MapaColors.onPastel; base = const Color(0x332D2A3E);
      case KeyKind.quiet:
        bg = c.raised; fg = c.ink2; base = Colors.transparent; shadow = false;
      case KeyKind.danger:
        bg = Colors.transparent; fg = c.bad; base = Colors.transparent; shadow = false;
        border = Border.all(color: c.bad, width: 1.5);
    }
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: widget.expand ? 24 : 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.radius),
            border: border,
            boxShadow: shadow
                ? [
                    BoxShadow(color: base, offset: const Offset(0, 4)),
                    BoxShadow(
                      color: c.shadow,
                      blurRadius: 22,
                      spreadRadius: -8,
                      offset: Offset(0, _down ? 4 : 12),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.fontSize + 5, color: fg),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: inter(widget.fontSize, 700, color: fg, tabular: false)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text button used for secondary links ("Skip", "Not now", "Scan the QR instead").
class QuietLink extends StatelessWidget {
  const QuietLink(this.label, {super.key, this.icon, this.onTap, this.size = 16, this.strong = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double size;
  final bool strong; // use full ink over busy backgrounds

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final col = strong ? c.ink : c.ink2;
    return InkResponse(
      onTap: onTap,
      radius: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: size + 4, color: col), const SizedBox(width: 8)],
          Text(label, style: inter(size, 600, color: col, tabular: false)),
        ]),
      ),
    );
  }
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.initial, {super.key, this.tone = Tone.peach, this.size = 44, this.color});
  final String initial;
  final Tone tone;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color ?? tone.color, shape: BoxShape.circle),
        child: Text(initial,
            style: inter(size * .42, 800, color: MapaColors.onPastel, tabular: false)),
      );
}

class MCard extends StatelessWidget {
  const MCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.radius = 26});
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: c.shadow, blurRadius: 30, spreadRadius: -18, offset: const Offset(0, 14)),
          BoxShadow(color: c.line, offset: const Offset(0, 1)),
        ],
      ),
      child: child,
    );
  }
}

enum Status { taken, next, later, missed }

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.label});
  final Status status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    late Color bg, fg;
    late String text;
    switch (status) {
      case Status.taken: bg = c.okBg; fg = c.ok; text = 'Taken';
      case Status.next: bg = MapaColors.butter; fg = MapaColors.nextText; text = 'Up next';
      case Status.later: bg = c.raised; fg = c.ink2; text = 'Later';
      case Status.missed: bg = c.badBg; fg = c.bad; text = 'Missed';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label ?? text, style: inter(12, 700, color: fg, tabular: false)),
    );
  }
}

class StreakPill extends StatelessWidget {
  const StreakPill(this.text, {super.key, required this.tone});
  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
        decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(LucideIcons.flame, size: 18, color: MapaColors.onPastel),
          const SizedBox(width: 7),
          Text(text, style: inter(14, 700, color: MapaColors.onPastel, tabular: false)),
        ]),
      );
}

/// Frosted glass. Used only where it earns its keep: tab bar, add menu,
/// live call, slide-to-answer.
class Frost extends StatelessWidget {
  const Frost({super.key, required this.child, this.radius = 0, this.blur = 24, this.border = true});
  final Widget child;
  final double radius, blur;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: c.frost,
            borderRadius: BorderRadius.circular(radius),
            border: border ? Border.all(color: c.frostLine) : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class RoundBack extends StatelessWidget {
  const RoundBack({super.key, this.onTap, this.icon = LucideIcons.chevronLeft});
  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, boxShadow: [
            BoxShadow(color: c.line, offset: const Offset(0, 1)),
          ]),
          child: Icon(icon, size: 24, color: c.ink),
        ),
      ),
    );
  }
}

class MapaNav extends StatelessWidget {
  const MapaNav({super.key, required this.title, this.subtitle, this.leading, this.onBack});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(children: [
        RoundBack(onTap: onBack),
        const SizedBox(width: 12),
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: inter(17, 700, color: c.ink, tabular: false)),
            if (subtitle != null)
              Text(subtitle!, style: inter(12.5, 500, color: c.ink2, tabular: false)),
          ]),
        ),
      ]),
    );
  }
}

/// Page frame: themed background, status bar style, safe area.
class MapaScaffold extends StatelessWidget {
  const MapaScaffold({super.key, required this.child, this.background, this.bottom, this.safeBottom = true});
  final Widget child;
  final Decoration? background;
  final Widget? bottom;
  final bool safeBottom;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(c),
      child: Scaffold(
        backgroundColor: c.bg,
        body: DecoratedBox(
          decoration: background ?? BoxDecoration(color: c.bg),
          child: Stack(children: [
            Positioned.fill(child: SafeArea(bottom: safeBottom, child: child)),
            if (bottom != null) Positioned(left: 0, right: 0, bottom: 0, child: bottom!),
          ]),
        ),
      ),
    );
  }
}

/// Soft blurred colour blobs for the landing and call screens.
class Blobs extends StatelessWidget {
  const Blobs(this.blobs, {super.key});
  final List<(Alignment, double, Color, double)> blobs;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(children: [
        for (final b in blobs)
          Align(
            alignment: b.$1,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46, tileMode: TileMode.decal),
              child: Container(
                width: b.$2,
                height: b.$2,
                decoration: BoxDecoration(shape: BoxShape.circle, color: b.$3.withValues(alpha: b.$4)),
              ),
            ),
          ),
      ]),
    );
  }
}
