import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/common.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final alerts = repo.alerts;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 150),
          children: [
            Text('Alerts', style: T.h1(c.ink)),
            const SizedBox(height: 4),
            Text('Mapa only flags what needs you.', style: inter(15, 500, color: c.ink2, tabular: false)),
            const SizedBox(height: 22),
            if (alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Column(children: [
                  const Buddy(color: MapaColors.mint, size: 120, mood: Mood.calm),
                  const SizedBox(height: 14),
                  Text('All quiet.', style: T.h2(c.ink)),
                  const SizedBox(height: 8),
                  Text("Nothing needs you right now.", style: inter(17, 500, color: c.ink2, tabular: false)),
                ]),
              )
            else
              for (final a in alerts) _AlertCard(a),
          ],
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard(this.alert);
  final AlertItem alert;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final link = repo.linkById(alert.linkId);
    final urgent = alert.unseen && alert.kind != 'no_answer';
    final when = '${dayName(alert.createdAt, DateTime.now())}, ${timeText(alert.createdAt)}';
    return Opacity(
      opacity: alert.unseen ? 1 : .62,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: urgent ? c.badBg : c.surface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: urgent ? null : [BoxShadow(color: c.line, offset: const Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            PersonAvatar(link?.initial ?? '?', tone: link?.tone ?? Tone.lilac, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(alert.message, style: inter(17, 700, color: c.ink, height: 1.25, tabular: false)),
                const SizedBox(height: 2),
                Text(when, style: inter(13, 500, color: urgent ? c.bad : c.ink2)),
              ]),
            ),
          ]),
          if (alert.unseen) ...[
            const SizedBox(height: 16),
            KeyButton(
              label: 'Got it',
              height: 46,
              fontSize: 15,
              radius: 16,
              kind: urgent ? KeyKind.primary : KeyKind.secondary,
              onTap: () => repo.markSeen(alert.id),
            ),
          ],
        ]),
      ),
    );
  }
}
