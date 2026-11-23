import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'courses.dart';
import 'liaison.dart';
import 'notes.dart';
import 'store.dart';
import 'ui.dart';

const _catIcons = <String, IconData>{
  'Courses': Icons.shopping_cart_rounded,
  'Codes et adresses': Icons.location_on_rounded,
  'Mots de passe': Icons.key_rounded,
  'Jetons': Icons.vpn_key_rounded,
  'Mémos': Icons.sticky_note_2_rounded,
};
const _catColors = <String, Color>{
  'Courses': Color(0xFF22C55E),
  'Codes et adresses': Color(0xFF0EA5E9),
  'Mots de passe': Color(0xFFEF4444),
  'Jetons': Color(0xFFF97316),
  'Mémos': Color(0xFFA855F7),
};
/// Catégories où l'on range une valeur à masquer.
const secretCats = ['Mots de passe', 'Jetons'];
IconData _iconOf(String c) => _catIcons[c] ?? Icons.label_rounded;
Color _colorOf(String c) => _catColors[c] ?? const Color(0xFF667085);

Widget _label(BuildContext c, String s) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(s,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Pal.of(c).sub)),
    );

void _copy(BuildContext context, String text, String what) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what copié'), duration: const Duration(seconds: 1)));
}

/// L'onglet Notes : coffre personnel chiffré, synchronisé entre le téléphone et le PC.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String cat = '';
  String query = '';
  final quick = TextEditingController();
  final quickFocus = FocusNode();

  /// Une ligne tapée, Entrée : la note existe. Le reste se règle en l'ouvrant.
  void capture() {
    final s = quick.text.trim();
    if (s.isEmpty) return;
    notes.save(Note(title: s, cat: cat.isEmpty ? 'Mémos' : cat));
    quick.clear();
    quickFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: notes,
        builder: (context, _) {
          final p = Pal.of(context);
          if (!notes.unlocked) {
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              const CoursesPanel(),
              // Pas relié : le coffre existe peut-être ailleurs, on n'en crée pas un second.
              if (!store.linked && !notes.exists) const _LinkFirst() else _Gate(create: !notes.exists),
            ]);
          }
          final q = query.toLowerCase();
          final all = notes.all;
          final shown = [
            for (final n in all)
              if ((cat.isEmpty || n.cat == cat) &&
                  (q.isEmpty ||
                      n.title.toLowerCase().contains(q) ||
                      n.body.toLowerCase().contains(q) ||
                      n.items.any((i) => i.text.toLowerCase().contains(q))))
                n
          ];
          final used = [for (final c in notes.cats) if (all.any((n) => n.cat == c)) c];
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            const CoursesPanel(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: quick,
                    focusNode: quickFocus,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => capture(),
                    decoration: InputDecoration(
                        hintText: 'Écrire une note',
                        isDense: true,
                        prefixIcon: Icon(Icons.edit_note_rounded, color: p.sub),
                        hintStyle: TextStyle(color: p.sub)),
                  ),
                ),
                IconButton(
                    tooltip: 'Fermer le coffre',
                    onPressed: notes.lock,
                    icon: Icon(Icons.lock_open_rounded, color: p.sub)),
              ]),
            ),
            if (notes.state == 'error')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(notes.error, style: TextStyle(color: prioColors[0], fontSize: 13)),
              ),
            if (used.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Row(children: [
                  Pick('Toutes · ${all.length}', cat.isEmpty, () => setState(() => cat = '')),
                  for (final c in used)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Pick('$c · ${all.where((n) => n.cat == c).length}', cat == c,
                          () => setState(() => cat = cat == c ? '' : c),
                          color: _colorOf(c), icon: _iconOf(c)),
                    ),
                ]),
              ),
            // La recherche n'apparaît que quand il y a de quoi chercher.
            if (all.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                      hintText: 'Chercher dans les notes',
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, color: p.sub),
                      hintStyle: TextStyle(color: p.sub)),
                ),
              ),
            if (all.isNotEmpty && shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Text('Rien ne correspond.',
                    textAlign: TextAlign.center, style: TextStyle(color: p.sub)),
              ),
            for (final n in shown) _NoteCard(n, key: ValueKey(n.id)),
          ]);
        },
      );
}

/// Création du coffre ou saisie du code.
class _Gate extends StatefulWidget {
  final bool create;
  const _Gate({required this.create});
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  final code = TextEditingController();
  final again = TextEditingController();
  String error = '';

