import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'store.dart';

/// Catégories proposées d'office ; on peut en taper d'autres. Les courses ont leur propre
/// liste, hors du coffre (courses.dart).
const noteCats = ['Mémos', 'Codes et adresses', 'Mots de passe', 'Jetons'];

class NoteItem {
  String id, text;
  bool done;
  NoteItem(this.text, {String? id, this.done = false}) : id = id ?? newId();
}

/// Une note en clair (elle n'existe sous cette forme qu'en mémoire, coffre ouvert).
class Note {
  String id;
  int updatedAt;
  String title, cat, body, secret;
  bool pinned;
  List<NoteItem> items;
  Note({
    String? id,
    int? updatedAt,
    this.title = '',
    this.cat = 'Mémos',
    this.body = '',
    this.secret = '',
    this.pinned = false,
    List<NoteItem>? items,
  })  : id = id ?? newId(),
        updatedAt = updatedAt ?? nowMs(),
        items = items ?? [];

  Map<String, dynamic> toPlain() => {
        'title': title,
        'cat': cat,
        if (body.isNotEmpty) 'body': body,
        if (secret.isNotEmpty) 'secret': secret,
        if (pinned) 'pinned': true,
        if (items.isNotEmpty)
          'items': [
            for (final i in items) {'id': i.id, 'text': i.text, if (i.done) 'done': true}
          ],
      };

  static Note fromPlain(String id, int updatedAt, Map<String, dynamic> j) => Note(
        id: id,
        updatedAt: updatedAt,
        title: j['title'] as String? ?? '',
        cat: j['cat'] as String? ?? 'Mémos',
        body: j['body'] as String? ?? '',
        secret: j['secret'] as String? ?? '',
        pinned: j['pinned'] == true,
        items: [
          for (final i in (j['items'] as List? ?? []))
            NoteItem(i['text'] as String? ?? '', id: i['id'] as String?, done: i['done'] == true)
        ],
      );
}

/// Le coffre de notes : tout est chiffré sur l'appareil (AES-256-GCM, clé tirée du code
/// par PBKDF2) avant d'être rangé dans `notes.json` du dépôt privé. GitHub ne voit que
/// du texte illisible ; le code ne quitte jamais l'appareil.
class Notes extends ChangeNotifier {
  static const iterations = 150000;
  final _aes = AesGcm.with256bits();

  String? salt; // base64 ; absent = pas encore de coffre
  int iter = iterations;
  String check = ''; // le mot « bim » chiffré : sert à vérifier le code
  /// Notes chiffrées : {id, updatedAt, deleted?, c}
  List<Map<String, dynamic>> raw = [];

  SecretKey? _key;
  final Map<String, Note> _open = {};
  String state = 'idle'; // idle | sync | error
  String error = '';
  bool busy = false; // calcul de la clé en cours

  late SharedPreferences _prefs;
  Timer? _debounce;
  bool _syncing = false;

  bool get exists => salt != null;
  bool get unlocked => _key != null;

