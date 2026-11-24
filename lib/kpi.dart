// Tableau de bord : les chiffres et les courbes pour analyser ce qui a été fait ou non.
// Tout est recalculé à partir des tâches et des clôtures ; rien n'est enregistré ici.
// La version bureau fait les mêmes calculs (bureau/src/lib/kpi.svelte.js).
import 'dart:math';

import 'package:flutter/material.dart';

import 'cloture.dart';
import 'models.dart';
import 'sante.dart';
import 'store.dart';
import 'ui.dart';

const _day = 86400000;
const _ok = Color(0xFF22C55E);
const _blue = Color(0xFF0EA5E9);
const kindColors = <String, Color>{
  'rue': Color(0xFFF59E0B),
  'paris': Color(0xFFEF4444),
  'montee': Color(0xFFA855F7),
  'short': Color(0xFF0EA5E9),
  'rangement': Color(0xFF22C55E),
  'recap': Color(0xFF14B8A6),
  'echauffement': Color(0xFFF97316),
};

/// Tous les indicateurs sur les `weeks` dernières semaines (semaine en cours comprise).
class Kpi {
  final int weeks;
  final List<DateTime> mondays = [];
  final List<int> created = [], done = [], dropped = [];
  final List<Map<String, int>> points = []; // par semaine : type → points de valeur
  final Map<String, int> byCat = {}, byPrio = {};
  final List<double> lead = []; // jours entre la création et la fin
  final Map<int, List<double>> leadByPrio = {};
  int open = 0, parked = 0, noSprint = 0, stale = 0, reported = 0, reportedTwice = 0;
  final List<int> ages = [0, 0, 0, 0]; // 0–7 j, 8–30 j, 31–90 j, plus
  // Sprint en cours : points restant à la fin de chaque jour (jusqu'à aujourd'hui).
  String? burnSprint;
  int burnTotal = 0;
  final List<int> burn = [];
  // Sprints clôturés (du plus ancien au plus récent) : (lundi, terminées, engagées, points, cible).
  final List<(String, int, int, int, int)> sprints = [];

  Kpi(this.weeks) {
    final now = DateTime.now();
    final m0 = Schedule.mondayOf(now);
    for (var i = weeks - 1; i >= 0; i--) {
      mondays.add(DateTime(m0.year, m0.month, m0.day - 7 * i));
    }
    int ix(int? ms) {
      if (ms == null) return -1;
      for (var i = 0; i < weeks; i++) {
        final a = mondays[i].millisecondsSinceEpoch;
        final b = DateTime(mondays[i].year, mondays[i].month, mondays[i].day + 7)
            .millisecondsSinceEpoch;
        if (ms >= a && ms < b) return i;
      }
      return -1;
    }

    created.addAll(List.filled(weeks, 0));
    done.addAll(List.filled(weeks, 0));
    dropped.addAll(List.filled(weeks, 0));
    for (var i = 0; i < weeks; i++) {
      final a = mondays[i].millisecondsSinceEpoch;
      final b =
          DateTime(mondays[i].year, mondays[i].month, mondays[i].day + 7).millisecondsSinceEpoch;
      final u = store.unitsBetween(a, b);
      points.add({for (final e in u.entries) e.key: e.value * (store.schedule.coef[e.key] ?? 0)});
    }
    final nowMs = now.millisecondsSinceEpoch;
    for (final t in store.tasks) {
      if (t.deleted) continue;
      final c = ix(t.createdAt);
      if (c >= 0) created[c]++;
      if (t.status == 'done') {
        final d = ix(t.doneAt);
        if (d >= 0) {
          done[d]++;
          byCat[t.cat] = (byCat[t.cat] ?? 0) + 1;
          byPrio[prioNames[t.priority]] = (byPrio[prioNames[t.priority]] ?? 0) + 1;
          if (t.createdAt > 0) {
            final days = max(0, t.doneAt! - t.createdAt) / _day;
            lead.add(days);
            leadByPrio.putIfAbsent(t.priority, () => []).add(days);
          }
        }
      } else if (t.status == 'dropped') {
        final d = ix(t.updatedAt);
        if (d >= 0) dropped[d]++;
      } else if (t.parked) {
        parked++;
      } else {
        open++;
        if (store.sprintOf(t) == null) noSprint++;
        if (t.updatedAt < nowMs - 7 * _day) stale++;
        if (t.reports >= 1) reported++;
        if (t.reports >= 2) reportedTwice++;
        final age = (nowMs - t.createdAt) / _day;
        ages[age <= 7 ? 0 : (age <= 30 ? 1 : (age <= 90 ? 2 : 3))]++;
      }
    }
    // Burndown du sprint en cours, s'il a commencé.
    final s = store.current;
    if (s.compareTo(store.thisMonday) <= 0 && store.schedule.sprints.contains(s)) {
      burnSprint = s;
      final ts = store.tasks.where((t) => !t.deleted && t.sprint == s && t.status != 'dropped');
      burnTotal = ts.fold(0, (a, t) => a + store.plannedOf(t));
      final start = dateOf(s);
      for (var i = 0; i < 7; i++) {
        final end = DateTime(start.year, start.month, start.day + i + 1).millisecondsSinceEpoch;
        if (DateTime(start.year, start.month, start.day + i).millisecondsSinceEpoch > nowMs) break;
        var got = 0;
        for (final t in ts) {
          final c = store.coefOf(t);
          if (c == 0) continue;
          if (t.subs.isEmpty || t.whole) {
            if (t.status == 'done' && (t.doneAt ?? t.updatedAt) < end) got += c;
          } else {
            got += c *
                t.subs.where((x) => x.done && (x.doneAt ?? t.doneAt ?? t.updatedAt) < end).length;
          }
        }
        burn.add(burnTotal - got);
      }
    }
    for (final k in store.closedSprints.take(12).toList().reversed) {
      final b = store.schedule.closures[k]!;
      int n(String key) => (b[key] as List? ?? []).length;
      sprints.add((
        k,
        n('done'),
        n('done') + n('carried') + n('parked') + n('dropped'),
        (b['points'] as num).toInt(),
        (b['target'] as num).toInt()
      ));
    }
  }

