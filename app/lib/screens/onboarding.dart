import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _i = 0;

  static const _titles = ['Tell Mapa once.', 'Mapa makes the call.', 'You stay in the loop.'];
  static const _bodies = [
    "Type it the way you'd say it. Mapa turns it into a daily call.",
    'A friendly voice asks if the medicine was taken and how they feel, in English or Telugu.',
    "See what they said, keep the streak going, and get a nudge if anything's off.",
  ];

  Future<void> _finish() async {
    await repo.markOnboardingSeen();
    if (mounted) context.go('/role');
  }

  void _next() {
    if (_i == 2) {
      _finish();
    } else {
      _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MapaScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Align(alignment: Alignment.centerRight, child: QuietLink('Skip', onTap: _finish)),
          Expanded(
            flex: 6,
            child: PageView(
              controller: _pc,
              onPageChanged: (v) => setState(() => _i = v),
              children: const [_ArtChat(), _ArtRing(), _ArtLog()],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Column(
              key: ValueKey(_i),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titles[_i], style: inter(34, 800, color: c.ink, spacing: -.035, height: 1.05, tabular: false)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 330),
                  child: Text(_bodies[_i], style: inter(17.5, 500, color: c.ink2, height: 1.45, tabular: false)),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(children: [
            Row(children: [
              for (var d = 0; d < 3; d++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.only(right: 8),
                  width: d == _i ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: d == _i ? c.ink : c.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ]),
            const Spacer(),
            SizedBox(
              width: _i == 2 ? 172 : 150,
              child: KeyButton(label: _i == 2 ? "Let's go" : 'Next', onTap: _next),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ArtChat extends StatelessWidget {
  const _ArtChat();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: MCard(
        padding: const EdgeInsets.all(18),
        radius: 24,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: c.ink,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6)),
            ),
            child: Text('Amma, BP tablet, 8:30 every morning for a month',
                style: inter(17, 500, color: c.bg, height: 1.35, tabular: false)),
          ),
          const SizedBox(height: 14),
          const Row(children: [_Chip('8:00'), SizedBox(width: 8), _Chip('8:30', on: true), SizedBox(width: 8), _Chip('9:00')]),
          const SizedBox(height: 18),
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: MapaColors.peach, shape: BoxShape.circle),
              child: const Icon(LucideIcons.check, size: 20, color: MapaColors.onPastel),
            ),
            const SizedBox(width: 10),
            Text('Daily at 8:30 am for 30 days', style: inter(15, 700, color: c.ink, tabular: false)),
          ]),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.t, {this.on = false});
  final String t;
  final bool on;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: on ? MapaColors.butter : c.surface,
        borderRadius: BorderRadius.circular(99),
        border: on ? null : Border.all(color: c.line, width: 1.5),
      ),
      child: Text(t, style: inter(15, 700, color: on ? MapaColors.nextText : c.ink)),
    );
  }
}

class _ArtRing extends StatefulWidget {
  const _ArtRing();
  @override
  State<_ArtRing> createState() => _ArtRingState();
}

class _ArtRingState extends State<_ArtRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: RingingBuddy(controller: _c, color: Tone.peach.color, size: 190));
  }
}

/// Mascot with two soft pulse rings behind it.
class RingingBuddy extends StatelessWidget {
  const RingingBuddy({super.key, required this.controller, required this.color, this.size = 180, this.wobble = true});
  final AnimationController controller;
  final Color color;
  final double size;
  final bool wobble;

  @override
  Widget build(BuildContext context) {
    final box = size * 1.4;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(alignment: Alignment.center, children: [
        for (final off in const [0.0, .5])
          AnimatedBuilder(
            animation: controller,
            builder: (_, _) {
              final t = (controller.value + off) % 1;
              final s = .62 + .56 * Curves.easeOutCubic.transform(t);
              return Opacity(
                opacity: (1 - t) * .55,
                child: Container(
                  width: box * s,
                  height: box * s,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              );
            },
          ),
        Buddy(color: color, size: size, wobble: wobble),
      ]),
    );
  }
}

class _ArtLog extends StatelessWidget {
  const _ArtLog();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: MCard(
        radius: 24,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const PersonAvatar('A'),
              const SizedBox(width: 13),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Amma · BP tablet', style: T.row(c.ink)),
                  const SizedBox(height: 6),
                  Text('"Took it with idli, feeling good!"', style: inter(14.5, 500, color: c.ink, height: 1.35, tabular: false)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('9:00 am', style: inter(14, 700, color: c.ink)),
                const SizedBox(height: 5),
                const StatusPill(Status.taken),
              ]),
            ]),
          ),
          Divider(height: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const PersonAvatar('N', tone: Tone.mint),
              const SizedBox(width: 13),
              Expanded(child: Text('Nanna · Metformin', style: T.row(c.ink))),
              Text('1:30 pm', style: inter(14, 700, color: c.ink)),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(alignment: Alignment.centerLeft, child: StreakPill('Amma · 12 days', tone: Tone.peach)),
          ),
        ]),
      ),
    );
  }
}
