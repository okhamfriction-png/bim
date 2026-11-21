import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

DateTime _day(DateTime d, [int plus = 0]) => DateTime(d.year, d.month, d.day + plus);

const _statusNames = {
  'tenu': 'Tenu',
  'manque': 'Manqué',
  'ouvert': 'Maintenant',
  'attente': 'À venir',
  'hors': 'Non compté',
};
const _statusColors = {
  'tenu': Color(0xFF22C55E),
  'manque': Color(0xFFEF4444),
  'ouvert': Color(0xFFF97316),
  'attente': Color(0xFF94A3B8),
  'hors': Color(0xFF94A3B8),
};

/// La date ponctuelle du jour qui attend encore l'heure de fin de son bloc.
Map<String, dynamic>? _cutToAsk(DateTime now) {
  final m = now.hour * 60 + now.minute;
  final occs = store.schedule.occs(now);
  for (final e in store.schedule.eventsOn(now)) {
    if (e['cutEnd'] != null) continue;
    if (occs.any((o) => o.block.id == e['blockId'] && o.end > m)) return e;
  }
  return null;
}

Future<void> _askCut(BuildContext context, Map<String, dynamic> e) async {
  final b = store.schedule.blocks.where((b) => b.id == e['blockId']).firstOrNull;
  final init = b?.end ?? 18 * 60;
  final t = await showTimePicker(
      context: context,
      helpText: 'Fin du bloc ce jour-là',
      initialTime: TimeOfDay(hour: init ~/ 60, minute: init % 60));
  if (t != null) store.setCut(e, t.hour * 60 + t.minute);
}

/// Question posée les jours de date ponctuelle : à quelle heure le bloc s'arrête.
class _CutAsk extends StatelessWidget {
  final Map<String, dynamic> event;
  const _CutAsk(this.event);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final b = store.schedule.blocks.where((b) => b.id == event['blockId']).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
          color: p.accent.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.accent)),
      child: Row(children: [
        Expanded(
          child: Text(
              '${event['label']} à ${hm((event['start'] as num).toInt())}. '
              'À quelle heure s\'arrête ${b?.label ?? 'le bloc'} ?',
              style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: () => _askCut(context, event), child: const Text('Choisir')),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Maintenant

class NowScreen extends StatefulWidget {
  const NowScreen({super.key});
  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen> {
  bool bim = false;

  void done(Task t) {
    HapticFeedback.mediumImpact();
    store.complete(t);
    cheer();
  }

  void cheer() {
    setState(() => bim = true);
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => bim = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    final s = store.schedule;
    final occs = s.occs(now);
    final cur = occs.where((o) => o.start <= m && m < o.end).firstOrNull;
    final (held, planned) = s.count(Schedule.mondayOf(now));
    final ask = _cutToAsk(now);

    // Ligne d'agenda : le bloc en cours, sinon le prochain.
    final st = cur == null ? null : s.statusOf(cur);
    final nxt = occs.where((o) => o.start > m).firstOrNull;
    final agenda = [
      if (cur != null)
        '${cur.block.label} jusqu\'à ${hm(cur.end)}'
      else if (nxt != null)
        '${nxt.block.label} à ${hm(nxt.start)}, dans ${dur(nxt.start - m)}',
      for (final e in s.eventsOn(now)) '${e['label']} à ${hm((e['start'] as num).toInt())}',
    ].join('  ·  ');
    final review = now.weekday == 7 && s.reviewedOn != ymd(now);

    // La tâche en gros plan, puis le reste du sprint par priorité.
    final queue = store.queue;
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: w);

    return LayoutBuilder(
      builder: (context, box) => ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        // Où j'en suis : la date, le compte des blocs, la ligne d'agenda.
        Panel(margin: const EdgeInsets.fromLTRB(16, 2, 16, 6), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            child: Row(children: [
              Expanded(
                  child: Text(longDate(now),
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800, color: p.ink))),
              if (planned > 0)
                Pill('Blocs tenus  $held / $planned', _statusColors['tenu']!,
                    icon: Icons.check_circle_rounded),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
            child: Row(children: [
              Icon(Icons.emoji_events_rounded, size: 19, color: p.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Score  ${store.weekScore} pts',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  style: TextStyle(fontSize: 14.5, color: p.ink),
                ),
              ),
              if (store.sprintGrade != null)
                Pill('Sprint  ${store.sprintGrade} / 100', p.accent),
            ]),
          ),
          if (store.sprints.contains(store.thisMonday) || store.valueWeek > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.stars_rounded, size: 19, color: _statusColors['tenu']),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                        'Valeur  ${store.valueWeek} / ${store.targetOf(store.thisMonday)} pts',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800, color: p.ink)),
                  ),
                  Text('+${store.valueToday} aujourd\'hui',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700, color: p.sub)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                      value: store.targetOf(store.thisMonday) == 0
                          ? 0
                          : (store.valueWeek / store.targetOf(store.thisMonday)).clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: p.line,
                      color: _statusColors['tenu']),
                ),
                const SizedBox(height: 8),
                const BonusRow(),
              ]),
            ),
          if (agenda.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
              child: Row(children: [
                Icon(cur != null ? Icons.lock_clock_rounded : Icons.schedule,
                    size: 19, color: cur != null ? _statusColors[st] : p.sub),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(agenda,
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink))),
                if (st == 'ouvert')
                  FilledButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        store.check(cur!);
                      },
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 16)),
                      child: const Text('J\'y suis',
                          style: TextStyle(fontWeight: FontWeight.w900)))
                else if (st == 'tenu' || st == 'manque')
                  Pill(_statusNames[st]!, _statusColors[st]!),
              ]),
            ),
        ]),
        if (ask != null) pad(_CutAsk(ask)),
        if (review)
          pad(Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.icon(
                onPressed: () => openReview(context),
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('Faire la revue de la semaine',
                    style: TextStyle(fontWeight: FontWeight.w800))),
          )),
        const SizedBox(height: 8),
        if (queue.isEmpty)
          pad(SizedBox(
              height: (box.maxHeight * .5).clamp(280.0, 460.0),
              child: const _Empty(key: ValueKey('vide'))))
        else
          Panel(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            header: PanelHead('À faire dans le sprint',
                icon: Icons.flag_rounded, color: p.accent, count: '${queue.length}'),
            children: [_DragList(queue, lanes: true)],
          ),
      ]),
    );
  }
}