  int get totalDone => done.fold(0, (a, b) => a + b);
  int get totalCreated => created.fold(0, (a, b) => a + b);
  int get totalDropped => dropped.fold(0, (a, b) => a + b);
  int get totalPoints => points.fold(0, (a, w) => a + w.values.fold(0, (x, y) => x + y));

  static double? median(List<double> l) {
    if (l.isEmpty) return null;
    final s = [...l]..sort();
    return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
  }

  /// « 3 j », « 5 h », « – » sans donnée.
  static String days(double? d) {
    if (d == null) return '–';
    if (d < 1) return '${max(1, (d * 24).round())} h';
    return d < 10 ? '${d.toStringAsFixed(1).replaceAll('.', ',')} j' : '${d.round()} j';
  }
}

void openKpi(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KpiPage()));

class KpiPage extends StatefulWidget {
  const KpiPage({super.key});
  @override
  State<KpiPage> createState() => _KpiPageState();
}

class _KpiPageState extends State<KpiPage> {
  int weeks = 8;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final p = Pal.of(context);
          final k = Kpi(weeks);
          final labels = [for (final m in k.mondays) '${m.day}/${m.month}'];
          final rate = k.totalCreated == 0 ? null : (100 * k.totalDone / k.totalCreated).round();
          Widget tile(String label, String value, [String? sub, Color? color]) => Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(fontSize: 12.5, color: p.sub)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w900, color: color ?? p.ink)),
                  if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: p.sub)),
                ]),
              );
          Widget chart(String title, String sub, Widget child, [List<(String, Color)>? legend]) =>
              Panel(header: PanelHead(title, subtitle: sub), children: [
                Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 8), child: child),
                if (legend != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Wrap(spacing: 14, runSpacing: 4, children: [
                      for (final l in legend)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                  color: l.$2, borderRadius: BorderRadius.circular(3))),
                          Text(l.$1, style: TextStyle(fontSize: 12.5, color: p.sub)),
                        ]),
                    ]),
                  ),
              ]);
          Widget share(String title, String sub, Map<String, int> data, Color Function(String) c,
              List<String> order) {
            final total = data.values.fold(0, (a, b) => a + b);
            return Panel(header: PanelHead(title, subtitle: sub), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(children: [
                  if (total == 0) Text('Rien sur la période.', style: TextStyle(color: p.sub)),
                  for (final key in order)
                    if ((data[key] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(width: 86, child: Text(key)),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                  value: data[key]! / total,
                                  minHeight: 9,
                                  backgroundColor: p.line,
                                  color: c(key)),
                            ),
                          ),
                          SizedBox(
                            width: 74,
                            child: Text(
                                '${data[key]} · ${(100 * data[key]! / total).round()} %',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ]),
                      ),
                ]),
              ),
            ]);
          }

          final usedKinds = [
            for (final kk in kinds.keys)
              if (k.points.any((w) => (w[kk] ?? 0) > 0)) kk
          ];
          return Scaffold(
            appBar: AppBar(title: const Text('Tableau de bord')),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Segmented(const {'4': '4 semaines', '8': '8 semaines', '12': '12 semaines'},
                        '$weeks', (v) => setState(() => weeks = int.parse(v)),
                        expand: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.45,
                      children: [
                        tile('Faites', '${k.totalDone}', 'sur $weeks semaines', _ok),
                        tile('Créées', '${k.totalCreated}',
                            rate == null ? null : '$rate % de faites'),
                        tile('Points', '${k.totalPoints}', 'de valeur'),
                        tile('Délai médian', Kpi.days(Kpi.median(k.lead)), 'création → fait'),
                        tile('Ouvertes', '${k.open}', '${k.parked} au parking'),
                        tile('Abandonnées', '${k.totalDropped}', null,
                            k.totalDropped > 0 ? prioColors[0] : null),
                      ],
                    ),
                  ),
                  if (k.burnSprint != null)
                    chart(
                        'Burndown du sprint en cours',
                        'Sprint du ${sprintRange(k.burnSprint!)} · points restants',
                        SizedBox(
                            height: 170,
                            child: CustomPaint(painter: _Burn(k.burnTotal, k.burn, p))),
                        [('Restant', p.accent), ('Rythme idéal', p.sub)]),
                  chart(
                      'Créées et faites par semaine',
                      'Si les créées dépassent les faites, le backlog grossit',
                      SizedBox(
                          height: 170,
                          child: CustomPaint(
                              painter: _Bars(labels, [
                            [for (final v in k.created) v.toDouble()],
                            [for (final v in k.done) v.toDouble()],
                          ], [
                            p.sub,
                            _ok
                          ], p))),
                      [('Créées', p.sub), ('Faites', _ok)]),
                  chart(
                      'Points de valeur par semaine',
                      'Par type de tâche',
                      SizedBox(
                          height: 170,
                          child: CustomPaint(
                              painter: _Bars(labels, [
                            for (final kk in usedKinds)
                              [for (final w in k.points) (w[kk] ?? 0).toDouble()]
                          ], [
                            for (final kk in usedKinds) kindColors[kk]!
                          ], p, stacked: true))),
                      [for (final kk in usedKinds) (kinds[kk]!.$1, kindColors[kk]!)]),
                  if (k.sprints.isNotEmpty)
                    chart(
                        'Engagement tenu par sprint',
                        'Tâches terminées sur tâches engagées, à la clôture',
                        SizedBox(
                            height: 170,
                            child: CustomPaint(
                                painter: _Bars([
                              for (final s in k.sprints)
                                '${dateOf(s.$1).day}/${dateOf(s.$1).month}'
                            ], [
                              [for (final s in k.sprints) s.$3 == 0 ? 0 : 100 * s.$2 / s.$3],
                            ], [
                              _blue
                            ], p, suffix: ' %', top: 100))),
                        null),
                  share('Faites par catégorie', 'Sur $weeks semaines', k.byCat, domainOf, cats),
                  share('Faites par priorité', 'Sur $weeks semaines', k.byPrio,
                      (s) => prioColors[prioNames.indexOf(s)], prioNames),
                  Panel(
                      header: const PanelHead('Délai de réalisation',
                          subtitle: 'De la création à la fin, médiane par priorité'),
                      children: [
                        for (var i = 0; i <= 4; i++)
                          if (k.leadByPrio[i] != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              child: Row(children: [
                                PrioChip(i),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text('${k.leadByPrio[i]!.length} tâches',
                                        style: TextStyle(color: p.sub))),
                                Text(Kpi.days(Kpi.median(k.leadByPrio[i]!)),
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                              ]),
                            ),
                        if (k.lead.isEmpty)
                          Padding(
                              padding: const EdgeInsets.all(14),
                              child:
                                  Text('Rien de terminé sur la période.', style: TextStyle(color: p.sub))),
                      ]),
                  const SanteKpiView(),
                  Panel(
                      header: const PanelHead('Ce qui reste ouvert',
                          subtitle: 'Hors parking, aujourd\'hui'),
                      children: [
                        for (final r in [
                          ('Créées depuis 7 jours ou moins', k.ages[0], null),
                          ('Entre 8 et 30 jours', k.ages[1], null),
                          ('Entre 31 et 90 jours', k.ages[2], null),
                          ('Plus de 90 jours', k.ages[3], k.ages[3] > 0 ? prioColors[0] : null),
                          ('Hors sprint', k.noSprint, null),
                          ('Jamais touchées depuis 7 jours', k.stale, null),
                          ('Déjà reportées', k.reported, null),
                          ('Reportées 2 fois ou plus', k.reportedTwice,
                              k.reportedTwice > 0 ? prioColors[0] : null),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            child: Row(children: [
                              Expanded(child: Text(r.$1)),
                              Text('${r.$2}',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: r.$3)),
                            ]),
                          ),
                      ]),
                ]),
              ),
            ),
          );
        },
      );
}

