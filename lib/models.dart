import 'dart:convert';
import 'dart:math';

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOf(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

final _rnd = Random();
String newId() {
  const c = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(8, (_) => c[_rnd.nextInt(c.length)]).join();
}

/// Catégories, dans l'ordre de priorité. Le Parking n'apparaît jamais dans Maintenant.
const cats = ['Mission', 'Contenu', 'Destiny', 'Personnel', 'Parking'];

/// Types de tâche qui rapportent des points de valeur : (nom, unité au pluriel, points par
/// unité par défaut). Une tâche n'a qu'un type : pas de cumul.
const kinds = <String, (String, String, int)>{
  'rue': ('Rue', 'blocs', 3),
  'paris': ('Vidéo Paris', 'vidéos', 2),
  'montee': ('Vidéo montée', 'vidéos', 2),
  'short': ('Short', 'shorts', 1),
  'rangement': ('Rangement', 'jours', 1),
  'echauffement': ('Échauffement', 'sprints', 2),
};

/// Types payés une seule fois, quand la tâche entière est validée : ses sous-tâches
/// (les prises à publier) ne rapportent rien une par une.
const wholeKinds = {'echauffement'};

/// Demandes de rue dans un bloc.
const askPerBlock = 20;

/// Ce qu'on note à la fin d'un bloc de rue : (clé, libellé, vrai si c'est un nombre).
const blockFields = <(String, String, bool)>[
  ('approches', 'Approches (sur 20)', true),
  ('avant', 'Abonnés de la page avant', true),
  ('apres', 'Abonnés de la page après', true),
  ('demandes', 'Demandes de place faites', true),
  ('oui', 'Nombre de oui', true),
  ('objection', 'Objection la plus entendue', false),
  ('changer', 'Une chose à changer au bloc suivant', false),
];

/// Un jeton bonus à dépenser tous les 30 points gagnés en abordage de rue.
const bonusEvery = 30;

/// Une sous-tâche : un titre et une case à cocher.
class Sub {
  String title;
  bool done;
  int? doneAt; // instant où la case a été cochée
  String result; // résultat propre à la sous-tâche (score d'une prise d'échauffement)
  Map<String, dynamic> data; // résultat chiffré d'un bloc de rue (clés de `blockFields`)
  Sub(this.title, {this.done = false, this.doneAt, this.result = '', Map<String, dynamic>? data})
      : data = data ?? {};

  int? count(String k) => (data[k] as num?)?.toInt();

  // ---- Prise d'échauffement : secondes tenues avant le premier « euh », levier joué ou non ----
  int? get held => count('duree');
  bool get noted => (held ?? 0) > 0;
  bool get leverOk => data['levierOk'] == true;

  /// Prise réussie : le levier du jour a été joué avant le premier « euh ».
  bool get success => noted && leverOk;

  /// Abonnés gagnés pendant le bloc, si les deux compteurs sont notés.
  int? get gained => count('avant') != null && count('apres') != null ? count('apres')! - count('avant')! : null;

  /// « 20/20 · +3 abonnés · 1/4 places », vide si rien n'est noté.
  String get blockSummary => [
        if (count('approches') != null) '${count('approches')}/$askPerBlock',
        if (gained != null) '${gained! >= 0 ? '+' : ''}$gained ab.',
        if (count('demandes') != null || count('oui') != null)
          '${count('oui') ?? 0}/${count('demandes') ?? 0} places',
      ].join(' · ');
  factory Sub.fromJson(Map<String, dynamic> j) => Sub((j['title'] ?? '') as String,
      done: (j['done'] ?? false) as bool,
      doneAt: (j['doneAt'] as num?)?.toInt(),
      result: '${j['result'] ?? ''}',
      data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : null);
  Map<String, dynamic> toJson() => {
        'title': title,
        'done': done,
        if (doneAt != null) 'doneAt': doneAt,
        if (result.isNotEmpty) 'result': result,
        if (data.isNotEmpty) 'data': data,
      };
}

/// Une tâche du backlog. Format partagé avec la commande `bin/bim`.
class Task {
  String id;
  String title;
  String note;
  String domain; // catégorie
  int priority; // P0 (le plus urgent) à P4
  String source; // conversation ou agent qui a créé la tâche
  List<String> links; // liens, vidéos, images
  double rank;
  String status; // todo | done | dropped (abandonnée à une clôture : gardée, plus affichée)
  int createdAt;
  int updatedAt;
  int? doneAt;
  String? pickedOn; // jour (aaaa-mm-jj) où elle a été choisie parmi les 3 tâches du jour
  bool call; // appel ou entretien de mission : passe devant tout
  String? sprint; // lundi (aaaa-mm-jj) du sprint d'une semaine où elle est rangée
  bool deleted;
  List<Sub> subs; // sous-tâches (aucune pour une tâche simple)
  bool archived; // tâche terminée rangée dans les archives
  String result; // résultat facultatif, montré dans la revue (« 2 venus »)
  String kind; // type de points de valeur (clé de `kinds`), vide = aucun
  Map<String, dynamic> meta; // réservé aux échauffements : niveau, durée, cible, leviers

  Task({
    String? id,
    required this.title,
    this.note = '',
    this.domain = 'Mission',
    this.priority = 2,
    this.source = '',
    List<String>? links,
    this.rank = 0,
    this.status = 'todo',
    int? createdAt,
    int? updatedAt,
    this.doneAt,
    this.pickedOn,
    this.call = false,
    this.sprint,
    this.deleted = false,
    List<Sub>? subs,
    this.result = '',
    this.kind = '',
    this.archived = false,
    Map<String, dynamic>? meta,
  })  : id = id ?? newId(),
        meta = meta ?? {},
        subs = subs ?? [],
        links = links ?? [],
        createdAt = createdAt ?? nowMs(),
        updatedAt = updatedAt ?? nowMs();

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        note: (j['note'] ?? '') as String,
        domain: (j['domain'] ?? 'Personnel') as String,
        priority: ((j['priority'] ?? 2) as num).toInt().clamp(0, 4),
        source: (j['source'] ?? '') as String,
        links: ((j['links'] ?? []) as List).map((e) => '$e').toList(),
        rank: ((j['rank'] ?? 0) as num).toDouble(),
        status: (j['status'] ?? 'todo') as String,
        createdAt: ((j['createdAt'] ?? 0) as num).toInt(),
        updatedAt: ((j['updatedAt'] ?? 0) as num).toInt(),
        doneAt: (j['doneAt'] as num?)?.toInt(),
        pickedOn: j['pickedOn'] as String?,
        call: (j['call'] ?? false) as bool,
        sprint: j['sprint'] as String?,
        deleted: (j['deleted'] ?? false) as bool,
        subs: ((j['subs'] ?? []) as List)
            .map((e) => Sub.fromJson(e as Map<String, dynamic>))
            .toList(),
        result: (j['result'] ?? '') as String,
        kind: (j['kind'] ?? '') as String,
        archived: (j['archived'] ?? false) as bool,
        meta: j['meta'] is Map ? Map<String, dynamic>.from(j['meta'] as Map) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'domain': domain,
        'priority': priority,
        'source': source,
        'links': links,
        'rank': rank,
        'status': status,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'doneAt': doneAt,
        'pickedOn': pickedOn,
        'call': call,
        'sprint': sprint,
        'deleted': deleted,
        if (subs.isNotEmpty) 'subs': [for (final s in subs) s.toJson()],
        if (result.isNotEmpty) 'result': result,
        if (kind.isNotEmpty) 'kind': kind,
        if (archived) 'archived': true,
        if (meta.isNotEmpty) 'meta': meta,
      };

  /// Catégorie reconnue (les anciennes valeurs retombent sur Mission ou Personnel).
  String get cat =>
      cats.contains(domain) ? domain : (domain == 'Travail' ? 'Mission' : 'Personnel');
  int get catRank => cats.indexOf(cat);
  bool get parked => cat == 'Parking';
  bool get open => !deleted && status == 'todo';

  /// Terminée pour de bon : cochée, et toutes ses sous-tâches aussi.
  bool get complete => status == 'done' && subs.every((s) => s.done);

  /// Reports d'un sprint au suivant, décidés à la clôture.
  int get reports => (meta['reports'] as num?)?.toInt() ?? 0;
  String? get reportedFrom => meta['reporteDe'] as String?;
  int get subsDone => subs.where((s) => s.done).length;
  String get progress => '$subsDone/${subs.length}';

  /// Type de points : celui choisi, sinon celui annoncé au début du titre (« Rue · … »).
  String get kindOf {
    if (kinds.containsKey(kind)) return kind;
    final s = title.toLowerCase();
    if (s.startsWith('rue ·')) return 'rue';
    if (s.startsWith('vidéo paris')) return 'paris';
    if (s.startsWith('vidéo montée')) return 'montee';
    if (s.startsWith('short ·')) return 'short';
    if (s.startsWith('rangement ·')) return 'rangement';
    if (s.startsWith('échauffement ·')) return 'echauffement';
    return '';
  }

  /// Unités à livrer : une par sous-tâche, sinon la tâche elle-même.
  bool get whole => wholeKinds.contains(kindOf);

  /// Record du sprint : le plus de secondes tenues avant le premier « euh » (null si rien n'est noté).
  int? get best {
    final r = [for (final s in subs) if (s.noted) s.held!];
    return r.isEmpty ? null : r.reduce(max);
  }
  int get successes => subs.where((s) => s.success).length;
  int get unitsTotal => subs.isEmpty || whole ? 1 : subs.length;
  int get unitsDone => subs.isEmpty || whole ? (status == 'done' ? 1 : 0) : subsDone;
  Sub? get nextSub => subs.where((s) => !s.done).firstOrNull;
  bool get pickedToday => pickedOn == ymd(DateTime.now());
  bool doneOn(DateTime d) =>
      doneAt != null && ymd(DateTime.fromMillisecondsSinceEpoch(doneAt!)) == ymd(d);
}

