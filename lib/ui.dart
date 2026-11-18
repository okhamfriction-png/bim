import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

/// Palette claire et sombre.
class Pal {
  final Color bg, card, ink, sub, line, accent, onAccent;
  const Pal(this.bg, this.card, this.ink, this.sub, this.line, this.accent, this.onAccent);

  static const light = Pal(Color(0xFFFAF6EE), Color(0xFFFFFFFF), Color(0xFF1C1917),
      Color(0xFF78716C), Color(0xFFE9E1D4), Color(0xFFFFB000), Color(0xFF1C1917));
  static const dark = Pal(Color(0xFF141210), Color(0xFF211D1A), Color(0xFFF5F0E8),
      Color(0xFFA8A29E), Color(0xFF342F2A), Color(0xFFFFB627), Color(0xFF1C1917));

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

const prioColors = [Color(0xFFEF4444), Color(0xFFF97316), Color(0xFF3B82F6), Color(0xFF94A3B8)];
const prioNames = ['Échéance', 'Urgent', 'Important', 'Quand je peux'];

const domains = <String, Color>{
  'Travail': Color(0xFF3B82F6),
  'Contenu': Color(0xFFF59E0B),
  'Destiny': Color(0xFFA855F7),
  'Projets': Color(0xFF14B8A6),
  'Sport': Color(0xFF22C55E),
  'Famille': Color(0xFFEC4899),
  'Perso': Color(0xFF84CC16),
};

Color domainOf(String d) => domains[d] ?? const Color(0xFF94A3B8);

const dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const dayNames = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const monthNames = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
  'septembre', 'octobre', 'novembre', 'décembre'
];

String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String longDate(DateTime d) =>
    '${cap(dayNames[d.weekday - 1])} ${d.day} ${monthNames[d.month - 1]}';
String hm(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String dur(int minutes) {
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return m == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

String dueLabel(String due) {
  final p = due.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  final n = DateTime.now();
  final diff = d.difference(DateTime(n.year, n.month, n.day)).inDays;
  if (diff < 0) return 'en retard';
  if (diff == 0) return 'aujourd\'hui';
  if (diff == 1) return 'demain';
  return '${d.day} ${monthNames[d.month - 1]}';
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color.lerp(color, Pal.of(context).ink, .35))),
      );
}

class Pick extends StatelessWidget {
  final String label;
  final bool on;
  final Color? color;
  final VoidCallback onTap;
  const Pick(this.label, this.on, this.onTap, {this.color, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = color ?? p.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? c.withValues(alpha: .2) : Colors.transparent,
          border: Border.all(color: on ? c : p.line, width: 1.5),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label,
            style: TextStyle(
                fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: p.ink)),
      ),
    );
  }
}

Future<T?> sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).card,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), child: child)),
      ),
    );

Widget _label(BuildContext c, String s) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(s,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: Pal.of(c).sub)),
    );

/// Création ou modification d'une tâche.
class TaskSheet extends StatefulWidget {
  final Task? task;
  const TaskSheet({this.task, super.key});
  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late final title = TextEditingController(text: widget.task?.title ?? '');
  late final note = TextEditingController(text: widget.task?.note ?? '');
  late int priority = widget.task?.priority ?? 2;
  late String domain = widget.task?.domain ?? 'Perso';
  late String? due = widget.task?.due;
  late List<int> days = [...?widget.task?.days];
  late bool more = widget.task != null;

