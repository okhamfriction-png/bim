import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
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

String fr(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
String goalText(double g) => '${g == g.roundToDouble() ? g.round() : fr(g)} euh par minute ou moins';

/// Compte les « euh » d'une transcription : euh, heu, hum, bah, ben, et « du coup » en début de phrase.
int countEuh(String text) {
  final t = text.toLowerCase();
  final words = RegExp(r'(?<![a-zà-ÿ])(e+u+h+|h+e+u+|h+u+m+|h+m+|bah|ben)(?![a-zà-ÿ])').allMatches(t).length;
  final duCoup = RegExp(r'(^|[.!?…\n]\s*|^\s*)du coup(?![a-zà-ÿ])', multiLine: true).allMatches(t).length;
  return words + duCoup;
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

bool _over(Task t) {
  final d = DateTime.tryParse(t.sprint ?? '');
  return d != null && !DateTime.now().isBefore(d.add(const Duration(days: 7)));
}

/// Trois prises d'affilée à plus de 3 « euh » par minute en moyenne.
bool _threeBad(Task t) {
  final r = [for (final s in t.subs) if (s.noted) s.rate!];
  for (var i = 0; i + 3 <= r.length; i++) {
    if ((r[i] + r[i + 1] + r[i + 2]) / 3 > 3) return true;
  }
  return false;
}

/// Ce qui est demandé pour un niveau, une fois l'adaptation appliquée.
class Plan {
  final int n;
  int minutes = 3;
  double goal = 3;
  Map<String, int> steps = {}; // levier → palier en cours (chute, voix, émotion, personnages, images, corps)
  List<(String, int)> fresh = []; // leviers nouveaux de ce sprint
  bool surprise = false, exam = false, deferred = false, dropped = false;
  String decision = 'Le sprint suit le plan.';
  Plan(this.n);

  Level get level => levels[n];
  int stepOf(String lever) => switch (lever) {
        'duree' => minutes >= 8 ? 3 : (minutes >= 5 ? 2 : 1),
        'fluidite' => goal <= 1 ? 3 : (goal <= 2 ? 2 : 1),
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
  var before = 3;
  for (var lv = 1; lv <= n; lv++) {
    final prev = taskOfLevel(lv - 1);
    final failed = lv >= 2 && prev != null && _over(prev) && prev.successes < 4;
    before = p.minutes;
    p.fresh = [];
    p.surprise = p.exam = false;
    p.deferred = failed;
    if (failed) {
      p.decision = 'Moins de 4 prises réussies au sprint précédent (${prev.successes} sur ${prev.subs.length}) : '
          'le levier nouveau est reporté, la durée ne monte pas, tu retravailles le levier le plus faible.';
    } else {
      idx++;
      final st = stages[idx];
      p.minutes = st.minutes;
      p.goal = st.goal;
      p.fresh = st.fresh;
      p.surprise = st.surprise;
      p.exam = st.exam;
      for (final f in st.fresh) {
        p.steps[f.$1] = max(p.steps[f.$1] ?? 0, f.$2);
      }
      p.decision = idx == lv
          ? 'Le sprint suit le plan.'
          : 'Le plan a ${lv - idx} sprint${lv - idx > 1 ? 's' : ''} de retard : le levier nouveau est celui qui avait été reporté.';
    }
    // Paliers avancés à la main après trois prises réussies d'affilée.
    final boost = taskOfLevel(lv)?.meta['boost'];
    if (boost is Map) {
      boost.forEach((k, v) {
        final lever = leverOf('$k');
        p.steps[lever.id] = min(lever.steps.length, (p.steps[lever.id] ?? 0) + (v as num).toInt());
      });
    }
  }
  final t = taskOfLevel(n);
  if (t != null && p.minutes > before && _threeBad(t)) {
    p.minutes = before;
    p.dropped = true;
    p.decision = 'Plus de 3 « euh » par minute sur trois prises d\'affilée après la hausse de durée : '
        'retour à $before minutes pour le reste du sprint.';
  }
  return p;
}

String unitName(String u) {
  if (u == 'depart') return 'Démarrer et finir';
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

/// Meilleure prise sur un niveau : le moins de « euh » par minute.
double? levelBest(int n) {
  final r = [for (final t in warmups()) if (levelNo(t) == n && t.bestRate != null) t.bestRate!];
  return r.isEmpty ? null : r.reduce(min);
}

bool starOf(Task t) => t.subs.isNotEmpty && t.successes >= min(4, t.subs.length);

/// Proposition d'avancer d'un palier : trois prises d'affilée réussies à 1 « euh » par minute ou moins.
String? boostOffer(Task t, Plan p) {
  final noted = [for (final s in t.subs) if (s.noted) s];
  if (noted.length < 3) return null;
  if (!noted.sublist(noted.length - 3).every((s) => s.success && s.rate! <= 1)) return null;
  final at = (t.meta['boostAt'] as num?)?.toInt();
  if (at != null && noted.length - at < 3) return null;
  final lever = p.fresh.isNotEmpty ? p.fresh.last.$1 : leverOfDay(p).split(':').first;
  if (!levers.any((l) => l.id == lever)) return null;
  if ((p.steps[lever] ?? 0) >= leverOf(lever).steps.length) return null;
  return lever;
}

void acceptBoost(Task t, String lever) {
  final b = Map<String, dynamic>.from(t.meta['boost'] as Map? ?? {});
  b[lever] = ((b[lever] as num?)?.toInt() ?? 0) + 1;
  t.meta['boost'] = b;
  t.meta['boostAt'] = t.subs.where((s) => s.noted).length;
  store.touch(t);
}

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
    final offer = boostOffer(task, plan);
    return Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('NIVEAU ${l.n} · ${l.name.toUpperCase()} · ${plan.minutes} MIN',
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
                Pill(goalText(plan.goal), _red, icon: Icons.flag_rounded),
                Pill(best != null ? 'Record : ${fr(best)} euh/min' : 'Pas encore de record', _amber,
                    icon: Icons.emoji_events_rounded),
                Pill('${task.successes}/${task.subs.length} réussies${starOf(task) ? ' ★' : ''}', _green,
                    icon: Icons.videocam_rounded),
              ]),
          if (offer != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(
                  child: Text(
                      'Trois prises réussies d\'affilée à 1 euh/min ou moins. '
                      'Avancer d\'un palier en ${leverOf(offer).name} ?',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                TextButton(onPressed: () => acceptBoost(task, offer), child: const Text('Avancer')),
              ]),
            ),
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
  int held = 0;
  bool half = false, last = false, swapped = false;
  Sub? saved;
  late final Plan plan = planOf(levelNo(widget.task));
  late final String unit = leverOfDay(plan);
  late final String surprise = surprises[Random().nextInt(surprises.length)];
  late String subject = _draw();

  int get total => plan.minutes * 60;
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

  Future<void> buzz(int ms) async {
    try {
      HapticFeedback.heavyImpact();
      await Vibration.vibrate(duration: ms);
    } catch (_) {}
  }

  void go() {
    WakelockPlus.enable().catchError((_) {});
    setState(() {
      phase = 'run';
      start = DateTime.now();
    });
    tick?.cancel();
    tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (phase == 'run') {
        final e = elapsed;
        if (!half && e >= total ~/ 2) {
          half = true;
          buzz(500);
        }
        if (!last && e >= total - 30) {
          last = true;
          buzz(900);
        }
        if (e >= total) {
          buzz(1200);
          finish(total);
          return;
        }
      }
      setState(() {});
    });
  }

  void finish(int s) {
    final t = widget.task;
    final sub = t.nextSub;
    if (sub != null) {
      sub.data = {
        ...sub.data,
        'duree': s,
        'levier': unit,
        if (unit == 'surprise') 'ligne': surprise,
        'cible': plan.goal,
        'min': plan.minutes,
        if (subjects[plan.n] != null) 'sujet': subject,
      };
      store.toggleSub(t, sub);
    }
    setState(() {
      phase = 'done';
      held = s;
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
                  Text('${t.subsDone}/${t.subs.length} prises',
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
    final best = levelBest(l.n);
    final pool = subjects[plan.n] != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Niveau ${l.n} · ${l.name} · ${plan.minutes} min',
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
              Expanded(child: _box(p, 'LA CIBLE', goalText(plan.goal))),
              const SizedBox(width: 10),
              Expanded(child: _box(p, 'MON RECORD', best != null ? '${fr(best)} euh/min' : '—')),
            ]),
          ]),
        ),
      ),
      if (widget.task.nextSub == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Toutes les prises du sprint sont faites : celle-ci ne sera pas enregistrée.',
              textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
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

  Widget _run(Pal p) {
    final left = (total - elapsed).clamp(0, total);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      _box(p, 'SUJET', subject),
      const SizedBox(height: 10),
      _box(p, 'LEVIER DU JOUR', leverLine, accent: p.accent),
      const Spacer(),
      Text(mmss(left),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: p.sub,
              fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
            value: 1 - left / total, minHeight: 6, backgroundColor: p.line, color: p.accent),
      ),
      const SizedBox(height: 8),
      Text('Vibration à mi-temps, puis à 30 secondes de la fin.',
          textAlign: TextAlign.center, style: TextStyle(color: p.sub, fontSize: 13.5)),
      const Spacer(),
      OutlinedButton(
        onPressed: () => finish(elapsed),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        child: const Text('Terminer la prise',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ),
    ]);
  }

  Widget _done(Pal p) {
    final left = approachLeft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Spacer(),
      Text('Prise terminée', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: p.sub)),
      Text(mmss(held),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 72, height: 1.1, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      Text('Finis par : « $defiOutro »',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Text(
          saved == null
              ? 'Prise libre, non enregistrée.'
              : 'Tu noteras tes 4 résultats après le bloc de rue.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.sub, fontSize: 15)),
      if (saved != null)
        TextButton(
            onPressed: () async {
              await askPrise(context, widget.task, saved!);
              if (mounted) setState(() {});
            },
            child: Text(saved!.noted ? 'Corriger les résultats' : 'Noter maintenant')),
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

// ---- Les 4 résultats d'une prise ----

int? _parseTime(String v) {
  final s = v.trim().replaceAll(',', '.');
  if (s.isEmpty) return null;
  if (s.contains(':')) {
    final x = s.split(':');
    final m = int.tryParse(x[0]), sec = int.tryParse(x[1].isEmpty ? '0' : x[1]);
    return m == null || sec == null ? null : m * 60 + sec;
  }
  final m = double.tryParse(s);
  return m == null ? null : (m * 60).round();
}

/// Après le bloc de rue : durée tenue, nombre de « euh », histoire terminée, levier réussi.
Future<void> askPrise(BuildContext context, Task t, Sub s) async {
  final plan = planOf(levelNo(t));
  final unit = (s.data['levier'] as String?) ?? leverOfDay(plan);
  final line = (s.data['ligne'] as String?) ?? unitLine(unit);
  final dur = TextEditingController(text: s.held != null ? mmss(s.held!) : '${plan.minutes}:00');
  final euh = TextEditingController(text: s.euh?.toString() ?? '');
  final text = TextEditingController();
  var finie = s.finished, ok = s.leverOk;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(s.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: dur,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Durée tenue', hintText: '3:00', isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: euh,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nombre de « euh »', isDense: true),
                ),
              ),
            ]),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Histoire terminée'),
                value: finie,
                onChanged: (v) => set(() => finie = v)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Levier du jour réussi'),
                subtitle: Text(line),
                value: ok,
                onChanged: (v) => set(() => ok = v)),
            const SizedBox(height: 6),
            TextField(
              controller: text,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Transcription (facultatif)',
                  hintText: 'Colle le texte : les « euh » sont comptés pour toi',
                  isDense: true),
              onChanged: (v) {
                if (v.trim().isNotEmpty) set(() => euh.text = '${countEuh(v)}');
              },
            ),
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
  final d = _parseTime(dur.text);
  final n = int.tryParse(euh.text.trim());
  if (!s.done) store.toggleSub(t, s);
  store.setSubData(t, s, {
    ...s.data,
    if (d != null && d > 0) 'duree': d,
    if (n != null) 'euh': n,
    'finie': finie,
    'levierOk': ok,
    'levier': unit,
    'cible': s.data['cible'] ?? plan.goal,
    'min': s.data['min'] ?? plan.minutes,
  });
}