/// La tâche en gros plan (plus affichée : Maintenant montre la liste du sprint).
// ignore: unused_element
class _Card extends StatelessWidget {
  final Task task;
  final VoidCallback onDone, onSub;
  const _Card({required this.task, required this.onDone, required this.onSub, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = task;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.line),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                    color: const Color(0xFF101828).withValues(alpha: .10),
                    blurRadius: 28,
                    offset: const Offset(0, 10))
              ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 5, color: prioColors[t.priority]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
          child: Row(children: [
            Expanded(
              child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PrioChip(t.priority),
                    Pill(t.cat, domainOf(t.cat), icon: iconOf(t.cat)),
                    if (t.call) Pill('Appel', prioColors[1], icon: Icons.phone_in_talk_rounded),
                    if (store.valueLabel(t).isNotEmpty)
                      Pill(store.valueLabel(t), _statusColors['tenu']!, icon: Icons.stars_rounded),
                  ]),
            ),
            IconButton(
                tooltip: 'Modifier',
                onPressed: () => sheet(context, TaskSheet(task: t)),
                icon: Icon(Icons.edit_outlined, size: 21, color: p.sub)),
          ]),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Column(children: [
                Text(t.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: t.title.length > 60 ? 24 : 31,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.6,
                        color: p.ink)),
                if (t.note.isNotEmpty || t.links.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TaskBody(t,
                        align: t.note.length > 160 ? TextAlign.start : TextAlign.center),
                  ),
                if (t.source.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('via ${t.source}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.sub, fontSize: 13)),
                  ),
              ]),
            ),
          ),
        ),
        if (t.subs.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            decoration: BoxDecoration(
                color: p.soft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('PROCHAINE SOUS-TÂCHE',
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: .6,
                        fontWeight: FontWeight.w800,
                        color: p.sub)),
                const Spacer(),
                SubProgress(t, width: 64),
              ]),
              if (t.nextSub != null)
                SubCheck(t, t.nextSub!, onChanged: onSub)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Toutes cochées.', style: TextStyle(color: p.sub)),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: SizedBox(
            height: 58,
            child: FilledButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.check_rounded, size: 28),
              label: const Text('Terminé',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final none = !store.sprints.contains(store.thisMonday);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.line)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
              color: p.accent.withValues(alpha: .18), shape: BoxShape.circle),
          child: Icon(Icons.flag_rounded, size: 36, color: p.accent),
        ),
        const SizedBox(height: 16),
        Text(none ? 'Pas de sprint cette semaine' : 'Sprint vide',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: p.ink)),
        const SizedBox(height: 6),
        Text(
            none
                ? 'Crée le sprint dans le Backlog et ranges-y tes tâches.'
                : 'Range des tâches dans le sprint depuis le Backlog.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub, fontSize: 15)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Backlog

class BacklogScreen extends StatefulWidget {
  const BacklogScreen({super.key});
  @override
  State<BacklogScreen> createState() => _BacklogScreenState();
}

class _BacklogScreenState extends State<BacklogScreen> {
  String group = 'cat'; // cat | source
  String addCat = 'Mission';
  int addPrio = 2;
  final quick = TextEditingController();
  final focus = FocusNode();

  void add() {
    final s = quick.text.trim();
    if (s.isEmpty) return;
    store.add(Task(title: s, domain: addCat, priority: addPrio));
    quick.clear();
    focus.requestFocus();
  }

  Widget sprintBox(BuildContext context, String sp) {
    final p = Pal.of(context);
    final current = sp == store.thisMonday;
    final open = store.sprintTasks(sp);
    final done = store.sprintDone(sp);
    final total = open.length + done;
    return Panel(
      accent: current ? p.accent : null,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelHead(
          current ? 'Sprint en cours' : 'Sprint à venir',
          icon: Icons.flag_rounded,
          color: current ? Color.lerp(p.accent, p.ink, .25) : p.sub,
          subtitle: cap(_range(dateOf(sp))),
          count: total == 0 ? '0' : '$done / $total',
        ),
        if (total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 9, right: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                  value: done / total,
                  minHeight: 5,
                  backgroundColor: p.line,
                  color: _statusColors['tenu']),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              'Prévu ${store.plannedIn(sp)} pts · cible ${store.targetOf(sp)}'
              '${store.plannedIn(sp) < store.targetOf(sp) ? ' · sous la cible' : ''}'
              '${store.p0In(sp) > 3 ? ' · ${store.p0In(sp)} P0 (3 max)' : ''}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: store.plannedIn(sp) < store.targetOf(sp) || store.p0In(sp) > 3
                      ? prioColors[0]
                      : p.sub)),
        ),
      ]),
      children: [
        if (open.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(children: [
              Icon(total > 0 ? Icons.celebration_rounded : Icons.inbox_rounded,
                  color: p.sub, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    total > 0
                        ? 'Tout est fait dans ce sprint.'
                        : 'Vide. Déplie une tâche du backlog et touche « Sprint ».',
                    style: TextStyle(color: p.sub)),
              ),
            ]),
          ),
        _DragList(open, lanes: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final all = store.backlog;
    final done = store.finished;
    final nArch = store.archived.length;
    final todo = all.where((t) => !t.parked).length;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Backlog',
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.5, color: p.ink)),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text('$todo à faire', style: TextStyle(color: p.sub, fontSize: 14.5)),
        ),
      ]),
    );

    final adder = Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line, width: 1.5)),
      child: Row(children: [
        Icon(Icons.add_rounded, color: p.sub),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: quick,
            focusNode: focus,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
                hintText: 'Ajouter une tâche',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintStyle: TextStyle(color: p.sub)),
            onSubmitted: (_) => add(),
          ),
        ),
        PopupMenuButton<int>(
          tooltip: 'Priorité : ${prioNames[addPrio]}',
          initialValue: addPrio,
          onSelected: (v) => setState(() => addPrio = v),
          itemBuilder: (_) => [
            for (var i = 0; i <= 4; i++) PopupMenuItem(value: i, child: PrioChip(i)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: PrioChip(addPrio),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Catégorie : $addCat',
          initialValue: addCat,
          onSelected: (c) => setState(() => addCat = c),
          itemBuilder: (_) => [
            for (final c in cats)
              PopupMenuItem(
                  value: c,
                  child: Row(children: [
                    Icon(iconOf(c), color: domainOf(c), size: 20),
                    const SizedBox(width: 10),
                    Text(c),
                  ])),
          ],
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(iconOf(addCat), color: domainOf(addCat), size: 22),
              Icon(Icons.arrow_drop_down, color: p.sub),
            ]),
          ),
        ),
      ]),
    );

    const mine = 'Ajoutées par moi';
    final loose = all.where((t) => t.parked || store.sprintOf(t) == null).toList();
    final groups = <String, List<Task>>{};
    if (group == 'cat') {
      for (final c in cats) {
        groups[c] = loose.where((t) => t.cat == c).toList();
      }
    } else {
      for (final t in loose) {
        groups.putIfAbsent(t.source.isEmpty ? mine : t.source, () => []).add(t);
      }
    }
    groups.removeWhere((k, v) => v.isEmpty);

    return ListView(children: [
      header,
      adder,
      SectionTitle('SPRINTS',
          trailing: TextButton.icon(
              onPressed: store.createSprint,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nouveau sprint'))),
      if (store.sprints.isEmpty)
        Panel(children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Icon(Icons.flag_outlined, size: 30, color: p.sub),
              const SizedBox(height: 8),
              Text('Aucun sprint. Un sprint dure une semaine, du lundi au dimanche.',
                  textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: store.createSprint,
                  icon: const Icon(Icons.flag_rounded, size: 18),
                  label: const Text('Créer le sprint de cette semaine',
                      style: TextStyle(fontWeight: FontWeight.w800))),
            ]),
          ),
        ]),
      for (final sp in store.sprints) sprintBox(context, sp),
      SectionTitle('HORS SPRINT',
          trailing: Segmented(const {'cat': 'Catégorie', 'source': 'Origine'}, group,
              (v) => setState(() => group = v))),
      if (loose.isEmpty)
        Panel(children: [
          Padding(
            padding: const EdgeInsets.all(22),
            child: Text('Rien hors sprint.',
                textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
          ),
        ]),
      for (final g in groups.entries)
        Panel(
          header: PanelHead(g.key,
              icon: group == 'cat'
                  ? iconOf(g.key)
                  : (g.key == mine ? Icons.person_rounded : Icons.forum_rounded),
              color: group == 'cat' ? domainOf(g.key) : null,
              count: '${g.value.length}'),
          children: [_DragList(g.value)],
        ),
      if (done.isNotEmpty || nArch > 0)
        SectionTitle('TERMINÉ',
            trailing: nArch == 0
                ? null
                : TextButton.icon(
                    onPressed: () => openArchive(context),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text('Archives · $nArch'))),
      if (done.isNotEmpty)
        Panel(
          header: PanelHead('Terminées',
              icon: Icons.check_circle_rounded,
              color: _statusColors['tenu'],
              count: '${done.length}',
              trailing: TextButton.icon(
                  onPressed: () {
                    final n = done.length;
                    store.archiveFinished();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(n == 1 ? '1 tâche archivée.' : '$n tâches archivées.')));
                  },
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Archiver'))),
          children: [for (final t in done) _Tile(t, key: ValueKey('d${t.id}'))],
        ),
      const SizedBox(height: 40),
    ]);
  }
}