  List<Note> get all {
    final l = _open.values.toList();
    l.sort((a, b) => a.pinned != b.pinned
        ? (a.pinned ? -1 : 1)
        : a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return l;
  }

  List<String> get cats {
    final extra = {for (final n in _open.values) n.cat}..removeAll(noteCats);
    return [...noteCats, ...extra.toList()..sort()];
  }

  // ---- Chargement et stockage local ----

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final s = _prefs.getString('notes');
    if (s != null) {
      try {
        _adopt(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    final k = _prefs.getString('notesKey');
    if (k != null && exists) {
      _key = SecretKey(base64.decode(k));
      if (await _valid()) {
        await _decryptAll();
      } else {
        _key = null;
        _prefs.remove('notesKey');
      }
    }
    notifyListeners();
    Timer.periodic(const Duration(seconds: 90), (_) => sync());
    sync();
  }

  void _adopt(Map<String, dynamic> j) {
    salt = j['salt'] as String?;
    iter = j['iter'] as int? ?? iterations;
    check = j['check'] as String? ?? '';
    raw = [for (final n in (j['notes'] as List? ?? [])) Map<String, dynamic>.from(n as Map)];
  }

  String _encode() {
    final l = [...raw]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return const JsonEncoder.withIndent(' ')
        .convert({'v': 1, 'salt': salt, 'iter': iter, 'check': check, 'notes': l});
  }

  void _persist() => _prefs.setString('notes', _encode());

  // ---- Chiffrement ----

  Future<SecretKey> _derive(String code, String salt64, int n) async {
    final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: n, bits: 256)
        .deriveKeyFromPassword(password: code, nonce: base64.decode(salt64));
    return SecretKey(await k.extractBytes());
  }

  Future<String> _enc(String text, [SecretKey? key]) async {
    final box = await _aes.encrypt(utf8.encode(text), secretKey: key ?? _key!);
    return base64.encode(box.concatenation());
  }

  Future<String> _dec(String c, [SecretKey? key]) async {
    final box = SecretBox.fromConcatenation(base64.decode(c), nonceLength: 12, macLength: 16);
    return utf8.decode(await _aes.decrypt(box, secretKey: key ?? _key!));
  }

  Future<bool> _valid([SecretKey? key]) async {
    try {
      return await _dec(check, key) == 'bim';
    } catch (_) {
      return false;
    }
  }

  Future<void> _decryptAll() async {
    _open.clear();
    for (final r in raw) {
      await _decryptOne(r);
    }
  }

  Future<void> _decryptOne(Map<String, dynamic> r) async {
    final id = r['id'] as String;
    if (r['deleted'] == true) {
      _open.remove(id);
      return;
    }
    try {
      final plain = jsonDecode(await _dec(r['c'] as String)) as Map<String, dynamic>;
      _open[id] = Note.fromPlain(id, r['updatedAt'] as int, plain);
    } catch (_) {
      _open.remove(id); // note illisible avec cette clé : on ne la montre pas, on ne la perd pas
    }
  }

  // ---- Créer, ouvrir, fermer ----

  /// Crée le coffre. Renvoie un message d'erreur, ou null si tout va bien.
  Future<String?> create(String code) async {
    if (code.length < 6) return 'Choisis un code d\'au moins 6 caractères.';
    busy = true;
    notifyListeners();
    try {
      if (store.linked) {
        await sync();
        if (state == 'error') {
          return 'Impossible de vérifier s\'il existe déjà un coffre : $error';
        }
        if (exists) return 'Un coffre existe déjà sur un autre appareil : entre son code.';
      }
      final rnd = Random.secure();
      final s = base64.encode(Uint8List.fromList([for (var i = 0; i < 16; i++) rnd.nextInt(256)]));
      final key = await _derive(code, s, iterations);
      salt = s;
      iter = iterations;
      check = await _enc('bim', key);
      raw = [];
      _key = key;
      _open.clear();
      _prefs.setString('notesKey', base64.encode(await key.extractBytes()));
      _persist();
      sync();
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> unlock(String code) async {
    if (!exists) return 'Pas encore de coffre.';
    busy = true;
    notifyListeners();
    try {
      final key = await _derive(code, salt!, iter);
      if (!await _valid(key)) return 'Ce n\'est pas le bon code.';
      _key = key;
      _prefs.setString('notesKey', base64.encode(await key.extractBytes()));
      await _decryptAll();
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Referme le coffre sur cet appareil : il faudra retaper le code.
  void lock() {
    _key = null;
    _open.clear();
    _prefs.remove('notesKey');
    notifyListeners();
  }

  // ---- Modifier ----

  Future<void> save(Note n) async {
    if (!unlocked) return;
    n.updatedAt = nowMs();
    _open[n.id] = n;
    notifyListeners();
    final rec = {'id': n.id, 'updatedAt': n.updatedAt, 'c': await _enc(jsonEncode(n.toPlain()))};
    final i = raw.indexWhere((r) => r['id'] == n.id);
    // Deux enregistrements rapprochés : seul le plus récent compte.
    if (i >= 0 && (raw[i]['updatedAt'] as int) > n.updatedAt) return;
    if (i >= 0) {
      raw[i] = rec;
    } else {
      raw.add(rec);
    }
    _changed();
  }

  void remove(Note n) {
    _open.remove(n.id);
    final rec = {'id': n.id, 'updatedAt': nowMs(), 'deleted': true, 'c': ''};
    final i = raw.indexWhere((r) => r['id'] == n.id);
    if (i >= 0) {
      raw[i] = rec;
    } else {
      raw.add(rec);
    }
    notifyListeners();
    _changed();
  }

  void _changed() {
    _persist();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), sync);
  }

  // ---- Synchro (fichier notes.json du dépôt privé) ----

  Future<void> sync() async {
    if (!store.linked || _syncing) return;
    _syncing = true;
    state = 'sync';
    notifyListeners();
    final base = 'https://api.github.com/repos/${store.repo}/contents/notes.json';
    final headers = {
      'Authorization': 'Bearer ${store.token}',
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
          theirs = utf8.decode(base64.decode((j['content'] as String).replaceAll('\n', '')));
          await _merge(jsonDecode(theirs) as Map<String, dynamic>);
        } else if (r.statusCode != 404) {
          throw 'GitHub a répondu ${r.statusCode}';
        }
        if (!exists) break;
        final mine = _encode();
        if (mine == theirs) break;
        final p = await http
            .put(Uri.parse(base),
                headers: headers,
                body: jsonEncode({
                  'message': 'bim : notes',
                  'content': base64.encode(utf8.encode(mine)),
                  'sha': ?sha,
                }))
            .timeout(const Duration(seconds: 20));
        if (p.statusCode == 200 || p.statusCode == 201) break;
        if (p.statusCode != 409 && p.statusCode != 422) {
          throw 'GitHub a refusé l\'écriture (${p.statusCode})';
        }
        if (i == 2) throw 'Conflit de synchro, réessaie';
      }
      state = 'idle';
      error = '';
    } on TimeoutException {
      state = 'error';
      error = 'GitHub ne répond pas.';
    } catch (e) {
      state = 'error';
      error = '$e';
    }
    _syncing = false;
    notifyListeners();
  }

  Future<void> _merge(Map<String, dynamic> remote) async {
    final rSalt = remote['salt'] as String?;
    if (rSalt == null) return;
    if (salt != rSalt) {
      if (exists && raw.any((n) => n['deleted'] != true)) {
        throw 'Deux coffres différents (un sur cet appareil, un autre déjà synchronisé). '
            'Recopie tes notes d\'ici, puis vide les données de l\'appli pour reprendre l\'autre.';
      }
      // Le coffre vient d'un autre appareil : on l'adopte, il faudra son code.
      _adopt(remote);
      _key = null;
      _open.clear();
      _prefs.remove('notesKey');
      _persist();
      return;
    }
    final byId = {for (final n in raw) n['id'] as String: n};
    var changed = false;
    for (final x in (remote['notes'] as List? ?? [])) {
      final r = Map<String, dynamic>.from(x as Map);
      final l = byId[r['id']];
      if (l == null) {
        raw.add(r);
      } else if ((r['updatedAt'] as int) > (l['updatedAt'] as int)) {
        raw[raw.indexOf(l)] = r;
      } else {
        continue;
      }
      changed = true;
      if (unlocked) await _decryptOne(r);
    }
    // Les suppressions de plus de 60 jours ne servent plus à rien.
    final old = nowMs() - const Duration(days: 60).inMilliseconds;
    raw.removeWhere((n) => n['deleted'] == true && (n['updatedAt'] as int) < old);
    if (changed) _persist();
  }
}

final notes = Notes();
