---
version: 1
slug: "app"
primary_target: "app"
related_targets: []
---

# Mapa app (Flutter): caretaker + recipient

Scope: the whole Flutter app. Mode: Operate (the in-app landing/onboarding follows the same world). Caretaker on iPhone; recipient on Android, 60+, needing large type and few taps. The caretaker's main moment is checking Today. Voice: playful buddy. The mascot is required. Avoid looking clinical or generic.

## Direction contract

THESIS: Mapa is a phone call from you. Every reminder is a scheduled call, and Today reads as a warm call log led by the next call. This refuses the category default of a pill-icon checklist on white with a streak flame.

OWN-WORLD: The pastel push-button landline. A cool near-white ground (#F7F7FB) that becomes a night-ink ground in dark mode, plum-ink text (#2D2A3E), and a phone colour per person (peach #FFC9B0, mint #BFE8D6, butter #FFE7A3, lilac #D9CCFF) used everywhere as that person's code. Chunky keypad buttons press down on a 4px base. A coiled-cord line is the one ornament. Frosted phone-screen glass is used only over live-call and overlay moments. Inter, with large tabular numerals for times.

STORY: The caretaker opens Mapa, sees who Mapa calls next and what Amma said at 9:00, trusts that it's handled, and adds a reminder by chatting. The recipient just answers a cute ringing call.

FIRST VIEWPORT: Large "Today" title + date, with the caretaker avatar on the right. A "Mapa calls next" card in the person's phone colour: a 56pt tabular time, the person and the medicine, the person's bubble with a coiled cord, and two keypad buttons (Call now, Snooze). Then a "Call log" grouped list: avatar, medicine, outcome, their quote, time and status. A plum + button bottom-right.

FORM: The Call Home, position 3 on the grounded list (re-roll 1). seed:9c98c8e0abde1c1f. Raises: tabular monumental times (Datamatics); isolated outline-only destructive actions (Graphite Console); person colour as a consistent code (Catalog Sleeve); the live call lifts while the rest dims behind frost (Title Wall).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Signature interaction
The incoming call: the mascot (a round handset-buddy with a face) wobbles in on a ring. Slide-to-answer is a frosted track where the coiled cord stretches as you drag, then springs back if released. Motion is springy but brief, and honours Reduce Motion with a crossfade.

## Open decisions
- The mascot's final form and name.
- Whether recipient screen text appears in Telugu.