void _label(Canvas c, String s, Offset center, Color color, {bool bold = false}) {
  final t = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      textDirection: TextDirection.ltr)
    ..layout();
  t.paint(c, center - Offset(t.width / 2, t.height / 2));
}

/// Barres par semaine : groupées (une par série) ou empilées.
class _Bars extends CustomPainter {
  final List<String> labels;
  final List<List<double>> series;
  final List<Color> colors;
  final Pal p;
  final bool stacked;
  final String suffix;
  final double? top;
  _Bars(this.labels, this.series, this.colors, this.p,
      {this.stacked = false, this.suffix = '', this.top});

  @override
  void paint(Canvas canvas, Size size) {
    const up = 16.0, down = 20.0;
    final h = size.height - up - down;
    final n = labels.length;
    if (n == 0) return;
    var hi = top ?? 1.0;
    for (var i = 0; i < n; i++) {
      final v = stacked
          ? series.fold(0.0, (a, s) => a + s[i])
          : series.fold(0.0, (a, s) => max(a, s[i]));
      if (v > hi) hi = v;
    }
    double y(double v) => up + h - h * v / hi;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), Paint()..color = p.line);
    final slot = size.width / n;
    final group = min(slot * .72, 44.0);
    for (var i = 0; i < n; i++) {
      final x = slot * (i + .5);
      if (stacked) {
        var base = 0.0;
        for (var s = 0; s < series.length; s++) {
          final v = series[s][i];
          if (v <= 0) continue;
          canvas.drawRect(Rect.fromLTRB(x - group / 2, y(base + v), x + group / 2, y(base)),
              Paint()..color = colors[s]);
          base += v;
        }
        if (base > 0) {
          _label(canvas, '${base.round()}$suffix', Offset(x, y(base) - 8), p.ink, bold: true);
        }
      } else {
        final w = group / max(1, series.length);
        for (var s = 0; s < series.length; s++) {
          final v = series[s][i];
          final x0 = x - group / 2 + w * s;
          if (v > 0) {
            canvas.drawRRect(
                RRect.fromRectAndCorners(Rect.fromLTRB(x0 + 1, y(v), x0 + w - 1, y(0)),
                    topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
                Paint()..color = colors[s]);
            _label(canvas, '${v.round()}$suffix', Offset(x0 + w / 2, y(v) - 8), p.ink, bold: true);
          }
        }
      }
      if (n <= 8 || i.isEven) _label(canvas, labels[i], Offset(x, size.height - 7), p.sub);
    }
  }

  @override
  bool shouldRepaint(covariant _Bars old) => true;
}

