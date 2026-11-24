// Rappels de l'agenda : une phrase, un jour, une heure. Pas un créneau : un repère à l'heure dite,
// qu'on coche quand c'est fait. « Préparer la tablette dimanche 11h » se range tout seul.
import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

const rappelColor = Color(0xFF0D9488);

const _l = r'(?<![a-zà-ÿ0-9])'; // pas au milieu d'un mot
const _r = r'(?![a-zà-ÿ0-9])';
const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _months = [
  'janvier', 'f[ée]vrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'ao[ûu]t',
  'septembre', 'octobre', 'novembre', 'd[ée]cembre'
];

RegExp _re(String s) => RegExp(s, caseSensitive: false);

/// « préparer la tablette dimanche 11h » → le texte sans la date, le jour, l'heure (minutes).
/// Ce qui n'est pas dit reste null.
({String text, DateTime? day, int? minutes}) parseReminder(String said, [DateTime? at]) {
  final now = at ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime plus(int d) => DateTime(today.year, today.month, today.day + d);
  var s = ' ${said.trim()} ';
  int? minutes;
  DateTime? day;
  RegExpMatch? take(String pattern) {
    final m = _re(pattern).firstMatch(s);
    if (m != null) s = '${s.substring(0, m.start)} ${s.substring(m.end)}';
    return m;
  }

  // L'heure : « 11h », « 11 h 30 », « 11 heures », « 11:30 », « midi ».
  var m = take('$_l(?:[àa] |vers |pour )?(\\d{1,2}) ?(?:heures?|h|:) ?(\\d{2})?$_r');
  if (m != null) {
    final h = int.parse(m[1]!), mn = int.parse(m[2] ?? '0');
    if (h < 24 && mn < 60) minutes = h * 60 + mn;
  } else if (take('$_l(?:[àa] |vers |pour )?midi$_r') != null) {
    minutes = 12 * 60;
  }

  // Le jour.
  if (take("$_l(?:apr[èe]s[- ]demain)$_r") != null) {
    day = plus(2);
  } else if (take('${_l}demain(?: matin| soir| apr[èe]s[- ]midi)?$_r') != null) {
    day = plus(1);
  } else if (take('${_l}ce soir$_r') != null) {
    day = today;
    minutes ??= 20 * 60;
  } else if (take("${_l}(?:aujourd['’]hui|ce matin|cet apr[èe]s[- ]midi|tout [àa] l['’]heure)$_r") != null) {
    day = today;
  } else if ((m = take('$_l(?:le |pour )?(${_days.join('|')})( prochain)?$_r')) != null) {
    var d = (_days.indexOf(m![1]!.toLowerCase()) + 1 - today.weekday) % 7;
    final passed = minutes != null && minutes <= now.hour * 60 + now.minute;
    if (d == 0 && (m[2] != null || passed)) d = 7;
    day = plus(d);
  } else if ((m = take('$_l(?:le )?(\\d{1,2})(?:er)? (${_months.join('|')})$_r')) != null) {
    final mo = _months.indexWhere((x) => _re('^$x\$').hasMatch(m![2]!)) + 1;
    day = DateTime(today.year, mo, int.parse(m![1]!));
    if (day.isBefore(today)) day = DateTime(today.year + 1, mo, day.day);
  } else if ((m = take('$_l(?:le )?(\\d{1,2})/(\\d{1,2})$_r')) != null) {
    day = DateTime(today.year, int.parse(m![2]!), int.parse(m[1]!));
    if (day.isBefore(today)) day = DateTime(today.year + 1, day.month, day.day);
  } else if ((m = take('${_l}le (\\d{1,2})(?:er)?$_r')) != null) {
    day = DateTime(today.year, today.month, int.parse(m![1]!));
    if (day.isBefore(today)) day = DateTime(today.year, today.month + 1, day.day);
  }

  final text = s
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(_re(r"(?:[\s,;:.-]|(?<![a-zà-ÿ])(?:à|a|le|pour|vers))+$"), '')
      .replaceFirst(_re(r"^(?:de |d['’])"), '')
      .trim();
  return (text: cap(text), day: day, minutes: minutes);
}

/// Heure proposée quand la phrase n'en dit pas : la prochaine heure pleine aujourd'hui, 9 h sinon.
int defaultReminderTime(DateTime day, [DateTime? at]) {
  final now = at ?? DateTime.now();
  if (ymd(day) != ymd(now)) return 9 * 60;
  return ((now.hour + 1).clamp(0, 23)) * 60;
}

/// « dimanche 29 novembre à 11 h », avec aujourd'hui et demain dits simplement.
String reminderWhen(DateTime day, int minutes) {
  final now = DateTime.now();
  final d = ymd(day);
  final name = d == ymd(now)
      ? 'aujourd\'hui'
      : d == ymd(DateTime(now.year, now.month, now.day + 1))
          ? 'demain'
          : longDate(day).toLowerCase();
  return '$name à ${hm(minutes)}';
}

