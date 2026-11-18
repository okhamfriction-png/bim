import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

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

  /// Où on en est dans la journée : (texte, rendez-vous fixe en cours).
  (String, bool)? moment() {
    final n = DateTime.now();
    final m = n.hour * 60 + n.minute;
    final bl = store.schedule.blocksFor(store.schedule.weekOf(n), n.weekday);
    final cur = bl.where((b) => b.start <= m && m < b.end).firstOrNull;
    final nxt = bl.where((b) => b.start > m).firstOrNull;
    String name(Block b) => b.label.isEmpty ? 'Backlog' : b.label;
    if (cur != null) {
      return cur.fixed
          ? ('${name(cur)} jusqu\'à ${hm(cur.end)}', true)
          : ('${name(cur)} · encore ${dur(cur.end - m)}', false);
    }
    if (nxt != null) return ('Libre encore ${dur(nxt.start - m)}, puis ${name(nxt)}', false);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ready = store.ready;
    final t = ready.firstOrNull;
    final next = ready.length > 1 ? ready[1] : null;
    final mo = moment();
    final nDone = store.doneToday.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(longDate(DateTime.now()),
            style: TextStyle(color: p.sub, fontWeight: FontWeight.w600)),
        if (mo != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Icon(mo.$2 ? Icons.event_busy : Icons.schedule,
                  size: 18, color: mo.$2 ? prioColors[1] : p.sub),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(mo.$1,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: mo.$2 ? prioColors[1] : p.ink))),
            ]),
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
              child: t == null
                  ? _Empty(key: const ValueKey('vide'), done: nDone)
                  : _Card(key: ValueKey(t.id), task: t),
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
            Expanded(
                child: TextButton.icon(
                    onPressed: () => store.start(t),
                    icon: Icon(t.startedAt == null ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    label: Text(t.startedAt == null ? 'Démarrer' : 'Pause'))),
            Expanded(
                child: TextButton.icon(
                    onPressed: () => sheet(context, SnoozeSheet(t)),
                    icon: const Icon(Icons.snooze_rounded),
                    label: const Text('Plus tard'))),
            Expanded(
                child: TextButton.icon(
                    onPressed: () => sheet(context, TaskSheet(task: t)),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'))),
          ]),
          const SizedBox(height: 6),
        ],
        Text(
            [
              if (next != null) 'Ensuite : ${next.title}',
              if (nDone > 0) '$nDone faite${nDone > 1 ? 's' : ''} aujourd\'hui',
            ].join('  ·  '),
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
    final d = domainOf(t.domain);
    final mins = t.startedAt == null ? null : ((nowMs() - t.startedAt!) / 60000).floor();
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
          Pill(t.domain, d),
          Pill(t.eff == 0 ? 'Échéance ${dueLabel(t.due!)}' : prioNames[t.eff], prioColors[t.eff]),
          if (t.repeats) Pill('Rituel', p.sub),
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
                if (t.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(t.note,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, height: 1.4, color: p.sub)),
                  ),
              ]),
            ),
          ),
        ),
        Row(children: [
          if (t.source.isNotEmpty)
            Expanded(
                child: Text('via ${t.source}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.sub, fontSize: 13)))
          else
            const Spacer(),
          if (mins != null)
            Text('En cours · ${dur(mins)}',
                style: TextStyle(fontWeight: FontWeight.w800, color: p.ink)),
        ]),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  final int done;
  const _Empty({required this.done, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wb_sunny_rounded, size: 56, color: p.accent),
        const SizedBox(height: 12),
        Text(done > 0 ? 'Tout est fait.' : 'Rien à faire pour l\'instant.',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: p.ink)),
        const SizedBox(height: 6),
        Text('Ajoute une tâche avec le bouton +',
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
  String? filter;

  String waitReason(Task t) {
    final n = DateTime.now();
    if (t.snoozed) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.snoozeUntil!);
      return ymd(d) == ymd(n)
          ? 'revient à ${hm(d.hour * 60 + d.minute)}'
          : 'revient ${dayNames[d.weekday - 1]}';
    }
    if (t.doneOn(n)) return 'faite aujourd\'hui';
    for (var i = 1; i <= 7; i++) {
      final wd = (n.weekday - 1 + i) % 7 + 1;
      if (t.days.contains(wd)) return i == 1 ? 'revient demain' : 'revient ${dayNames[wd - 1]}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    bool keep(Task t) => filter == null || t.domain == filter;
    final ready = store.ready.where(keep).toList();
    final waiting = store.waiting.where(keep).toList();
    final done = store.doneToday.where((t) => !t.repeats && keep(t)).toList();
    final used = {for (final t in store.tasks.where((t) => t.open)) t.domain};

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${store.ready.length} à faire',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: p.ink)),
        if (used.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Pick('Tout', filter == null, () => setState(() => filter = null)),
                for (final d in domains.keys.where(used.contains))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Pick(d, filter == d,
                        () => setState(() => filter = d),
                        color: domainOf(d)),
                  ),
              ]),
            ),
          ),
      ]),
    );

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
          child: Text(title,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub)),
        );

    final footer = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ready.isEmpty)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Text('Rien de prêt ici.',
              textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
        ),
      if (waiting.isNotEmpty) section('EN ATTENTE'),
      for (final t in waiting) _Tile(t, index: null, sub: waitReason(t), dim: true),
      if (done.isNotEmpty) section('FAIT AUJOURD\'HUI'),
      for (final t in done) _Tile(t, index: null, dim: true, struck: true),
      const SizedBox(height: 90),
    ]);

    return ReorderableListView.builder(
      header: header,
      footer: footer,
      buildDefaultDragHandles: false,
      itemCount: ready.length,
      onReorder: store.reorder,
      proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
      itemBuilder: (c, i) =>
          _Tile(ready[i], key: ValueKey(ready[i].id), index: filter == null ? i : null),
    );
  }
}