/// Un élément récurrent de la semaine : bloc fixe à tenir, ou simple repère (contrainte enfants).
class Block {
  String id;
  String week; // a | b | * (les deux)
  List<int> days; // 1 = lundi … 7 = dimanche
  int start; // minutes depuis minuit
  int end;
  String label;
  bool fixed; // true = bloc à tenir, false = repère affiché seulement

  Block({
    required this.id,
    this.week = '*',
    List<int>? days,
    this.start = 540,
    this.end = 720,
    this.label = '',
    this.fixed = true,
  }) : days = days ?? [];

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        id: j['id'] as String,
        week: (j['week'] ?? '*') as String,
        days: ((j['days'] ?? []) as List).map((e) => (e as num).toInt()).toList(),
        start: ((j['start'] ?? 0) as num).toInt(),
        end: ((j['end'] ?? 0) as num).toInt(),
        label: (j['label'] ?? '') as String,
        fixed: (j['fixed'] ?? true) as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'week': week,
        'days': days,
        'start': start,
        'end': end,
        'label': label,
        'fixed': fixed,
      };
}

/// Un bloc fixe à une date précise (éventuellement déplacé ou raccourci).
class Occ {
  final Block block;
  final String origDate; // date prévue au départ : sert d'identifiant avec le bloc
  final String date; // date réelle
  final int start;
  final int end;
  final bool moved;
  Occ(this.block, this.origDate, this.date, this.start, this.end, this.moved);

