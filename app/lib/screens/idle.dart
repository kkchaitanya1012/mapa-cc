import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/common.dart';

/// What the parent sees between calls: when the next one is, nothing else.
class IdleScreen extends StatelessWidget {
  const IdleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final link = repo.links.firstOrNull;
        final next = repo.nextCall;
        final today = repo.today;
        final who = (link?.caretakerName ?? '').isEmpty ? 'Your family' : link!.caretakerName;
        return MapaScaffold(
          child: RefreshIndicator(
            onRefresh: repo.refresh,
            color: c.ink,
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 18),
                    child: Column(children: [
                      // Long-press the mascot to simulate Mapa calling (until real calls are wired up).
                      GestureDetector(
                        onLongPress: () => context.go('/call/incoming'),
                        child: Buddy(color: link?.tone.color ?? MapaColors.mint, size: 150, mood: Mood.calm),
                      ),
                      const SizedBox(height: 18),
                      if (next == null) ..._nothing(c, who) else ..._upcoming(c, next),
                      const SizedBox(height: 28),
                      for (var i = 0; i < today.length; i++) ...[
                        _DayRow(today[i], isNext: today[i].id == next?.id),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 12),
                      if (link != null)
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          PersonAvatar(who.runes.isEmpty ? '?' : String.fromCharCode(who.runes.first).toUpperCase(), tone: Tone.lilac, size: 36),
                          const SizedBox(width: 12),
                          Flexible(child: Text('$who set this up for you', style: inter(17, 600, color: c.ink2, tabular: false))),
                        ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _nothing(MapaColors c, String who) => [
        Text('No calls yet', style: inter(30, 800, color: c.ink, spacing: -.03, tabular: false)),
        const SizedBox(height: 10),
        Text('$who will add your reminders. Mapa will call when it is time.',
            textAlign: TextAlign.center, style: inter(19, 500, color: c.ink2, height: 1.4, tabular: false)),
      ];

  List<Widget> _upcoming(MapaColors c, Occurrence next) {
    final t = timeParts(next.at);
    final rem = repo.reminderById(next.reminderId);
    final tomorrow = next.at.day != DateTime.now().day;
    return [
      Text(tomorrow ? 'Mapa will call you tomorrow at' : 'Mapa will call you at',
          style: inter(26, 700, color: c.ink2, spacing: -.02, tabular: false)),
      const SizedBox(height: 8),
      Semantics(
        label: 'Next call at ${t.hm} ${t.ampm}',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(t.hm, style: T.time(84, c.ink)),
          const SizedBox(width: 6),
          Text(t.ampm, style: inter(34, 800, color: c.ink)),
        ]),
      ),
      if (rem != null) ...[
        const SizedBox(height: 12),
        Text([rem.medicine, if (rem.dose != null) rem.dose!].join(', '), style: inter(22, 600, color: c.ink, tabular: false)),
      ],
    ];
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow(this.o, {required this.isNext});
  final Occurrence o;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = o.status == 'completed';
    final missed = o.status == 'no_answer' || o.status == 'failed';
    final icon = done ? LucideIcons.check : (isNext ? LucideIcons.phone : (missed ? LucideIcons.x : LucideIcons.clock));
    final tag = done ? 'Done' : (missed ? 'Missed' : (isNext ? 'Next' : 'Later'));
    final fg = isNext ? MapaColors.nextText : c.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isNext ? MapaColors.butter : c.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: isNext ? null : [BoxShadow(color: c.line, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        Icon(icon, size: 26, color: done ? c.ok : (isNext ? fg : (missed ? c.bad : c.ink2))),
        const SizedBox(width: 14),
        Text(timeText(o.at), style: inter(21, 700, color: fg)),
        const Spacer(),
        Text(tag, style: inter(16, 600, color: isNext ? const Color(0xFF6A5200) : c.ink2, tabular: false)),
      ]),
    );
  }
}
