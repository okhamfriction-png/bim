import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'defi_data.dart';
import 'defi_sources.dart';
import 'models.dart';
import 'store.dart';
import 'ui.dart';

export 'defi_data.dart';

const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _amber = Color(0xFFF59E0B);

/// « 45 s », « 1 min 30 ».
String secs(int s) => s < 60 ? '$s s' : (s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min ${(s % 60).toString().padLeft(2, '0')}');
String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

double? median(Iterable<int> v) {
  final l = v.toList()..sort();
  if (l.isEmpty) return null;
  return l.length.isOdd ? l[l.length ~/ 2].toDouble() : (l[l.length ~/ 2 - 1] + l[l.length ~/ 2]) / 2;
}

// ---- Niveaux, plan et adaptation ----

int levelNo(Task t) {
  final m = t.meta['level'];
  if (m is num) return m.toInt().clamp(0, levels.length - 1);
  final r = RegExp(r'niveau\s+(\d+)', caseSensitive: false).firstMatch(t.title);
  return (r == null ? 0 : int.parse(r.group(1)!)).clamp(0, levels.length - 1);
}

Level levelOf(Task t) => levels[levelNo(t)];

/// Les échauffements, du plus ancien sprint au plus récent.
List<Task> warmups() => store.tasks.where((t) => !t.deleted && t.whole).toList()
  ..sort((a, b) => (a.sprint ?? '').compareTo(b.sprint ?? ''));

Task? taskOfLevel(int n) => warmups().where((t) => levelNo(t) == n).firstOrNull;

/// Toutes les prises faites, dans l'ordre : la première est le « Jour 1 ».
List<Sub> takes() => [
      for (final t in warmups())
        for (final s in t.subs)
          if (s.done) s
    ]..sort((a, b) => (a.doneAt ?? 0).compareTo(b.doneAt ?? 0));

int dayNo(Sub s) => takes().indexOf(s) + 1;

/// Une prise a déjà été faite aujourd'hui : une seule compte par sortie.
bool takenToday() {
  final d = ymd(DateTime.now());
  return takes().any((s) => s.doneAt != null && ymd(DateTime.fromMillisecondsSinceEpoch(s.doneAt!)) == d);
}

int? levelBest(int n) {
  final r = [for (final t in warmups()) if (levelNo(t) == n && t.best != null) t.best!];
  return r.isEmpty ? null : r.reduce(max);
}

int? absBest() {
  final r = [for (final t in warmups()) if (t.best != null) t.best!];
  return r.isEmpty ? null : r.reduce(max);
}

double? taskMedian(Task? t) => median([for (final s in t?.subs ?? <Sub>[]) if (s.noted) s.held!]);

bool _over(Task t) {
  final d = DateTime.tryParse(t.sprint ?? '');
  return d != null && !DateTime.now().isBefore(d.add(const Duration(days: 7)));
}

/// Record visé pour un niveau. Dès qu'il y a des scores, il est recalé : le sprint qui suit la
/// dernière prise vise le meilleur score arrondi au palier supérieur, puis un palier de plus par sprint.
int? targetOf(int n) {
  int? best;
  var last = -1;
  for (final t in warmups()) {
    final l = levelNo(t);
    if (l >= n || t.best == null) continue;
    best = best == null ? t.best! : max(best, t.best!);
    last = max(last, l);
  }
  if (best == null) return stages[n].target;
  var i = enduranceSteps.indexWhere((x) => x > best!);
  if (i < 0) i = enduranceSteps.length - 1;
  return enduranceSteps[min(enduranceSteps.length - 1, i + (n - last - 1))];
}

/// Ce qui est demandé pour un niveau, une fois l'adaptation appliquée.
class Plan {
  final int n;
  Map<String, int> steps = {}; // levier → palier en cours (chute, voix, émotion, personnages, images, corps)
  List<(String, int)> fresh = []; // leviers nouveaux de ce sprint
  bool surprise = false, exam = false, deferred = false;
  String decision = 'Le sprint suit le plan.';
  Plan(this.n);

  Level get level => levels[n];
  int? get target => targetOf(n);
  int stepOf(String lever) => switch (lever) {
        'endurance' => enduranceSteps.where((x) => x <= (absBest() ?? 0)).length,
        'silence' => 1,
        'structure' => n,
        _ => steps[lever] ?? 0,
      };

  /// Unités travaillées (« chute:1 ») : les nouvelles du sprint et le palier en cours des autres.
  List<String> get units => {
        for (final e in steps.entries)
          if (!fresh.any((f) => f.$1 == e.key)) '${e.key}:${e.value}',
        for (final f in fresh) '${f.$1}:${f.$2}',
      }.toList();
}

Plan planOf(int n) {
  final p = Plan(n);
  var idx = 0;
  var added = false; // le sprint précédent a-t-il ajouté un levier ?
  for (var lv = 1; lv <= n; lv++) {
    final prev = taskOfLevel(lv - 1);
    final over = prev != null && _over(prev);
    final failed = lv >= 2 && over && prev.successes < 4;
    final m = taskMedian(prev), m0 = taskMedian(lv >= 2 ? taskOfLevel(lv - 2) : null);
    final lower = lv >= 2 && over && added && m != null && m0 != null && m < m0;
    p.fresh = [];
    p.surprise = p.exam = false;
    p.deferred = failed || lower;
    if (failed) {
      p.decision = 'Moins de 4 prises réussies au sprint précédent (${prev.successes} sur ${prev.subs.length}) : '
          'le genre avance, le nouveau levier attend.';
      added = false;
    } else if (lower) {
      p.decision = 'Ta médiane a baissé au sprint précédent après l\'ajout d\'un levier '
          '(${secs(m.round())} contre ${secs(m0.round())}) : tu gardes ce levier un sprint de plus.';
      added = false;
    } else {
      idx++;
      final st = stages[idx];
      p.fresh = st.fresh;
      p.surprise = st.surprise;
      p.exam = st.exam;
      added = st.fresh.isNotEmpty;
      for (final f in st.fresh) {
        p.steps[f.$1] = max(p.steps[f.$1] ?? 0, f.$2);
      }
      p.decision = idx == lv
          ? 'Le sprint suit le plan.'
          : 'Le plan a ${lv - idx} sprint${lv - idx > 1 ? 's' : ''} de retard : le levier nouveau est celui qui attendait.';
    }
  }
  return p;
}

String unitName(String u) {
  if (u == 'depart') return 'Démarrer sans préparation';
  if (u == 'surprise') return 'Contrainte surprise';
  if (u == 'examen') return 'Prise d\'examen';
  final x = u.split(':');
  return '${leverOf(x[0]).name} · palier ${x[1]}';
}

String unitLine(String u) {
  if (u == 'depart') return startLine;
  if (u == 'examen') return examLine;
  if (u == 'surprise') return 'Contrainte surprise';
  final x = u.split(':');
  return leverOf(x[0]).steps[int.parse(x[1]) - 1];
}

/// Réussites et essais d'une unité, sur toutes les prises notées (ou celles d'une tâche).
(int, int) unitStats(String u, {Task? only}) {
  var ok = 0, all = 0;
  for (final t in only == null ? warmups() : [only]) {
    for (final s in t.subs) {
      if (s.noted && s.data['levier'] == u) {
        all++;
        if (s.leverOk) ok++;
      }
    }
  }
  return (ok, all);
}

/// Le levier du jour : celui où le taux de réussite est le plus bas parmi les leviers actifs.
String leverOfDay(Plan p) {
  if (p.exam) return 'examen';
  if (p.surprise) return 'surprise';
  final u = p.units;
  if (u.isEmpty) return 'depart';
  var best = u.first;
  var bestRate = 2.0;
  for (final x in u) {
    final (ok, all) = unitStats(x);
    final r = all == 0 ? -1.0 : ok / all;
    if (r <= bestRate) {
      best = x;
      bestRate = r;
    }
  }
  return best;
}

bool starOf(Task t) => t.subs.isNotEmpty && t.successes >= min(4, t.subs.length);

// ---- Fiche dans le détail de la tâche ----

class DefiCard extends StatelessWidget {
  final Task task;
  final TextAlign align;
  const DefiCard(this.task, {this.align = TextAlign.start, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final plan = planOf(levelNo(task));
    final l = plan.level;
    final best = levelBest(l.n);
    final center = align == TextAlign.center;
    return Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('NIVEAU ${l.n} · ${l.name.toUpperCase()}',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: p.sub)),
          const SizedBox(height: 6),
          Text(l.defi,
              textAlign: align,
              style: const TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: center ? WrapAlignment.center : WrapAlignment.start,
              children: [
                const Pill('Stop au premier « euh »', _red, icon: Icons.block_rounded),
                Pill(best != null ? 'Record : ${secs(best)}' : 'Pas encore de record', _amber,
                    icon: Icons.emoji_events_rounded),
                if (plan.target != null) Pill('Visé : ${secs(plan.target!)}', _amber, icon: Icons.flag_rounded),
                Pill('${task.successes}/${task.subs.length} réussies${starOf(task) ? ' ★' : ''}', _green,
                    icon: Icons.videocam_rounded),
              ]),
          const SizedBox(height: 14),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: center ? WrapAlignment.center : WrapAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => DefiPage(task), fullscreenDialog: true)),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Lancer le défi',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                OutlinedButton(
                    onPressed: () => sheet(context, WhySheet(task)),
                    child: const Text('Pourquoi ce niveau ?')),
                OutlinedButton(
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ProgressionPage())),
                    child: const Text('Progression')),
              ]),
        ]);
  }
}