  String get key => '${block.id}|$origDate';
  int get startMs => dateOf(date).add(Duration(minutes: start)).millisecondsSinceEpoch;
}

class Schedule {
  int updatedAt;
  String anchor; // un lundi de semaine A
  String nameA;
  String nameB;
  List<Block> blocks;

  /// Dates ponctuelles : {id, date, start, label, blockId, cutEnd}. Un rappel est une date
  /// avec `rappel: true`, `done` et `at` (instant de la dernière modification).
  /// `blockId` est le bloc raccourci ce jour-là, `cutEnd` l'heure choisie (minutes) ou null.
  List<Map<String, dynamic>> events;

  /// Blocs déplacés pour un entretien : {key, toDate, toStart}.
  List<Map<String, dynamic>> moves;

  /// Appuis sur « J'y suis » : clé du bloc → heure de l'appui (ms).
  Map<String, int> checks;

  String? reviewedOn; // dimanche de la dernière revue faite
  List<String> sprints; // sprints créés : le lundi de chaque semaine
  int since; // les blocs commencés avant cet instant ne sont pas comptés
  Map<String, int> coef; // points de valeur par unité, par type
  Map<String, int> targets; // cible de points corrigée à la main, par sprint
  int targetKids; // cible d'une semaine avec enfants
  int targetFree; // cible d'une semaine sans enfants
  List<int> spent; // jetons bonus dépensés : l'instant de chaque dépense (ms)
  bool hasPoints; // faux si le fichier lu ne connaissait pas encore les points

