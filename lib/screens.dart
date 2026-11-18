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
    final count = planned == 0 ? '' : 'Blocs tenus : $held / $planned';
    final ask = _cutToAsk(now);

    // À l'heure d'un bloc, on n'affiche que lui.
    if (cur != null) {
      final st = s.statusOf(cur);
      final left = 15 - ((nowMs() - cur.startMs) / 60000).floor();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(longDate(now), style: TextStyle(color: p.sub, fontWeight: FontWeight.w600)),
          if (ask != null) _CutAsk(ask),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _statusColors[st]!, width: 2)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Pill('Bloc fixe', p.sub, icon: Icons.lock_clock_rounded),
                const SizedBox(height: 18),
                Text(cur.block.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 40,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                        color: p.ink)),
                const SizedBox(height: 10),
                Text('${hm(cur.start)} – ${hm(cur.end)}',
                    style: TextStyle(fontSize: 18, color: p.sub, fontWeight: FontWeight.w600)),
                const SizedBox(height: 22),
                if (st == 'tenu')
                  Pill('Tenu', _statusColors['tenu']!, icon: Icons.check_circle_rounded)
                else if (st == 'manque')
                  Text('Manqué : plus de 15 minutes après le début.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _statusColors['manque'], fontWeight: FontWeight.w700))
                else
                  Text('Encore $left min pour le valider',
                      style: TextStyle(color: p.sub, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          if (st == 'ouvert')
            SizedBox(
              height: 68,
              child: FilledButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  store.check(cur);
                },
                icon: const Icon(Icons.place_rounded, size: 28),
                label: const Text('J\'y suis',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
              ),
            ),
          const SizedBox(height: 10),
          Text(count, textAlign: TextAlign.center, style: TextStyle(color: p.sub, fontSize: 13.5)),
        ]),
      );
    }

    // Hors bloc : un appel ou un entretien d'abord, sinon la première tâche du jour.
    final queue = [...store.calls, ...store.todayTodo];
    final t = queue.firstOrNull;
    final next = queue.length > 1 ? queue[1] : null;
    final choosing = t == null && store.canPick && store.pickable.isNotEmpty;
    final nxt = occs.where((o) => o.start > m).firstOrNull;
    final agenda = [
      if (nxt != null) '${nxt.block.label} à ${hm(nxt.start)}, dans ${dur(nxt.start - m)}',
      for (final e in s.eventsOn(now)) '${e['label']} à ${hm((e['start'] as num).toInt())}',
    ].join('  ·  ');
    final review = now.weekday == 7 && s.reviewedOn != ymd(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(longDate(now), style: TextStyle(color: p.sub, fontWeight: FontWeight.w600)),
        if (agenda.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.schedule, size: 18, color: p.sub),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(agenda,
                      style: TextStyle(fontWeight: FontWeight.w700, color: p.ink))),
            ]),
          ),
        if (ask != null) _CutAsk(ask),
        if (review)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton.icon(
                onPressed: () => openReview(context),
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('Faire la revue de la semaine',
                    style: TextStyle(fontWeight: FontWeight.w800))),
          ),
        const SizedBox(height: 14),
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                      position: Tween(begin: const Offset(0, .08), end: Offset.zero).animate(a),
                      child: c)),
              child: t != null
                  ? _Card(key: ValueKey(t.id), task: t)
                  : choosing
                      ? const _Picker(key: ValueKey('choix'))
                      : _Empty(key: const ValueKey('vide'), picked: store.picks.length),
            ),
            IgnorePointer(
              child: AnimatedScale(
                scale: bim ? 1 : .4,
                duration: const Duration(milliseconds: 350),
                curve: Curves.elasticOut,
                child: AnimatedOpacity(
                  opacity: bim ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 16),
                    decoration: BoxDecoration(
                        color: p.accent, borderRadius: BorderRadius.circular(99)),
                    child: Text('Bim !',
                        style: TextStyle(
                            fontSize: 44, fontWeight: FontWeight.w900, color: p.onAccent)),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (t != null) ...[
          SizedBox(
            height: 68,
            child: FilledButton.icon(
              onPressed: () => done(t),
              icon: const Icon(Icons.check_rounded, size: 30),
              label: const Text('Terminé',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (!t.call)
              Expanded(
                  child: TextButton.icon(
                      onPressed: () => store.unpick(t),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Retirer du jour'))),
            Expanded(
                child: TextButton.icon(
                    onPressed: () => sheet(context, TaskSheet(task: t)),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'))),
          ]),
          const SizedBox(height: 6),
        ],
        Text([if (next != null) 'Ensuite : ${next.title}', if (count.isNotEmpty) count].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub, fontSize: 13.5)),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final Task task;
  const _Card({required this.task, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = task;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 30,
              offset: const Offset(0, 12))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill(t.cat, domainOf(t.cat), icon: iconOf(t.cat)),
          if (t.call)
            Pill('Appel ou entretien', prioColors[1], icon: Icons.phone_in_talk_rounded),
        ]),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(children: [
                Text(t.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: t.title.length > 60 ? 26 : 34,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                        color: p.ink)),
                if (t.note.isNotEmpty || t.links.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: TaskBody(t,
                        align: t.note.length > 160 ? TextAlign.start : TextAlign.center),
                  ),
              ]),
            ),
          ),
        ),
        if (t.source.isNotEmpty)
          Text('via ${t.source}',
              overflow: TextOverflow.ellipsis, style: TextStyle(color: p.sub, fontSize: 13)),
      ]),
    );
  }
}