/// Points restants jour après jour, et la droite du rythme idéal.
class _Burn extends CustomPainter {
  final int total;
  final List<int> left;
  final Pal p;
  _Burn(this.total, this.left, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    const up = 16.0, down = 20.0, pad = 14.0;
    final h = size.height - up - down;
    final hi = max(1, total).toDouble();
    double y(num v) => up + h - h * v / hi;
    double x(int day) => pad + (size.width - 2 * pad) * day / 7; // 0 = lundi matin, 7 = dimanche soir
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), Paint()..color = p.line);
    canvas.drawLine(
        Offset(x(0), y(total)),
        Offset(x(7), y(0)),
        Paint()
          ..color = p.sub
          ..strokeWidth = 1.5);
    final line = Paint()
      ..color = p.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(x(0), y(total));
    for (var i = 0; i < left.length; i++) {
      path.lineTo(x(i + 1), y(left[i]));
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < left.length; i++) {
      canvas.drawCircle(Offset(x(i + 1), y(left[i])), 3.5, Paint()..color = p.accent);
    }
    _label(canvas, '$total', Offset(x(0), y(total) - 9), p.ink, bold: true);
    if (left.isNotEmpty) {
      _label(canvas, '${left.last}', Offset(x(left.length), y(left.last) - 10), p.ink, bold: true);
    }
    for (var i = 0; i < 7; i++) {
      _label(canvas, dayLetters[i], Offset((x(i) + x(i + 1)) / 2, size.height - 7), p.sub);
    }
  }

  @override
  bool shouldRepaint(covariant _Burn old) => true;
}