  /// Sprints clôturés : lundi → bilan figé (`closedAt`, cible, points, listes, textes).
  /// Un sprint rouvert ne garde que `reopenedAt`. `at` date la dernière décision.
  Map<String, Map<String, dynamic>> closures;

  Schedule({
    this.updatedAt = 0,
    this.anchor = '2026-01-05',
    this.nameA = 'Semaine A',
    this.nameB = 'Semaine B',
    List<Block>? blocks,
    List<Map<String, dynamic>>? events,
    List<Map<String, dynamic>>? moves,
    Map<String, int>? checks,
    this.reviewedOn,
    this.since = 0,
    List<String>? sprints,
    Map<String, int>? coef,
    Map<String, int>? targets,
    this.targetKids = 70,
    this.targetFree = 90,
    List<int>? spent,
    this.hasPoints = true,
    Map<String, Map<String, dynamic>>? closures,
  })  : spent = spent ?? [],
        closures = closures ?? {},
        coef = {for (final k in kinds.entries) k.key: coef?[k.key] ?? k.value.$3},
        targets = targets ?? {},
        blocks = blocks ?? [],
        sprints = sprints ?? [],
        events = events ?? [],
        moves = moves ?? [],
        checks = checks ?? {};

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      ((v ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        updatedAt: ((j['updatedAt'] ?? 0) as num).toInt(),
        anchor: (j['anchor'] ?? '2026-01-05') as String,
        nameA: (j['nameA'] ?? 'Semaine A') as String,
        nameB: (j['nameB'] ?? 'Semaine B') as String,
        blocks: ((j['blocks'] ?? []) as List)
            .map((e) => Block.fromJson(e as Map<String, dynamic>))
            .toList(),
        events: _maps(j['events']),
        moves: _maps(j['moves']),
        checks: ((j['checks'] ?? {}) as Map)
            .map((k, v) => MapEntry('$k', (v as num).toInt())),
        reviewedOn: j['reviewedOn'] as String?,
        since: ((j['since'] ?? 0) as num).toInt(),
        sprints: ((j['sprints'] ?? []) as List).map((e) => '$e').toList(),
        coef: _ints(j['points']?['coef']),
        targets: _ints(j['points']?['targets']),
        targetKids: ((j['points']?['kids'] ?? 70) as num).toInt(),
        targetFree: ((j['points']?['free'] ?? 90) as num).toInt(),
        spent: [for (final x in (j['points']?['spent'] ?? []) as List) (x as num).toInt()],
        hasPoints: j['points'] != null,
        closures: ((j['closures'] ?? {}) as Map)
            .map((k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map))),
      );

  static Map<String, int> _ints(dynamic v) =>
      ((v ?? {}) as Map).map((k, x) => MapEntry('$k', (x as num).toInt()));

