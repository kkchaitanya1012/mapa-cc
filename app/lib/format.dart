/// "1:30" and "pm" for a local time; the two parts are styled separately.
({String hm, String ampm}) timeParts(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return (hm: '$h:${t.minute.toString().padLeft(2, '0')}', ampm: t.hour < 12 ? 'am' : 'pm');
}

String timeText(DateTime t) {
  final p = timeParts(t);
  return '${p.hm} ${p.ampm}';
}

/// "in 3 h 49 min", "in 12 min", "now".
String untilText(Duration d) {
  if (d.inMinutes <= 0) return 'now';
  if (d.inMinutes < 60) return 'in ${d.inMinutes} min';
  final h = d.inHours, m = d.inMinutes % 60;
  return m == 0 ? 'in $h h' : 'in $h h $m min';
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String dateText(DateTime d) => '${_wd[d.weekday - 1]}, ${d.day} ${_mo[d.month - 1]}';

String dayName(DateTime d, DateTime now) {
  final a = DateTime(d.year, d.month, d.day), b = DateTime(now.year, now.month, now.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return _wd[d.weekday - 1];
}

/// "every day", "weekdays", "Mon, Wed, Fri".
String daysText(int mask) {
  if (mask == 127) return 'every day';
  if (mask == 31) return 'weekdays';
  if (mask == 96) return 'weekends';
  return [for (var i = 0; i < 7; i++) if (mask & (1 << i) != 0) _wd[i]].join(', ');
}