// ---- Écran du défi ----

class DefiPage extends StatefulWidget {
  final Task task;
  const DefiPage(this.task, {super.key});
  @override
  State<DefiPage> createState() => _DefiPageState();
}

class _DefiPageState extends State<DefiPage> {
  String phase = 'ready'; // ready | run | done
  DateTime? start, ended;
  Timer? tick;
  int score = 0;
  bool swapped = false;
  Sub? saved;
  int? before, beforeAll; // records avant cette prise
  late final Plan plan = planOf(levelNo(widget.task));
  late final String unit = leverOfDay(plan);
  late final String surprise = surprises[Random().nextInt(surprises.length)];
  late final bool extra = takenToday() || widget.task.nextSub == null; // prise hors compte
  late String subject = _draw();

  int get elapsed => start == null ? 0 : DateTime.now().difference(start!).inSeconds;
  int get approachLeft =>
      ended == null ? approachSeconds : approachSeconds - DateTime.now().difference(ended!).inSeconds;
  String get leverLine => unit == 'surprise' ? surprise : unitLine(unit);

  /// Un sujet de la réserve, jamais deux fois dans le même sprint.
  String _draw([String? not]) {
    final pool = subjects[plan.n];
    if (pool == null) return fixedSubject;
    final used = {for (final s in widget.task.subs) s.data['sujet'], not};
    final free = pool.where((s) => !used.contains(s)).toList();
    final from = free.isEmpty ? pool : free;
    return from[Random().nextInt(from.length)];
  }

