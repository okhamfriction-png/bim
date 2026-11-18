import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'media_io.dart' if (dart.library.js_interop) 'media_web.dart';
import 'models.dart';
import 'store.dart';

/// Palette claire et sombre.
class Pal {
  final Color bg, card, ink, sub, line, accent, onAccent;
  const Pal(this.bg, this.card, this.ink, this.sub, this.line, this.accent, this.onAccent);

  static const light = Pal(Color(0xFFFAF6EE), Color(0xFFFFFFFF), Color(0xFF1C1917),
      Color(0xFF78716C), Color(0xFFE9E1D4), Color(0xFFFFB000), Color(0xFF1C1917));
  static const dark = Pal(Color(0xFF141210), Color(0xFF211D1A), Color(0xFFF5F0E8),
      Color(0xFFA8A29E), Color(0xFF342F2A), Color(0xFFFFB627), Color(0xFF1C1917));

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

const prioColors = [
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFF3B82F6),
  Color(0xFF64748B),
  Color(0xFFCBD5E1),
];
const prioNames = ['P0', 'P1', 'P2', 'P3', 'P4'];

const domains = <String, Color>{
  'Mission': Color(0xFF3B82F6),
  'Contenu': Color(0xFFF59E0B),
  'Destiny': Color(0xFFA855F7),
  'Personnel': Color(0xFF22C55E),
  'Parking': Color(0xFF94A3B8),
};

const domainIcons = <String, IconData>{
  'Mission': Icons.work_rounded,
  'Contenu': Icons.videocam_rounded,
  'Destiny': Icons.theater_comedy_rounded,
  'Personnel': Icons.menu_book_rounded,
  'Parking': Icons.local_parking_rounded,
};

IconData iconOf(String d) => domainIcons[d] ?? Icons.label_rounded;

Color domainOf(String d) => domains[d] ?? const Color(0xFF94A3B8);

const dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const dayNames = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const monthNames = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
  'septembre', 'octobre', 'novembre', 'décembre'
];

String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String longDate(DateTime d) =>
    '${cap(dayNames[d.weekday - 1])} ${d.day} ${monthNames[d.month - 1]}';
String hm(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String dur(int minutes) {
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return m == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, this.color, {this.icon, super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null)
            Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(icon, size: 15, color: Color.lerp(color, Pal.of(context).ink, .35))),
          Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color.lerp(color, Pal.of(context).ink, .35))),
        ]),
      );
}

class Pick extends StatelessWidget {
  final String label;
  final bool on;
  final Color? color;
  final IconData? icon;
  final VoidCallback onTap;
  const Pick(this.label, this.on, this.onTap, {this.color, this.icon, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = color ?? p.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? c.withValues(alpha: .2) : Colors.transparent,
          border: Border.all(color: on ? c : p.line, width: 1.5),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null)
            Padding(
                padding: const EdgeInsets.only(right: 6), child: Icon(icon, size: 17, color: c)),
          Text(label,
              style: TextStyle(
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: p.ink)),
        ]),
      ),
    );
  }
}

Future<T?> sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).card,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), child: child)),
      ),
    );

Widget _label(BuildContext c, String s) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(s,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: Pal.of(c).sub)),
    );

/// Création ou modification d'une tâche.
class TaskSheet extends StatefulWidget {
  final Task? task;
  const TaskSheet({this.task, super.key});
  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late final title = TextEditingController(text: widget.task?.title ?? '');
  late final note = TextEditingController(text: widget.task?.note ?? '');
  late final links = TextEditingController(text: (widget.task?.links ?? []).join('\n'));
  late int priority = widget.task?.priority ?? 2;
  late String domain = widget.task?.cat ?? 'Mission';
  late bool call = widget.task?.call ?? false;
  late bool more = widget.task != null;