  Future<void> go() async {
    if (notes.busy) return;
    if (widget.create && code.text != again.text) {
      setState(() => error = 'Les deux codes ne sont pas identiques.');
      return;
    }
    setState(() => error = '');
    final e = widget.create ? await notes.create(code.text) : await notes.unlock(code.text);
    if (!mounted) return;
    if (e != null) {
      setState(() => error = e);
    } else {
      code.clear();
      again.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final create = widget.create;
    return Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Icon(Icons.lock_rounded, size: 40, color: p.accent),
      const SizedBox(height: 14),
      Text(create ? 'Crée ton coffre de notes' : 'Tes notes sont sous clé',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Text(
          create
              ? 'Codes de bâtiment, adresses, mots de passe, jetons : tout est chiffré sur '
                  'ton appareil avec un code que toi seul connais, puis synchronisé entre le téléphone et le PC.'
              : 'Entre ton code pour les voir. Il n\'est demandé qu\'une fois par appareil.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.sub, fontSize: 15, height: 1.35)),
      const SizedBox(height: 22),
      TextField(
        controller: code,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
            labelText: create ? 'Code du coffre (6 caractères ou plus)' : 'Code du coffre'),
        onSubmitted: (_) => create ? null : go(),
      ),
      if (create) ...[
        const SizedBox(height: 12),
        TextField(
          controller: again,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Le même code, une seconde fois'),
          onSubmitted: (_) => go(),
        ),
      ],
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(error, style: TextStyle(color: prioColors[0], fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: notes.busy ? null : go,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        child: Text(
            notes.busy ? 'Un instant…' : (create ? 'Créer le coffre' : 'Ouvrir'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      if (create) ...[
        const SizedBox(height: 18),
        Text(
            'Retiens bien ce code : il n\'est écrit nulle part. Si tu l\'oublies, personne ne peut '
            'rouvrir le coffre, ni toi ni moi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub, fontSize: 13.5, height: 1.35)),
      ],
    ]));
  }
}

/// Coffre introuvable tant que Bim n'est pas relié : on renvoie vers la liaison.
class _LinkFirst extends StatelessWidget {
  const _LinkFirst();
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.link_rounded, size: 40, color: p.accent),
          const SizedBox(height: 14),
          const Text('Relie d\'abord cet appareil',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
              'Ton coffre de notes est rangé dans ton dépôt GitHub. Relie Bim ici, puis ouvre le '
              'coffre avec ton code habituel. Sur ton téléphone : Réglages → Relier un autre appareil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.sub, fontSize: 15, height: 1.35)),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => sheet(context, const ReceiveLinkSheet()),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Relier avec un code de liaison',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () => sheet(context, const SyncSheet()),
              child: const Text('Saisir le dépôt et le jeton à la main')),
        ]));
  }
}

class _NoteCard extends StatefulWidget {
  final Note note;
  const _NoteCard(this.note, {super.key});
  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool reveal = false;
  final add = TextEditingController();
  final focus = FocusNode();

  void addItem() {
    final s = add.text.trim();
    if (s.isEmpty) return;
    widget.note.items.add(NoteItem(s));
    notes.save(widget.note);
    add.clear();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final n = widget.note;
    final c = _colorOf(n.cat);
    final items = [...n.items.where((i) => !i.done), ...n.items.where((i) => i.done)];
    final done = n.items.where((i) => i.done).length;
    return Panel(
      header: InkWell(
        onTap: () => sheet(context, NoteSheet(note: n)),
        child: Row(children: [
          Icon(_iconOf(n.cat), size: 20, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title.isEmpty ? 'Sans titre' : n.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text(n.items.isEmpty ? n.cat : '${n.cat} · $done/${n.items.length}',
                  style: TextStyle(fontSize: 12.5, color: p.sub)),
            ]),
          ),
          if (n.pinned) Icon(Icons.push_pin_rounded, size: 17, color: p.sub),
          const SizedBox(width: 6),
          Icon(Icons.edit_rounded, size: 18, color: p.sub),
          const SizedBox(width: 4),
        ]),
      ),
      children: [
        if (n.body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: SelectableText(n.body, style: const TextStyle(fontSize: 15, height: 1.35))),
              IconButton(
                  tooltip: 'Copier',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context, n.body, 'Texte'),
                  icon: Icon(Icons.copy_rounded, size: 19, color: p.sub)),
            ]),
          ),
        if (n.secret.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(children: [
              Icon(Icons.key_rounded, size: 18, color: p.sub),
              const SizedBox(width: 10),
              Expanded(
                child: Text(reveal ? n.secret : '••••••••••',
                    style: TextStyle(
                        fontSize: 15,
                        fontFamily: reveal ? 'monospace' : null,
                        letterSpacing: reveal ? 0 : 2)),
              ),
              IconButton(
                  tooltip: reveal ? 'Cacher' : 'Montrer',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => reveal = !reveal),
                  icon: Icon(reveal ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 20, color: p.sub)),
              IconButton(
                  tooltip: 'Copier',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context, n.secret, 'Code'),
                  icon: Icon(Icons.copy_rounded, size: 19, color: p.sub)),
            ]),
          ),
        if (n.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final i in items)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    i.done = !i.done;
                    notes.save(n);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                    child: Row(children: [
                      Icon(
                          i.done
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 22,
                          color: i.done ? const Color(0xFF22C55E) : p.sub),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(i.text,
                            style: TextStyle(
                                fontSize: 15,
                                color: i.done ? p.sub : p.ink,
                                decoration: i.done ? TextDecoration.lineThrough : null)),
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
                        hintText: 'Ajouter à la liste',
                        isDense: true,
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.add_rounded, color: p.sub, size: 22),
                        prefixIconConstraints: const BoxConstraints(minWidth: 34),
                        hintStyle: TextStyle(color: p.sub)),
                    onSubmitted: (_) => addItem(),
                  ),
                ),
                if (done > 0)
                  TextButton(
                      onPressed: () {
                        n.items.removeWhere((i) => i.done);
                        notes.save(n);
                      },
                      child: Text(done > 1 ? 'Retirer les $done cochés' : 'Retirer le coché')),
              ]),
            ]),
          ),
      ],
    );
  }
}