/// Ranger une tâche dans un sprint, ou la remettre au backlog.
/// Pour une tâche archivée : la changer de sprint, sprints passés compris.
/// Une liste de tâches qu'on réordonne en restant appuyé sur une ligne puis en la glissant.
/// Avec [lanes], la liste est découpée en couloirs P0 à P4 : déposer une tâche dans un
/// couloir lui donne cette priorité.
class _DragList extends StatelessWidget {
  final List<Task> tasks;
  final bool lanes;
  const _DragList(this.tasks, {this.lanes = false});

  static const laneNames = ['Non négociable', 'Important', 'Si le temps', 'Petite tâche', 'Parking'];

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // Lignes affichées : un en-tête de couloir (tâche nulle) ou une tâche.
    final rows = <(Task?, int)>[
      if (lanes)
        for (var i = 0; i <= 4; i++) ...[
          (null, i),
          for (final t in tasks.where((t) => t.priority == i)) (t, i),
        ]
      else
        for (final t in tasks) (t, t.priority),
    ];
    void drop(int from, int to) {
      final t = rows[from].$1;
      if (t == null) return;
      if (to > from) to--;
      final l = [...rows]..removeAt(from);
      l.insert(to, (t, 0));
      Task? at(int i) => i >= 0 && i < l.length ? l[i].$1 : null;
      if (!lanes) {
        store.moveTask(tasks, tasks.indexOf(t), to);
        return;
      }
      var lane = 0;
      for (var i = to - 1; i >= 0; i--) {
        if (l[i].$1 == null) {
          lane = l[i].$2;
          break;
        }
      }
      store.placeTask(t, lane, at(to - 1), at(to + 1));
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorder: drop,
      proxyDecorator: (child, _, _) => Material(
          color: p.card,
          elevation: 8,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: child),
      itemBuilder: (context, i) {
        final (t, lane) = rows[i];
        if (t == null) {
          final inLane = tasks.where((x) => x.priority == lane);
          return Container(
            key: ValueKey('couloir$lane'),
            decoration: BoxDecoration(
                color: Color.alphaBlend(prioColors[lane].withValues(alpha: .10), p.soft),
                border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(children: [
              PrioChip(lane),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(laneNames[lane],
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub))),
              Text(inLane.isEmpty ? 'vide' : store.lanePoints(inLane),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.sub)),
            ]),
          );
        }
        return ReorderableDelayedDragStartListener(
          key: ValueKey(t.id),
          index: i,
          child: DecoratedBox(
            decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
            child: _Tile(t),
          ),
        );
      },
    );
  }
}