/// Le choix du matin : 3 tâches au maximum pour la journée.
class _Picker extends StatefulWidget {
  const _Picker({super.key});
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final sel = <String>{};
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final room = 3 - store.picks.length;
    final list = store.pickable;
    sel.removeWhere((id) => !list.any((t) => t.id == id));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          room == 3
              ? 'Choisis 3 tâches au maximum pour aujourd\'hui'
              : 'Tâches du jour faites. Tu peux encore en choisir $room.',
          style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w900, color: p.ink)),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(children: [
          for (final t in list)
            GestureDetector(
              onTap: () => setState(() {
                if (sel.contains(t.id)) {
                  sel.remove(t.id);
                } else if (sel.length < room) {
                  sel.add(t.id);
                }
              }),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                    color: sel.contains(t.id) ? p.accent.withValues(alpha: .18) : p.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: sel.contains(t.id) ? p.accent : p.line, width: 1.5)),
                child: Row(children: [
                  Icon(iconOf(t.cat), color: domainOf(t.cat), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(t.title,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, color: p.ink))),
                  Icon(sel.contains(t.id) ? Icons.check_circle : Icons.circle_outlined,
                      color: sel.contains(t.id) ? p.accent : p.sub),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 60,
        child: FilledButton(
          onPressed: sel.isEmpty
              ? null
              : () {
                  for (final t in list.where((t) => sel.contains(t.id)).toList()) {
                    store.pick(t);
                  }
                },
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          child: Text(sel.isEmpty ? 'Touche les tâches à garder' : 'C\'est parti (${sel.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ),
      ),
    ]);
  }
}

