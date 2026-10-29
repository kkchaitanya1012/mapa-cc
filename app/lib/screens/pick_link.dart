import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Which person is this for? Skips the question when there's only one.
Future<Link?> pickLink(BuildContext context) async {
  if (repo.links.length <= 1) return repo.links.firstOrNull;
  final c = context.c;
  return showModalBottomSheet<Link>(
    context: context,
    backgroundColor: c.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Who is this for?', style: inter(24, 800, color: c.ink, spacing: -.02, tabular: false)),
          const SizedBox(height: 14),
          for (final l in repo.links)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.pop(ctx, l),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    PersonAvatar(l.initial, tone: l.tone, size: 48),
                    const SizedBox(width: 14),
                    Expanded(child: Text(l.nickname, style: inter(18, 700, color: c.ink, tabular: false))),
                    Icon(LucideIcons.chevronRight, color: c.ink2),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    ),
  );
}