/// Résumé d'une prise notée : « 1,7 euh/min ✓ ».
String priseSummary(Sub s) => s.noted ? '${fr(s.rate!)} euh/min ${s.success ? '✓' : '✗'}' : 'Résultat';

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
        if (plan.stepOf(lv.id) > 0) lv
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
      line('Durée cible', '${plan.minutes} minutes, à la caméra, une prise par sortie'),
      line('Cible', goalText(plan.goal)),
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
                  ? '${s.title} : ${mmss(s.held!)} tenues, ${s.euh} euh (${fr(s.rate!)}/min), '
                      'histoire ${s.finished ? 'terminée' : 'non terminée'}, levier ${s.leverOk ? 'réussi' : 'raté'}'
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
                final takes = [
                  for (final t in all)
                    for (final s in t.subs)
                      if (s.noted) s
                ]..sort((a, b) => (a.doneAt ?? 0).compareTo(b.doneAt ?? 0));
                final now = ymd(Schedule.mondayOf(DateTime.now()));
                final cur = all.where((t) => (t.sprint ?? '').compareTo(now) <= 0).lastOrNull;
                final plan = planOf(cur == null ? 0 : levelNo(cur));
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
                  h('« EUH » PAR MINUTE'),
                  _Chart([for (final s in takes) s.rate!], target: 1, color: _red, unit: ''),
                  h('DURÉE TENUE (MINUTES)'),
                  _Chart([for (final s in takes) s.held! / 60], target: 8, color: p.accent, unit: ''),
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
                      final r = [for (final s in t?.subs ?? <Sub>[]) if (s.noted) s.rate!];
                      final best = levelBest(l.n);
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
                                      ? '${stages[l.n].minutes} min · pas encore de prise notée'
                                      : 'record ${fr(best ?? r.reduce(min))} · moyenne ${fr(r.reduce((a, b) => a + b) / r.length)} euh/min · '
                                          '${r.length} prise${r.length > 1 ? 's' : ''} · ${t!.successes} réussie${t.successes > 1 ? 's' : ''}',
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
    const left = 26.0;
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
    label(fr(target), y(target));
    label(fr(top), 6);
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
    double? mean(Task? x) {
      final r = [for (final s in x?.subs ?? <Sub>[]) if (s.noted) s.rate!];
      return r.isEmpty ? null : r.reduce((a, b) => a + b) / r.length;
    }

    final m = mean(t), before = mean(i > 0 ? all[i - 1] : null);
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
      if (levelNo(t) >= 1 && t.successes < 4) {
        return 'Le genre avance (${levels[next].name}), mais le levier nouveau est reporté et la durée ne monte pas : '
            '${t.successes} prise${t.successes > 1 ? 's' : ''} réussie${t.successes > 1 ? 's' : ''} sur ${t.subs.length}, il en faut 4.';
      }
      final st = stages[min(next, stages.length - 1)];
      return 'Le sprint suivant suit le plan : ${levels[next].name}, ${st.minutes} min'
          '${st.fresh.isEmpty ? '' : ', levier nouveau ${st.fresh.map((f) => '${leverOf(f.$1).name} palier ${f.$2}').join(' et ')}'}, '
          'parce que ${levelNo(t) == 0 ? 'le sprint « Fiction time » sert de mise en route' : 'au moins 4 prises sont réussies'}.';
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
      row('Niveau', '${plan.level.n} · ${plan.level.name} · ${plan.minutes} min${starOf(t) ? ' ★' : ''}'),
      row(
          'Euh par minute',
          m == null
              ? 'aucune prise notée'
              : '${fr(m)} en moyenne'
                  '${before == null ? '' : (m < before ? ' (${fr(before - m)} de moins qu\'au sprint précédent)' : m > before ? ' (${fr(m - before)} de plus qu\'au sprint précédent)' : ' (stable)')}'),
      row('Prises réussies', '${t.successes} sur ${t.subs.length}'),
      for (final u in units)
        row(unitName(u), () {
          final (ok, n) = unitStats(u, only: t);
          return '$ok réussite${ok > 1 ? 's' : ''} sur $n';
        }()),
      if (weak != null) row('Levier le plus faible', unitName(weak)),
      row('Sprint suivant', decision()),
    ]);
  }
}
