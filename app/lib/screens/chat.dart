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
import '../widgets/common.dart';

/// Reminder chat. Mapa never writes free text: it asks a tappable question,
/// shows a confirmation card, or answers off-topic input with one fixed line.
/// All the understanding happens on the server (POST /chat).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.linkId});
  final String linkId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _Step { idle, thinking, asking, confirm, saving, done }

class _ChatScreenState extends State<ChatScreen> {
  static const _offTopic =
      'I can only set medicine reminders. Try something like "BP tablet at 9 am every day for a month".';

  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final _history = <({String role, String text})>[];
  final _items = <Widget>[];
  _Step _step = _Step.idle;
  List<String> _options = const [];
  Map<String, dynamic>? _draft;

  Link? get _link => repo.linkById(widget.linkId);

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _step == _Step.thinking || _step == _Step.saving) return;
    _ctl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _items.add(_Mine(text));
      _options = const [];
      _step = _Step.thinking;
    });
    _scrollDown();
    try {
      final reply = await repo.api.chat(widget.linkId, [..._history, (role: 'user', text: text)]);
      if (!mounted) return;
      switch (reply.type) {
        case 'clarify':
          _history.add((role: 'user', text: text));
          _history.add((role: 'assistant', text: reply.question!));
          setState(() {
            _items.add(_Ask(reply.question!));
            _options = reply.options;
            _step = _Step.asking;
          });
        case 'create':
          _history.add((role: 'user', text: text));
          setState(() {
            _draft = reply.draft;
            _items.add(const _Ask('Got it. Does this look right?'));
            _step = _Step.confirm;
          });
        default: // reject: keep the conversation clean of the off-topic message
          setState(() {
            _items.add(const _Ask(_offTopic));
            _step = _history.isEmpty ? _Step.idle : _Step.asking;
            if (_history.isNotEmpty) _options = const [];
          });
      }
    } on ApiError catch (e) {
      _failed(e.message);
    } catch (_) {
      _failed("Can't reach Mapa right now. Check your connection.");
    }
    _scrollDown();
  }

  void _failed(String msg) {
    if (!mounted) return;
    setState(() {
      _items.add(_Ask(msg));
      _step = _history.isEmpty ? _Step.idle : _Step.asking;
    });
  }

  Future<void> _confirm() async {
    setState(() => _step = _Step.saving);
    try {
      await repo.addReminder(widget.linkId, _draft!);
      if (!mounted) return;
      setState(() => _step = _Step.done);
      Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        context.canPop() ? context.pop() : context.go('/home');
      });
    } on ApiError catch (e) {
      setState(() => _step = _Step.confirm);
      _failed(e.message);
    } catch (_) {
      setState(() => _step = _Step.confirm);
      _failed("Couldn't save that. Please try again.");
    }
  }

  void _startOver() => setState(() {
        _history.clear();
        _items.clear();
        _options = const [];
        _draft = null;
        _step = _Step.idle;
      });

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 240,
              duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
        }
      });

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final link = _link;
    if (link == null) {
      return const MapaScaffold(child: MapaNav(title: 'New reminder'));
    }
    final locked = _step == _Step.confirm || _step == _Step.saving || _step == _Step.done;
    return MapaScaffold(
      child: Column(children: [
        MapaNav(
          title: 'New reminder',
          subtitle: 'for ${link.nickname}',
          leading: PersonAvatar(link.initial, tone: link.tone, size: 36),
        ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            children: [
              if (_items.isEmpty) _Empty(link: link),
              for (final w in _items) Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
              if (_step == _Step.thinking) Padding(padding: const EdgeInsets.only(bottom: 12), child: _Thinking(link: link)),
              if (_step == _Step.asking && _options.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 44, bottom: 12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final t in _options) _ChipBtn(t, onTap: () => _send(t)),
                  ]),
                ),
              if (locked && _draft != null)
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: _Confirm(
                    draft: _draft!,
                    language: link.language,
                    saving: _step == _Step.saving,
                    done: _step == _Step.done,
                    onOk: _confirm,
                    onChange: _startOver,
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          color: c.bg,
          child: Row(children: [
            Expanded(
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: c.line, width: 1.5),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _ctl,
                  enabled: !locked,
                  onSubmitted: _send,
                  textInputAction: TextInputAction.send,
                  style: inter(16, 500, color: c.ink, tabular: false),
                  cursorColor: c.ink,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: _step == _Step.asking ? 'Or type your answer' : 'Type a reminder',
                    hintStyle: inter(16, 500, color: c.ink2, tabular: false),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Send',
              child: GestureDetector(
                onTap: locked ? null : () => _send(_ctl.text),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: locked ? c.raised : c.ink, shape: BoxShape.circle),
                  child: Icon(LucideIcons.send, size: 22, color: locked ? c.ink2 : c.bg),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.link});
  final Link link;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(children: [
        Buddy(color: link.tone.color, size: 96),
        const SizedBox(height: 14),
        Text('Tell me the medicine, time and days.', textAlign: TextAlign.center, style: inter(18, 700, color: c.ink, tabular: false)),
        const SizedBox(height: 6),
        Text('Like "BP tablet every morning after breakfast for a month".',
            textAlign: TextAlign.center, style: inter(15, 500, color: c.ink2, height: 1.4, tabular: false)),
      ]),
    );
  }
}

