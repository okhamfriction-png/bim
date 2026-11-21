import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

/// Un niveau d'échauffement : un défi d'une minute, sans « euh ».
class Level {
  final int n;
  final String name, defi, skill;
  final String? fixed; // sujet imposé quand le niveau n'a pas de réserve
  const Level(this.n, this.name, this.defi, this.skill, {this.fixed});
}

const defiSeconds = 60;
const approachSeconds = 300;
const defiRule = 'Zéro « euh »';
const defiOutro = 'Allez là où l\'IA ne va pas.';

const levels = <Level>[
  Level(0, 'Fiction time',
      'Invente une histoire avec ce lieu et ce danger : un personnage veut quelque chose, le danger arrive, il décide.',
      'Démarrer sans préparation',
      fixed: 'Lieu : le premier endroit que tu vois.\nDanger : le premier mot que tu lis.'),
  Level(1, 'Fable', 'Raconte une histoire inventée et finis par sa morale en une phrase.',
      'Structurer vite'),
  Level(2, 'Récit',
      'Raconte un fait réel de ta journée : qui, quoi, où, quand, pourquoi. Aucune opinion.',
      'La clarté'),
  Level(3, 'Anecdote',
      'Pars de cette phrase qu\'on t\'a dite : qui l\'a dite, ce qu\'elle veut dire, un exemple, ta conclusion.',
      'Rebondir'),
  Level(4, 'Maxime',
      'Défends ce proverbe : explique-le, donne un exemple vécu, un contre-exemple, conclus.',
      'Argumenter'),
  Level(5, 'Réfutation',
      'Démonte cette idée reçue : énonce-la honnêtement, deux raisons qu\'elle est fausse, ce qui est vrai.',
      'Contredire sans agresser'),
  Level(6, 'Lieu commun',
      'Attaque ce défaut répandu, jamais une personne : décris-le, montre ses conséquences, appelle à faire autrement.',
      'Monter en intensité'),
  Level(7, 'Éloge ou blâme', 'Fais l\'éloge (ou le blâme) de ce que tu as devant toi.', 'L\'émotion'),
  Level(8, 'Comparaison', 'Compare ces deux choses sur trois critères et tranche.', 'Décider'),
  Level(9, 'Éthopée',
      'Fais parler ce personnage à la première personne : son passé, son présent, ce qu\'il attend.',
      'Incarner'),
  Level(10, 'Description', 'Fais voir ce lieu à quelqu\'un qui n\'y est pas, du large au détail.',
      'Les images'),
  Level(11, 'Thèse', 'Réponds à cette question : les raisons pour, les raisons contre, ta position.',
      'La nuance'),
  Level(12, 'Proposition de loi',
      'Propose cette règle : le problème, la règle, l\'objection la plus forte, ta réponse.',
      'Convaincre'),
];

/// Le niveau d'une tâche d'échauffement, d'après son titre.
Level levelOf(Task t) {
  final m = RegExp(r'niveau\s+(\d+)', caseSensitive: false).firstMatch(t.title);
  final n = m == null ? 0 : int.parse(m.group(1)!);
  return levels[n.clamp(0, levels.length - 1)];
}

/// Record sur un niveau, toutes tâches confondues (0 si aucune prise notée).
int levelRecord(Level l) => store.tasks
    .where((t) => !t.deleted && t.whole && levelOf(t).n == l.n)
    .fold(0, (a, t) => t.record > a ? t.record : a);

/// La fiche d'un échauffement : le défi, la contrainte, le score à battre.
class DefiCard extends StatelessWidget {
  final Task task;
  final TextAlign align;
  const DefiCard(this.task, {this.align = TextAlign.start, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final l = levelOf(task);
    final rec = levelRecord(l);
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
          Wrap(spacing: 8, runSpacing: 6, alignment: center ? WrapAlignment.center : WrapAlignment.start, children: [
            const Pill(defiRule, Color(0xFFEF4444), icon: Icons.block_rounded),
            Pill(rec > 0 ? 'Record à battre : $rec s' : 'Pas encore de record',
                const Color(0xFFF59E0B),
                icon: Icons.emoji_events_rounded),
            Pill('${task.subsDone}/${task.subs.length} prises', const Color(0xFF22C55E),
                icon: Icons.videocam_rounded),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => DefiPage(task), fullscreenDialog: true)),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Lancer le défi',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ]);
  }
}

/// L'écran du défi, à utiliser sur place : chrono d'une minute, bouton « Euh », score,
/// puis cinq minutes pour la première approche.
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
  late int before = levelRecord(levelOf(widget.task)); // record avant cette prise
  Sub? saved; // la prise où le score a été noté