class SprintSheet extends StatelessWidget {
  final Task task;
  const SprintSheet(this.task, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final arch = task.archived;
    final cur = arch ? store.archiveSprint(task) : store.sprintOf(task);
    final list = arch
        ? ({...store.schedule.sprints, cur!}.toList()..sort((a, b) => b.compareTo(a)))
        : store.sprints;
    Widget row(String label, String? value, IconData icon) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: cur == value ? p.accent : p.sub),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: cur == value ? Icon(Icons.check, color: p.accent) : null,
          onTap: () {
            store.setSprint(task, value);
            Navigator.pop(context);
          },
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('Dans quel sprint ?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      for (final sp in list)
        row('${sp == store.thisMonday ? 'Sprint en cours' : 'Sprint'} · ${_range(dateOf(sp))}',
            sp, Icons.flag_rounded),
      if (!arch) row('Backlog, hors sprint', null, Icons.inbox_rounded),
      if (!arch && store.sprints.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Aucun sprint pour l\'instant : crée-en un en haut du Backlog.',
              style: TextStyle(color: p.sub)),
        ),
    ]);
  }
}

/// Une ligne de tâche dans une boîte : icône et couleur de la catégorie,
/// priorité à droite, se déplie au toucher.
class _Tile extends StatefulWidget {
  final Task t;
  const _Tile(this.t, {super.key});
  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.t;
    final struck = t.status == 'done';
    final dim = struck || t.parked;
    final color = domainOf(t.cat);
    final meta = [
      if (store.unitsLabel(t).isNotEmpty) store.unitsLabel(t),
      if (t.call) 'appel ou entretien',
      if (t.pickedToday && !struck) 'aujourd\'hui',
      t.source.isNotEmpty ? 'via ${t.source}' : t.cat,
    ].join(' · ');
    Widget action(String label, IconData icon, VoidCallback? onTap) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            backgroundColor: p.card,
            side: BorderSide(color: p.line),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        icon: Icon(icon, size: 17),
        label: Text(label));
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          child: Opacity(
            opacity: dim && !open ? .55 : 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 2, 9),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(t.call ? Icons.phone_in_talk_rounded : taskIcon(t),
                      color: color, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title,
                        maxLines: open ? null : 2,
                        overflow: open ? null : TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15.5,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: p.ink,
                            decoration: struck ? TextDecoration.lineThrough : null)),
                    const SizedBox(height: 3),
                    Row(children: [
                      if (t.pickedToday && !struck)
                        Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.today_rounded, size: 14, color: p.accent)),
                      if (t.note.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.notes_rounded, size: 14, color: p.sub)),
                      if (t.links.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.play_circle_outline, size: 14, color: p.sub)),
                      Expanded(
                        child: Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: p.sub)),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                if (t.subs.isNotEmpty && store.valueLabel(t).isEmpty)
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SubProgress(t, width: 34)),
                if (store.pointsLabel(t).isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                        color: _statusColors['tenu']!.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(store.pointsLabel(t),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color.lerp(_statusColors['tenu'], p.ink, .25))),
                  ),
                PrioChip(t.priority),
                IconButton(
                  tooltip: struck ? 'Remettre à faire' : 'Terminé',
                  onPressed: struck
                      ? () => store.reopen(t)
                      : () {
                          HapticFeedback.lightImpact();
                          store.complete(t);
                        },
                  icon: Icon(struck ? Icons.check_circle : Icons.circle_outlined,
                      color: struck ? _statusColors['tenu'] : p.sub, size: 26),
                ),
              ]),
            ),
          ),
        ),
        if (open)
          Container(
            decoration: BoxDecoration(
                color: p.soft, border: Border(top: BorderSide(color: p.line))),
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Les cases à cocher d'abord : pas besoin de passer le descriptif pour cocher.
              if (t.subs.isNotEmpty) ...[SubList(t), const SizedBox(height: 12)],
              if (t.note.isEmpty && t.links.isEmpty)
                Text('Pas de descriptif.', style: TextStyle(color: p.sub))
              else
                TaskBody(t),
              const SizedBox(height: 12),
              if (t.subs.isEmpty) ...[SubList(t), const SizedBox(height: 12)],
              Wrap(spacing: 8, runSpacing: 4, children: [
                if (t.open && !t.parked && !t.call)
                  action(
                      t.pickedToday
                          ? 'Retirer du jour'
                          : (store.canPick ? 'Pour aujourd\'hui' : 'Déjà 3 aujourd\'hui'),
                      t.pickedToday ? Icons.remove_circle_outline : Icons.today_rounded,
                      t.pickedToday
                          ? () => store.unpick(t)
                          : (store.canPick ? () => store.pick(t) : null)),
                if (t.open && !t.parked)
                  action(
                      store.sprintOf(t) == null
                          ? 'Sprint'
                          : 'Sprint ${_range(dateOf(store.sprintOf(t)!))}',
                      Icons.flag_rounded,
                      () => sheet(context, SprintSheet(t))),
                if (t.archived)
                  action('Sprint ${_range(dateOf(store.archiveSprint(t)))}', Icons.flag_rounded,
                      () => sheet(context, SprintSheet(t))),
                action('Modifier', Icons.edit_outlined,
                    () => sheet(context, TaskSheet(task: t))),
              ]),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Semaine

class _DayChip extends StatelessWidget {
  final DateTime date;
  final bool on;
  final VoidCallback onTap;
  const _DayChip(this.date, this.on, this.onTap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final today = ymd(date) == ymd(DateTime.now());
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: on ? p.accent.withValues(alpha: .2) : Colors.transparent,
            border: Border.all(color: on ? p.accent : p.line, width: 1.5),
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(dayLetters[date.weekday - 1],
              style: TextStyle(fontSize: 12, color: p.sub, fontWeight: FontWeight.w700)),
          Text('${date.day}',
              style: TextStyle(
                  fontSize: 16,
                  color: p.ink,
                  fontWeight: today ? FontWeight.w900 : FontWeight.w600)),
        ]),
      ),
    );
  }
}

String _range(DateTime monday) {
  final sun = _day(monday, 6);
  return monday.month == sun.month
      ? '${monday.day} – ${sun.day} ${monthNames[sun.month - 1]}'
      : '${monday.day} ${monthNames[monday.month - 1]} – ${sun.day} ${monthNames[sun.month - 1]}';
}

const _kids = Color(0xFFEC4899);
const _solo = Color(0xFF0EA5E9);
bool _isKids(String w) => store.schedule.nameOf(w).toLowerCase().contains('avec');
Color _weekColor(String w) => _isKids(w) ? _kids : _solo;

