import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.linkId});
  final String linkId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final link = repo.linkById(linkId);
        if (link == null) {
          return MapaScaffold(child: Column(children: [const MapaNav(title: 'Person'), Expanded(child: Center(child: Text('Not paired any more.', style: T.body(c.ink2))))]));
        }
        final tone = link.tone;
        final streak = repo.streakFor(link.id);
        final week = repo.weekFor(link.id);
        final rems = repo.remindersFor(link.id);
        final hist = repo.historyFor(link.id);
        const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        return MapaScaffold(
          child: Column(children: [
            MapaNav(title: link.nickname),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                children: [
                  Row(children: [
                    PersonAvatar(link.initial, tone: tone, size: 84),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(link.nickname, style: inter(30, 800, color: c.ink, spacing: -.03, tabular: false)),
                        const SizedBox(height: 3),
                        Text('${link.language == 'te' ? 'Telugu' : 'English'} · paired ${link.createdAt.day} ${dateText(link.createdAt).split(' ').last}',
                            style: inter(15, 500, color: c.ink2)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  MCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(99)),
                          child: const Icon(LucideIcons.flame, size: 18, color: MapaColors.onPastel),
                        ),
                        const SizedBox(width: 10),
                        Text(streak == 0 ? 'Start a streak' : '$streak ${streak == 1 ? 'day' : 'days'} in a row',
                            style: inter(19, 800, color: c.ink, tabular: false)),
                      ]),
                      const SizedBox(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        for (final d in week) _Day(letters[d.day.weekday - 1], d.state, tone),
                      ]),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 26, 2, 12),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Reminders', style: T.title(c.ink)),
                      GestureDetector(
                        onTap: () => context.push('/chat?link=${link.id}'),
                        child: Text('Add', style: T.label(c.ink2)),
                      ),
                    ]),
                  ),
                  if (rems.isEmpty)
                    MCard(padding: const EdgeInsets.all(20), child: Text('No reminders yet.', style: inter(16, 500, color: c.ink2, tabular: false)))
                  else
                    MCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (var i = 0; i < rems.length; i++) _Rem(rems[i], tone, last: i == rems.length - 1),
                      ]),
                    ),
                  if (hist.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 26, 2, 12),
                      child: Text('Recent calls', style: T.title(c.ink)),
                    ),
                    MCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (var i = 0; i < hist.length; i++) _Call(hist[i], last: i == hist.length - 1),
                      ]),
                    ),
                  ],
                  // Destructive action sits alone, outlined, and asks twice.
                  const SizedBox(height: 48),
                  KeyButton(label: 'Unpair ${link.nickname}', kind: KeyKind.danger, onTap: () => _confirmUnpair(context, link)),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  void _confirmUnpair(BuildContext context, Link link) {
    final c = context.c;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Unpair ${link.nickname}?', style: inter(20, 800, color: c.ink, tabular: false)),
        content: Text("Mapa will stop calling and ${link.nickname}'s reminders will be removed.",
            style: inter(15.5, 500, color: c.ink2, height: 1.4, tabular: false)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Keep', style: inter(16, 700, color: c.ink, tabular: false))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await repo.unpair(link.id);
              if (context.mounted) context.go('/home');
            },
            child: Text('Unpair', style: inter(16, 700, color: c.bad, tabular: false)),
          ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day(this.letter, this.state, this.tone);
  final String letter, state; // done | missed | today | none
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = state == 'done', today = state == 'today', missed = state == 'missed';
    return Semantics(
      label: '$letter ${done ? "taken" : missed ? "missed" : today ? "today" : "no calls"}',
      child: Column(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? tone.color : (missed ? c.badBg : (today ? Colors.transparent : c.raised)),
            border: today ? Border.all(color: c.ink, width: 2.5) : null,
          ),
          child: done
              ? const Icon(LucideIcons.check, size: 19, color: MapaColors.onPastel)
              : missed
                  ? Icon(LucideIcons.x, size: 18, color: c.bad)
                  : null,
        ),
        const SizedBox(height: 7),
        Text(letter, style: inter(12.5, 700, color: c.ink2, tabular: false)),
      ]),
    );
  }
}

class _Rem extends StatelessWidget {
  const _Rem(this.r, this.tone, {required this.last});
  final Reminder r;
  final Tone tone;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final at = DateTime(2000, 1, 1, r.hour, r.minute);
    final until = r.end == null ? '' : ' · until ${r.end!.day} ${dateText(r.end!).split(' ').last}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(14)),
          child: const Icon(LucideIcons.pill, size: 20, color: MapaColors.onPastel),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([r.medicine, if (r.dose != null) r.dose!].join(' '), style: inter(16, 700, color: c.ink, tabular: false)),
            const SizedBox(height: 2),
            Text('${timeText(at)} · ${daysText(r.daysMask)}$until', style: T.small(c.ink2)),
          ]),
        ),
        IconButton(
          tooltip: 'Remove reminder',
          icon: Icon(LucideIcons.trash2, size: 20, color: c.ink2),
          onPressed: () => _confirmRemove(context),
        ),
      ]),
    );
  }

  void _confirmRemove(BuildContext context) {
    final c = context.c;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Remove ${r.medicine}?', style: inter(20, 800, color: c.ink, tabular: false)),
        content: Text('Mapa will stop calling about it.', style: inter(15.5, 500, color: c.ink2, tabular: false)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Keep', style: inter(16, 700, color: c.ink, tabular: false))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              repo.deleteReminder(r.id);
            },
            child: Text('Remove', style: inter(16, 700, color: c.bad, tabular: false)),
          ),
        ],
      ),
    );
  }
}

class _Call extends StatelessWidget {
  const _Call(this.o, {required this.last});
  final Occurrence o;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rem = repo.reminderById(o.reminderId)!;
    final st = repo.rowStatus(o, isNext: false);
    final note = repo.results[o.id]?.note;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rem.medicine, style: T.row(c.ink)),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('"$note"', style: inter(14.5, 500, color: c.ink, height: 1.4, tabular: false)),
            ],
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(dayName(o.at, DateTime.now()), style: inter(14, 700, color: c.ink, tabular: false)),
          const SizedBox(height: 5),
          StatusPill(st.status, label: st.label),
        ]),
      ]),
    );
  }
}