class _Tile extends StatelessWidget {
  final Task t;
  final int? index; // position pour le glisser-déposer
  final String? sub;
  final bool dim, struck;
  const _Tile(this.t, {required this.index, this.sub, this.dim = false, this.struck = false, super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    
    final meta = [
      t.domain,
      if (sub != null && sub!.isNotEmpty) sub!,
      if (sub == null && !t.repeats && t.due != null) dueLabel(t.due!),
      if (sub == null && t.repeats) 'rituel',
      if (t.source.isNotEmpty) 'via ${t.source}',
    ].join(' · ');
    final tile = Opacity(
      opacity: dim ? .55 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.line)),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: prioColors[t.eff]),
            IconButton(
              tooltip: struck ? 'Remettre à faire' : 'Terminé',
              onPressed: dim
                  ? (struck ? () => store.reopen(t) : null)
                  : () {
                      HapticFeedback.lightImpact();
                      store.complete(t);
                    },
              icon: Icon(struck ? Icons.check_circle : Icons.circle_outlined,
                  color: struck ? p.accent : p.sub, size: 26),
            ),
            Expanded(
              child: InkWell(
                onTap: () => sheet(context, TaskSheet(task: t)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(t.title,
                            style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                                decoration: struck ? TextDecoration.lineThrough : null)),
                        const SizedBox(height: 3),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: p.sub)),
                      ]),
                ),
              ),
            ),
            if (t.snoozed)
              IconButton(
                  tooltip: 'Réveiller',
                  onPressed: () => store.wake(t),
                  icon: Icon(Icons.alarm_on, color: p.sub)),
            if (index != null)
              ReorderableDragStartListener(
                index: index!,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Icons.drag_indicator, color: p.sub),
                ),
              )
            else
              const SizedBox(width: 12),
          ]),
        ),
      ),
    );
    return tile;
  }
}