/// Bandeau qui dit clairement si la semaine est avec ou sans enfants.
class _WeekBadge extends StatelessWidget {
  final DateTime day;
  const _WeekBadge(this.day);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final w = store.schedule.weekOf(day);
    final c = _weekColor(w);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Color.alphaBlend(c.withValues(alpha: .16), p.card),
      child: Row(children: [
        Icon(_isKids(w) ? Icons.family_restroom_rounded : Icons.person_rounded, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Semaine ${store.schedule.nameOf(w).toLowerCase()}',
              style: TextStyle(
                  fontSize: 16.5, fontWeight: FontWeight.w900, color: Color.lerp(c, p.ink, .45))),
        ),
      ]),
    );
  }
}

/// Légende des deux couleurs de semaine.
class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget item(String w) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: _weekColor(w).withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: _weekColor(w), width: 1.5))),
          const SizedBox(width: 7),
          Text(store.schedule.nameOf(w),
              style: TextStyle(fontWeight: FontWeight.w800, color: p.ink)),
        ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(spacing: 18, runSpacing: 6, children: [item('a'), item('b')]),
    );
  }
}

/// Un mois en grille : chaque ligne de semaine est teintée avec ou sans enfants.
class _MonthGrid extends StatelessWidget {
  final int year, month;
  final bool big;
  final void Function(DateTime) onDay;
  const _MonthGrid(this.year, this.month, {required this.big, required this.onDay});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = store.schedule;
    final today = ymd(DateTime.now());
    final rows = <Widget>[];
    for (var m = Schedule.mondayOf(DateTime(year, month, 1));
        m.isBefore(DateTime(year, month + 1, 1));
        m = _day(m, 7)) {
      final c = _weekColor(s.weekOf(m));
      rows.add(Container(
        margin: EdgeInsets.symmetric(vertical: big ? 2.5 : 1),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .2), borderRadius: BorderRadius.circular(big ? 10 : 5)),
        child: Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(builder: (context) {
                final d = _day(m, i);
                if (d.month != month) return SizedBox(height: big ? 52 : 19);
                final isToday = ymd(d) == today;
                final event = s.eventsOn(d).isNotEmpty;
                final n = big ? s.occs(d).length : 0;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onDay(d),
                  child: SizedBox(
                    height: big ? 52 : 19,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: big ? 7 : 3, vertical: big ? 2 : 0),
                        decoration: BoxDecoration(
                            color: isToday ? p.ink : (event ? p.accent : null),
                            borderRadius: BorderRadius.circular(99)),
                        child: Text('${d.day}',
                            style: TextStyle(
                                fontSize: big ? 15 : 10.5,
                                fontWeight: isToday || event ? FontWeight.w900 : FontWeight.w600,
                                color: isToday ? p.bg : (event ? p.onAccent : p.ink))),
                      ),
                      if (big)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            for (var k = 0; k < n.clamp(0, 3); k++)
                              Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  decoration: BoxDecoration(
                                      color: Color.lerp(c, p.ink, .4), shape: BoxShape.circle)),
                            if (n == 0) const SizedBox(height: 5),
                          ]),
                        ),
                    ]),
                  ),
                );
              }),
            ),
        ]),
      ));
    }
    return Column(children: [
      if (big)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            for (final l in dayLetters)
              Expanded(
                  child: Text(l,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: p.sub))),
          ]),
        ),
      ...rows,
    ]);
  }
}

const _blockColors = [
  Color(0xFFF97316),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFF2563EB),
  Color(0xFF0D9488),
];
Color _blockColor(String label) =>
    _blockColors[label.codeUnits.fold<int>(0, (a, b) => a + b) % _blockColors.length];

/// L'icône d'un bloc, d'après son nom.
IconData _blockIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('sport')) return Icons.fitness_center_rounded;
  if (l.contains('rue')) return Icons.record_voice_over_rounded;
  if (l.contains('répét') || l.contains('repet') || l.contains('destiny')) {
    return Icons.theater_comedy_rounded;
  }
  if (l.contains('écri') || l.contains('ecri')) return Icons.edit_rounded;
  if (l.contains('vidéo') || l.contains('video') || l.contains('montage')) {
    return Icons.videocam_rounded;
  }
  if (l.contains('lecture')) return Icons.menu_book_rounded;
  return Icons.event_rounded;
}

/// Grille horaire façon agenda : les jours en colonnes, les heures en lignes,
/// les blocs en rectangles de couleur placés à leur heure.
class _TimeGrid extends StatelessWidget {
  final List<DateTime> days;
  final void Function(DateTime) onDay;
  final double? height; // hauteur disponible : la grille s'y ajuste pour tout montrer
  const _TimeGrid(this.days, {required this.onDay, this.height});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = store.schedule;
    final wide = days.length == 1;
    final now = DateTime.now();
    final today = ymd(now);

    // Plage d'heures affichée : au moins 8 h – 20 h, élargie à ce qui est prévu.
    var lo = 8 * 60, hi = 20 * 60;
    for (final d in days) {
      for (final o in s.occs(d)) {
        if (o.start < lo) lo = o.start;
        if (o.end > hi) hi = o.end;
      }
      for (final e in s.eventsOn(d)) {
        final st = (e['start'] as num).toInt();
        if (st < lo) lo = st;
        if (st + 90 > hi) hi = st + 90;
      }
      for (final h in s.hints(d)) {
        if (h.start < lo) lo = h.start;
        if (h.start + 30 > hi) hi = h.start + 30;
      }
    }
    // L'heure qu'il est doit toujours tomber dans la plage, pour que la ligne bleue soit visible.
    final nowMin = now.hour * 60 + now.minute;
    final showNow = days.any((d) => ymd(d) == today);
    if (showNow) {
      if (nowMin < lo) lo = nowMin;
      if (nowMin + 30 > hi) hi = nowMin + 30;
    }
    const nowBlue = Color(0xFF2563EB);
    final h0 = lo ~/ 60, h1 = ((hi + 59) ~/ 60).clamp(0, 24);
    final hh = height == null
        ? 46.0
        : ((height! - (wide ? 8 : 60)) / (h1 - h0)).clamp(14.0, 80.0);
    final step = hh < 20 ? 2 : 1; // heures trop serrées : une étiquette sur deux
    final total = (h1 - h0) * hh;
    double y(int m) => (m - h0 * 60) / 60 * hh;

