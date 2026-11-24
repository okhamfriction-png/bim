// Santé du jour : deux cases par jour (physique, mentale), comptées à part des points du sprint.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

const santeColor = Color(0xFFEC4899);
const santeP = Color(0xFF22C55E); // physique
const santeM = Color(0xFF8B5CF6); // mentale
const _keys = [('p', 'Santé physique', santeP), ('m', 'Santé mentale', santeM)];
const _short = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];

DateTime _plus(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Une case à trois états : tenu, pas tenu, pas renseigné.
class _Box extends StatelessWidget {
  final bool? value;
  final Color color;
  final VoidCallback? onTap;
  const _Box(this.value, this.color, this.onTap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = value == true ? color : (value == false ? prioColors[0] : p.line);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Center(
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: value == true ? c : (value == false ? c.withValues(alpha: .14) : null),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c, width: 2)),
            child: value == null
                ? null
                : Icon(value! ? Icons.check_rounded : Icons.close_rounded,
                    size: 21, color: value! ? Colors.white : c),
          ),
        ),
      ),
    );
  }
}

/// Le bloc en bas du sprint : une ligne par jour, du lundi au dimanche.
/// Replié par défaut : seule la ligne du jour est affichée. Un appui sur l'en-tête montre la semaine.
class SantePanel extends StatefulWidget {
  final String sprint;
  const SantePanel(this.sprint, {super.key});
  @override
  State<SantePanel> createState() => _SantePanelState();
}

class _SantePanelState extends State<SantePanel> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final sprint = widget.sprint;
    final d0 = dateOf(sprint);
    final today = ymd(DateTime.now());
    final (a, b) = store.healthIn(sprint);
    // Aujourd'hui hors de cette semaine : rien à replier sur le jour, on montre tout.
    final inWeek = [for (var i = 0; i < 7; i++) ymd(_plus(d0, i))].contains(today);
    return Panel(
      header: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => open = !open),
        child: PanelHead('Santé du jour',
            subtitle: 'Est-ce que j\'ai tenu ?',
            icon: Icons.favorite_rounded,
            color: santeColor,
            count: 'Santé : ${a + b}/14',
            trailing: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: p.sub)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
          child: Row(children: [
            const SizedBox(width: 76),
            for (final k in _keys)
              Expanded(
                child: Text(k.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub)),
              ),
          ]),
        ),
        for (var i = 0; i < 7; i++)
          if (open || inWeek == false || ymd(_plus(d0, i)) == today)
          Builder(builder: (context) {
            final day = _plus(d0, i);
            final d = ymd(day);
            final future = d.compareTo(today) > 0;
            final now = d == today;
            return Opacity(
              opacity: future ? .35 : 1,
              child: Container(
                color: now ? santeColor.withValues(alpha: .10) : null,
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Row(children: [
                  SizedBox(
                    width: 76,
                    child: Text('${_short[i]} ${day.day}',
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: now ? FontWeight.w900 : FontWeight.w600,
                            color: p.ink)),
                  ),
                  for (final k in _keys)
                    Expanded(
                      child: _Box(
                          store.health(d, k.$1),
                          k.$3,
                          future
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  store.cycleHealth(d, k.$1);
                                }),
                    ),
                ]),
              ),
            );
          }),
      ],
    );
  }
}

/// Chiffres de la section « Santé » du tableau de bord, sur 8 semaines.
class SanteKpi {
  static const weeks = 8;
  final List<DateTime> mondays = [];
  final List<int> p = [], m = [], both = []; // jours tenus par semaine
  final Map<String, int> streak = {}, best = {}; // série en cours et meilleure série, par case
  // Approches de rue les jours « mentale tenue » et « pas tenue » : (jours, moyenne).
  (int, double) rueHeld = (0, 0), rueMissed = (0, 0);

  SanteKpi() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final m0 = Schedule.mondayOf(now);
    for (var i = weeks - 1; i >= 0; i--) {
      final mo = _plus(m0, -7 * i);
      mondays.add(mo);
      var a = 0, b = 0, c = 0;
      for (var j = 0; j < 7; j++) {
        final d = ymd(_plus(mo, j));
        final x = store.health(d, 'p') == true, y = store.health(d, 'm') == true;
        if (x) a++;
        if (y) b++;
        if (x && y) c++;
      }
      p.add(a);
      m.add(b);
      both.add(c);
    }
    final days = [
      for (final e in store.schedule.events)
        if (e['sante'] is String && e['deleted'] != true) e['sante'] as String
    ]..sort();
    for (final k in ['p', 'm']) {
      // En cours : on remonte depuis aujourd'hui (ou hier si aujourd'hui n'est pas renseigné).
      var d = store.health(ymd(today), k) == null ? _plus(today, -1) : today;
      var n = 0;
      while (store.health(ymd(d), k) == true) {
        n++;
        d = _plus(d, -1);
      }
      streak[k] = n;
      var top = 0, run = 0;
      if (days.isNotEmpty) {
        for (var x = dateOf(days.first); !x.isAfter(today); x = _plus(x, 1)) {
          run = store.health(ymd(x), k) == true ? run + 1 : 0;
          top = max(top, run);
        }
      }
      best[k] = top;
    }
    // Approches notées par jour (le jour où le bloc de rue a été coché).
    final rue = <String, int>{};
    for (final t in store.tasks) {
      if (t.deleted || t.kindOf != 'rue') continue;
      for (final s in t.subs) {
        final n = s.count('approches');
        if (n == null || s.doneAt == null) continue;
        final d = ymd(DateTime.fromMillisecondsSinceEpoch(s.doneAt!));
        rue[d] = (rue[d] ?? 0) + n;
      }
    }
    final held = <int>[], missed = <int>[];
    rue.forEach((d, n) {
      final v = store.health(d, 'm');
      if (v == true) held.add(n);
      if (v == false) missed.add(n);
    });
    double avg(List<int> l) => l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;
    rueHeld = (held.length, avg(held));
    rueMissed = (missed.length, avg(missed));
  }
}