  void save() {
    final s = title.text.trim();
    if (s.isEmpty) return;
    final t = widget.task;
    final ls = links.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final isCall = call && domain == 'Mission';
    if (t == null) {
      store.add(Task(
          title: s,
          note: note.text.trim(),
          links: ls,
          priority: priority,
          domain: domain,
          call: isCall));
    } else {
      t
        ..title = s
        ..note = note.text.trim()
        ..links = ls
        ..priority = priority
        ..domain = domain
        ..call = isCall;
      if (domain == 'Parking') t.pickedOn = null;
      store.touch(t);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.task;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: title,
        autofocus: t == null,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
            hintText: 'Quoi faire ?', border: InputBorder.none, hintStyle: TextStyle(color: p.sub)),
        onSubmitted: (_) => save(),
      ),
      if (t != null && t.source.isNotEmpty)
        Text('Ajoutée par ${t.source}', style: TextStyle(color: p.sub, fontSize: 13)),
      _label(context, 'CATÉGORIE'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in domains.entries)
          Pick(d.key, domain == d.key, () => setState(() => domain = d.key),
              color: d.value, icon: iconOf(d.key)),
      ]),
      _label(context, 'PRIORITÉ'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i <= 4; i++)
          Pick(prioNames[i], priority == i, () => setState(() => priority = i),
              color: prioColors[i]),
      ]),
      if (domain == 'Mission')
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Pick('Appel ou entretien : passe devant tout', call,
              () => setState(() => call = !call),
              icon: Icons.phone_in_talk_rounded, color: domains['Mission']),
        ),
      if (!more)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextButton(
              onPressed: () => setState(() => more = true),
              child: const Text('Descriptif, liens…')),
        ),
      if (more) ...[
        _label(context, 'DESCRIPTIF'),
        TextField(
          controller: note,
          minLines: 1,
          maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              hintText: 'Descriptif, script, contexte', isDense: true, hintStyle: TextStyle(color: p.sub)),
        ),
        _label(context, 'LIENS ET VIDÉOS'),
        TextField(
          controller: links,
          minLines: 1,
          maxLines: 5,
          autocorrect: false,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
              hintText: 'Une adresse par ligne', isDense: true, hintStyle: TextStyle(color: p.sub)),
        ),
      ],
      const SizedBox(height: 22),
      Row(children: [
        if (t != null)
          IconButton(
              tooltip: 'Supprimer',
              onPressed: () {
                store.remove(t);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline)),
        if (t != null && t.status == 'done')
          TextButton(
              onPressed: () {
                store.reopen(t);
                Navigator.pop(context);
              },
              child: const Text('Remettre à faire')),
        const Spacer(),
        FilledButton(
            onPressed: save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
            child: Text(t == null ? 'Ajouter' : 'Enregistrer',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      ]),
    ]);
  }
}

/// Réglages de synchro GitHub.
class SyncSheet extends StatefulWidget {
  const SyncSheet({super.key});
  @override
  State<SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<SyncSheet> {
  late final repo = TextEditingController(text: store.repo);
  late final token = TextEditingController(text: store.token);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Réglages', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        _label(context, 'VUE DE L\'AGENDA À L\'OUVERTURE'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in const [
            ('jour', 'Jour'),
            ('semaine', 'Semaine'),
            ('mois', 'Mois'),
            ('annee', 'Année')
          ])
            Pick(v.$2, store.agendaView == v.$1, () => store.setAgendaView(v.$1)),
        ]),
        _label(context, 'SYNCHRONISATION'),
        Text(
            'Le backlog vit dans un fichier d\'un dépôt GitHub privé. Le téléphone, le web et tes sessions Claude lisent et écrivent le même.',
            style: TextStyle(color: p.sub)),
        const SizedBox(height: 14),
        TextField(
            controller: repo,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Dépôt', hintText: 'compte/bim-data')),
        const SizedBox(height: 10),
        TextField(
            controller: token,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Jeton d\'accès GitHub')),
        const SizedBox(height: 14),
        Text(
            switch (store.syncState) {
              'ok' => 'Synchronisé',
              'sync' => 'Synchronisation…',
              'error' => store.syncError,
              _ => 'Pas encore relié : les tâches restent sur cet appareil.',
            },
            style: TextStyle(
                color: store.syncState == 'error' ? prioColors[0] : p.sub,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        FilledButton(
            onPressed: store.syncState == 'sync'
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    FocusScope.of(context).unfocus();
                    await store.setLink(repo.text, token.text);
                    if (store.syncState != 'ok') return;
                    // Réussi : on ferme et on dit ce qui est arrivé.
                    nav.pop();
                    final blocks = store.schedule.blocks.where((b) => b.fixed).length;
                    messenger.showSnackBar(SnackBar(
                        duration: const Duration(seconds: 6),
                        content: Text('Relié à GitHub : ${store.backlog.length} tâches dans le '
                            'Backlog, $blocks blocs fixes dans l\'Agenda.')));
                  },
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(
                store.syncState == 'sync' ? 'Synchronisation…' : 'Relier et synchroniser',
                style: const TextStyle(fontWeight: FontWeight.w800))),
      ]),
    );
  }
}