    Widget box(String label, Color color, int start, int end,
        {double alpha = 1, IconData? icon, VoidCallback? onTap}) {
      final height = (y(end) - y(start) - 2).clamp(16.0, total);
      final size = wide ? 14.5 : 10.5;
      final tiny = height < 30;
      return Positioned(
        top: y(start) + 1,
        left: 2,
        right: 2,
        height: height,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: wide ? 10 : 3, vertical: tiny ? 1 : (wide ? 6 : 3)),
            decoration: BoxDecoration(
                color: color.withValues(alpha: alpha), borderRadius: BorderRadius.circular(7)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (icon != null && !tiny)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Icon(icon, size: wide ? 18 : 14, color: Colors.white),
                ),
              Flexible(
                child: Text(wide ? '$label  ·  ${hm(start)} – ${hm(end)}' : label,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                        fontSize: size,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      if (!wide)
        Padding(
          padding: EdgeInsets.zero,
          child: Row(children: [
            const SizedBox(width: 38),
            for (final d in days)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onDay(d),
                  child: Column(children: [
                    Text(dayLetters[d.weekday - 1],
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800, color: p.sub)),
                    const SizedBox(height: 2),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: ymd(d) == today ? p.ink : Colors.transparent,
                          shape: BoxShape.circle),
                      child: Text('${d.day}',
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: ymd(d) == today ? p.bg : p.ink)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      const SizedBox(height: 7),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 38,
          height: total,
          child: Stack(clipBehavior: Clip.none, children: [
            for (var h = h0; h < h1; h += step)
              Positioned(
                  top: y(h * 60) - 7,
                  right: 6,
                  child: Text('$h h', style: TextStyle(fontSize: 11, color: p.sub))),
            // L'heure qu'il est, en bleu, au bout de la ligne « maintenant ».
            if (showNow)
              Positioned(
                top: y(nowMin) - 9,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                      color: nowBlue, borderRadius: BorderRadius.circular(6)),
                  child: Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ]),
        ),
        for (final d in days)
          Expanded(
            child: Container(
              height: total,
              decoration: BoxDecoration(
                  color: ymd(d) == today && !wide ? p.accent.withValues(alpha: .08) : null,
                  border: Border(left: BorderSide(color: p.line))),
              child: Stack(children: [
                for (var h = h0; h < h1; h++)
                  Positioned(
                      top: y(h * 60),
                      left: 0,
                      right: 0,
                      child: Container(height: 1, color: p.line)),
                for (final o in s.occs(d))
                  () {
                    final st = s.statusOf(o);
                    return box(o.block.label, _blockColor(o.block.label), o.start, o.end,
                        alpha: st == 'manque' || st == 'hors' ? .4 : 1,
                        icon: st == 'tenu' ? Icons.check_circle : _blockIcon(o.block.label),
                        onTap: st == 'attente'
                            ? () => sheet(context, MoveSheet(o, Schedule.mondayOf(d)))
                            : null);
                  }(),
                for (final e in s.eventsOn(d))
                  box('${e['label']}', const Color(0xFFCA8A04), (e['start'] as num).toInt(),
                      (e['start'] as num).toInt() + 90,
                      icon: Icons.star_rounded, onTap: () => _askCut(context, e)),
                for (final h in s.hints(d))
                  Positioned(
                    top: y(h.start) - (wide ? 9 : 7),
                    left: 2,
                    right: 2,
                    child: Row(children: [
                      Icon(Icons.family_restroom_rounded, size: wide ? 16 : 13, color: _kids),
                      Expanded(
                        child: wide
                            ? Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text('${hm(h.start)}  ${h.label}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color.lerp(_kids, p.ink, .35))),
                              )
                            : Container(height: 2, color: _kids),
                      ),
                    ]),
                  ),
                // Ligne « maintenant » : épaisse avec un point sur aujourd'hui, fine sur les autres jours.
                if (showNow && ymd(d) != today)
                  Positioned(
                    top: y(nowMin),
                    left: 0,
                    right: 0,
                    child: Container(height: 1, color: nowBlue.withValues(alpha: .35)),
                  ),
                if (ymd(d) == today) ...[
                  Positioned(
                    top: y(nowMin) - 1.5,
                    left: 0,
                    right: 0,
                    child: Container(height: 3, color: nowBlue),
                  ),
                  Positioned(
                    top: y(nowMin) - 5,
                    left: -1,
                    child: Container(
                        width: 10,
                        height: 10,
                        decoration:
                            const BoxDecoration(color: nowBlue, shape: BoxShape.circle)),
                  ),
                ],
              ]),
            ),
          ),
      ]),
    ]);
  }
}