  @override
  void dispose() {
    tick?.cancel();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void go() {
    WakelockPlus.enable().catchError((_) {});
    setState(() {
      phase = 'run';
      start = DateTime.now();
    });
    tick?.cancel();
    tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  /// Le « euh » est tombé : le score est figé et noté dans la prise du jour.
  void stop() {
    final s = max(1, elapsed);
    before = levelBest(plan.n);
    beforeAll = absBest();
    final t = widget.task;
    final sub = extra ? null : t.nextSub;
    if (sub != null) {
      sub.data = {
        ...sub.data,
        'duree': s,
        'levier': unit,
        if (unit == 'surprise') 'ligne': surprise,
        if (subjects[plan.n] != null) 'sujet': subject,
      };
      store.toggleSub(t, sub);
    }
    setState(() {
      phase = 'done';
      score = s;
      saved = sub;
      ended = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.task;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded)),
                  const Spacer(),
                  Text(
                      extra && saved == null
                          ? '${t.subsDone}/${t.subs.length} prises'
                          : 'Jour ${saved != null ? dayNo(saved!) : takes().length + 1} · ${t.subsDone}/${t.subs.length} prises',
                      style: TextStyle(color: p.sub, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                ]),
                Expanded(
                  child: switch (phase) {
                    'run' => _run(p),
                    'done' => _done(p),
                    _ => _ready(p),
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ready(Pal p) {
    final l = plan.level;
    final best = levelBest(l.n), all = absBest();
    final pool = subjects[plan.n] != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Niveau ${l.n} · ${l.name}',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.accent)),
            const SizedBox(height: 12),
            Text(l.defi,
                style: TextStyle(
                    fontSize: l.defi.length > 110 ? 21 : 25,
                    height: 1.22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3)),
            const SizedBox(height: 16),
            _box(p, 'LE SUJET DU JOUR', subject,
                action: pool && !swapped
                    ? TextButton(
                        onPressed: () => setState(() {
                              subject = _draw(subject);
                              swapped = true;
                            }),
                        child: const Text('Autre sujet'))
                    : null),
            const SizedBox(height: 10),
            _box(p, 'LE LEVIER DU JOUR', leverLine, accent: p.accent),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _box(p, 'RECORD DU NIVEAU', best != null ? secs(best) : '—')),
              const SizedBox(width: 10),
              Expanded(child: _box(p, 'RECORD ABSOLU', all != null ? secs(all) : '—')),
            ]),
          ]),
        ),
      ),
      if (extra)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
              widget.task.nextSub == null
                  ? 'Toutes les prises du sprint sont faites : celle-ci ne comptera pas.'
                  : 'Ta prise du jour est déjà faite : celle-ci ne comptera pas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.sub)),
        ),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: go,
        style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        child: const Text('Démarrer', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      ),
    ]);
  }

  Widget _run(Pal p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        _box(p, 'LEVIER DU JOUR', leverLine, accent: p.accent),
        const Spacer(),
        Text(mmss(elapsed),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 110,
                height: 1,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()])),
        Text('sans « euh » · un silence ne compte pas',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: p.sub)),
        const Spacer(),
        SizedBox(
          height: 200,
          child: FilledButton(
            onPressed: stop,
            style: FilledButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
            child: const Text('Euh', style: TextStyle(fontSize: 60, fontWeight: FontWeight.w900)),
          ),
        ),
      ]);

  Widget _done(Pal p) {
    final left = approachLeft;
    final beaten = before == null || score > before!;
    final all = beforeAll != null && score > beforeAll!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Spacer(),
      Text(secs(score),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 84, height: 1, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(
          before == null
              ? 'Premier score sur ce niveau : c\'est ton record.'
              : all
                  ? 'Record absolu battu (+${secs(score - beforeAll!)})'
                  : beaten
                      ? 'Record du niveau battu (+${secs(score - before!)})'
                      : score == before
                          ? 'Record égalé'
                          : '${secs(before! - score)} sous ton record (${secs(before!)})',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: beaten ? _green : p.sub)),
      const SizedBox(height: 12),
      Text('Finis par : « $defiOutro »',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(
          saved == null
              ? 'Prise hors compte, non enregistrée.'
              : 'Après le bloc : confirme les secondes et dis si le levier a été joué.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.sub, fontSize: 15)),
      if (saved != null)
        TextButton(
            onPressed: () async {
              await askPrise(context, widget.task, saved!);
              if (mounted) setState(() => score = saved!.held ?? score);
            },
            child: const Text('Noter maintenant')),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
            color: left <= 0 ? _green : p.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: left <= 0 ? _green : p.line)),
        child: Column(children: [
          Text(left <= 0 ? 'Aborde maintenant.' : 'PREMIÈRE APPROCHE',
              style: TextStyle(
                  fontSize: left <= 0 ? 28 : 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: left <= 0 ? -.4 : .6,
                  color: left <= 0 ? Colors.white : p.sub)),
          if (left > 0) ...[
            Text(mmss(left),
                style: const TextStyle(
                    fontSize: 60,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Text('Téléphone dans la poche.', style: TextStyle(color: p.sub, fontSize: 15)),
          ],
        ]),
      ),
    ]);
  }

  Widget _box(Pal p, String label, String text, {Widget? action, Color? accent}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent ?? p.line, width: accent != null ? 1.5 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: p.sub)),
            ),
            if (action != null) SizedBox(height: 26, child: action),
          ]),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ---- Les 2 résultats d'une prise ----