/// Le contenu d'une tâche : descriptif complet, vidéos, images et liens.
class TaskBody extends StatelessWidget {
  final Task task;
  final TextAlign align;
  const TaskBody(this.task, {this.align = TextAlign.start, super.key});

  static bool _is(String u, List<String> ext) {
    final path = (Uri.tryParse(u)?.path ?? u).toLowerCase();
    return ext.any(path.endsWith);
  }

  static String _host(String u) {
    final h = Uri.tryParse(u)?.host.replaceFirst('www.', '') ?? '';
    if (h.contains('youtu')) return 'YouTube';
    if (h.contains('instagram')) return 'Instagram';
    if (h.contains('tiktok')) return 'TikTok';
    if (h.contains('facebook') || h == 'fb.watch') return 'Facebook';
    return h.isEmpty ? u : h;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = task;
    return Column(
        crossAxisAlignment:
            align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (t.note.isNotEmpty)
            SelectableText(t.note,
                textAlign: align,
                style: TextStyle(fontSize: 15.5, height: 1.45, color: p.ink)),
          for (final u in t.links)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _is(u, ['.mp4', '.mov', '.webm', '.m4v'])
                  ? InlineVideo(u)
                  : _is(u, ['.png', '.jpg', '.jpeg', '.webp', '.gif'])
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: u.startsWith('media/')
                              ? PrivateImage(u)
                              : Image.network(u,
                                  errorBuilder: (c, e, s) => Text('Image introuvable',
                                      style: TextStyle(color: p.sub))))
                      : u.startsWith('media/')
                          ? Text(u.substring(6), style: TextStyle(color: p.sub))
                      : OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri.parse(u),
                              mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(_host(u), overflow: TextOverflow.ellipsis)),
            ),
        ]);
  }
}

/// Une image privée du dépôt de données.
class PrivateImage extends StatefulWidget {
  final String path;
  const PrivateImage(this.path, {super.key});
  @override
  State<PrivateImage> createState() => _PrivateImageState();
}

class _PrivateImageState extends State<PrivateImage> {
  late final Future<Uint8List> bytes = store.media(widget.path);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: bytes,
        builder: (c, s) => s.hasData
            ? Image.memory(s.data!)
            : Padding(
                padding: const EdgeInsets.all(12),
                child: s.hasError
                    ? Text('${s.error}', style: TextStyle(color: Pal.of(c).sub))
                    : const Center(child: CircularProgressIndicator())),
      );
}

/// Une vidéo lue dans la tâche. Elle ne se charge qu'au premier toucher.
/// Une adresse « media/… » désigne un fichier privé du dépôt de données.
class InlineVideo extends StatefulWidget {
  final String url;
  const InlineVideo(this.url, {super.key});
  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? c;
  String? error;
  bool loading = false;

  Future<void> toggle() async {
    if (loading) return;
    if (c != null) {
      c!.value.isPlaying ? c!.pause() : c!.play();
      return;
    }
    setState(() => loading = true);
    try {
      final u = widget.url;
      final v = u.startsWith('media/')
          ? await privateVideo(u, () => store.media(u))
          : VideoPlayerController.networkUrl(Uri.parse(u));
      await v.initialize();
      v.addListener(() {
        if (mounted) setState(() {});
      });
      c = v;
    } catch (e) {
      debugPrint('Bim vidéo : $e');
      error = e is String ? e : 'Vidéo illisible';
    }
    if (mounted) setState(() => loading = false);
    // Le navigateur peut refuser la lecture automatique : un second toucher la lance.
    c?.play().catchError((_) {});
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = c != null && c!.value.isInitialized;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GestureDetector(
        onTap: error == null ? toggle : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: AspectRatio(
            aspectRatio: ready ? c!.value.aspectRatio : 16 / 9,
            child: Stack(alignment: Alignment.center, children: [
              const ColoredBox(color: Colors.black, child: SizedBox.expand()),
              if (ready) VideoPlayer(c!),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)))
              else if (loading)
                const CircularProgressIndicator(color: Colors.white)
              else if (!ready || !c!.value.isPlaying)
                const Icon(Icons.play_circle_fill, size: 64, color: Colors.white),
              if (ready)
                Align(
                    alignment: Alignment.bottomCenter,
                    child: VideoProgressIndicator(c!, allowScrubbing: true)),
            ]),
          ),
        ),
      ),
    );
  }
}
