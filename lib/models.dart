import 'dart:convert';
import 'dart:math';

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _rnd = Random();
String newId() {
  const c = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(8, (_) => c[_rnd.nextInt(c.length)]).join();
}

/// Une tâche du backlog. Format partagé avec la commande `bin/bim`.
class Task {
  String id;
  String title;
  String note;
  String domain;
  int priority; // 1 urgent, 2 important, 3 quand je peux
  String? due; // aaaa-mm-jj
  List<int> days; // jours de répétition (1 = lundi … 7 = dimanche), vide = une seule fois
  String source; // conversation ou agent qui a créé la tâche
  List<String> links; // liens, vidéos, images
  double rank;
  String status; // todo | done
  int createdAt;
  int updatedAt;
  int? doneAt;
  int? snoozeUntil;
  int? startedAt;
  bool deleted;

  Task({
    String? id,
    required this.title,
    this.note = '',
    this.domain = 'Perso',
    this.priority = 2,
    this.due,
    List<int>? days,
    this.source = '',
    List<String>? links,
    this.rank = 0,
    this.status = 'todo',
    int? createdAt,
    int? updatedAt,
    this.doneAt,
    this.snoozeUntil,
    this.startedAt,
    this.deleted = false,
  })  : id = id ?? newId(),
        days = days ?? [],
        links = links ?? [],
        createdAt = createdAt ?? nowMs(),
        updatedAt = updatedAt ?? nowMs();

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        note: (j['note'] ?? '') as String,
        domain: (j['domain'] ?? 'Perso') as String,
        priority: ((j['priority'] ?? 2) as num).toInt().clamp(1, 3),
        due: j['due'] as String?,
        days: ((j['days'] ?? []) as List).map((e) => (e as num).toInt()).toList(),
        source: (j['source'] ?? '') as String,
        links: ((j['links'] ?? []) as List).map((e) => '$e').toList(),
        rank: ((j['rank'] ?? 0) as num).toDouble(),
        status: (j['status'] ?? 'todo') as String,
        createdAt: ((j['createdAt'] ?? 0) as num).toInt(),
        updatedAt: ((j['updatedAt'] ?? 0) as num).toInt(),
        doneAt: (j['doneAt'] as num?)?.toInt(),
        snoozeUntil: (j['snoozeUntil'] as num?)?.toInt(),
        startedAt: (j['startedAt'] as num?)?.toInt(),
        deleted: (j['deleted'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'domain': domain,
        'priority': priority,
        'due': due,
        'days': days,
        'source': source,
        'links': links,
        'rank': rank,
        'status': status,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'doneAt': doneAt,
        'snoozeUntil': snoozeUntil,
        'startedAt': startedAt,
        'deleted': deleted,
      };

  bool get repeats => days.isNotEmpty;

  bool doneOn(DateTime d) =>
      doneAt != null && ymd(DateTime.fromMillisecondsSinceEpoch(doneAt!)) == ymd(d);

  bool get snoozed => snoozeUntil != null && snoozeUntil! > nowMs();

  /// Encore dans le backlog (prête ou en attente).
  bool get open => !deleted && (repeats || status == 'todo');

  /// À faire maintenant.
  bool get ready {
    if (!open || snoozed) return false;
    final now = DateTime.now();
    if (repeats) return days.contains(now.weekday) && !doneOn(now);
    return true;
  }

  /// Priorité effective : 0 quand l'échéance est arrivée.
  int get eff =>
      (!repeats && due != null && due!.compareTo(ymd(DateTime.now())) <= 0) ? 0 : priority;
}

/// Un bloc de l'emploi du temps : rendez-vous fixe ou créneau backlog.
class Block {
  String id;
  String week; // a | b | * (les deux)
  List<int> days;
  int start; // minutes depuis minuit
  int end;
  String label;
  bool fixed;

  Block({
    String? id,
    this.week = '*',
    List<int>? days,
    this.start = 540,
    this.end = 720,
    this.label = '',
    this.fixed = true,
  })  : id = id ?? newId(),
        days = days ?? [1, 2, 3, 4, 5];

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

class Schedule {
  int updatedAt;
  String anchor; // un lundi de semaine A
  String nameA;
  String nameB;
  List<Block> blocks;

  Schedule({
    this.updatedAt = 0,
    this.anchor = '2026-01-05',
    this.nameA = 'Semaine A',
    this.nameB = 'Semaine B',
    List<Block>? blocks,
  }) : blocks = blocks ?? [];

  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        updatedAt: ((j['updatedAt'] ?? 0) as num).toInt(),
        anchor: (j['anchor'] ?? '2026-01-05') as String,
        nameA: (j['nameA'] ?? 'Semaine A') as String,
        nameB: (j['nameB'] ?? 'Semaine B') as String,
        blocks: ((j['blocks'] ?? []) as List)
            .map((e) => Block.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'updatedAt': updatedAt,
        'anchor': anchor,
        'nameA': nameA,
        'nameB': nameB,
        'blocks': (blocks.toList()..sort((a, b) => a.id.compareTo(b.id)))
            .map((b) => b.toJson())
            .toList(),
      };

  static DateTime mondayOf(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  String weekOf(DateTime d) {
    final p = anchor.split('-').map(int.parse).toList();
    final a = mondayOf(DateTime.utc(p[0], p[1], p[2]));
    final w = (mondayOf(d).difference(a).inDays / 7).round();
    return w.isEven ? 'a' : 'b';
  }

  String nameOf(String w) => w == 'a' ? nameA : nameB;

  List<Block> blocksFor(String week, int day) => blocks
      .where((b) => (b.week == '*' || b.week == week) && b.days.contains(day))
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
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
        'version': 1,
        'tasks': (tasks.toList()..sort((a, b) => a.id.compareTo(b.id)))
            .map((t) => t.toJson())
            .toList(),
        'schedule': schedule.toJson(),
      });
}