int? _parseSecs(String v) {
  final s = v.trim();
  if (s.isEmpty) return null;
  if (s.contains(':')) {
    final x = s.split(':');
    final m = int.tryParse(x[0]), sec = int.tryParse(x[1].isEmpty ? '0' : x[1]);
    return m == null || sec == null ? null : m * 60 + sec;
  }
  return int.tryParse(s);
}

/// Après le bloc de rue : secondes tenues avant le premier « euh », levier du jour joué ou non.
Future<void> askPrise(BuildContext context, Task t, Sub s) async {
  final plan = planOf(levelNo(t));
  final unit = (s.data['levier'] as String?) ?? leverOfDay(plan);
  final line = (s.data['ligne'] as String?) ?? unitLine(unit);
  final dur = TextEditingController(text: s.held?.toString() ?? '');
  var ok = s.leverOk;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(s.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: dur,
              autofocus: s.held == null,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Secondes tenues avant le premier « euh »', suffixText: 's', isDense: true),
            ),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Levier du jour joué'),
                subtitle: Text(line),
                value: ok,
                onChanged: (v) => set(() => ok = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Noter')),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final d = _parseSecs(dur.text);
  if (!s.done) store.toggleSub(t, s);
  store.setSubData(t, s, {
    ...s.data,
    if (d != null && d > 0) 'duree': d,
    'levierOk': ok,
    'levier': unit,
  });
}

/// Résumé d'une prise : « Jour 2 · 41 s ✓ ».
String priseSummary(Sub s) =>
    s.noted ? '${s.done ? 'Jour ${dayNo(s)} · ' : ''}${secs(s.held!)} ${s.success ? '✓' : '✗'}' : 'Résultat';

// ---- Pourquoi ce niveau ? ----

class WhySheet extends StatelessWidget {
  final Task task;
  const WhySheet(this.task, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final plan = planOf(levelNo(task));
    final l = plan.level;
    final day = leverOfDay(plan);
    Widget h(String s) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(s, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub)),
        );
    Widget line(String a, String b) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$a : ', style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: b),
          ]), style: const TextStyle(fontSize: 15, height: 1.35)),
        );
    final active = [
      for (final lv in levers)
        if (plan.stepOf(lv.id) > 0 || lv.id == 'endurance') lv
    ];
    final topics = <String>[];
    for (final s in sources) {
      if (!topics.contains(s.topic)) topics.add(s.topic);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Niveau ${l.n} · ${l.name}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      if (phases[l.n].isNotEmpty)
        Text('Phase : ${phases[l.n]}', style: TextStyle(color: p.sub, fontSize: 14.5)),
      h('CE SPRINT'),
      line('Genre', '${l.name} (${l.skill.toLowerCase()})'),
      line('Règle', 'à la caméra, une prise par sortie ; elle s\'arrête au premier « euh » et le score est le nombre de secondes tenues'),
      line('Record visé', plan.target == null ? 'aucun : ton premier score sert de point de départ' : secs(plan.target!)),
      line('Levier nouveau',
          plan.fresh.isEmpty ? 'aucun' : plan.fresh.map((f) => '${leverOf(f.$1).name} palier ${f.$2}').join(', ')),
      line('Levier du jour', day == 'surprise' ? 'une contrainte surprise tirée au hasard' : unitLine(day)),
      line('Décision', plan.decision),
      const SizedBox(height: 4),
      Text(defiGoal, style: TextStyle(color: p.sub, fontSize: 14, height: 1.35)),
      h('LEVIERS ACTIFS'),
      for (final lv in active) ...[
        Text(
            '${lv.name} · palier ${lv.id == 'structure' ? '${plan.stepOf(lv.id)}/12' : '${plan.stepOf(lv.id)}/${lv.steps.length}'}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        line('Origine', lv.origin),
        line('Ce qu\'il apporte', lv.gain),
        line('Critère de réussite', lv.test),
        line('Erreur fréquente', lv.trap),
        const SizedBox(height: 10),
      ],
      h('RÉSULTATS PAR PRISE'),
      for (final s in task.subs)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
              s.noted
                  ? '${s.title} (jour ${dayNo(s)}) : ${secs(s.held!)} tenues, levier ${s.leverOk ? 'joué' : 'non joué'}'
                      '${s.success ? ' · réussie' : ''}'
                  : '${s.title} : ${s.done ? 'faite, pas encore notée' : 'à faire'}',
              style: const TextStyle(fontSize: 14.5, height: 1.35)),
        ),
      h('D\'OÙ VIENT LA MÉTHODE'),
      Text(methodText, style: const TextStyle(fontSize: 14.5, height: 1.4)),
      for (final topic in topics) ...[
        h('SOURCES · ${topic.toUpperCase()}'),
        for (final s in sources.where((s) => s.topic == topic))
          InkWell(
            onTap: s.url.isEmpty
                ? null
                : () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: s.label),
                TextSpan(
                    text: s.url.isEmpty ? '  (non vérifié)' : (s.checked ? '  ↗' : '  ↗ (lien donné, non relu)'),
                    style: TextStyle(color: p.sub)),
              ]), style: const TextStyle(fontSize: 14, height: 1.35)),
            ),
          ),
      ],
      const SizedBox(height: 10),
    ]);
  }
}