/// Créer ou modifier une note.
class NoteSheet extends StatefulWidget {
  final Note? note;
  final String cat;
  const NoteSheet({this.note, this.cat = 'Mémos', super.key});
  @override
  State<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<NoteSheet> {
  late final title = TextEditingController(text: widget.note?.title ?? '');
  late final body = TextEditingController(text: widget.note?.body ?? '');
  late final secret = TextEditingController(text: widget.note?.secret ?? '');
  final other = TextEditingController();
  final add = TextEditingController();
  final addFocus = FocusNode();
  late String cat = widget.note?.cat ?? widget.cat;
  late bool pinned = widget.note?.pinned ?? false;
  late List<NoteItem> items = [
    for (final i in widget.note?.items ?? <NoteItem>[]) NoteItem(i.text, id: i.id, done: i.done)
  ];
  bool showSecret = false;
  // Le reste (cases à cocher, autre catégorie, épingle) reste replié tant qu'on n'en a pas besoin.
  late bool more = items.isNotEmpty || pinned || !noteCats.contains(cat);

  void addItem() {
    final s = add.text.trim();
    if (s.isEmpty) return;
    setState(() => items.add(NoteItem(s)));
    add.clear();
    addFocus.requestFocus();
  }

  void save() {
    addItem();
    final c = other.text.trim().isNotEmpty ? other.text.trim() : cat;
    if (title.text.trim().isEmpty && body.text.trim().isEmpty && secret.text.isEmpty && items.isEmpty) {
      return;
    }
    final n = widget.note ?? Note();
    n
      ..title = title.text.trim()
      ..cat = c
      ..body = body.text.trim()
      ..secret = secret.text.trim()
      ..pinned = pinned
      ..items = items;
    notes.save(n);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final n = widget.note;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: title,
        autofocus: n == null,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
            hintText: 'Titre', border: InputBorder.none, hintStyle: TextStyle(color: p.sub)),
      ),
      TextField(
        controller: body,
        minLines: 2,
        maxLines: 12,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
            hintText: 'Le texte de la note (adresse, code de bâtiment…)',
            isDense: true,
            hintStyle: TextStyle(color: p.sub)),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in notes.cats)
          Pick(c, cat == c && other.text.trim().isEmpty, () => setState(() {
                cat = c;
                other.clear();
              }), color: _colorOf(c), icon: _iconOf(c)),
      ]),
      if (secretCats.contains(cat) || secret.text.isNotEmpty) ...[
        const SizedBox(height: 14),
        TextField(
          controller: secret,
          obscureText: !showSecret,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
              hintText: cat == 'Jetons' ? 'Le jeton (masqué dans la liste)' : 'Le mot de passe (masqué dans la liste)',
              isDense: true,
              hintStyle: TextStyle(color: p.sub),
              suffixIcon: IconButton(
                  onPressed: () => setState(() => showSecret = !showSecret),
                  icon: Icon(
                      showSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 20))),
        ),
      ],
      if (!more)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: () => setState(() => more = true),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Plus d\'options')),
        )
      else ...[
        _label(context, 'CASES À COCHER'),
        for (final i in items)
          Row(children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => i.done = !i.done),
                icon: Icon(
                    i.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: i.done ? const Color(0xFF22C55E) : p.sub)),
            Expanded(child: Text(i.text, style: const TextStyle(fontSize: 15))),
            IconButton(
                tooltip: 'Retirer',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => items.remove(i)),
                icon: Icon(Icons.close_rounded, size: 19, color: p.sub)),
          ]),
        TextField(
          controller: add,
          focusNode: addFocus,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              hintText: 'Ajouter une ligne (Entrée pour enchaîner)',
              isDense: true,
              hintStyle: TextStyle(color: p.sub)),
          onSubmitted: (_) => addItem(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: other,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              hintText: 'Ranger dans une nouvelle catégorie',
              isDense: true,
              hintStyle: TextStyle(color: p.sub)),
        ),
        const SizedBox(height: 14),
        Pick('Épingler en haut', pinned, () => setState(() => pinned = !pinned),
            icon: Icons.push_pin_rounded),
      ],
      const SizedBox(height: 22),
      Row(children: [
        if (n != null)
          IconButton(
              tooltip: 'Supprimer',
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                          title: const Text('Supprimer cette note ?'),
                          content: const Text('Elle disparaît aussi de tes autres appareils.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false), child: const Text('Garder')),
                            FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Supprimer')),
                          ],
                        ));
                if (ok == true && context.mounted) {
                  notes.remove(n);
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline)),
        const Spacer(),
        FilledButton(
            onPressed: save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
            child: Text(n == null ? 'Ajouter' : 'Enregistrer',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      ]),
    ]);
  }
}