class _Empty extends StatelessWidget {
  final int picked;
  const _Empty({required this.picked, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wb_sunny_rounded, size: 56, color: p.accent),
        const SizedBox(height: 12),
        Text(picked > 0 ? 'Journée bouclée.' : 'Rien dans le backlog.',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: p.ink)),
        const SizedBox(height: 6),
        Text(picked > 0 ? 'Tes tâches du jour sont faites.' : 'Ajoute une tâche avec le bouton +',
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
  final quick = TextEditingController();
  final focus = FocusNode();

  void add() {
    final s = quick.text.trim();
    if (s.isEmpty) return;
    store.add(Task(title: s, domain: addCat));
    quick.clear();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final all = store.backlog;
    final done = store.doneToday;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${all.where((t) => !t.parked).length} à faire',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: p.ink)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.line, width: 1.5)),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: quick,
                focusNode: focus,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    hintText: 'Ajouter une tâche, puis Entrée',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: p.sub)),
                onSubmitted: (_) => add(),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(iconOf(addCat), color: domainOf(addCat), size: 22),
                  Icon(Icons.arrow_drop_down, color: p.sub),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Pick('Catégorie', group == 'cat', () => setState(() => group = 'cat'),
              icon: Icons.category_rounded),
          const SizedBox(width: 8),
          Pick('Origine', group == 'source', () => setState(() => group = 'source'),
              icon: Icons.forum_rounded),
        ]),
      ]),
    );

    Widget section(String title, {IconData? icon, Color? color}) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Row(children: [
            if (icon != null)
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(icon, size: 18, color: color ?? p.sub)),
            Text(title,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub)),
          ]),
        );

    const mine = 'Ajoutées par moi';
    final groups = <String, List<Task>>{};
    if (group == 'cat') {
      for (final c in cats) {
        groups[c] = all.where((t) => t.cat == c).toList();
      }
    } else {
      for (final t in all) {
        groups.putIfAbsent(t.source.isEmpty ? mine : t.source, () => []).add(t);
      }
    }
    groups.removeWhere((k, v) => v.isEmpty);

    return ListView(children: [
      header,
      if (all.isEmpty)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Text('Le backlog est vide.',
              textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
        ),
      for (final g in groups.entries) ...[
        section('${g.key.toUpperCase()} · ${g.value.length}',
            icon: group == 'cat'
                ? iconOf(g.key)
                : (g.key == mine ? Icons.person_rounded : Icons.forum_rounded),
            color: group == 'cat' ? domainOf(g.key) : null),
        for (final t in g.value) _Tile(t, key: ValueKey(t.id)),
      ],
      if (done.isNotEmpty) section('FAIT AUJOURD\'HUI'),
      for (final t in done) _Tile(t, key: ValueKey('d${t.id}')),
      const SizedBox(height: 40),
    ]);
  }
}

