import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/common.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key, this.splash = false});

  /// The launch splash: the same screen without its button, shown while Mapa loads.
  final bool splash;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MapaScaffold(
      background: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .55, 1.15],
          colors: [c.landTop, c.landMid, c.landBot],
        ),
      ),
      child: Stack(children: [
        const Blobs([
          (Alignment(-1.3, -1.0), 320, MapaColors.lilac, .75),
          (Alignment(1.4, .55), 280, MapaColors.mint, .7),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Column(children: [
            const Spacer(flex: 3),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .6, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Semantics(
                label: 'Mapa mascot',
                child: const Buddy(color: MapaColors.butter, size: 190, wobble: true),
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onLongPress: splash ? null : () => context.push('/demo'),
              child: Text('mapa',
                  style: inter(76, 800, color: c.isDark ? c.ink : MapaColors.onPastel, spacing: -.06, height: 1, tabular: false)),
            ),
            const SizedBox(height: 14),
            Text(
              "A call from you, even when you can't call.",
              textAlign: TextAlign.center,
              style: inter(21, 600,
                  color: c.isDark ? c.ink : const Color(0xFF3A3650), height: 1.35, tabular: false),
            ),
            const Spacer(flex: 4),
            if (splash)
              const SizedBox(height: 50 + 14 + 17) // the button's space, so nothing jumps when it appears
            else ...[
              KeyButton(
                label: 'Get started',
                onTap: () => context.go(repo.onboardingSeen ? '/role' : '/onboarding'),
              ),
              const SizedBox(height: 14),
              Text('Takes about a minute to set up',
                  style: inter(14, 600, color: c.ink2, tabular: false)),
            ],
          ]),
        ),
      ]),
    );
  }
}