void openReminder(BuildContext context, {Map<String, dynamic>? event, DateTime? day}) =>
    sheet(context, ReminderSheet(event: event, day: day));

class ReminderSheet extends StatefulWidget {
  final Map<String, dynamic>? event;
  final DateTime? day;
  const ReminderSheet({this.event, this.day, super.key});
  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  late final text = TextEditingController(text: '${widget.event?['label'] ?? ''}');
  late DateTime day;
  late int minutes;
  bool dayPicked = false, timePicked = false; // choisi à la main : la phrase ne le change plus

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    final now = DateTime.now();
    day = e != null ? dateOf('${e['date']}') : (widget.day ?? DateTime(now.year, now.month, now.day));
    minutes = e != null ? (e['start'] as num).toInt() : defaultReminderTime(day);
  }

  void typed(String _) {
    final r = parseReminder(text.text);
    setState(() {
      if (r.day != null && !dayPicked) {
        day = r.day!;
        if (r.minutes == null && !timePicked && widget.event == null) {
          minutes = defaultReminderTime(day);
        }
      }
      if (r.minutes != null && !timePicked) minutes = r.minutes!;
    });
  }

  Future<void> pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: day,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 3));
    if (d != null) {
      setState(() {
        day = d;
        dayPicked = true;
      });
    }
  }

  Future<void> pickTime() async {
    final t = await showTimePicker(
        context: context,
        helpText: 'Heure du rappel',
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    if (t != null) {
      setState(() {
        minutes = t.hour * 60 + t.minute;
        timePicked = true;
      });
    }
  }

  void save() {
    final label = parseReminder(text.text).text;
    if (label.isEmpty) return;
    store.saveReminder(widget.event, label, day, minutes);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('Rappel ${reminderWhen(day, minutes)} : $label'),
          duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final e = widget.event;
    Widget chip(IconData icon, String label, VoidCallback onTap, {int flex = 2}) => Expanded(
          flex: flex,
          child: OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 19, color: rappelColor),
              label: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, color: p.ink)),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                  side: BorderSide(color: p.line, width: 1.5))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        const Icon(Icons.notifications_active_rounded, color: rappelColor, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Text(e == null ? 'Nouveau rappel' : 'Rappel',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ),
        if (e != null)
          IconButton(
              tooltip: 'Supprimer',
              onPressed: () {
                store.removeReminder(e);
                Navigator.pop(context);
              },
              icon: Icon(Icons.delete_outline_rounded, color: prioColors[0])),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: text,
        autofocus: e == null,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: typed,
        onSubmitted: (_) => save(),
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(
            hintText: 'Préparer la tablette dimanche 11h', hintStyle: TextStyle(color: p.sub)),
      ),
      const SizedBox(height: 6),
      Text('Écris le jour et l\'heure dans la phrase, ou choisis-les ici.',
          style: TextStyle(fontSize: 13, color: p.sub)),
      const SizedBox(height: 12),
      Row(children: [
        chip(Icons.event_rounded,
            '${cap(dayNames[day.weekday - 1].substring(0, 3))}. ${day.day} ${monthNames[day.month - 1]}', pickDay, flex: 3),
        const SizedBox(width: 10),
        chip(Icons.schedule_rounded, hm(minutes), pickTime),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        if (e != null) ...[
          Expanded(
            child: OutlinedButton(
                onPressed: () {
                  store.toggleReminder(e);
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(e['done'] == true ? 'À refaire' : 'C\'est fait',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton(
            onPressed: text.text.trim().isEmpty ? null : save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ]),
    ]);
  }
}

/// Dans Maintenant : les rappels du jour, et ceux d'avant restés sans coche.
class RemindersPanel extends StatelessWidget {
  const RemindersPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = store.remindersNow;
    if (list.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = ymd(now), m = now.hour * 60 + now.minute;
    return Panel(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      header: PanelHead('Rappels',
          icon: Icons.notifications_active_rounded,
          color: rappelColor,
          count: '${list.where((e) => e['done'] != true).length}'),
      children: [
        for (final e in list)
          () {
            final done = e['done'] == true;
            final start = (e['start'] as num).toInt();
            final overdue = !done && (e['date'] != today || start <= m);
            final d = dateOf('${e['date']}');
            final when = e['date'] == today
                ? hm(start)
                : '${dayNames[d.weekday - 1].substring(0, 3)}. ${d.day}/${d.month} · ${hm(start)}';
            return InkWell(
              onTap: () => openReminder(context, event: e),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 14, 2),
                child: Row(children: [
                  IconButton(
                      tooltip: done ? 'À refaire' : 'C\'est fait',
                      onPressed: () => store.toggleReminder(e),
                      icon: Icon(done ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: done ? rappelColor : p.sub)),
                  Expanded(
                    child: Text('${e['label']}',
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: done ? p.sub : p.ink,
                            decoration: done ? TextDecoration.lineThrough : null)),
                  ),
                  const SizedBox(width: 8),
                  Text(when,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: overdue ? prioColors[0] : p.sub)),
                ]),
              ),
            );
          }(),
      ],
    );
  }
}