/// Une tâche dans la liste : icône et couleur de la catégorie, se déplie au toucher.
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
      if (t.call) 'appel ou entretien',
      if (t.pickedToday && !struck) 'aujourd\'hui',
      t.source.isNotEmpty ? 'via ${t.source}' : t.cat,
    ].join(' · ');
    return Opacity(
      opacity: dim && !open ? .6 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: open ? color : p.line)),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: ColoredBox(color: prioColors[t.priority])),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                onTap: () => setState(() => open = !open),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 6, 10),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .18), shape: BoxShape.circle),
                      child: Icon(t.call ? Icons.phone_in_talk_rounded : iconOf(t.cat),
                          color: color, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title,
                            style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                                decoration: struck ? TextDecoration.lineThrough : null)),
                        const SizedBox(height: 3),
                        Row(children: [
                          if (t.pickedToday && !struck)
                            Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Icon(Icons.today_rounded, size: 15, color: p.accent)),
                          if (t.note.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Icon(Icons.notes_rounded, size: 15, color: p.sub)),
                          if (t.links.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Icon(Icons.play_circle_outline, size: 15, color: p.sub)),
                          Expanded(
                            child: Text(meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: p.sub)),
                          ),
                        ]),
                      ]),
                    ),
                    IconButton(
                      tooltip: struck ? 'Remettre à faire' : 'Terminé',
                      onPressed: struck
                          ? () => store.reopen(t)
                          : () {
                              HapticFeedback.lightImpact();
                              store.complete(t);
                            },
                      icon: Icon(struck ? Icons.check_circle : Icons.circle_outlined,
                          color: struck ? p.accent : p.sub, size: 28),
                    ),
                  ]),
                ),
              ),
              if (open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 2, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (t.note.isEmpty && t.links.isEmpty)
                      Text('Pas de descriptif.', style: TextStyle(color: p.sub))
                    else
                      TaskBody(t),
                    const SizedBox(height: 8),
                    Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          Pill('Priorité ${prioNames[t.priority].toLowerCase()}',
                              prioColors[t.priority]),
                          if (t.open && !t.parked && !t.call)
                            TextButton.icon(
                                onPressed: t.pickedToday
                                    ? () => store.unpick(t)
                                    : (store.canPick ? () => store.pick(t) : null),
                                icon: Icon(
                                    t.pickedToday
                                        ? Icons.remove_circle_outline
                                        : Icons.today_rounded,
                                    size: 18),
                                label: Text(t.pickedToday
                                    ? 'Retirer du jour'
                                    : (store.canPick ? 'Pour aujourd\'hui' : 'Déjà 3 aujourd\'hui'))),
                          TextButton.icon(
                              onPressed: () => sheet(context, TaskSheet(task: t)),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Modifier')),
                        ]),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
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

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});
  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  DateTime monday = Schedule.mondayOf(DateTime.now());
  int day = DateTime.now().weekday;

  void shift(int weeks) => setState(() => monday = _day(monday, 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = store.schedule;
    final date = _day(monday, day - 1);
    final (held, planned) = s.count(monday);
    final occs = s.occs(date);
    final hints = s.hints(date);
    final events = s.eventsOn(date);
    Widget card({required Widget child, Color? border, Color? fill, VoidCallback? onTap}) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: fill ?? p.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border ?? p.line)),
            child: child,
          ),
        );
    Widget time(String a, [String? b]) => SizedBox(
          width: 84,
          child: Text(b == null ? a : '$a\n$b',
              style: TextStyle(color: p.sub, fontWeight: FontWeight.w700, height: 1.35)),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
      Row(children: [
        Expanded(
          child: Text('Semaine',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: p.ink)),
        ),
        if (planned > 0)
          Pill('Blocs tenus : $held / $planned', _statusColors['tenu']!,
              icon: Icons.check_circle_rounded),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(
            tooltip: 'Semaine précédente',
            onPressed: () => shift(-1),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text('${_range(monday)} · ${s.nameOf(s.weekOf(monday))}',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, color: p.ink)),
        ),
        IconButton(
            tooltip: 'Semaine suivante',
            onPressed: () => shift(1),
            icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 1; i <= 7; i++)
          _DayChip(_day(monday, i - 1), day == i, () => setState(() => day = i)),
      ]),
      const SizedBox(height: 18),
      if (occs.isEmpty && hints.isEmpty && events.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Text('Rien de fixe ce ${dayNames[day - 1]} :\ntout le temps est au backlog.',
              textAlign: TextAlign.center, style: TextStyle(color: p.sub, fontSize: 15)),
        ),
      for (final o in occs)
        Builder(builder: (context) {
          final st = s.statusOf(o);
          return card(
            onTap: st == 'attente' ? () => sheet(context, MoveSheet(o, monday)) : null,
            child: Row(children: [
              time(hm(o.start), hm(o.end)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.block.label,
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.ink)),
                  Text(o.moved ? 'Bloc fixe, déplacé pour un entretien' : 'Bloc fixe',
                      style: TextStyle(color: p.sub, fontSize: 13)),
                ]),
              ),
              Pill(_statusNames[st]!, _statusColors[st]!),
            ]),
          );
        }),
      for (final e in events)
        card(
          fill: p.accent.withValues(alpha: .14),
          border: p.accent.withValues(alpha: .6),
          onTap: () => _askCut(context, e),
          child: Row(children: [
            time(hm((e['start'] as num).toInt())),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['label']}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.ink)),
                Text(
                    e['cutEnd'] == null
                        ? 'Touche pour dire à quelle heure la rue s\'arrête'
                        : 'La rue s\'arrête à ${hm((e['cutEnd'] as num).toInt())}',
                    style: TextStyle(color: p.sub, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      for (final h in hints)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(children: [
            time(hm(h.start)),
            Icon(Icons.family_restroom_rounded, size: 18, color: p.sub),
            const SizedBox(width: 8),
            Expanded(child: Text(h.label, style: TextStyle(color: p.sub, fontSize: 15))),
          ]),
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
          onPressed: () => openReview(context),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          icon: const Icon(Icons.fact_check_rounded),
          label: const Text('Revue de la semaine')),
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
                  h('TÂCHES FAITES · ${done.length}'),
                  if (done.isEmpty) Text('Aucune cette semaine.', style: TextStyle(color: p.sub)),
                  for (final t in done)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(iconOf(t.cat), size: 18, color: domainOf(t.cat)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(t.title,
                                style: TextStyle(fontSize: 15.5, color: p.ink))),
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
                          Icon(iconOf(t.cat), size: 18, color: domainOf(t.cat)),
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