  Map<String, dynamic> toJson() => {
        'updatedAt': updatedAt,
        'anchor': anchor,
        'nameA': nameA,
        'nameB': nameB,
        'blocks': (blocks.toList()..sort((a, b) => a.id.compareTo(b.id)))
            .map((b) => b.toJson())
            .toList(),
        'events': events,
        'moves': moves.toList()..sort((a, b) => '${a['key']}'.compareTo('${b['key']}')),
        'checks': Map.fromEntries(
            checks.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
        'reviewedOn': reviewedOn,
        'since': since,
        'sprints': sprints.toList()..sort(),
        'points': {
          'coef': {for (final k in kinds.keys) k: coef[k]},
          'targets': Map.fromEntries(
              targets.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
          'kids': targetKids,
          'free': targetFree,
          'spent': spent.toList()..sort(),
        },
        if (closures.isNotEmpty)
          'closures': Map.fromEntries(
              closures.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      };

  static DateTime mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  String weekOf(DateTime d) {
    final a = mondayOf(dateOf(anchor));
    final m = mondayOf(d);
    final w = (DateTime.utc(m.year, m.month, m.day)
                .difference(DateTime.utc(a.year, a.month, a.day))
                .inDays /
            7)
        .round();
    return w.isEven ? 'a' : 'b';
  }

  String nameOf(String w) => w == 'a' ? nameA : nameB;

  bool _on(Block b, DateTime day) =>
      (b.week == '*' || b.week == weekOf(day)) && b.days.contains(day.weekday);

  /// Les blocs fixes d'un jour, déplacements et dates ponctuelles appliqués.
  List<Occ> occs(DateTime day) {
    final d = ymd(day);
    final out = <Occ>[];
    int cut(Block b, int end) {
      for (final e in events) {
        if (e['date'] == d && e['blockId'] == b.id && e['cutEnd'] != null) {
          final c = (e['cutEnd'] as num).toInt();
          if (c < end) return c;
        }
      }
      return end;
    }

    for (final b in blocks.where((b) => b.fixed && _on(b, day))) {
      if (moves.any((m) => m['key'] == '${b.id}|$d')) continue;
      final end = cut(b, b.end);
      if (end > b.start) out.add(Occ(b, d, d, b.start, end, false));
    }
    for (final m in moves.where((m) => m['toDate'] == d)) {
      final parts = (m['key'] as String).split('|');
      final b = blocks.where((b) => b.id == parts[0]).firstOrNull;
      if (b == null) continue;
      final s = (m['toStart'] as num).toInt();
      out.add(Occ(b, parts[1], d, s, s + (b.end - b.start), true));
    }
    return out..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Les repères d'un jour (contraintes enfants) : affichés, jamais comptés.
  List<Block> hints(DateTime day) =>
      blocks.where((b) => !b.fixed && _on(b, day)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  List<Map<String, dynamic>> eventsOn(DateTime day) => events
      .where((e) => e['date'] == ymd(day) && e['tag'] != true && e['rappel'] != true)
      .toList();

  /// Les rappels d'un jour, par heure : des dates marquées `rappel`, montrées comme un repère
  /// à cocher (`done`) et non comme un créneau. Supprimé = `deleted`, sans date.
  List<Map<String, dynamic>> remindersOn(DateTime day) => events
      .where((e) => e['rappel'] == true && e['deleted'] != true && e['date'] == ymd(day))
      .toList()
    ..sort((a, b) => (a['start'] as num).compareTo(b['start'] as num));

  /// Libellé d'un bloc ce jour-là : une date « étiquette » (`tag`) rattachée au bloc le
  /// précise (la salle de la répétition, par exemple) sans ajouter de case à l'agenda.
  String labelOf(Occ o) {
    for (final e in events) {
      if (e['tag'] == true && e['date'] == o.origDate && e['blockId'] == o.block.id) {
        return '${e['label']}';
      }
    }
    return o.block.label;
  }

  /// tenu | manque | ouvert (dans les 15 premières minutes) | attente (pas encore l'heure)
  /// | hors (bloc d'avant la mise en place, non compté).
  String statusOf(Occ o) {
    const grace = 15 * 60000;
    final c = checks[o.key];
    if (c != null && c <= o.startMs + grace) return 'tenu';
    if (o.startMs < since) return 'hors';
    final now = nowMs();
    if (now < o.startMs) return 'attente';
    return now <= o.startMs + grace ? 'ouvert' : 'manque';
  }

  /// Compte de la semaine qui commence ce lundi : (tenus, prévus).
  (int, int) count(DateTime monday) {
    var held = 0, planned = 0;
    for (var i = 0; i < 7; i++) {
      for (final o in occs(DateTime(monday.year, monday.month, monday.day + i))) {
        final st = statusOf(o);
        if (st == 'hors') continue;
        planned++;
        if (st == 'tenu') held++;
      }
    }
    return (held, planned);
  }
}

class Doc {
  List<Task> tasks;
  Schedule schedule;
  Doc(this.tasks, this.schedule);

  factory Doc.fromJson(Map<String, dynamic> j) => Doc(
        ((j['tasks'] ?? []) as List)
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
        Schedule.fromJson((j['schedule'] ?? <String, dynamic>{}) as Map<String, dynamic>),
      );

  String encode() => const JsonEncoder.withIndent(' ').convert({
        'version': 2,
        'tasks': (tasks.toList()..sort((a, b) => a.id.compareTo(b.id)))
            .map((t) => t.toJson())
            .toList(),
        'schedule': schedule.toJson(),
      });
}
