import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../format.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/coil.dart';
import '../widgets/common.dart';
import 'pick_link.dart';

Future<void> startReminder(BuildContext context) async {
  final link = await pickLink(context);
  if (link != null && context.mounted) context.push('/chat?link=${link.id}');
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final name = repo.links.firstOrNull?.caretakerName ?? '';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Today', style: T.h1(c.ink)),
                  const SizedBox(height: 4),
                  Text(dateText(DateTime.now()), style: inter(15, 500, color: c.ink2)),
                ]),
              ),
              PersonAvatar(name.isEmpty ? 'Me' : String.fromCharCode(name.runes.first).toUpperCase(), tone: Tone.lilac, size: 44),
            ]),
          ),
          Expanded(
            child: repo.links.isEmpty
                ? const _NobodyYet()
                : repo.hasReminders
                    ? const _Populated()
                    : _Empty(first: repo.links.first),
          ),
        ]);
      },
    );
  }
}

class _NobodyYet extends StatelessWidget {
  const _NobodyYet();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 96),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Buddy(color: MapaColors.lilac, size: 150, wobble: true),
        const SizedBox(height: 14),
        Text("Let's pair a phone.", style: T.h2(c.ink)),
        const SizedBox(height: 10),
        Text("Mapa will call the person you care for. First, link their phone to yours.",
            textAlign: TextAlign.center, style: inter(17, 500, color: c.ink2, height: 1.45, tabular: false)),
        const SizedBox(height: 26),
        KeyButton(label: 'Pair a phone', icon: LucideIcons.users, onTap: () => context.push('/pair')),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.first});
  final Link first;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 96),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Buddy(color: first.tone.color, size: 150, wobble: true),
        const SizedBox(height: 14),
        Text('${first.nickname} is paired.', style: T.h2(c.ink)),
        const SizedBox(height: 10),
        Text('What should Mapa remind them about?',
            textAlign: TextAlign.center, style: inter(17, 500, color: c.ink2, height: 1.45, tabular: false)),
        const SizedBox(height: 26),
        KeyButton(label: 'Add a reminder', icon: LucideIcons.messageCircle, onTap: () => startReminder(context)),
        const SizedBox(height: 12),
        KeyButton(label: 'Add another person', icon: LucideIcons.users, kind: KeyKind.secondary, onTap: () => context.push('/pair')),
      ]),
    );
  }
}

class _Populated extends StatelessWidget {
  const _Populated();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final next = repo.nextCall;
    final today = repo.today;
    return RefreshIndicator(
      onRefresh: repo.refresh,
      color: c.ink,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 190),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in repo.links)
              if (repo.streakFor(l.id) > 0) StreakPill('${l.nickname} · ${repo.streakFor(l.id)} days', tone: l.tone),
          ]),
          if (repo.links.any((l) => repo.streakFor(l.id) > 0)) const SizedBox(height: 18),
          next == null ? const _NothingNext() : NextCallCard(occurrence: next),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 26, 2, 12),
            child: Text('Call log', style: T.title(c.ink)),
          ),
          if (today.isEmpty)
            MCard(
              padding: const EdgeInsets.all(20),
              child: Text('No calls today.', style: inter(16, 500, color: c.ink2, tabular: false)),
            )
          else
            MCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (var i = 0; i < today.length; i++)
                  _LogRow(today[i], isNext: today[i].id == next?.id, last: i == today.length - 1),
              ]),
            ),
        ],
      ),
    );
  }
}

class _NothingNext extends StatelessWidget {
  const _NothingNext();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MCard(
      padding: const EdgeInsets.all(22),
      radius: 30,
      child: Row(children: [
        const Buddy(color: MapaColors.butter, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("You're all caught up.", style: inter(19, 800, color: c.ink, tabular: false)),
            const SizedBox(height: 3),
            Text('No calls coming up soon.', style: T.small(c.ink2)),
          ]),
        ),
      ]),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.o, {required this.isNext, required this.last});
  final Occurrence o;
  final bool isNext, last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rem = repo.reminderById(o.reminderId)!;
    final link = repo.linkOf(o)!;
    final st = repo.rowStatus(o, isNext: isNext);
    final res = repo.results[o.id];
    final quote = res?.note;
    return InkWell(
      onTap: () => context.push('/person/${link.id}'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PersonAvatar(link.initial, tone: link.tone),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${link.nickname} · ${rem.medicine}', style: T.row(c.ink)),
              if (rem.dose != null) ...[const SizedBox(height: 2), Text(rem.dose!, style: T.small(c.ink2))],
              if (quote != null && quote.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text('"$quote"', style: inter(14.5, 500, color: c.ink, height: 1.4, tabular: false)),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(timeText(o.at), style: inter(14, 700, color: c.ink)),
            const SizedBox(height: 5),
            StatusPill(st.status, label: st.label),
          ]),
        ]),
      ),
    );
  }
}

