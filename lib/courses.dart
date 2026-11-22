// La liste de courses : en clair dans courses.json du dépôt privé, donc visible sans code et
// modifiable par la commande `bim courses` (Claude, Rafik). Le coffre garde tout le reste.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'notes.dart';
import 'store.dart';
import 'ui.dart';

class Courses extends ChangeNotifier {
  /// Articles : {id, text, done, updatedAt, deleted?}
  List<Map<String, dynamic>> raw = [];
  String error = '';
  late SharedPreferences _prefs;
  Timer? _debounce;
  bool _syncing = false;
  bool _absorbing = false;

  List<Map<String, dynamic>> get items {
    final l = [for (final i in raw) if (i['deleted'] != true) i];
    return [...l.where((i) => i['done'] != true), ...l.where((i) => i['done'] == true)];
  }

  int get left => raw.where((i) => i['deleted'] != true && i['done'] != true).length;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      _adopt(jsonDecode(_prefs.getString('courses') ?? '{}') as Map<String, dynamic>);
    } catch (_) {}
    notes.addListener(_absorb);
    _absorb();
    Timer.periodic(const Duration(seconds: 90), (_) => sync());
    sync();
  }

  void _adopt(Map<String, dynamic> j) =>
      raw = [for (final i in (j['items'] as List? ?? [])) Map<String, dynamic>.from(i as Map)];

  String _encode() {
    final l = [...raw]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return const JsonEncoder.withIndent(' ').convert({'v': 1, 'items': l});
  }

  void _changed() {
    notifyListeners();
    _prefs.setString('courses', _encode());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), sync);
  }

  void add(String text) {
    final s = text.trim();
    if (s.isEmpty) return;
    final same = raw
        .where((i) => i['deleted'] != true && '${i['text']}'.toLowerCase() == s.toLowerCase())
        .firstOrNull;
    if (same != null) {
      // Déjà dans la liste : on le remet simplement à acheter.
      if (same['done'] != true) return;
      same['done'] = false;
      same['updatedAt'] = nowMs();
    } else {
      raw.add({'id': newId(), 'text': s, 'done': false, 'updatedAt': nowMs()});
    }
    _changed();
  }

  void toggle(Map<String, dynamic> i) {
    i['done'] = i['done'] != true;
    i['updatedAt'] = nowMs();
    _changed();
  }

  void clearDone() {
    for (final i in raw) {
      if (i['deleted'] != true && i['done'] == true) {
        i['deleted'] = true;
        i['updatedAt'] = nowMs();
      }
    }
    _changed();
  }

  /// Les listes rangées dans la catégorie « Courses » du coffre rejoignent la liste commune.
  void _absorb() {
    if (!notes.unlocked || _absorbing) return;
    _absorbing = true;
    for (final n in notes.all.where((n) => n.cat == 'Courses' && n.items.isNotEmpty)) {
      for (final i in n.items.where((i) => !i.done)) {
        add(i.text);
      }
      if (n.body.isEmpty && n.secret.isEmpty) {
        notes.remove(n);
      } else {
        n.items = [];
        n.cat = 'Mémos';
        notes.save(n);
      }
    }
    _absorbing = false;
  }

  Future<void> sync() async {
    if (!store.linked || _syncing) return;
    _syncing = true;
    final base = 'https://api.github.com/repos/${store.repo}/contents/courses.json';
    final headers = {
      'Authorization': 'Bearer ${store.token}',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    try {
      for (var n = 0; n < 3; n++) {
        final r = await http
            .get(Uri.parse('$base?t=${nowMs()}'), headers: headers)
            .timeout(const Duration(seconds: 20));
        String? sha;
        String? theirs;
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          sha = j['sha'] as String;
          theirs = utf8.decode(base64.decode((j['content'] as String).replaceAll('\n', '')));
          _merge(jsonDecode(theirs) as Map<String, dynamic>);
        } else if (r.statusCode != 404) {
          throw 'GitHub a répondu ${r.statusCode}';
        }
        final mine = _encode();
        if (mine == theirs || (theirs == null && raw.isEmpty)) break;
        final p = await http
            .put(Uri.parse(base),
                headers: headers,
                body: jsonEncode({
                  'message': 'bim : courses',
                  'content': base64.encode(utf8.encode(mine)),
                  'sha': ?sha,
                }))
            .timeout(const Duration(seconds: 20));
        if (p.statusCode == 200 || p.statusCode == 201) break;
        if (p.statusCode != 409 && p.statusCode != 422) {
          throw 'GitHub a refusé l\'écriture (${p.statusCode})';
        }
        if (n == 2) throw 'Conflit de synchro, réessaie';
      }
      error = '';
    } on TimeoutException {
      error = 'GitHub ne répond pas.';
    } catch (e) {
      error = '$e';
    }
    _syncing = false;
    notifyListeners();
  }

  void _merge(Map<String, dynamic> remote) {
    final byId = {for (final i in raw) i['id'] as String: i};
    for (final x in (remote['items'] as List? ?? [])) {
      final r = Map<String, dynamic>.from(x as Map);
      final l = byId[r['id']];
      if (l == null) {
        raw.add(r);
      } else if ((r['updatedAt'] as int) > (l['updatedAt'] as int)) {
        raw[raw.indexOf(l)] = r;
      }
    }
    // Les articles retirés depuis plus de 30 jours ne servent plus à rien.
    final old = nowMs() - const Duration(days: 30).inMilliseconds;
    raw.removeWhere((i) => i['deleted'] == true && (i['updatedAt'] as int) < old);
    _prefs.setString('courses', _encode());
  }
}

