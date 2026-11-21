// Consignes envoyées à l'agent de l'appli par le connecteur Claude (fichier consignes.json du
// dépôt de données). L'agent ne change ni le code ni le format des données tant que le plan
// n'a pas été validé ici.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'store.dart';
import 'ui.dart';

const consigneStates = <String, String>{
  'recue': 'En file',
  'en_cours': 'En cours',
  'a_valider': 'À valider',
  'validee': 'Validée, exécution à venir',
  'terminee': 'Terminée',
  'refusee': 'Refusée',
  'echec': 'Échec',
};

class Consignes extends ChangeNotifier {
  List<Map<String, dynamic>> all = [];
  String error = '';
  bool busy = false;

  List<Map<String, dynamic>> get pending => all.where((c) => c['etat'] == 'a_valider').toList();

  String get _url => 'https://api.github.com/repos/${store.repo}/contents/consignes.json';
  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${store.token}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  void start() {
    refresh();
    Timer.periodic(const Duration(seconds: 90), (_) => refresh());
  }

  Future<(Map<String, dynamic>, String?)> _read() async {
    final r = await http
        .get(Uri.parse('$_url?t=${nowMs()}'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 404) return (<String, dynamic>{'v': 1, 'consignes': []}, null);
    if (r.statusCode != 200) throw 'GitHub a répondu ${r.statusCode}';
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final text = utf8.decode(base64.decode((j['content'] as String).replaceAll('\n', '')));
    return (jsonDecode(text) as Map<String, dynamic>, j['sha'] as String);
  }

  void _take(Map<String, dynamic> doc) {
    all = [for (final c in (doc['consignes'] ?? []) as List) Map<String, dynamic>.from(c as Map)]
        .reversed
        .toList();
  }

  Future<void> refresh() async {
    if (!store.linked || busy) return;
    try {
      _take((await _read()).$1);
      error = '';
    } on TimeoutException {
      error = 'GitHub ne répond pas.';
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  /// Valide ou refuse un plan en attente. Ne touche à rien d'autre dans le fichier.
  Future<void> decide(String id, bool ok) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      for (var i = 0; i < 3; i++) {
        final (doc, sha) = await _read();
        final list = (doc['consignes'] ?? []) as List;
        final c = list.cast<Map>().where((c) => c['id'] == id).firstOrNull;
        if (c == null || c['etat'] != 'a_valider') {
          _take(doc);
          break;
        }
        c['etat'] = ok ? 'validee' : 'refusee';
        c['decideLe'] = DateTime.now().toIso8601String();
        final p = await http
            .put(Uri.parse(_url),
                headers: _headers,
                body: jsonEncode({
                  'message': 'bim : consigne ${ok ? 'validée' : 'refusée'}',
                  'content': base64.encode(
                      utf8.encode(const JsonEncoder.withIndent(' ').convert(doc))),
                  'sha': ?sha,
                }))
            .timeout(const Duration(seconds: 20));
        if (p.statusCode == 200 || p.statusCode == 201) {
          _take(doc);
          break;
        }
        if (p.statusCode != 409 && p.statusCode != 422) {
          throw 'GitHub a refusé l\'écriture (${p.statusCode})';
        }
        if (i == 2) throw 'Conflit de synchro, réessaie';
      }
      error = '';
    } on TimeoutException {
      error = 'GitHub ne répond pas.';
    } catch (e) {
      error = '$e';
    }
    busy = false;
    notifyListeners();
  }
}

final consignes = Consignes();

/// Bandeau affiché en haut de l'appli tant qu'un plan attend une validation.
class ConsignesBanner extends StatelessWidget {
  const ConsignesBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final n = consignes.pending.length;
    if (n == 0) return const SizedBox.shrink();
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: p.accent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ConsignesPage())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Icon(Icons.rule_rounded, color: p.onAccent),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      n == 1
                          ? 'Un plan de l\'agent attend ta validation'
                          : '$n plans de l\'agent attendent ta validation',
                      style: TextStyle(fontWeight: FontWeight.w800, color: p.onAccent))),
              Icon(Icons.chevron_right_rounded, color: p.onAccent),
            ]),
          ),
        ),
      ),
    );
  }
}

class ConsignesPage extends StatelessWidget {
  const ConsignesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: consignes,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Consignes à l\'agent'),
          actions: [
            IconButton(
                tooltip: 'Actualiser',
                onPressed: consignes.refresh,
                icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              Text(
                  'Les consignes envoyées depuis Claude arrivent ici. L\'agent ne change ni le code '
                  'ni le format des données tant que tu n\'as pas validé son plan.',
                  style: TextStyle(color: p.sub)),
              if (consignes.error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(consignes.error,
                        style: TextStyle(color: prioColors[0], fontWeight: FontWeight.w700))),
              if (consignes.all.isEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                        child: Text('Aucune consigne pour l\'instant.',
                            style: TextStyle(color: p.sub)))),
              for (final c in consignes.all) _ConsigneCard(c),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ConsigneCard extends StatelessWidget {
  final Map<String, dynamic> c;
  const _ConsigneCard(this.c);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final etat = '${c['etat']}';
    final wait = etat == 'a_valider';
    Widget block(String title, String text) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12, letterSpacing: .5, fontWeight: FontWeight.w800, color: p.sub)),
            const SizedBox(height: 4),
            SelectableText(text),
          ]),
        );
    final changes = c['changements'] is List ? (c['changements'] as List).join('\n') : '';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: wait ? p.accent : p.line, width: wait ? 2 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
                color: wait ? p.accent : p.soft, borderRadius: BorderRadius.circular(99)),
            child: Text(consigneStates[etat] ?? etat,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: wait ? p.onAccent : p.ink)),
          ),
          const Spacer(),
          Text('${c['recueLe'] ?? ''}'.replaceFirst('T', ' ').split('+').first,
              style: TextStyle(fontSize: 12.5, color: p.sub)),
        ]),
        block('CONSIGNE', '${c['texte'] ?? ''}'),
        if ('${c['plan'] ?? ''}'.isNotEmpty) block('PLAN DE L\'AGENT', '${c['plan']}'),
        if ('${c['resume'] ?? ''}'.isNotEmpty) block('COMPTE RENDU', '${c['resume']}'),
        if (changes.isNotEmpty) block('CE QUI A CHANGÉ', changes),
        if ('${c['erreur'] ?? ''}'.isNotEmpty) block('ERREUR', '${c['erreur']}'),
        if (wait)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed:
                          consignes.busy ? null : () => consignes.decide('${c['id']}', false),
                      child: const Text('Refuser'))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      onPressed: consignes.busy ? null : () => consignes.decide('${c['id']}', true),
                      child: const Text('Valider le plan'))),
            ]),
          ),
      ]),
    );
  }
}