/// The hero of Today: who Mapa calls next, as large as anything on screen.
class NextCallCard extends StatefulWidget {
  const NextCallCard({super.key, required this.occurrence});
  final Occurrence occurrence;
  @override
  State<NextCallCard> createState() => _NextCallCardState();
}

class _NextCallCardState extends State<NextCallCard> {
  bool _asked = false; // tapped Call now; stays off until the call is shown as made

  @override
  void didUpdateWidget(NextCallCard old) {
    super.didUpdateWidget(old);
    if (old.occurrence.id != widget.occurrence.id) _asked = false; // a different call is up next
  }

  Future<void> _callNow(String name) async {
    setState(() => _asked = true);
    String msg;
    try {
      final r = await repo.api.callNow(widget.occurrence.id);
      msg = r == 'already_calling' ? 'Mapa is already calling $name.' : 'Calling $name in a few seconds.';
      repo.refresh();
    } on ApiError catch (e) {
      // The slot was already called (or the card is stale): refresh so the card says so.
      msg = e.message == 'already_called' ? 'Mapa already called $name for this one.' : e.message;
      repo.refresh();
      if (e.message != 'already_called') setState(() => _asked = false);
    } catch (_) {
      msg = "Couldn't start the call. Check your connection.";
      setState(() => _asked = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: context.c.ink,
      content: Text(msg, style: inter(15, 600, color: context.c.bg, tabular: false)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = widget.occurrence;
    final link = repo.linkOf(occurrence)!;
    final rem = repo.reminderById(occurrence.reminderId)!;
    final t = timeParts(occurrence.at);
    final tomorrow = occurrence.at.day != DateTime.now().day;
    final detail = [rem.medicine, if (rem.dose != null) rem.dose!].join(' ');
    // What is happening to this call right now decides what the button offers.
    final live = occurrence.status == 'ringing' ? 'Calling ${link.nickname}…' : occurrence.status == 'in_call' ? 'On a call with ${link.nickname}' : null;
    final calledAt = repo.calledEarlyAt(occurrence);
    final busy = live ?? (_asked ? 'Calling ${link.nickname}…' : null) ?? (calledAt == null ? null : 'Called at ${timeText(calledAt)}');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: link.tone.color,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: context.c.shadow, blurRadius: 34, spreadRadius: -18, offset: const Offset(0, 18))],
      ),
      child: Stack(children: [
        Positioned(right: 0, top: 0, child: PersonAvatar(link.initial, size: 62, color: Colors.white)),
        const Positioned(right: 20, top: 62, child: VCoil(color: MapaColors.onPastel)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            label: 'Next call at ${t.hm} ${t.ampm}',
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(t.hm, style: T.time(58, MapaColors.onPastel)),
              const SizedBox(width: 4),
              Text(t.ampm, style: inter(24, 700, color: MapaColors.onPastel)),
            ]),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 64),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mapa calls ${link.nickname}', style: inter(17, 700, color: MapaColors.onPastel, tabular: false)),
              const SizedBox(height: 2),
              Text('$detail · ${tomorrow ? 'tomorrow, ' : ''}${untilText(occurrence.at.difference(DateTime.now()))}',
                  style: inter(14.5, 500, color: MapaColors.onPastel2, tabular: false)),
              if (calledAt != null && live == null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Already called with Call now. Mapa still calls at the scheduled time.',
                      style: inter(14.5, 600, color: MapaColors.onPastel, tabular: false)),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          _OnPastelKey(
            label: busy ?? 'Call now',
            icon: busy == null ? LucideIcons.phone : null,
            onTap: busy == null ? () => _callNow(link.nickname) : null,
          ),
        ]),
      ]),
    );
  }
}

class _OnPastelKey extends StatelessWidget {
  const _OnPastelKey({required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap; // null while a call is in progress

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: onTap == null ? const Color(0x80FFFFFF) : Colors.white,
            borderRadius: BorderRadius.circular(17),
            boxShadow: onTap == null ? null : const [BoxShadow(color: Color(0x292D2A3E), offset: Offset(0, 4))],
          ),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 19, color: MapaColors.onPastel), const SizedBox(width: 8)],
            Text(label, style: inter(16, 700, color: MapaColors.onPastel, tabular: false)),
          ]),
        ),
      ),
    );
  }
}