// ---- Progression ----

class ProgressionPage extends StatelessWidget {
  const ProgressionPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final all = warmups();
                final noted = [for (final s in takes()) if (s.noted) s];
                final now = ymd(Schedule.mondayOf(DateTime.now()));
                final cur = all.where((t) => (t.sprint ?? '').compareTo(now) <= 0).lastOrNull;
                final plan = planOf(cur == null ? 0 : levelNo(cur));
                final best = absBest();
                Widget h(String s) => Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 8),
                      child: Text(s,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub)),
                    );
                return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
                  Row(children: [
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    const Text('Progression',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  ]),
                  Text(defiGoal, style: TextStyle(color: p.sub, fontSize: 14.5, height: 1.35)),
                  h('MON RECORD'),
                  Text(best == null ? '—' : secs(best),
                      style: const TextStyle(fontSize: 54, height: 1, fontWeight: FontWeight.w900)),
                  if (plan.target != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Record visé ce sprint : ${secs(plan.target!)}',
                          style: TextStyle(color: p.sub, fontSize: 15)),
                    ),
                  h('SECONDES TENUES, JOUR APRÈS JOUR'),
                  _Chart([for (final s in noted) s.held!.toDouble()],
                      target: (plan.target ?? 30).toDouble(), color: p.accent, unit: ''),
                  h('LES 9 LEVIERS'),
                  for (final lv in levers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        SizedBox(
                            width: 130,
                            child: Text(lv.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        Expanded(
                          child: Row(children: [
                            for (var i = 1; i <= (lv.id == 'structure' ? 12 : lv.steps.length); i++)
                              Expanded(
                                child: Container(
                                  height: 10,
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                      color: i <= plan.stepOf(lv.id) ? _green : p.line,
                                      borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                          ]),
                        ),
                        SizedBox(
                            width: 44,
                            child: Text(
                                '${plan.stepOf(lv.id)}/${lv.id == 'structure' ? 12 : lv.steps.length}',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: p.sub, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  h('LES 13 NIVEAUX'),
                  for (final l in levels)
                    Builder(builder: (context) {
                      final t = taskOfLevel(l.n);
                      final r = [for (final s in t?.subs ?? <Sub>[]) if (s.noted) s.held!];
                      final target = targetOf(l.n);
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration:
                            BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
                        child: Row(children: [
                          SizedBox(
                              width: 26,
                              child: Text('${l.n}',
                                  style: TextStyle(fontWeight: FontWeight.w900, color: p.sub))),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${l.name}${t != null && starOf(t) ? ' ★' : ''}',
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                              Text(
                                  r.isEmpty
                                      ? (target == null ? 'pas encore de prise notée' : 'record visé : ${secs(target)}')
                                      : 'record ${secs(r.reduce(max))} · médiane ${secs(median(r)!.round())} · '
                                          '${r.length} prise${r.length > 1 ? 's' : ''} · ${t!.successes} réussie${t.successes > 1 ? 's' : ''}'
                                          '${target == null ? '' : ' · visé ${secs(target)}'}',
                                  style: TextStyle(fontSize: 13, color: p.sub)),
                            ]),
                          ),
                        ]),
                      );
                    }),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  final List<double> values;
  final double target;
  final Color color;
  final String unit;
  const _Chart(this.values, {required this.target, required this.color, required this.unit});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (values.isEmpty) {
      return Container(
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line)),
        child: Text('La courbe apparaît dès la première prise notée.', style: TextStyle(color: p.sub)),
      );
    }
    return Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(10, 14, 14, 10),
      decoration: BoxDecoration(
          color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line)),
      child: CustomPaint(painter: _Line(values, target, color, p), size: Size.infinite),
    );
  }
}