  Level get level => levelOf(widget.task);

  @override
  void dispose() {
    tick?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  int get elapsed => start == null ? 0 : DateTime.now().difference(start!).inSeconds;
  int get approachLeft =>
      ended == null ? approachSeconds : approachSeconds - DateTime.now().difference(ended!).inSeconds;

  void go() {
    WakelockPlus.enable();
    setState(() {
      phase = 'run';
      start = DateTime.now();
    });
    tick?.cancel();
    tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (phase == 'run' && elapsed >= defiSeconds) {
        finish(defiSeconds);
      } else {
        setState(() {});
      }
    });
  }

  void finish(int s) {
    before = levelRecord(level);
    final t = widget.task;
    final sub = t.nextSub;
    if (sub != null) {
      store.toggleSub(t, sub);
      store.setSubResult(t, sub, '$s');
    }
    setState(() {
      phase = 'done';
      score = s.clamp(0, defiSeconds);
      saved = sub;
      ended = DateTime.now();
    });
  }

  Future<void> manual() async {
    final c = TextEditingController(text: phase == 'done' ? '$score' : '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Score de la prise'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              hintText: 'Secondes avant le premier « euh »', suffixText: 's'),
          onSubmitted: (x) => Navigator.pop(ctx, x),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Noter')),
        ],
      ),
    );
    final s = int.tryParse(v?.trim() ?? '');
    if (s == null) return;
    final n = s.clamp(0, defiSeconds);
    if (phase == 'done' && saved != null) {
      // Correction du score qui vient d'être noté.
      store.setSubResult(widget.task, saved!, '$n');
      setState(() => score = n);
    } else {
      tick?.cancel();
      finish(n);
      tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final l = level;
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
                    _ => _ready(p, l),
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ready(Pal p, Level l) {
    final rec = levelRecord(l);
    final left = widget.task.nextSub;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Niveau ${l.n} · ${l.name}',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.accent)),
            const SizedBox(height: 14),
            Text(l.defi,
                style: const TextStyle(
                    fontSize: 27, height: 1.2, fontWeight: FontWeight.w900, letterSpacing: -.4)),
            const SizedBox(height: 20),
            _box(p, 'LE SUJET DU JOUR', l.fixed ?? 'Réserve de sujets à venir.'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _box(p, 'CONTRAINTE', defiRule)),
              const SizedBox(width: 12),
              Expanded(child: _box(p, 'RECORD À BATTRE', rec > 0 ? '$rec s' : '—')),
            ]),
          ]),
        ),
      ),
      if (left == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Toutes les prises du sprint sont faites : celle-ci ne sera pas enregistrée.',
              textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
        ),
      FilledButton(
        onPressed: go,
        style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        child: const Text('Démarrer',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      ),
      TextButton(onPressed: manual, child: const Text('Saisir le score à la main')),
    ]);
  }

  Widget _run(Pal p) {
    final e = elapsed.clamp(0, defiSeconds);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Spacer(),
      Text('$e',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 120,
              height: 1,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()])),
      Text('secondes sans « euh »',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: p.sub)),
      const SizedBox(height: 18),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
            value: e / defiSeconds, minHeight: 10, backgroundColor: p.line, color: p.accent),
      ),
      const Spacer(),
      SizedBox(
        height: 190,
        child: FilledButton(
          onPressed: () => finish(elapsed),
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
          child: const Text('Euh', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900)),
        ),
      ),
    ]);
  }

  Widget _done(Pal p) {
    final beaten = score > before;
    final left = approachLeft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Spacer(),
      Text('$score s',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 96, height: 1, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(
          before == 0
              ? 'Premier score : c\'est ton record.'
              : beaten
                  ? 'Record battu (+${score - before} s)'
                  : score == before
                      ? 'Record égalé'
                      : '${before - score} s sous ton record ($before s)',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: beaten || before == 0 ? const Color(0xFF22C55E) : p.sub)),
      const SizedBox(height: 14),
      Text('Termine par : « $defiOutro »',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: p.ink)),
      if (saved == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Prise libre, non enregistrée.',
              textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
        ),
      TextButton(onPressed: manual, child: const Text('Corriger le score')),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
            color: left <= 0 ? const Color(0xFF22C55E) : p.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: left <= 0 ? const Color(0xFF22C55E) : p.line)),
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

  Widget _box(Pal p, String label, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: p.sub)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 19, height: 1.3, fontWeight: FontWeight.w700)),
        ]),
      );
}