const agendaViews = {'jour': 'Jour', 'semaine': 'Semaine', 'mois': 'Mois', 'annee': 'Année'};

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});
  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late String view = store.agendaView;
  DateTime cursor = _day(DateTime.now());

  void shift(int d) => setState(() {
        cursor = switch (view) {
          'jour' => _day(cursor, d),
          'semaine' => _day(cursor, 7 * d),
          'mois' => DateTime(cursor.year, cursor.month + d, 1),
          _ => DateTime(cursor.year + d, 1, 1),
        };
      });

  void go(String v, DateTime d) => setState(() {
        view = v;
        cursor = d;
      });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = store.schedule;
    final monday = Schedule.mondayOf(cursor);
    final (held, planned) = s.count(monday);
    final title = switch (view) {
      'jour' => longDate(cursor),
      'semaine' => _range(monday),
      'mois' => '${cap(monthNames[cursor.month - 1])} ${cursor.year}',
      _ => '${cursor.year}',
    };
    final body = <Widget>[];
    if (view == 'jour' || view == 'semaine') {
      // construit plus bas, ajusté à la hauteur de la fenêtre
    } else if (view == 'mois') {
      body.add(const _Legend());
      body.add(_MonthGrid(cursor.year, cursor.month, big: true, onDay: (d) => go('jour', d)));
      body.add(Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text('Point = bloc fixe · pastille jaune = spectacle · touche un jour pour l\'ouvrir',
            style: TextStyle(color: p.sub, fontSize: 13)),
      ));
    } else {
      body.add(const _Legend());
      for (var m = 1; m <= 12; m += 2) {
        body.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final mm in [m, m + 1]) ...[
              if (mm != m) const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () => go('mois', DateTime(cursor.year, mm, 1)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cap(monthNames[mm - 1]),
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900, color: p.ink)),
                    const SizedBox(height: 4),
                    _MonthGrid(cursor.year, mm,
                        big: false, onDay: (d) => go('mois', DateTime(d.year, d.month, 1))),
                  ]),
                ),
              ),
            ],
          ]),
        ));
      }
    }

    final grid = view == 'jour' || view == 'semaine';
    final top = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
      child: Row(children: [
        Expanded(
          child: Text('Agenda',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.5, color: p.ink)),
        ),
        if (planned > 0 && grid)
          Pill('Blocs tenus  $held / $planned', _statusColors['tenu']!,
              icon: Icons.check_circle_rounded),
        if (grid)
          IconButton(
              tooltip: 'Revue de la semaine',
              onPressed: () => openReview(context),
              icon: Icon(Icons.fact_check_rounded, color: p.sub))
        else
          const SizedBox(width: 8, height: 48),
      ]),
    );
    final tabs = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Segmented(agendaViews, view, (v) => setState(() => view = v), expand: true),
    );
    final nav = Row(children: [
      IconButton(
          tooltip: 'Précédent',
          visualDensity: VisualDensity.compact,
          onPressed: () => shift(-1),
          icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: Text(cap(title),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
      ),
      TextButton(
          onPressed: () => setState(() => cursor = _day(DateTime.now())),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('Aujourd\'hui')),
      IconButton(
          tooltip: 'Suivant',
          visualDensity: VisualDensity.compact,
          onPressed: () => shift(1),
          icon: const Icon(Icons.chevron_right)),
    ]);

    // Semaine et jour : vue d'ensemble, tout tient dans la fenêtre.
    if (grid) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        top,
        tabs,
        Expanded(
          child: Panel(
            fill: true,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            header: nav,
            children: [
              _WeekBadge(cursor),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 6),
                child: LayoutBuilder(
                  builder: (context, box) => _TimeGrid(
                      view == 'jour' ? [cursor] : [for (var i = 0; i < 7; i++) _day(monday, i)],
                      height: box.maxHeight,
                      onDay: (d) => go('jour', d)),
                ),
              ),
            ],
          ),
        ),
      ]);
    }

    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      top,
      tabs,
      const SizedBox(height: 6),
      Panel(header: nav, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
        ),
      ]),
    ]);
  }
}

/// Déplacer un bloc dans la même semaine, quand un entretien de mission tombe à son heure.
class MoveSheet extends StatefulWidget {
  final Occ occ;
  final DateTime monday;
  const MoveSheet(this.occ, this.monday, {super.key});
  @override
  State<MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<MoveSheet> {
  late int day = dateOf(widget.occ.date).weekday;
  late int start = widget.occ.start;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final o = widget.occ;
    final len = o.end - o.start;
    final late = start + len > 24 * 60;
    // Un bloc ne peut pas en recouvrir un autre.
    final clash = store.schedule
        .occs(_day(widget.monday, day - 1))
        .where((x) => x.key != o.key && x.start < start + len && start < x.end)
        .firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('Déplacer « ${o.block.label} »',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(
          'Un bloc ne se supprime pas. Si un entretien de mission tombe à cette heure, '
          'dis où le remettre cette semaine.',
          style: TextStyle(color: p.sub)),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 1; i <= 7; i++)
          _DayChip(_day(widget.monday, i - 1), day == i, () => setState(() => day = i)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        OutlinedButton(
            onPressed: () async {
              final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60));
              if (t != null) setState(() => start = t.hour * 60 + t.minute);
            },
            child: Text(hm(start))),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
              late
                  ? 'Trop tard : le bloc dépasse minuit'
                  : clash != null
                      ? 'Déjà pris par ${clash.block.label} (${hm(clash.start)} – ${hm(clash.end)})'
                      : 'jusqu\'à ${hm(start + len)}',
              style: TextStyle(
                  color: late || clash != null ? _statusColors['manque'] : p.sub)),
        ),
      ]),
      const SizedBox(height: 18),
      FilledButton(
          onPressed: late || clash != null
              ? null
              : () {
                  store.move(o, ymd(_day(widget.monday, day - 1)), start);
                  Navigator.pop(context);
                },
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: const Text('Déplacer le bloc', style: TextStyle(fontWeight: FontWeight.w800))),
    ]);
  }
}

// ---------------------------------------------------------------- Archives

void openArchive(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const ArchivePage()));

/// Les tâches terminées archivées, rangées par sprint. On peut les consulter, les changer
/// de sprint, les remettre à faire, ou vider les archives.
class ArchivePage extends StatelessWidget {
  const ArchivePage({super.key});

  Future<void> _clear(BuildContext context) async {
    final n = store.archived.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vider les archives ?'),
        content: Text(n == 1
            ? 'La tâche archivée sera supprimée.'
            : 'Les $n tâches archivées seront supprimées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vider')),
        ],
      ),
    );
    if (ok == true) store.clearArchive();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final groups = store.archiveBySprint;
                return ListView(padding: const EdgeInsets.only(top: 8, bottom: 30), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 12, 6),
                    child: Row(children: [
                      IconButton(
                          tooltip: 'Fermer',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close)),
                      Expanded(
                        child: Text('Archives',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w900, color: p.ink)),
                      ),
                      if (groups.isNotEmpty)
                        OutlinedButton.icon(
                            onPressed: () => _clear(context),
                            style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: _statusColors['manque']),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Vider')),
                    ]),
                  ),
                  if (groups.isEmpty)
                    Panel(children: [
                      Padding(
                        padding: const EdgeInsets.all(26),
                        child: Column(children: [
                          Icon(Icons.inventory_2_outlined, size: 32, color: p.sub),
                          const SizedBox(height: 10),
                          Text('Les archives sont vides.',
                              textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
                        ]),
                      ),
                    ]),
                  for (final g in groups.entries)
                    Panel(
                      header: PanelHead('Sprint ${_range(dateOf(g.key))}',
                          icon: Icons.flag_rounded,
                          color: p.sub,
                          subtitle:
                              '${g.value.fold<double>(0, (a, t) => a + Store.pointsOf(t)).round()} pts',
                          count: '${g.value.length}'),
                      children: [for (final t in g.value) _Tile(t, key: ValueKey('a${t.id}'))],
                    ),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Revue

void openReview(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const ReviewPage()));

