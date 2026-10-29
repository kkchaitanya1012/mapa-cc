import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Developer menu. Long-press the "mapa" wordmark on the landing screen.
/// Remove before release.
class DemoMenu extends StatelessWidget {
  const DemoMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget item(String label, String path) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: KeyButton(label: label, kind: KeyKind.secondary, height: 50, fontSize: 16, radius: 16, onTap: () => context.go(path)),
        );
    return MapaScaffold(
      child: Column(children: [
        const MapaNav(title: 'Developer menu'),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
            Text(repo.role == null ? 'Not signed in' : 'Signed in as ${repo.role}', style: T.label(c.ink2)),
            const SizedBox(height: 14),
            Text('Start over', style: T.title(c.ink)),
            const SizedBox(height: 10),
            KeyButton(
              label: 'Sign out and start fresh',
              kind: KeyKind.danger,
              height: 50,
              fontSize: 16,
              radius: 16,
              onTap: () async {
                await repo.signOutAndReset();
                if (context.mounted) context.go('/');
              },
            ),
            const SizedBox(height: 20),
            Text('Call screens (not live yet)', style: T.title(c.ink)),
            const SizedBox(height: 10),
            item('Incoming call', '/call/incoming'),
            item('On the call', '/call/live'),
            item('Call done', '/call/done'),
            const SizedBox(height: 16),
            Text('Jump to', style: T.title(c.ink)),
            const SizedBox(height: 10),
            item('Onboarding', '/onboarding'),
            item('Role choice', '/role'),
            item('Pairing (caretaker)', '/pair'),
            item('Enter code (parent)', '/join'),
          ]),
        ),
      ]),
    );
  }
}