class _Mine extends StatelessWidget {
  const _Mine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: c.ink,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22), topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22), bottomRight: Radius.circular(6)),
          ),
          child: Text(text, style: inter(16, 500, color: c.bg, height: 1.4, tabular: false)),
        ),
      ),
    );
  }
}

class _Ask extends StatelessWidget {
  const _Ask(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Buddy(color: repo.links.firstOrNull?.tone.color ?? MapaColors.peach, size: 34),
      const SizedBox(width: 10),
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: c.surface,
            boxShadow: [BoxShadow(color: c.line, offset: const Offset(0, 1))],
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22), topRight: Radius.circular(22),
                bottomRight: Radius.circular(22), bottomLeft: Radius.circular(6)),
          ),
          child: Text(text, style: inter(16, 600, color: c.ink, height: 1.4, tabular: false)),
        ),
      ),
    ]);
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking({required this.link});
  final Link link;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      Buddy(color: link.tone.color, size: 34, wobble: true),
      const SizedBox(width: 10),
      Text('One moment…', style: inter(15, 600, color: c.ink2, tabular: false)),
    ]);
  }
}

class _ChipBtn extends StatelessWidget {
  const _ChipBtn(this.t, {required this.onTap});
  final String t;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: t,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: c.line, width: 1.5),
          ),
          child: Text(t, style: inter(15, 700, color: c.ink)),
        ),
      ),
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({required this.draft, required this.language, required this.saving, required this.done, required this.onOk, required this.onChange});
  final Map<String, dynamic> draft;
  final String language;
  final bool saving, done;
  final VoidCallback onOk, onChange;

  String get _times => [
        for (final t in (draft['times'] as List).cast<String>())
          timeText(DateTime(2000, 1, 1, int.parse(t.split(':')[0]), int.parse(t.split(':')[1]))),
      ].join(' and ');

  String get _duration {
    final end = draft['end_date'] as String?;
    if (end == null) return 'keeps going';
    final days = DateTime.parse(end).difference(DateTime.parse(draft['start_date'] as String)).inDays + 1;
    return '$days days from today';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget line(IconData i, String a, String b, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            Icon(i, size: 20, color: c.ink2),
            const SizedBox(width: 12),
            Expanded(child: Text(a, style: inter(15.5, 600, color: c.ink, tabular: false))),
            Flexible(child: Text(b, textAlign: TextAlign.right, style: inter(14.5, 500, color: c.ink2, tabular: false))),
          ]),
        );
    return MCard(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        line(LucideIcons.pill, draft['medicine'] as String, (draft['dose'] as String?) ?? ''),
        line(LucideIcons.clock, _times, ''),
        line(LucideIcons.repeat, daysText(draft['days_mask'] as int), _duration),
        line(LucideIcons.globe, language == 'te' ? 'Telugu' : 'English', 'voice', last: true),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: done
              ? Row(key: const ValueKey('done'), mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(LucideIcons.check, color: c.ok, size: 22),
                  const SizedBox(width: 8),
                  Text('Reminder set', style: inter(16, 700, color: c.ok, tabular: false)),
                ])
              : Row(key: const ValueKey('btns'), children: [
                  Expanded(child: KeyButton(label: 'Start over', kind: KeyKind.secondary, height: 46, fontSize: 15, radius: 16, onTap: saving ? null : onChange)),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: KeyButton(label: saving ? 'Saving…' : 'Looks right', height: 46, fontSize: 15, radius: 16, onTap: saving ? null : onOk)),
                ]),
        ),
      ]),
    );
  }
}
