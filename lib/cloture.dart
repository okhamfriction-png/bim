// Clôture d'un sprint, en trois écrans : ce qui est terminé, le sort de chaque tâche qui ne
// l'est pas, puis le bilan. À la validation, le bilan est figé dans l'agenda (schedule.closures).
import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

String sprintRange(String s) {
  final m = dateOf(s);
  final sun = DateTime(m.year, m.month, m.day + 6);
  return m.month == sun.month
      ? '${m.day} au ${sun.day} ${monthNames[sun.month - 1]}'
      : '${m.day} ${monthNames[m.month - 1]} au ${sun.day} ${monthNames[sun.month - 1]}';
}

String _when(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${monthNames[d.month - 1]} à ${d.hour} h ${d.minute.toString().padLeft(2, '0')}';
}

String _pts(int n) => '$n pt${n > 1 ? 's' : ''}';

void openClose(BuildContext context, String sprint) => Navigator.of(context)
    .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ClosePage(sprint)));

const _choices = <String, (String, IconData, Color)>{
  'report': ('Reporter au sprint suivant', Icons.redo_rounded, Color(0xFF0EA5E9)),
  'parking': ('Parking', Icons.local_parking_rounded, Color(0xFF94A3B8)),
  'drop': ('Abandonner', Icons.block_rounded, Color(0xFFEF4444)),
};

class ClosePage extends StatefulWidget {
  final String sprint;
  const ClosePage(this.sprint, {super.key});
  @override
  State<ClosePage> createState() => _ClosePageState();
}

class _ClosePageState extends State<ClosePage> {
  int step = 0;
  final choices = <String, String>{}; // tâche → report | parking | drop
  final prios = <String, int>{}; // priorité choisie pour une tâche reportée
  final results = <String, TextEditingController>{};
  final keep = TextEditingController();
  final decisions = TextEditingController();

  String get sp => widget.sprint;

  TextEditingController _result(Task t) =>
      results.putIfAbsent(t.id, () => TextEditingController(text: t.result));

  void validate() {
    store.closeSprint(sp, choices, prios, keep: keep.text, decisions: decisions.text);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sprint du ${sprintRange(sp)} clôturé. '
            'Le sprint du ${sprintRange(store.current)} est en cours.')));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final p = Pal.of(context);
          final done = store.sprintComplete(sp);
          final rest = store.sprintUnfinished(sp);
          final chosen = rest.where((t) => choices.containsKey(t.id)).length;
          final ready = chosen == rest.length;
          const titles = ['Terminé', 'Non terminé', 'Bilan'];
          return Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Clôture · ${titles[step]}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('Sprint du ${sprintRange(sp)} · étape ${step + 1} sur 3',
                    style: TextStyle(fontSize: 12.5, color: p.sub)),
              ]),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                    child: Row(children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Container(
                            height: 5,
                            margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                            decoration: BoxDecoration(
                                color: i <= step ? p.accent : p.line,
                                borderRadius: BorderRadius.circular(99)),
                          ),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: ListView(
                        key: ValueKey(step), // chaque étape repart du haut
                        padding: const EdgeInsets.only(bottom: 20),
                        children: [
                      if (step == 0) ..._stepDone(context, done),
                      if (step == 1) ..._stepRest(context, rest, chosen),
                      if (step == 2) ..._stepBilan(context, rest),
                    ]),
                  ),
                  Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: SafeArea(
                      top: false,
                      child: Row(children: [
                        if (step > 0)
                          OutlinedButton(
                              onPressed: () => setState(() => step--),
                              child: const Text('Retour')),
                        const Spacer(),
                        if (step == 1 && !ready)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text('${rest.length - chosen} sans choix',
                                style: TextStyle(
                                    color: prioColors[0], fontWeight: FontWeight.w700)),
                          ),
                        FilledButton(
                          onPressed: step == 2
                              ? (ready ? validate : null)
                              : (step == 1 && !ready ? null : () => setState(() => step++)),
                          style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15)),
                          child: Text(step == 2 ? 'Clôturer le sprint' : 'Suivant',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );

  Widget _hint(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
        child: Text(s, style: TextStyle(color: Pal.of(context).sub, height: 1.35)),
      );

  // ---- 1. Terminé ----

  List<Widget> _stepDone(BuildContext context, List<Task> done) {
    final p = Pal.of(context);
    final total = done.fold(0, (a, t) => a + store.plannedOf(t));
    return [
      _hint(
          context,
          done.isEmpty
              ? 'Aucune tâche terminée dans ce sprint.'
              : '${done.length} tâche${done.length > 1 ? 's' : ''} terminée${done.length > 1 ? 's' : ''}, '
                  '${_pts(total)}. Tu peux encore corriger un résultat.'),
      for (final t in done)
        Panel(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: 10),
                  child: Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 21),
                ),
                Expanded(
                    child: Text(t.title,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                Text(store.plannedOf(t) > 0 ? _pts(store.plannedOf(t)) : 'sans points',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: store.plannedOf(t) > 0 ? p.ink : p.sub)),
              ]),
              if (store.unitsLabel(t).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 31, top: 2),
                  child: Text(store.unitsLabel(t), style: TextStyle(fontSize: 12.5, color: p.sub)),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 31, top: 8),
                child: TextField(
                  controller: _result(t),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (v) {
                    t.result = v.trim();
                    store.touch(t);
                  },
                  decoration: InputDecoration(
                      labelText: 'Résultat', isDense: true, hintStyle: TextStyle(color: p.sub)),
                ),
              ),
            ]),
          ),
        ]),
    ];
  }

  // ---- 2. Non terminé ----

  List<Widget> _stepRest(BuildContext context, List<Task> rest, int chosen) {
    final p = Pal.of(context);
    final next = store.nextSprint(sp);
    return [
      _hint(
          context,
          rest.isEmpty
              ? 'Tout est terminé : rien à décider.'
              : 'Pour chaque tâche, choisis ce qu\'elle devient. Rien n\'est reporté tout seul. '
                  'Sprint suivant : ${sprintRange(next)}. Décidées : $chosen sur ${rest.length}.'),
      for (final t in rest)
        Panel(
          accent: choices.containsKey(t.id) ? null : p.accent,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                      padding: const EdgeInsets.only(top: 2, right: 9),
                      child: PrioChip(prios[t.id] ?? t.priority)),
                  Expanded(
                      child: Text(t.title,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      [
                        t.cat,
                        if (t.subs.isNotEmpty) '${t.subsDone}/${t.subs.length} sous-tâches',
                        if (t.status == 'done') 'cochée, mais il reste des sous-tâches',
                        if (store.plannedOf(t) > 0) '0 sur ${_pts(store.plannedOf(t))}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: p.sub)),
                ),
                if (t.reports >= 2)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                        color: prioColors[0].withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(9)),
                    child: Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: prioColors[0]),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Déjà reportée ${t.reports} fois',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, color: prioColors[0]))),
                    ]),
                  )
                else if (t.reports == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Déjà reportée une fois',
                        style: TextStyle(fontSize: 12.5, color: p.sub)),
                  ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in _choices.entries)
                    Pick(c.value.$1, choices[t.id] == c.key, () => setState(() {
                          choices[t.id] = c.key;
                          if (c.key != 'report') prios.remove(t.id);
                        }), color: c.value.$3, icon: c.value.$2),
                ]),
                if (choices[t.id] == 'report')
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(children: [
                      Text('Priorité', style: TextStyle(fontSize: 12.5, color: p.sub)),
                      const SizedBox(width: 10),
                      for (var i = 0; i <= 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => prios[t.id] = i),
                            child: Opacity(
                                opacity: (prios[t.id] ?? t.priority) == i ? 1 : .35,
                                child: PrioChip(i)),
                          ),
                        ),
                    ]),
                  ),
              ]),
            ),
          ],
        ),
    ];
  }

  // ---- 3. Bilan ----

  List<Widget> _stepBilan(BuildContext context, List<Task> rest) => [
        BilanView(sp, store.closureDraft(sp, choices)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: keep,
            minLines: 2,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Ce que je retiens'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: decisions,
            minLines: 2,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Décisions pour le sprint suivant'),
          ),
        ),
        _hint(context,
            'Une fois le sprint clôturé, ses points et ce bilan sont figés. Le sprint suivant devient le sprint en cours.'),
      ];
}