// ---------------------------------------------------------------- Semaine

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});
  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  late String week = store.schedule.weekOf(DateTime.now());
  int day = DateTime.now().weekday;

  void setCurrent() {
    final m = Schedule.mondayOf(DateTime.now());
    store.schedule.anchor = ymd(week == 'a' ? m : m.subtract(const Duration(days: 7)));
    store.saveSchedule();
  }

  Future<void> rename() async {
    final s = store.schedule;
    final a = TextEditingController(text: s.nameA), b = TextEditingController(text: s.nameB);
    await sheet(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Nom des deux semaines',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: a, decoration: const InputDecoration(labelText: 'Première')),
          const SizedBox(height: 10),
          TextField(controller: b, decoration: const InputDecoration(labelText: 'Seconde')),
          const SizedBox(height: 16),
          Builder(
              builder: (c) => FilledButton(
                  onPressed: () => Navigator.pop(c), child: const Text('Enregistrer'))),
        ]));
    if (a.text.trim().isNotEmpty && b.text.trim().isNotEmpty) {
      s.nameA = a.text.trim();
      s.nameB = b.text.trim();
      store.saveSchedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = store.schedule;
    final current = s.weekOf(DateTime.now());
    final blocks = s.blocksFor(week, day);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 100), children: [
      Row(children: [
        Expanded(
          child: Text('Semaine',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: p.ink)),
        ),
        IconButton(
            tooltip: 'Renommer les semaines',
            onPressed: rename,
            icon: Icon(Icons.edit_outlined, color: p.sub)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final w in ['a', 'b'])
          Pick('${s.nameOf(w)}${w == current ? ' · en cours' : ''}', week == w,
              () => setState(() => week = w)),
      ]),
      if (week != current)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
              onPressed: setCurrent, child: const Text('En fait, c\'est celle-ci en ce moment')),
        ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 1; i <= 7; i++)
          Pick(dayLetters[i - 1], day == i, () => setState(() => day = i)),
      ]),
      const SizedBox(height: 18),
      if (blocks.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Text('Rien de fixe ce ${dayNames[day - 1]} :\ntout le temps est au backlog.',
              textAlign: TextAlign.center, style: TextStyle(color: p.sub, fontSize: 15)),
        ),
      for (final b in blocks)
        GestureDetector(
          onTap: () => sheet(context, BlockSheet(block: b)),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: b.fixed ? p.card : p.accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: b.fixed ? p.line : p.accent.withValues(alpha: .6)),
            ),
            child: Row(children: [
              SizedBox(
                width: 92,
                child: Text('${hm(b.start)}\n${hm(b.end)}',
                    style: TextStyle(color: p.sub, fontWeight: FontWeight.w700, height: 1.35)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.label.isEmpty ? 'Backlog' : b.label,
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800, color: p.ink)),
                  Text(b.fixed ? 'Rendez-vous fixe' : 'Créneau backlog : une tâche après l\'autre',
                      style: TextStyle(color: p.sub, fontSize: 13)),
                ]),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: () => sheet(context, BlockSheet(week: week, day: day)),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un bloc')),
    ]);
  }
}

class BlockSheet extends StatefulWidget {
  final Block? block;
  final String week;
  final int day;
  const BlockSheet({this.block, this.week = '*', this.day = 1, super.key});
  @override
  State<BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<BlockSheet> {
  late final b = widget.block;
  late final label = TextEditingController(text: b?.label ?? '');
  late bool fixed = b?.fixed ?? true;
  late String week = b?.week ?? '*';
  late List<int> days = b == null ? [widget.day] : [...b!.days];
  late int start = b?.start ?? 540;
  late int end = b?.end ?? 720;

  Future<void> pick(bool isStart) async {
    final v = isStart ? start : end;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: v ~/ 60, minute: v % 60));
    if (t == null) return;
    setState(() => isStart ? start = t.hour * 60 + t.minute : end = t.hour * 60 + t.minute);
  }

  void save() {
    if (days.isEmpty || end <= start) return;
    final x = b ?? Block();
    x
      ..label = label.text.trim()
      ..fixed = fixed
      ..week = week
      ..days = days
      ..start = start
      ..end = end;
    if (b == null) store.schedule.blocks.add(x);
    store.saveSchedule();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = store.schedule;
    Widget lab(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.sub)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: label,
        autofocus: b == null,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
            hintText: 'Nom du bloc', border: InputBorder.none, hintStyle: TextStyle(color: p.sub)),
      ),
      lab('TYPE'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Pick('Rendez-vous fixe', fixed, () => setState(() => fixed = true)),
        Pick('Créneau backlog', !fixed, () => setState(() => fixed = false)),
      ]),
      lab('HORAIRE'),
      Row(children: [
        OutlinedButton(onPressed: () => pick(true), child: Text(hm(start))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('→')),
        OutlinedButton(onPressed: () => pick(false), child: Text(hm(end))),
        if (end <= start)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text('La fin est avant le début', style: TextStyle(color: prioColors[0])),
          ),
      ]),
      lab('JOURS'),
      Wrap(spacing: 8, children: [
        for (var i = 1; i <= 7; i++)
          Pick(dayLetters[i - 1], days.contains(i),
              () => setState(() => days.contains(i) ? days.remove(i) : days.add(i))),
      ]),
      lab('SEMAINE'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Pick('Les deux', week == '*', () => setState(() => week = '*')),
        Pick(s.nameA, week == 'a', () => setState(() => week = 'a')),
        Pick(s.nameB, week == 'b', () => setState(() => week = 'b')),
      ]),
      const SizedBox(height: 22),
      Row(children: [
        if (b != null)
          IconButton(
              tooltip: 'Supprimer',
              onPressed: () {
                store.schedule.blocks.remove(b);
                store.saveSchedule();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline)),
        const Spacer(),
        FilledButton(
            onPressed: save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
            child: const Text('Enregistrer',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      ]),
    ]);
  }
}