  void save() {
    final s = title.text.trim();
    if (s.isEmpty) return;
    final t = widget.task;
    if (t == null) {
      store.add(Task(
          title: s,
          note: note.text.trim(),
          priority: priority,
          domain: domain,
          due: due,
          days: days));
    } else {
      t
        ..title = s
        ..note = note.text.trim()
        ..priority = priority
        ..domain = domain
        ..due = due
        ..days = days;
      store.touch(t);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.task;
    final today = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: title,
        autofocus: t == null,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
            hintText: 'Quoi faire ?', border: InputBorder.none, hintStyle: TextStyle(color: p.sub)),
        onSubmitted: (_) => save(),
      ),
      if (t != null && t.source.isNotEmpty)
        Text('Ajoutée par ${t.source}', style: TextStyle(color: p.sub, fontSize: 13)),
      _label(context, 'PRIORITÉ'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 1; i <= 3; i++)
          Pick(prioNames[i], priority == i, () => setState(() => priority = i),
              color: prioColors[i]),
      ]),
      _label(context, 'DOMAINE'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in domains.entries)
          Pick(d.key, domain == d.key, () => setState(() => domain = d.key), color: d.value),
      ]),
      if (!more)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextButton(
              onPressed: () => setState(() => more = true),
              child: const Text('Note, échéance, répétition…')),
        ),
      if (more) ...[
        _label(context, 'NOTE'),
        TextField(
          controller: note,
          minLines: 1,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              hintText: 'Détail, lien, contexte', isDense: true, hintStyle: TextStyle(color: p.sub)),
        ),
        _label(context, 'ÉCHÉANCE'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pick('Aucune', due == null, () => setState(() => due = null)),
          Pick('Aujourd\'hui', due == ymd(today), () => setState(() => due = ymd(today))),
          Pick('Demain', due == ymd(today.add(const Duration(days: 1))),
              () => setState(() => due = ymd(today.add(const Duration(days: 1))))),
          Pick(
              due != null && dueLabel(due!) != 'aujourd\'hui' && dueLabel(due!) != 'demain'
                  ? cap(dueLabel(due!))
                  : 'Choisir…',
              due != null && dueLabel(due!) != 'aujourd\'hui' && dueLabel(due!) != 'demain',
              () async {
            final d = await showDatePicker(
                context: context,
                firstDate: today.subtract(const Duration(days: 30)),
                lastDate: today.add(const Duration(days: 730)),
                initialDate: today);
            if (d != null) setState(() => due = ymd(d));
          }),
        ]),
        _label(context, 'REVIENT CHAQUE'),
        Wrap(spacing: 8, children: [
          for (var i = 1; i <= 7; i++)
            Pick(dayLetters[i - 1], days.contains(i),
                () => setState(() => days.contains(i) ? days.remove(i) : days.add(i))),
        ]),
      ],
      const SizedBox(height: 22),
      Row(children: [
        if (t != null)
          IconButton(
              tooltip: 'Supprimer',
              onPressed: () {
                store.remove(t);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline)),
        if (t != null && (t.status == 'done' || t.doneOn(today)))
          TextButton(
              onPressed: () {
                store.reopen(t);
                Navigator.pop(context);
              },
              child: const Text('Remettre à faire')),
        const Spacer(),
        FilledButton(
            onPressed: save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
            child: Text(t == null ? 'Ajouter' : 'Enregistrer',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      ]),
    ]);
  }
}

/// Reporter une tâche.
class SnoozeSheet extends StatelessWidget {
  final Task task;
  const SnoozeSheet(this.task, {super.key});
  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final tomorrow = DateTime(n.year, n.month, n.day + 1, 6);
    final opts = <(String, DateTime)>[
      ('Dans 1 heure', n.add(const Duration(hours: 1))),
      if (n.hour < 13) ('Cet après-midi', DateTime(n.year, n.month, n.day, 14)),
      if (n.hour < 19) ('Ce soir', DateTime(n.year, n.month, n.day, 20)),
      ('Demain', tomorrow),
      ('Lundi prochain', DateTime(n.year, n.month, n.day + (8 - n.weekday), 6)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('Elle revient quand ?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      for (final o in opts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(o.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            store.snooze(task, o.$2);
            Navigator.pop(context);
          },
        ),
    ]);
  }
}

/// Réglages de synchro GitHub.
class SyncSheet extends StatefulWidget {
  const SyncSheet({super.key});
  @override
  State<SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<SyncSheet> {
  late final repo = TextEditingController(text: store.repo);
  late final token = TextEditingController(text: store.token);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Synchronisation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
            'Le backlog vit dans un fichier d\'un dépôt GitHub privé. Le téléphone, le web et tes sessions Claude lisent et écrivent le même.',
            style: TextStyle(color: p.sub)),
        const SizedBox(height: 14),
        TextField(
            controller: repo,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Dépôt', hintText: 'compte/bim-data')),
        const SizedBox(height: 10),
        TextField(
            controller: token,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Jeton d\'accès GitHub')),
        const SizedBox(height: 14),
        Text(
            switch (store.syncState) {
              'ok' => 'Synchronisé',
              'sync' => 'Synchronisation…',
              'error' => store.syncError,
              _ => 'Pas encore relié : les tâches restent sur cet appareil.',
            },
            style: TextStyle(
                color: store.syncState == 'error' ? prioColors[0] : p.sub,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        FilledButton(
            onPressed: () => store.setLink(repo.text, token.text),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Relier et synchroniser',
                style: TextStyle(fontWeight: FontWeight.w800))),
      ]),
    );
  }
}