/// La section « Santé » du tableau de bord.
class SanteKpiView extends StatelessWidget {
  const SanteKpiView({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final k = SanteKpi();
    String j(int n) => '$n j';
    Widget cell(String s, {Color? color, bool bold = true, TextAlign align = TextAlign.center}) =>
        Text(s,
            textAlign: align,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? p.ink));
    Widget row(List<Widget> c, {Color? bg}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(children: [
            Expanded(flex: 3, child: c[0]),
            for (final w in c.skip(1)) Expanded(flex: 2, child: w),
          ]),
        );
    final ok = k.rueHeld.$1 >= 5 && k.rueMissed.$1 >= 5;
    String avg((int, double) g) =>
        g.$1 == 0 ? '–' : g.$2.toStringAsFixed(1).replaceAll('.', ',');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        header: const PanelHead('Santé',
            subtitle: 'Jours tenus sur 7, par semaine',
            icon: Icons.favorite_rounded,
            color: santeColor),
        children: [
          row([
            cell('Semaine du', color: p.sub, align: TextAlign.left),
            cell('Santé\nphysique', color: santeP),
            cell('Santé\nmentale', color: santeM),
            cell('Les deux', color: p.sub),
          ]),
          for (var i = SanteKpi.weeks - 1; i >= 0; i--)
            row([
              cell('${k.mondays[i].day} ${monthNames[k.mondays[i].month - 1]}',
                  bold: i == SanteKpi.weeks - 1, align: TextAlign.left),
              cell('${k.p[i]}/7'),
              cell('${k.m[i]}/7'),
              cell('${k.both[i]}/7'),
            ], bg: i == SanteKpi.weeks - 1 ? santeColor.withValues(alpha: .08) : null),
        ],
      ),
      Panel(header: const PanelHead('Séries', subtitle: 'Jours tenus d\'affilée'), children: [
        row([
          const SizedBox(),
          cell('En cours', color: p.sub),
          cell('Meilleure', color: p.sub),
        ]),
        for (final x in _keys)
          row([
            cell(x.$2, color: x.$3, align: TextAlign.left),
            cell(j(k.streak[x.$1]!)),
            cell(j(k.best[x.$1]!)),
          ]),
      ]),
      Panel(
        header: const PanelHead('Santé sur 8 semaines', subtitle: 'Jours tenus par semaine'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            child: SizedBox(
                height: 160,
                child: CustomPaint(
                    painter: _Lines([k.p, k.m], const [santeP, santeM],
                        [for (final mo in k.mondays) '${mo.day}/${mo.month}'], p))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Wrap(spacing: 14, children: [
              for (final x in _keys)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 6),
                      decoration:
                          BoxDecoration(color: x.$3, borderRadius: BorderRadius.circular(3))),
                  Text(x.$2, style: TextStyle(fontSize: 12.5, color: p.sub)),
                ]),
            ]),
          ),
        ],
      ),
      Panel(
        header: const PanelHead('Santé mentale et rue',
            subtitle: 'Moyenne d\'approches par jour de rue'),
        children: [
          row([
            cell('Santé mentale', color: p.sub, align: TextAlign.left),
            cell('Jours', color: p.sub),
            cell('Moyenne', color: p.sub),
          ]),
          row([
            cell('Tenue', align: TextAlign.left),
            cell('${k.rueHeld.$1}'),
            cell(ok ? avg(k.rueHeld) : '–'),
          ]),
          row([
            cell('Pas tenue', align: TextAlign.left),
            cell('${k.rueMissed.$1}'),
            cell(ok ? avg(k.rueMissed) : '–'),
          ]),
          if (!ok)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Text('Pas assez de données : il faut 5 jours dans chaque groupe.',
                  style: TextStyle(fontSize: 13, color: p.sub)),
            ),
        ],
      ),
    ]);
  }
}

/// Courbes : une ligne par case, de 0 à 7 jours.
class _Lines extends CustomPainter {
  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  final Pal p;
  _Lines(this.series, this.colors, this.labels, this.p);

  @override
  void paint(Canvas c, Size s) {
    const left = 18.0, down = 18.0, up = 6.0;
    final n = labels.length;
    double x(int i) => left + 6 + (s.width - left - 24) * (n == 1 ? .5 : i / (n - 1));
    double y(num v) => up + (s.height - up - down) * (1 - v / 7);
    void text(String t, Offset at, {TextAlign align = TextAlign.center}) {
      final tp = TextPainter(
          text: TextSpan(text: t, style: TextStyle(fontSize: 11, color: p.sub)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
    }

    for (final v in [0, 7]) {
      c.drawLine(Offset(left, y(v)), Offset(s.width, y(v)), Paint()..color = p.line);
      text('$v', Offset(6, y(v)));
    }
    for (var i = 0; i < n; i++) {
      text(labels[i], Offset(x(i), s.height - 6));
    }
    for (var k = 0; k < series.length; k++) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        i == 0 ? path.moveTo(x(i), y(series[k][i])) : path.lineTo(x(i), y(series[k][i]));
      }
      c.drawPath(
          path,
          Paint()
            ..color = colors[k]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round);
      for (var i = 0; i < n; i++) {
        c.drawCircle(Offset(x(i), y(series[k][i])), 3.5, Paint()..color = colors[k]);
      }
    }
  }

  @override
  bool shouldRepaint(_Lines o) => true;
}