/// Revue du dimanche : blocs tenus, tâches faites, tâches jamais touchées depuis 7 jours.
class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final (held, planned) = store.schedule.count(Schedule.mondayOf(DateTime.now()));
                final done = store.doneThisWeek;
                final stale = store.stale;
                final going = store.backlog.where((t) => t.subs.isNotEmpty).toList();
                Widget h(String s) => Padding(
                      padding: const EdgeInsets.only(top: 26, bottom: 8),
                      child: Text(s,
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub)),
                    );
                return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
                  Row(children: [
                    IconButton(
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                    Text('Revue de la semaine',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w900, color: p.ink)),
                  ]),
                  h('BLOCS TENUS'),
                  Text('$held / $planned',
                      style: TextStyle(
                          fontSize: 54, height: 1, fontWeight: FontWeight.w900, color: p.ink)),
                  h('POINTS DE VALEUR'),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${store.valueWeek}',
                        style: TextStyle(
                            fontSize: 54,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: p.ink)),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 6),
                      child: Text('/ ${store.targetOf(store.thisMonday)} pts',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800, color: p.sub)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                        value: store.targetOf(store.thisMonday) == 0
                            ? 0
                            : (store.valueWeek / store.targetOf(store.thisMonday)).clamp(0, 1),
                        minHeight: 7,
                        backgroundColor: p.line,
                        color: _statusColors['tenu']),
                  ),
                  const SizedBox(height: 10),
                  for (final k in kinds.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(
                            child: Text(
                                '${k.value.$1} : ${store.weekUnits[k.key] ?? 0} ${k.value.$2}',
                                style: TextStyle(fontSize: 15.5, color: p.ink))),
                        Text(
                            '${(store.weekUnits[k.key] ?? 0) * (store.schedule.coef[k.key] ?? 0)} pts',
                            style: TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w800, color: p.ink)),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  Text(
                      'Demandes de rue : ${(store.weekUnits['rue'] ?? 0) * askPerBlock}.  '
                      '${store.gapText.isEmpty ? 'Cible atteinte.' : store.gapText}',
                      style: TextStyle(
                          color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  const BonusRow(),
                  h('SCORE DE LA SEMAINE'),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${store.weekScore}',
                        style: TextStyle(
                            fontSize: 54,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: p.ink)),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 6),
                      child: Text('pts',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800, color: p.sub)),
                    ),
                    const Spacer(),
                    if (store.sprintGrade != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Pill('Sprint  ${store.sprintGrade} / 100', p.accent),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                      'Semaine dernière : ${store.lastWeekScore} pts.  '
                      '${[
                        for (var i = 0; i <= 4; i++)
                          if (done.any((t) => t.priority == i))
                            '${prioNames[i]} × ${done.where((t) => t.priority == i).length}'
                      ].join('  ·  ')}',
                      style: TextStyle(color: p.ink, fontSize: 14.5)),
                  const SizedBox(height: 6),
                  Text(
                      'Une tâche faite rapporte P0 = 8, P1 = 5, P2 = 3, P3 = 2, P4 = 1 point, '
                      'multiplié par l\'importance de la catégorie : Mission × 1,5, Contenu et '
                      'Destiny × 1,2, Personnel × 1. La note du sprint est la part des points '
                      'du sprint déjà gagnés.',
                      style: TextStyle(color: p.sub, fontSize: 13, height: 1.35)),
                  h('TÂCHES FAITES · ${done.length}'),
                  if (done.isEmpty) Text('Aucune cette semaine.', style: TextStyle(color: p.sub)),
                  for (final t in done)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(taskIcon(t), size: 18, color: domainOf(t.cat)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(t.title,
                                style: TextStyle(fontSize: 15.5, color: p.ink))),
                        if (t.result.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Pill(t.result, _statusColors['tenu']!),
                        ],
                      ]),
                    ),
                  if (going.isNotEmpty) h('EN COURS · ${going.length}'),
                  for (final t in going)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(taskIcon(t), size: 18, color: domainOf(t.cat)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text('${t.title} : ${t.progress}',
                                style: TextStyle(fontSize: 15.5, color: p.ink))),
                        if (t.result.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Pill(t.result, _statusColors['attente']!),
                        ],
                        const SizedBox(width: 8),
                        SubProgress(t, width: 54),
                      ]),
                    ),
                  h('JAMAIS TOUCHÉES DEPUIS 7 JOURS · ${stale.length}'),
                  if (stale.isEmpty)
                    Text('Aucune : tout a bougé cette semaine.', style: TextStyle(color: p.sub)),
                  for (final t in stale)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
                      decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: p.line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(taskIcon(t), size: 18, color: domainOf(t.cat)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(t.title,
                                  style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w700,
                                      color: p.ink))),
                        ]),
                        Wrap(children: [
                          TextButton(
                              onPressed: () => store.touch(t), child: const Text('Garder')),
                          TextButton(
                              onPressed: () => store.park(t), child: const Text('Parking')),
                          TextButton(
                              onPressed: () => store.remove(t),
                              child: Text('Supprimer',
                                  style: TextStyle(color: _statusColors['manque']))),
                        ]),
                      ]),
                    ),
                  const SizedBox(height: 22),
                  FilledButton(
                      onPressed: () {
                        store.reviewed();
                        Navigator.pop(context);
                      },
                      style:
                          FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Revue terminée',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Jetons bonus : un tous les 30 points gagnés en abordage de rue, à dépenser quand on veut.
class BonusRow extends StatelessWidget {
  const BonusRow({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final n = store.bonusLeft;
    final gold = const Color(0xFFF59E0B);
    return Row(children: [
      Icon(Icons.confirmation_number_rounded, size: 19, color: n > 0 ? gold : p.sub),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
            n > 0
                ? '$n jeton${n > 1 ? 's' : ''} bonus à dépenser'
                : 'Jeton bonus : ${store.bonusProgress} / $bonusEvery pts de rue',
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: n > 0 ? FontWeight.w800 : FontWeight.w700,
                color: n > 0 ? p.ink : p.sub)),
      ),
      if (n > 0)
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14)),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Dépenser un jeton bonus ?'),
                content: Text(n > 1 ? 'Il t\'en restera ${n - 1}.' : 'C\'est ton dernier.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Dépenser')),
                ],
              ),
            );
            if (ok == true) store.spendBonus();
          },
          child: const Text('Dépenser', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
    ]);
  }
}