final courses = Courses();

/// La liste de courses, toujours en haut de l'onglet Notes.
class CoursesPanel extends StatefulWidget {
  const CoursesPanel({super.key});
  @override
  State<CoursesPanel> createState() => _CoursesPanelState();
}

class _CoursesPanelState extends State<CoursesPanel> {
  final add = TextEditingController();
  final focus = FocusNode();

  void go() {
    courses.add(add.text);
    add.clear();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: courses,
        builder: (context, _) {
          final p = Pal.of(context);
          const green = Color(0xFF22C55E);
          final items = courses.items;
          final done = items.where((i) => i['done'] == true).length;
          return Panel(
            header: Row(children: [
              const Icon(Icons.shopping_cart_rounded, size: 20, color: green),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('Courses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              Text(courses.left == 0 ? 'Rien à acheter' : '${courses.left} à acheter',
                  style: TextStyle(fontSize: 12.5, color: p.sub)),
              const SizedBox(width: 6),
            ]),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (courses.error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(courses.error,
                          style: TextStyle(color: prioColors[0], fontSize: 13)),
                    ),
                  for (final i in items)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => courses.toggle(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        child: Row(children: [
                          Icon(
                              i['done'] == true
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 23,
                              color: i['done'] == true ? green : p.sub),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${i['text']}',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: i['done'] == true ? p.sub : p.ink,
                                    decoration:
                                        i['done'] == true ? TextDecoration.lineThrough : null)),
                          ),
                        ]),
                      ),
                    ),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: add,
                        focusNode: focus,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                            hintText: 'Ajouter un article',
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            prefixIcon: Icon(Icons.add_rounded, color: p.sub, size: 22),
                            prefixIconConstraints: const BoxConstraints(minWidth: 34),
                            hintStyle: TextStyle(color: p.sub)),
                        onSubmitted: (_) => go(),
                      ),
                    ),
                    if (done > 0)
                      TextButton(
                          onPressed: courses.clearDone,
                          child: Text(done > 1 ? 'Retirer les $done cochés' : 'Retirer le coché')),
                  ]),
                ]),
              ),
            ],
          );
        },
      );
}
