import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Recipient pairing: a phone keypad they already know how to use.
class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({super.key});
  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  String _code = '';
  String? _error;
  bool _busy = false;

  void _tap(String d) {
    if (_code.length >= 6 || _busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _code += d;
      _error = null;
    });
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.redeem(_code);
      if (mounted) context.go(!kIsWeb && defaultTargetPlatform == TargetPlatform.android ? '/allow-calls' : '/idle');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        if (e.code != 'unreachable') _code = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Can't reach Mapa right now. Check your connection.";
      });
    }
  }

  void _del() {
    if (_code.isEmpty || _busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _code = _code.substring(0, _code.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ready = _code.length == 6;
    return MapaScaffold(
      child: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: RoundBack(onTap: () => context.go('/role')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Enter the code from your family', style: inter(32, 800, color: c.ink, spacing: -.03, height: 1.08, tabular: false)),
          ),
        ),
        const SizedBox(height: 22),
        Semantics(
          label: 'Code entered: ${_code.split("").join(" ")}',
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 6; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 48,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: i == _code.length ? c.ink : c.line, width: i == _code.length ? 3 : 1.5),
                ),
                child: Text(i < _code.length ? _code[i] : '', style: inter(30, 800, color: c.ink)),
              ),
          ]),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _error == null
              ? const SizedBox(key: ValueKey('none'), height: 14)
              : Padding(
                  key: ValueKey(_error),
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                  child: Text(_error!, textAlign: TextAlign.center, style: inter(16, 600, color: c.bad, height: 1.35, tabular: false)),
                ),
        ),
        const SizedBox(height: 6),
        QuietLink(
          'Scan the QR instead',
          icon: LucideIcons.scanLine,
          size: 17,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: c.ink,
              content: Text('Camera scanning arrives with the pairing backend.', style: inter(15, 600, color: c.bg, tabular: false)),
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            childAspectRatio: 1.62,
            children: [
              for (final d in const ['1', '2', '3', '4', '5', '6', '7', '8', '9']) _Key(d, onTap: () => _tap(d)),
              const SizedBox.shrink(),
              _Key('0', onTap: () => _tap('0')),
              _Key('', icon: LucideIcons.delete, plain: true, label: 'Delete', onTap: _del),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: KeyButton(
            label: _busy ? 'Connecting…' : 'Connect',
            height: 64,
            fontSize: 20,
            kind: ready ? KeyKind.primary : KeyKind.quiet,
            onTap: ready && !_busy ? _connect : null,
          ),
        ),
      ]),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key(this.digit, {required this.onTap, this.icon, this.plain = false, this.label});
  final String digit;
  final IconData? icon;
  final bool plain;
  final String? label;
  final VoidCallback onTap;
  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: widget.label ?? widget.digit,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
          alignment: Alignment.center,
          decoration: widget.plain
              ? null
              : BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: c.line, offset: const Offset(0, 4)),
                    BoxShadow(color: c.shadow, blurRadius: 16, spreadRadius: -10, offset: const Offset(0, 8)),
                  ],
                ),
          child: widget.icon != null
              ? Icon(widget.icon, size: 32, color: c.ink)
              : Text(widget.digit, style: inter(30, 700, color: c.ink)),
        ),
      ),
    );
  }
}
