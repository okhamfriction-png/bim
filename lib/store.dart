import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

final store = Store();

/// État de l'appli : backlog, emploi du temps, sauvegarde locale et synchro GitHub.
class Store extends ChangeNotifier {
  List<Task> tasks = [];
  Schedule schedule = Schedule();

  String repo = '';
  String token = '';
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
    sync();
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

  static int _order(Task a, Task b) {
    final p = a.eff.compareTo(b.eff);
    return p != 0 ? p : a.rank.compareTo(b.rank);
  }

  List<Task> get ready => tasks.where((t) => t.ready).toList()..sort(_order);

  List<Task> get waiting =>
      tasks.where((t) => t.open && !t.ready).toList()..sort(_order);

  List<Task> get doneToday {
    final now = DateTime.now();
    return tasks.where((t) => !t.deleted && t.doneOn(now)).toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
  }

  // ---- Écriture ----

  void _changed() {
    notifyListeners();
    _prefs.setString('doc', Doc(tasks, schedule).encode());
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), sync);
  }

  double _endRank() =>
      tasks.fold<double>(0, (m, t) => t.rank > m ? t.rank : m) + 1;

  void add(Task t) {
    t.rank = _endRank();
    tasks.add(t);
    _changed();
  }

  void touch(Task t) {
    t.updatedAt = nowMs();
    _changed();
  }

  void complete(Task t) {
    t.doneAt = nowMs();
    t.startedAt = null;
    t.snoozeUntil = null;
    if (!t.repeats) t.status = 'done';
    touch(t);
  }

  void reopen(Task t) {
    t.doneAt = null;
    t.status = 'todo';
    touch(t);
  }

  void snooze(Task t, DateTime until) {
    t.snoozeUntil = until.millisecondsSinceEpoch;
    t.startedAt = null;
    touch(t);
  }

  void wake(Task t) {
    t.snoozeUntil = null;
    touch(t);
  }

  void start(Task t) {
    t.startedAt = t.startedAt == null ? nowMs() : null;
    touch(t);
  }

  void remove(Task t) {
    t.deleted = true;
    touch(t);
  }

  /// Déplace une tâche dans la liste « prêtes » : elle prend la priorité de sa voisine.
  void reorder(int from, int to) {
    final list = ready;
    if (to > from) to -= 1;
    final t = list.removeAt(from);
    list.insert(to, t);
    final prev = to > 0 ? list[to - 1] : null;
    final next = to < list.length - 1 ? list[to + 1] : null;
    final target = ((prev ?? next)?.eff ?? t.priority).clamp(1, 3);
    final lo = (prev != null && prev.eff == target) ? prev.rank : null;
    final hi = (next != null && next.eff == target) ? next.rank : null;
    t.priority = target;
    if (lo != null && hi != null) {
      t.rank = (lo + hi) / 2;
    } else if (lo != null) {
      t.rank = lo + 1;
    } else if (hi != null) {
      t.rank = hi - 1;
    }
    touch(t);
  }

  void saveSchedule() {
    schedule.updatedAt = nowMs();
    _changed();
  }

  void _purge() {
    final old = nowMs() - const Duration(days: 60).inMilliseconds;
    tasks.removeWhere((t) =>
        (t.deleted || (t.status == 'done' && !t.repeats)) && t.updatedAt < old);
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
    if (remote.schedule.updatedAt > schedule.updatedAt) schedule = remote.schedule;
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
        final r = await http.get(Uri.parse('$base?t=${nowMs()}'), headers: headers);
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
        } else if (r.statusCode != 404) {
          throw 'GitHub a répondu ${r.statusCode}';
        }
        final mine = Doc(tasks, schedule).encode();
        if (mine == theirs) break;
        final p = await http.put(Uri.parse(base),
            headers: headers,
            body: jsonEncode({
              'message': 'bim : synchro',
              'content': base64.encode(utf8.encode(mine)),
              if (sha != null) 'sha': sha,
            }));
        if (p.statusCode == 200 || p.statusCode == 201) break;
        if (p.statusCode != 409 && p.statusCode != 422) {
          throw 'GitHub a refusé l\'écriture (${p.statusCode})';
        }
        if (i == 2) throw 'Conflit de synchro, réessaie';
      }
      syncState = 'ok';
      syncError = '';
      lastSync = nowMs();
    } catch (e) {
      syncState = 'error';
      syncError = '$e';
    }
    _syncing = false;
    notifyListeners();
  }
}
