import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

final store = Store();

/// État de l'appli : backlog, blocs fixes, sauvegarde locale et synchro GitHub.
class Store extends ChangeNotifier {
  List<Task> tasks = [];
  Schedule schedule = Schedule();

  String repo = '';
  String token = '';
  String themeMode = 'system'; // apparence : system | light | dark
  String agendaView = 'semaine'; // vue de l'agenda à l'ouverture : jour | semaine | mois | annee
  String syncState = 'off'; // off | sync | ok | error
  String syncError = '';
  int? lastSync;

  late SharedPreferences _prefs;
  Timer? _debounce;
  bool _syncing = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    repo = _prefs.getString('repo') ?? '';
    token = _prefs.getString('token') ?? '';
    agendaView = _prefs.getString('agendaView') ?? 'semaine';
    themeMode = _prefs.getString('themeMode') ?? 'system';
    final raw = _prefs.getString('doc');
    if (raw != null) {
      try {
        final d = Doc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        tasks = d.tasks;
        schedule = d.schedule;
      } catch (_) {}
    }
    _purge();
    Timer.periodic(const Duration(seconds: 30), (_) => notifyListeners());
    Timer.periodic(const Duration(seconds: 90), (_) => sync());
    _feedWidget();
    sync();
  }

  void setAgendaView(String v) {
    agendaView = v;
    _prefs.setString('agendaView', v);
    notifyListeners();
  }

  void setThemeMode(String v) {
    themeMode = v;
    _prefs.setString('themeMode', v);
    notifyListeners();
  }

  bool get linked => repo.isNotEmpty && token.isNotEmpty;

  Future<void> setLink(String r, String t) async {
    repo = r.trim();
    token = t.trim();
    await _prefs.setString('repo', repo);
    await _prefs.setString('token', token);
    syncState = linked ? 'sync' : 'off';
    notifyListeners();
    await sync();
  }

  // ---- Lecture ----

  /// Ordre : priorité (P0 d'abord), puis catégorie (Mission d'abord), puis ancienneté.
  static int _order(Task a, Task b) {
    final p = a.priority.compareTo(b.priority);
    if (p != 0) return p;
    final c = a.catRank.compareTo(b.catRank);
    return c != 0 ? c : a.rank.compareTo(b.rank);
  }

  /// Tout le backlog ouvert, Parking compris.
  List<Task> get backlog => tasks.where((t) => t.open).toList()..sort(_order);

  /// Les tâches choisies pour aujourd'hui (3 au maximum), faites ou non.
  List<Task> get picks =>
      tasks.where((t) => !t.deleted && t.pickedToday).toList()..sort(_order);

  /// Celles qu'il reste à faire aujourd'hui.
  List<Task> get todayTodo => picks.where((t) => t.open && !t.parked).toList();

  /// Appels et entretiens de mission : ils passent devant tout.
  List<Task> get calls => backlog.where((t) => t.call && !t.parked).toList();

  /// Ce qu'on peut encore choisir pour aujourd'hui.
  List<Task> get pickable =>
      backlog.where((t) => !t.parked && !t.pickedToday && !t.call).toList();

  bool get canPick => picks.length < 3;

  // ---- Sprints d'une semaine (lundi → dimanche) ----

  String get thisMonday => ymd(Schedule.mondayOf(DateTime.now()));

  /// Le sprint d'une tâche ; un sprint passé ne compte plus, la tâche retourne au backlog.
  String? sprintOf(Task t) =>
      (t.sprint != null && t.sprint!.compareTo(thisMonday) >= 0) ? t.sprint : null;

  /// Sprints en cours et à venir.
  List<String> get sprints =>
      schedule.sprints.where((s) => s.compareTo(thisMonday) >= 0).toSet().toList()..sort();

  List<Task> sprintTasks(String s) =>
      backlog.where((t) => !t.parked && sprintOf(t) == s).toList();

  /// Tâches du sprint déjà terminées.
  int sprintDone(String s) =>
      tasks.where((t) => !t.deleted && t.status == 'done' && t.sprint == s).length;

  /// Crée le prochain sprint qui n'existe pas encore (cette semaine d'abord).
  void createSprint() {
    var m = Schedule.mondayOf(DateTime.now());
    while (schedule.sprints.contains(ymd(m))) {
      m = DateTime(m.year, m.month, m.day + 7);
    }
    schedule.sprints.add(ymd(m));
    _saveSchedule();
  }

  void setSprint(Task t, String? s) {
    t.sprint = s;
    touch(t);
  }

  /// Ce que Maintenant déroule : appels et entretiens, tâches choisies pour aujourd'hui,
  /// puis le reste du sprint en cours par priorité.
  List<Task> get queue {
    final out = <Task>[...calls, ...todayTodo.where((t) => !t.call)];
    for (final t in sprintTasks(thisMonday)) {
      if (!out.contains(t)) out.add(t);
    }
    return out;
  }

  List<Task> get doneToday {
    final now = DateTime.now();
    return tasks.where((t) => !t.deleted && t.status == 'done' && t.doneOn(now)).toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
  }

  /// Tâches faites depuis lundi.
  List<Task> get doneThisWeek {
    final m = Schedule.mondayOf(DateTime.now()).millisecondsSinceEpoch;
    return tasks
        .where((t) => !t.deleted && t.status == 'done' && (t.doneAt ?? 0) >= m)
        .toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
  }

  /// Tâches ouvertes (hors Parking) jamais touchées depuis 7 jours.
  List<Task> get stale {
    final limit = nowMs() - const Duration(days: 7).inMilliseconds;
    return backlog.where((t) => !t.parked && t.updatedAt < limit).toList();
  }

  // ---- Tâches ----

  /// Résumé lu par le widget d'écran d'accueil Android : les tâches du sprint et
  /// l'agenda des 14 prochains jours (le widget choisit la ligne du jour).
  Future<void> _feedWidget() async {
    if (kIsWeb) return;
    String h(int m) => m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
    final q = queue;
    final now = DateTime.now();
    final days = <String, dynamic>{};
    for (var i = 0; i < 14; i++) {
      final d = DateTime(now.year, now.month, now.day + i);
      final w = schedule.weekOf(d);
      // (début, fin, libellé) : le widget masque ce qui est déjà terminé.
      final lines = <(int, int, String)>[
        for (final o in schedule.occs(d)) (o.start, o.end, o.block.label),
        for (final e in schedule.eventsOn(d))
          ((e['start'] as num).toInt(), 24 * 60, '${e['label']}'),
        for (final b in schedule.hints(d)) (b.start, b.start, b.label),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      days[ymd(d)] = {
        'week': schedule.nameOf(w),
        'kids': schedule.nameOf(w).toLowerCase().contains('avec'),
        'lines': [for (final l in lines) {'h': h(l.$1), 'end': l.$2, 'l': l.$3}],
      };
    }
    await _prefs.setString(
        'widget',
        jsonEncode({
          'count': q.length,
          'tasks': [for (final t in q.take(4)) {'p': t.priority, 't': t.title}],
          'days': days,
        }));
    try {
      await const MethodChannel('bim/widget').invokeMethod('refresh');
    } catch (_) {}
  }

  void _changed() {
    notifyListeners();
    _prefs.setString('doc', Doc(tasks, schedule).encode());
    _feedWidget();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), sync);
  }

  void add(Task t) {
    t.rank = tasks.fold<double>(0, (m, x) => x.rank > m ? x.rank : m) + 1;
    tasks.add(t);
    _changed();
  }

  void touch(Task t) {
    t.updatedAt = nowMs();
    _changed();
  }

  void complete(Task t) {
    t.doneAt = nowMs();
    t.status = 'done';
    touch(t);
  }

  void reopen(Task t) {
    t.doneAt = null;
    t.status = 'todo';
    touch(t);
  }

  // ---- Sous-tâches ----

  /// Toutes cochées : la tâche est faite. Une case décochée : elle redevient à faire.
  void _settle(Task t) {
    if (t.subs.isEmpty) return;
    final all = t.subs.every((s) => s.done);
    if (all && t.status != 'done') {
      t.doneAt = nowMs();
      t.status = 'done';
    } else if (!all && t.status == 'done') {
      t.doneAt = null;
      t.status = 'todo';
    }
  }

  void addSubs(Task t, String title, [int count = 1]) {
    final s = title.trim();
    if (s.isEmpty || count < 1) return;
    for (var i = 1; i <= count; i++) {
      t.subs.add(Sub(count == 1 ? s : '$s ($i/$count)'));
    }
    _settle(t);
    touch(t);
  }

  void toggleSub(Task t, Sub s) {
    s.done = !s.done;
    _settle(t);
    touch(t);
  }

  void removeSub(Task t, Sub s) {
    t.subs.remove(s);
    _settle(t);
    touch(t);
  }

  void pick(Task t) {
    if (!canPick || t.parked) return;
    t.pickedOn = ymd(DateTime.now());
    touch(t);
  }

  void unpick(Task t) {
    t.pickedOn = null;
    touch(t);
  }

  void park(Task t) {
    t.domain = 'Parking';
    t.sprint = null;
    t.pickedOn = null;
    t.call = false;
    touch(t);
  }

  void remove(Task t) {
    t.deleted = true;
    touch(t);
  }

  // ---- Blocs ----

  void _saveSchedule() {
    schedule.updatedAt = nowMs();
    _changed();
  }

  /// « J'y suis » : enregistre l'heure de l'appui.
  void check(Occ o) {
    schedule.checks[o.key] = nowMs();
    _saveSchedule();
  }

  /// Heure de fin choisie pour le bloc raccourci par une date ponctuelle.
  void setCut(Map<String, dynamic> event, int minutes) {
    event['cutEnd'] = minutes;
    _saveSchedule();
  }

  /// Déplace un bloc dans la même semaine (entretien de mission à son heure).
  void move(Occ o, String toDate, int toStart) {
    schedule.moves.removeWhere((m) => m['key'] == o.key);
    schedule.moves.add({'key': o.key, 'toDate': toDate, 'toStart': toStart});
    _saveSchedule();
  }

  void reviewed() {
    schedule.reviewedOn = ymd(DateTime.now());
    _saveSchedule();
  }

  void _purge() {
    final old = nowMs() - const Duration(days: 60).inMilliseconds;
    tasks.removeWhere((t) => (t.deleted || t.status == 'done') && t.updatedAt < old);
  }

  /// Télécharge un fichier privé du dépôt de données (vidéo ou image jointe à une tâche).
  Future<Uint8List> media(String path) async {
    if (!linked) throw 'Relie Bim à GitHub (icône nuage) pour voir ce fichier';
    final r = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/contents/${Uri.encodeFull(path)}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.raw',
          'X-GitHub-Api-Version': '2022-11-28',
        });
    if (r.statusCode != 200) throw 'Fichier introuvable (${r.statusCode})';
    return r.bodyBytes;
  }

  // ---- Synchro GitHub (fichier backlog.json d'un dépôt privé) ----

  void _merge(Doc remote) {
    final byId = {for (final t in tasks) t.id: t};
    for (final r in remote.tasks) {
      final l = byId[r.id];
      if (l == null) {
        tasks.add(r);
      } else if (r.updatedAt > l.updatedAt) {
        tasks[tasks.indexOf(l)] = r;
      }
    }
    _mergeSchedule(remote.schedule);
  }

  /// Fusionne l'agenda sans jamais rien perdre : un agenda local vide ne peut pas
  /// effacer les blocs du dépôt, et les appuis « J'y suis », déplacements, sprints
  /// et heures de fin des deux côtés sont réunis.
  void _mergeSchedule(Schedule r) {
    final l = schedule;
    final remoteNewer = r.updatedAt > l.updatedAt;
    final newer = remoteNewer ? r : l;
    final older = remoteNewer ? l : r;
    // Réglages (blocs, dates, alternance) : le côté le plus récent qui a des blocs.
    final cfg = newer.blocks.isNotEmpty ? newer : (older.blocks.isNotEmpty ? older : newer);
    final other = identical(cfg, l) ? r : l;
    final events = [
      for (final e in cfg.events)
        {
          ...e,
          'cutEnd': newer.events.where((x) => x['id'] == e['id']).firstOrNull?['cutEnd'] ??
              older.events.where((x) => x['id'] == e['id']).firstOrNull?['cutEnd'] ??
              e['cutEnd'],
        }
    ];
    final moves = <String, Map<String, dynamic>>{
      for (final m in older.moves) '${m['key']}': m,
      for (final m in newer.moves) '${m['key']}': m,
    };
    final checks = <String, int>{...other.checks};
    cfg.checks.forEach((k, v) => checks[k] = checks.containsKey(k) && checks[k]! < v ? checks[k]! : v);
    final reviews = [l.reviewedOn, r.reviewedOn].whereType<String>().toList()..sort();
    schedule = Schedule(
      updatedAt: newer.updatedAt,
      anchor: cfg.anchor,
      nameA: cfg.nameA,
      nameB: cfg.nameB,
      blocks: cfg.blocks,
      events: events,
      moves: moves.values.toList(),
      checks: checks,
      reviewedOn: reviews.isEmpty ? null : reviews.last,
      since: cfg.since,
      sprints: {...l.sprints, ...r.sprints}.toList()..sort(),
    );
  }

  Future<void> sync() async {
    if (!linked || _syncing) return;
    _syncing = true;
    syncState = 'sync';
    notifyListeners();
    final base = 'https://api.github.com/repos/$repo/contents/backlog.json';
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    try {
      for (var i = 0; i < 3; i++) {
        final r = await http
            .get(Uri.parse('$base?t=${nowMs()}'), headers: headers)
            .timeout(const Duration(seconds: 20));
        String? sha;
        String? theirs;
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          sha = j['sha'] as String;
          final text =
              utf8.decode(base64.decode((j['content'] as String).replaceAll('\n', '')));
          final remote = Doc.fromJson(jsonDecode(text) as Map<String, dynamic>);
          theirs = remote.encode();
          _merge(remote);
          _prefs.setString('doc', Doc(tasks, schedule).encode());
        } else if (r.statusCode == 401) {
          throw 'GitHub ne reconnaît pas ce jeton : il est mal copié ou expiré.';
        } else if (r.statusCode == 404) {
          // Fichier absent (premier lancement) ou dépôt invisible pour ce jeton ?
          final repoCheck = await http
              .get(Uri.parse('https://api.github.com/repos/$repo'), headers: headers)
              .timeout(const Duration(seconds: 20));
          if (repoCheck.statusCode != 200) {
            throw 'Ce jeton ne voit pas le dépôt $repo. Sur GitHub, modifie le jeton : '
                '« Only select repositories » → bim-data, puis Contents → « Read and write ».';
          }
        } else {
          throw 'GitHub a répondu ${r.statusCode}';
        }
        final mine = Doc(tasks, schedule).encode();
        if (mine == theirs) break;
        final p = await http.put(Uri.parse(base),
            headers: headers,
            body: jsonEncode({
              'message': 'bim : synchro',
              'content': base64.encode(utf8.encode(mine)),
              'sha': ?sha,
            })).timeout(const Duration(seconds: 20));
        if (p.statusCode == 200 || p.statusCode == 201) break;
        if (p.statusCode == 403 || p.statusCode == 404) {
          throw 'Ce jeton peut lire $repo mais pas y écrire. Sur GitHub, modifie le jeton : '
              'Contents → « Read and write ».';
        }
        if (p.statusCode != 409 && p.statusCode != 422) {
          throw 'GitHub a refusé l\'écriture (${p.statusCode})';
        }
        if (i == 2) throw 'Conflit de synchro, réessaie';
      }
      _feedWidget();
      syncState = 'ok';
      syncError = '';
      lastSync = nowMs();
    } on TimeoutException {
      syncState = 'error';
      syncError = 'GitHub ne répond pas. Vérifie la connexion, puis réessaie.';
    } catch (e) {
      syncState = 'error';
      syncError = '$e';
    }
    _syncing = false;
    notifyListeners();
  }
}
