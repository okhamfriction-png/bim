// Dictée : on parle, Bim range. Le premier mot dit où : « note… », « tâche… », « courses… »,
// « rappel… » (avec le jour et l'heure dans la phrase).
// Sans mot-clé, c'est une note. Rien n'est enregistré avant l'appui sur « Enregistrer ».
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'courses.dart';
import 'models.dart';
import 'notes.dart';
import 'rappels.dart';
import 'store.dart';
import 'ui.dart';

const _kinds = <String, (String, IconData, Color)>{
  'note': ('Note', Icons.sticky_note_2_rounded, Color(0xFFA855F7)),
  'tache': ('Tâche', Icons.check_circle_rounded, Color(0xFF3B82F6)),
  'courses': ('Courses', Icons.shopping_cart_rounded, Color(0xFF22C55E)),
  'rappel': ('Rappel', Icons.notifications_active_rounded, rappelColor),
};

// Mots-clés reconnus au début de la phrase, du plus long au plus court.
const _words = <(String, String)>[
  ('liste de courses', 'courses'),
  ('nouvelle tâche', 'tache'),
  ('nouvelle tache', 'tache'),
  ('nouvelle note', 'note'),
  ('à faire', 'tache'),
  ('a faire', 'tache'),
  ('courses', 'courses'),
  ('course', 'courses'),
  ('achète', 'courses'),
  ('acheter', 'courses'),
  ('tâche', 'tache'),
  ('tache', 'tache'),
  ('rappelle-moi de', 'rappel'),
  ('rappelle-moi', 'rappel'),
  ('rappel', 'rappel'),
  ('notes', 'note'),
  ('note', 'note'),
  ('mémo', 'note'),
  ('memo', 'note'),
];

/// Ce qu'une phrase dictée devient : (destination, texte sans le mot-clé).
(String, String) routeDictation(String said) {
  final s = said.trim();
  final low = s.toLowerCase();
  for (final (word, kind) in _words) {
    if (low == word) return (kind, '');
    if (low.startsWith(word) && !RegExp(r'[a-zà-ÿ]').hasMatch(low[word.length])) {
      return (kind, cap(s.substring(word.length).replaceFirst(RegExp(r'^[\s:,.-]+'), '')));
    }
  }
  return ('note', cap(s));
}

/// « pain, lait et œufs » → trois articles.
List<String> splitArticles(String s) => [
      for (final a in s.split(RegExp(r',|;|\bet\b|\bpuis\b', caseSensitive: false)))
        if (a.trim().isNotEmpty) cap(a.trim())
    ];

/// Lancement par l'icône « Bim dictée » (Android) : ouvre le micro tout de suite.
class DictationLaunch {
  static const _channel = MethodChannel('bim/lancement');

  static Future<void> listen(VoidCallback open) async {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'dicter') open();
    });
    try {
      if (await _channel.invokeMethod<bool>('dictee') == true) open();
    } catch (_) {}
  }
}

bool _dictating = false;

void openDictation(BuildContext context) {
  if (_dictating) return;
  _dictating = true;
  sheet(context, const DictationSheet()).whenComplete(() => _dictating = false);
}

class DictationSheet extends StatefulWidget {
  const DictationSheet({super.key});
  @override
  State<DictationSheet> createState() => _DictationSheetState();
}

class _DictationSheetState extends State<DictationSheet> {
  final speech = SpeechToText();
  final text = TextEditingController();
  String kind = 'note';
  bool chosen = false; // destination choisie à la main : la phrase ne la change plus
  bool listening = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    start();
  }

  @override
  void dispose() {
    speech.cancel();
    super.dispose();
  }

  Future<void> start() async {
    setState(() => error = '');
    try {
      final ok = await speech.initialize(
        onStatus: (s) {
          if (mounted) setState(() => listening = s == 'listening');
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            listening = false;
            if (text.text.isEmpty) {
              error = e.errorMsg.contains('permission')
                  ? 'Bim n\'a pas le droit d\'utiliser le micro.'
                  : 'Je n\'ai rien entendu. Touche le micro pour réessayer, ou écris.';
            }
          });
        },
      );
      if (!ok) {
        if (mounted) {
          setState(() => error = 'La dictée n\'est pas disponible ici. Écris ta phrase.');
        }
        return;
      }
      await speech.listen(
        listenOptions: SpeechListenOptions(
            localeId: 'fr_FR',
            partialResults: true,
            cancelOnError: true,
            pauseFor: const Duration(seconds: 4)),
        onResult: (r) {
          if (!mounted) return;
          final (k, t) = routeDictation(r.recognizedWords);
          setState(() {
            if (!chosen) kind = k;
            text.text = t;
          });
        },
      );
    } catch (_) {
      if (mounted) setState(() => error = 'La dictée n\'est pas disponible ici. Écris ta phrase.');
    }
  }

  void save() {
    final s = text.text.trim();
    if (s.isEmpty) return;
    var where = '';
    switch (kind) {
      case 'courses':
        final l = splitArticles(s);
        for (final a in l) {
          courses.add(a);
        }
        where = l.length > 1 ? '${l.length} articles ajoutés aux courses' : 'Ajouté aux courses';
      case 'rappel':
        final r = parseReminder(s);
        if (r.text.isEmpty) return;
        final now = DateTime.now();
        final day = r.day ?? DateTime(now.year, now.month, now.day);
        final at = r.minutes ?? defaultReminderTime(day);
        store.saveReminder(null, r.text, day, at);
        where = 'Rappel ${reminderWhen(day, at)}';
      case 'tache':
        store.add(Task(title: s, domain: 'Personnel', source: 'Dictée'));
        where = 'Tâche ajoutée au backlog';
      default:
        if (!notes.unlocked) return;
        notes.save(Note(title: s));
        where = 'Note enregistrée';
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$where : $s'), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final locked = kind == 'note' && !notes.unlocked;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        GestureDetector(
          onTap: listening ? speech.stop : start,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
                color: listening ? prioColors[0] : p.accent, shape: BoxShape.circle),
            child: Icon(listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                color: listening ? Colors.white : p.onAccent, size: 28),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(listening ? 'Je t\'écoute…' : 'Dictée',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text('Commence par « note », « tâche », « courses » ou « rappel ».',
                style: TextStyle(fontSize: 13, color: p.sub)),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      TextField(
        controller: text,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(
            hintText: 'Ce que tu dis s\'écrit ici', hintStyle: TextStyle(color: p.sub)),
      ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(error, style: TextStyle(color: prioColors[0], fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in _kinds.entries)
          Pick(k.value.$1, kind == k.key, () => setState(() {
                kind = k.key;
                chosen = true;
              }), color: k.value.$3, icon: k.value.$2),
      ]),
      if (kind == 'rappel' && text.text.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Builder(builder: (context) {
            final r = parseReminder(text.text);
            final now = DateTime.now();
            final day = r.day ?? DateTime(now.year, now.month, now.day);
            return Text(
                'Rappel ${reminderWhen(day, r.minutes ?? defaultReminderTime(day))}. '
                'Dis le jour et l\'heure dans la phrase pour les changer.',
                style: const TextStyle(color: rappelColor, fontWeight: FontWeight.w700, fontSize: 13.5));
          }),
        ),
      if (locked)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
              'Le coffre de notes est fermé : ouvre-le dans l\'onglet Notes, ou range ça en tâche.',
              style: TextStyle(color: prioColors[1], fontSize: 13.5)),
        ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: text.text.trim().isEmpty || locked ? null : save,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
    ]);
  }
}