/// Le bilan chiffré d'un sprint (brouillon avant la clôture, ou bilan figé).
class BilanView extends StatelessWidget {
  final String sprint;
  final Map<String, dynamic> b;
  const BilanView(this.sprint, this.b, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final points = (b['points'] as num).toInt();
    final target = (b['target'] as num).toInt();
    final gap = points - target;
    final byCat = Map<String, dynamic>.from(b['byCat'] as Map);
    int n(String k) => (b[k] as List).length;
    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$points',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 4),
                child: Text('/ ${_pts(target)}',
                    style: TextStyle(fontSize: 16, color: p.sub, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Pill(
                  gap >= 0 ? 'Cible atteinte${gap > 0 ? ' · +$gap' : ''}' : 'Écart  $gap',
                  gap >= 0 ? const Color(0xFF22C55E) : prioColors[0]),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                  value: target == 0 ? 0 : (points / target).clamp(0, 1),
                  minHeight: 7,
                  backgroundColor: p.line,
                  color: gap >= 0 ? const Color(0xFF22C55E) : p.accent),
            ),
          ]),
        ),
      ]),
      Panel(header: const PanelHead('Points par catégorie'), children: [
        for (final c in Store.bilanCats) line(c, _pts((byCat[c] as num? ?? 0).toInt())),
      ]),
      Panel(header: const PanelHead('Tâches'), children: [
        line('Terminées', '${n('done')}', color: const Color(0xFF22C55E)),
        line('Reportées', '${n('carried')}'),
        line('Au parking', '${n('parked')}'),
        line('Abandonnées', '${n('dropped')}', color: n('dropped') > 0 ? prioColors[0] : null),
      ]),
    ]);
  }
}

/// Le dernier sprint clôturé, sous les sprints : son score figé, et de quoi le rouvrir.
class ClosedLine extends StatelessWidget {
  final String sprint;
  const ClosedLine(this.sprint, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final b = store.schedule.closures[sprint]!;
    return Panel(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(children: [
          Icon(Icons.lock_rounded, size: 19, color: p.sub),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sprint du ${sprintRange(sprint)} · clôturé',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                  '${b['points']} / ${_pts((b['target'] as num).toInt())} · le ${_when((b['closedAt'] as num).toInt())}',
                  style: TextStyle(fontSize: 12.5, color: p.sub)),
            ]),
          ),
          TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                          title: const Text('Rouvrir ce sprint ?'),
                          content: const Text(
                              'Son bilan ne sera plus figé et il faudra le clôturer à nouveau. '
                              'Les tâches reportées, mises au parking ou abandonnées restent où elles sont.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Laisser clôturé')),
                            FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Rouvrir')),
                          ],
                        ));
                if (ok == true) store.reopenSprint(sprint);
              },
              child: const Text('Rouvrir')),
        ]),
      ),
    ]);
  }
}