class _Line extends CustomPainter {
  final List<double> v;
  final double target;
  final Color color;
  final Pal p;
  _Line(this.v, this.target, this.color, this.p);
  @override
  void paint(Canvas c, Size s) {
    const left = 44.0;
    final top = max(v.reduce(max), target) * 1.15;
    double y(double x) => s.height - (x / top) * s.height;
    double x(int i) => v.length == 1 ? (left + s.width) / 2 : left + i * (s.width - left) / (v.length - 1);
    void label(String t, double yy) {
      final tp = TextPainter(
          text: TextSpan(text: t, style: TextStyle(fontSize: 11, color: p.sub)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(0, yy - tp.height / 2));
    }

    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    c.drawLine(Offset(left, s.height), Offset(s.width, s.height), grid);
    final dash = Paint()
      ..color = _green
      ..strokeWidth = 1.5;
    for (var xx = left; xx < s.width; xx += 10) {
      c.drawLine(Offset(xx, y(target)), Offset(min(xx + 5, s.width), y(target)), dash);
    }
    label(secs(target.round()), y(target));
    label(secs(top.round()), 6);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      i == 0 ? path.moveTo(x(i), y(v[i])) : path.lineTo(x(i), y(v[i]));
    }
    c.drawPath(path, line);
    for (var i = 0; i < v.length; i++) {
      c.drawCircle(Offset(x(i), y(v[i])), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_Line o) => true;
}

// ---- Bloc « Échauffement » de la revue de la semaine ----

class DefiReview extends StatelessWidget {
  const DefiReview({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final all = warmups();
    final now = ymd(Schedule.mondayOf(DateTime.now()));
    final i = all.lastIndexWhere((t) => (t.sprint ?? '').compareTo(now) <= 0);
    if (i < 0) return const SizedBox.shrink();
    final t = all[i];
    final m = taskMedian(t), before = taskMedian(i > 0 ? all[i - 1] : null);
    final plan = planOf(levelNo(t));
    final units = {
      for (final s in t.subs)
        if (s.noted && s.data['levier'] is String) s.data['levier'] as String
    };
    String? weak;
    var weakRate = 2.0;
    for (final u in units) {
      final (ok, n) = unitStats(u, only: t);
      if (n > 0 && ok / n < weakRate) {
        weak = u;
        weakRate = ok / n;
      }
    }
    final next = levelNo(t) + 1 < levels.length ? levelNo(t) + 1 : null;
    // La décision du sprint suivant, comme si celui-ci était terminé.
    String decision() {
      if (next == null) return 'Dernier sprint du plan.';
      final aim = t.best == null
          ? targetOf(next)
          : enduranceSteps.firstWhere((x) => x > (absBest() ?? 0), orElse: () => enduranceSteps.last);
      final goal = aim == null ? '' : ' Record visé : ${secs(aim)}${t.best == null ? '' : ', ton meilleur score arrondi au palier supérieur'}.';
      if (levelNo(t) >= 1 && t.successes < 4) {
        return 'Le genre avance (${levels[next].name}), mais le nouveau levier attend : '
            '${t.successes} prise${t.successes > 1 ? 's' : ''} réussie${t.successes > 1 ? 's' : ''} sur ${t.subs.length}, il en faut 4.$goal';
      }
      if (levelNo(t) >= 1 && plan.fresh.isNotEmpty && m != null && before != null && m < before) {
        return 'Le genre avance (${levels[next].name}), mais tu gardes le levier de ce sprint un sprint de plus : '
            'ta médiane a baissé après son ajout.$goal';
      }
      final st = stages[min(next, stages.length - 1)];
      return 'Le sprint suivant suit le plan : ${levels[next].name}'
          '${st.fresh.isEmpty ? '' : ', levier nouveau ${st.fresh.map((f) => '${leverOf(f.$1).name} palier ${f.$2}').join(' et ')}'}.$goal';
    }

    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 150, child: Text(a, style: TextStyle(color: p.sub, fontSize: 14.5))),
            Expanded(
                child: Text(b, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row('Niveau', '${plan.level.n} · ${plan.level.name}${starOf(t) ? ' ★' : ''}'),
      row('Record du sprint',
          t.best == null ? 'aucune prise notée' : '${secs(t.best!)}${plan.target == null ? '' : ' (visé : ${secs(plan.target!)})'}'),
      if (m != null)
        row(
            'Médiane',
            '${secs(m.round())}'
                '${before == null ? '' : (m > before ? ' (+${secs((m - before).round())} sur le sprint précédent)' : m < before ? ' (−${secs((before - m).round())} sur le sprint précédent)' : ' (stable)')}'),
      row('Prises réussies', '${t.successes} sur ${t.subs.length}'),
      for (final u in units)
        row(unitName(u), () {
          final (ok, n) = unitStats(u, only: t);
          return 'joué $ok fois sur $n';
        }()),
      if (weak != null) row('Levier le plus faible', unitName(weak)),
      row('Sprint suivant', decision()),
    ]);
  }
}
