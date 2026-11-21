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
  String themeMode = 'system'; // apparence : system | light | dark | auto (selon l'heure)
  int darkFrom = 19; // en mode horaire : heure où l'appli passe en sombre
  int lightFrom = 7; // en mode horaire : heure où elle repasse en clair

  /// Vrai si le mode horaire demande le thème sombre à cette heure-ci.
  bool get darkNow {
    final h = DateTime.now().hour;
    if (darkFrom == lightFrom) return false;
    return darkFrom > lightFrom ? (h >= darkFrom || h < lightFrom) : (h >= darkFrom && h < lightFrom);
  }

  void setThemeHours({int? dark, int? light}) {
    if (dark != null) darkFrom = dark % 24;
    if (light != null) lightFrom = light % 24;
    _prefs.setInt('darkFrom', darkFrom);
    _prefs.setInt('lightFrom', lightFrom);
    notifyListeners();
  }
  int widgetOpacity = 100; // opacité du fond du widget Android, en %
  Set<int> widgetPrios = {0, 1, 2, 3, 4}; // priorités montrées dans le widget
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
    darkFrom = _prefs.getInt('darkFrom') ?? 19;
    lightFrom = _prefs.getInt('lightFrom') ?? 7;
    widgetOpacity = _prefs.getInt('widgetOpacity') ?? 100;
    widgetPrios = (_prefs.getStringList('widgetPrios') ?? ['0', '1', '2', '3', '4'])
        .map(int.parse)
        .toSet();
    final raw = _prefs.getString('doc');
    if (raw != null) {
      try {
        final d = Doc.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        tasks = d.tasks;
        schedule = d.schedule;
      } catch (_) {}
    }
    _purge();
    await loadWidgetConfig();
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

  /// Les réglages du widget vivent côté Android (on peut aussi les changer par un
  /// appui long sur le widget) : on les relit au démarrage et au retour dans l'appli.
  Future<void> loadWidgetConfig() async {
    if (kIsWeb) return;
    try {
      final c = await _widgetChannel.invokeMethod<Map>('config');
      if (c == null) {
        await _pushWidgetConfig(); // première fois : on y porte les réglages de l'appli
      } else {
        widgetOpacity = (c['alpha'] as num).toInt();
        widgetPrios = {for (final p in c['prios'] as List) (p as num).toInt()};
        notifyListeners();
      }
    } catch (_) {}
  }

  static const _widgetChannel = MethodChannel('bim/widget');

  Future<void> _pushWidgetConfig() async {
    try {
      await _widgetChannel
          .invokeMethod('setConfig', {'alpha': widgetOpacity, 'prios': widgetPrios.toList()..sort()});
    } catch (_) {}
  }

  void setWidgetOpacity(int v) {
    widgetOpacity = v.clamp(0, 100);
    _prefs.setInt('widgetOpacity', widgetOpacity);
    notifyListeners();
    _pushWidgetConfig();
  }

  /// Montre ou cache une priorité dans le widget (il en reste toujours au moins une).
  void toggleWidgetPrio(int p) {
    if (widgetPrios.contains(p)) {
      if (widgetPrios.length == 1) return;
      widgetPrios.remove(p);
    } else {
      widgetPrios.add(p);
    }
    _prefs.setStringList('widgetPrios', [for (final x in widgetPrios) '$x']);
    notifyListeners();
    _pushWidgetConfig();
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

  /// Ordre : priorité (P0 d'abord), puis le rang (ordre d'ajout, ou celui choisi en glissant).
  static int _order(Task a, Task b) {
    final p = a.priority.compareTo(b.priority);
    return p != 0 ? p : a.rank.compareTo(b.rank);
  }

  /// Range une tâche dans un couloir de priorité, entre deux voisines du même couloir.
  void placeTask(Task t, int priority, Task? prev, Task? next) {
    t.priority = priority.clamp(0, 4);
    final lo = prev?.rank, hi = next?.rank;
    if (lo != null && hi != null) {
      t.rank = (lo + hi) / 2;
    } else if (lo != null) {
      t.rank = lo + 1;
    } else if (hi != null) {
      t.rank = hi - 1;
    }
    touch(t);
  }

  /// Déplace une tâche dans une liste affichée. Glissée parmi des tâches d'une autre
  /// priorité, elle prend cette priorité : la liste reste rangée par priorité.
  void moveTask(List<Task> list, int from, int to) {
    if (from == to) return;
    final l = [...list];
    final t = l.removeAt(from);
    l.insert(to, t);
    final prev = to > 0 ? l[to - 1] : null;
    final next = to < l.length - 1 ? l[to + 1] : null;
    if (prev != null && t.priority < prev.priority) {
      t.priority = prev.priority;
    } else if (next != null && t.priority > next.priority) {
      t.priority = next.priority;
    }
    final lo = prev != null && prev.priority == t.priority ? prev.rank : null;
    final hi = next != null && next.priority == t.priority ? next.rank : null;
    if (lo != null && hi != null) {
      t.rank = (lo + hi) / 2;
    } else if (lo != null) {
      t.rank = lo + 1;
    } else if (hi != null) {
      t.rank = hi - 1;
    }
    touch(t);
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

  // ---- Terminées et archives ----

  /// Tâches terminées pas encore archivées, la plus récente d'abord.
  List<Task> get finished =>
      tasks.where((t) => !t.deleted && t.status == 'done' && !t.archived).toList()
        ..sort((a, b) => (b.doneAt ?? 0).compareTo(a.doneAt ?? 0));

  List<Task> get archived =>
      tasks.where((t) => !t.deleted && t.status == 'done' && t.archived).toList()
        ..sort((a, b) => (b.doneAt ?? 0).compareTo(a.doneAt ?? 0));

  /// Le sprint d'une tâche archivée : celui où elle était rangée, sinon la semaine où
  /// elle a été terminée.
  String archiveSprint(Task t) =>
      t.sprint ??
      ymd(Schedule.mondayOf(DateTime.fromMillisecondsSinceEpoch(t.doneAt ?? t.updatedAt)));

  /// Les archives rangées par sprint, le plus récent d'abord.
  Map<String, List<Task>> get archiveBySprint {
    final out = <String, List<Task>>{};
    for (final t in archived) {
      out.putIfAbsent(archiveSprint(t), () => []).add(t);
    }
    return {for (final k in out.keys.toList()..sort((a, b) => b.compareTo(a))) k: out[k]!};
  }

  /// Range toutes les tâches terminées dans les archives.
  void archiveFinished() {
    final now = nowMs();
    for (final t in finished) {
      t.archived = true;
      t.updatedAt = now;
    }
    _changed();
  }

  /// Vide les archives.
  void clearArchive() {
    final now = nowMs();
    for (final t in archived) {
      t.deleted = true;
      t.updatedAt = now;
    }
    _changed();
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

  // ---- Score ----

  /// Points d'une tâche faite : la priorité donne la base (P0 = 8 … P4 = 1, comme des
  /// points d'effort agiles), la catégorie la pondère selon son importance.
  static const prioPoints = [8, 5, 3, 2, 1];
  static const catWeight = {
    'Mission': 1.5,
    'Contenu': 1.2,
    'Destiny': 1.2,
    'Personnel': 1.0,
    'Parking': 0.5,
  };
  static double pointsOf(Task t) => prioPoints[t.priority] * (catWeight[t.cat] ?? 1);

  int _scoreBetween(int from, int to) => tasks
      .where((t) =>
          !t.deleted && t.status == 'done' && (t.doneAt ?? 0) >= from && (t.doneAt ?? 0) < to)
      .fold<double>(0, (a, t) => a + pointsOf(t))
      .round();

  /// Points gagnés depuis lundi.
  int get weekScore =>
      _scoreBetween(Schedule.mondayOf(DateTime.now()).millisecondsSinceEpoch, nowMs() + 1);

  /// Points de la semaine précédente, pour comparer.
  int get lastWeekScore {
    final m = Schedule.mondayOf(DateTime.now());
    return _scoreBetween(DateTime(m.year, m.month, m.day - 7).millisecondsSinceEpoch,
        m.millisecondsSinceEpoch);
  }

  /// Note du sprint en cours sur 100 : part des points engagés déjà gagnés.
  /// Finir un P0 de Mission pèse donc bien plus que finir un P4. Nul sans sprint.
  int? get sprintGrade {
    final s = thisMonday;
    var done = 0.0, all = 0.0;
    for (final t in tasks) {
      if (t.deleted || t.sprint != s || t.parked) continue;
      all += pointsOf(t);
      if (t.status == 'done') done += pointsOf(t);
    }
    return all == 0 ? null : (100 * done / all).round();
  }

  /// Résumé lu par le widget d'écran d'accueil Android : les tâches du sprint et
  /// l'agenda des 14 prochains jours (le widget choisit la ligne du jour).
  Future<void> _feedWidget() async {
    if (kIsWeb) return;
    String h(int m) => m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
    final q = queue; // le widget filtre lui-même les priorités choisies
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
          'tasks': [for (final t in q.take(40)) {'p': t.priority, 't': t.title, 'c': t.cat, 'k': t.kindOf, 'call': t.call}],
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
    t.archived = false;
    t.doneAt = null;
    t.status = 'todo';
    touch(t);
  }

  // ---- Sous-tâches ----

  // ---- Points de valeur : la valeur livrée, comptée quand la case est cochée ----

  int coefOf(Task t) {
    final k = t.kindOf;
    // Un seul échauffement payé par sprint : le plus ancien.
    if (t.whole &&
        t.sprint != null &&
        tasks.any((o) =>
            !identical(o, t) &&
            !o.deleted &&
            o.sprint == t.sprint &&
            o.kindOf == k &&
            (o.createdAt < t.createdAt || (o.createdAt == t.createdAt && o.id.compareTo(t.id) < 0)))) {
      return 0;
    }
    return schedule.coef[k] ?? 0;
  }
  int plannedOf(Task t) => coefOf(t) * t.unitsTotal;
  int earnedOf(Task t) => coefOf(t) * t.unitsDone;

  static String _pts(int n) => '$n pt${n > 1 ? 's' : ''}';

  /// « 0/9 pts » ou « 2 pts », vide pour une tâche sans points.
  String pointsLabel(Task t) {
    if (t.kindOf.isEmpty) return '';
    return '${earnedOf(t)}/${_pts(plannedOf(t))}';
  }

  /// « 0/3 blocs », vide pour une tâche sans sous-tâche à points.
  String unitsLabel(Task t) {
    final k = kinds[t.kindOf];
    if (k == null || t.subs.isEmpty) return '';
    if (t.kindOf == 'rue') {
      // Bilan des blocs notés : abonnés gagnés et places vendues.
      final noted = t.subs.where((s) => s.data.isNotEmpty);
      final ab = noted.fold(0, (a, s) => a + (s.gained ?? 0));
      final oui = noted.fold(0, (a, s) => a + (s.count('oui') ?? 0));
      return '${t.unitsDone}/${t.unitsTotal} ${k.$2}'
          '${noted.isEmpty ? '' : ' · ${ab >= 0 ? '+' : ''}$ab ab. · $oui place${oui > 1 ? 's' : ''}'}';
    }
    return t.whole
        ? '${t.subsDone}/${t.subs.length} prises${t.record > 0 ? ' · record ${t.record} s' : ''}'
        : '${t.unitsDone}/${t.unitsTotal} ${k.$2}';
  }

  /// Points d'un groupe de tâches : « 3/13 pts » dès qu'il y en a de gagnés, sinon « 13 pts ».
  String lanePoints(Iterable<Task> ts) {
    final planned = ts.fold(0, (a, t) => a + plannedOf(t));
    final earned = ts.fold(0, (a, t) => a + earnedOf(t));
    return earned > 0 ? '$earned/${_pts(planned)}' : _pts(planned);
  }

  /// « Rue 3/10 blocs · 9/30 pts », vide pour une tâche sans points.
  String valueLabel(Task t) {
    final k = kinds[t.kindOf];
    if (k == null) return '';
    final c = coefOf(t);
    String pts(int n) => '$n pt${n > 1 ? 's' : ''}';
    return t.subs.isEmpty || t.whole
        ? pts(c)
        : '${t.unitsDone}/${t.unitsTotal} ${k.$2} · ${earnedOf(t)}/${pts(plannedOf(t))}';
  }

  /// Instants où les unités d'une tâche ont été livrées.
  Iterable<int> _deliveries(Task t) sync* {
    if (t.subs.isEmpty || t.whole) {
      if (t.status == 'done') yield t.doneAt ?? t.updatedAt;
    } else {
      for (final s in t.subs) {
        if (s.done) yield s.doneAt ?? t.doneAt ?? t.updatedAt;
      }
    }
  }

  /// Unités livrées par type entre deux instants.
  Map<String, int> unitsBetween(int from, int to) {
    final out = <String, int>{};
    for (final t in tasks) {
      if (t.deleted || t.kindOf.isEmpty || coefOf(t) == 0) continue;
      final n = _deliveries(t).where((d) => d >= from && d < to).length;
      if (n > 0) out[t.kindOf] = (out[t.kindOf] ?? 0) + n;
    }
    return out;
  }

  int _value(Map<String, int> units) =>
      units.entries.fold(0, (a, e) => a + e.value * (schedule.coef[e.key] ?? 0));

  (int, int) get _weekSpan {
    final m = Schedule.mondayOf(DateTime.now());
    return (m.millisecondsSinceEpoch, DateTime(m.year, m.month, m.day + 7).millisecondsSinceEpoch);
  }

  /// Unités livrées depuis lundi, par type.
  Map<String, int> get weekUnits => unitsBetween(_weekSpan.$1, _weekSpan.$2);

  /// Points de valeur gagnés depuis lundi.
  int get valueWeek => _value(weekUnits);

  int get valueToday {
    final n = DateTime.now();
    return _value(unitsBetween(DateTime(n.year, n.month, n.day).millisecondsSinceEpoch,
        DateTime(n.year, n.month, n.day + 1).millisecondsSinceEpoch));
  }

  bool kidsWeek(String sprint) =>
      schedule.nameOf(schedule.weekOf(dateOf(sprint))).toLowerCase().contains('avec');

  /// Cible d'un sprint : celle corrigée à la main, sinon selon la semaine avec ou sans enfants.
  int targetOf(String sprint) =>
      schedule.targets[sprint] ??
      (kidsWeek(sprint) ? schedule.targetKids : schedule.targetFree);

  /// Points planifiés dans un sprint, tâches faites comprises.
  int plannedIn(String sprint) => tasks
      .where((t) => !t.deleted && t.sprint == sprint)
      .fold(0, (a, t) => a + plannedOf(t));

  int p0In(String sprint) =>
      tasks.where((t) => !t.deleted && t.sprint == sprint && t.priority == 0).length;

  /// « Il manque 12 points, soit 4 blocs de rue. », vide si la cible est atteinte.
  String get gapText {
    final gap = targetOf(thisMonday) - valueWeek;
    if (gap <= 0) return '';
    final c = schedule.coef['rue'] ?? 0;
    final n = c > 0 ? (gap / c).ceil() : 0;
    return 'Il manque $gap point${gap > 1 ? 's' : ''}'
        '${n > 0 ? ', soit $n bloc${n > 1 ? 's' : ''} de rue' : ''}.';
  }

  /// Points gagnés en abordage de rue depuis le début, tous sprints confondus.
  int get rueTotal => _value({'rue': unitsBetween(0, 9007199254740991)['rue'] ?? 0});

  int get bonusEarned => rueTotal ~/ bonusEvery;

  /// Jetons bonus disponibles : un tous les 30 points de rue, moins ceux dépensés.
  int get bonusLeft => (bonusEarned - schedule.spent.length).clamp(0, 9999);

  /// Points de rue déjà gagnés vers le prochain jeton.
  int get bonusProgress => rueTotal % bonusEvery;

  void spendBonus() {
    if (bonusLeft == 0) return;
    schedule.spent.add(nowMs());
    _saveSchedule();
  }

  void setCoef(String kind, int v) {
    schedule.coef[kind] = v.clamp(0, 20);
    _saveSchedule();
  }

  void setTarget(String sprint, int v) {
    schedule.targets[sprint] = v.clamp(0, 500);
    _saveSchedule();
  }

  void setDefaultTarget({required bool kids, required int v}) {
    if (kids) {
      schedule.targetKids = v.clamp(0, 500);
    } else {
      schedule.targetFree = v.clamp(0, 500);
    }
    _saveSchedule();
  }

  /// Toutes cochées : la tâche est faite. Une case décochée : elle redevient à faire.
  void _settle(Task t) {
    if (t.subs.isEmpty) return;
    final all = t.subs.every((s) => s.done);
    if (all && t.status != 'done') {
      t.doneAt = nowMs();
      t.status = 'done';
    } else if (!all && t.status == 'done') {
      t.archived = false;
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
    s.doneAt = s.done ? nowMs() : null;
    _settle(t);
    touch(t);
  }

  void setSubData(Task t, Sub s, Map<String, dynamic> d) {
    s.data = d;
    touch(t);
  }

  void setSubResult(Task t, Sub s, String v) {
    s.result = v.trim();
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
    tasks.removeWhere((t) => t.deleted && t.updatedAt < old);
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
    // Réglages des points : le côté le plus récent qui les connaît.
    final pts = newer.hasPoints ? newer : (older.hasPoints ? older : newer);
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
      coef: pts.coef,
      targets: {...(identical(pts, l) ? r : l).targets, ...pts.targets},
      targetKids: pts.targetKids,
      targetFree: pts.targetFree,
      spent: {...l.spent, ...r.spent}.toList()..sort(), // une dépense n'est jamais perdue
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
