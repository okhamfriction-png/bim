import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'liaison.dart';
import 'media_io.dart' if (dart.library.js_interop) 'media_web.dart';
import 'defi.dart';
import 'models.dart';
import 'notes.dart';
import 'store.dart';

/// Palette claire et sombre.
class Pal {
  final Color bg, card, ink, sub, line, accent, onAccent, soft;
  const Pal(this.bg, this.card, this.ink, this.sub, this.line, this.accent, this.onAccent,
      this.soft);

  static const light = Pal(Color(0xFFF2F3F6), Color(0xFFFFFFFF), Color(0xFF14161B),
      Color(0xFF667085), Color(0xFFDFE2E8), Color(0xFFFFB000), Color(0xFF1C1917),
      Color(0xFFF7F8FA));
  static const dark = Pal(Color(0xFF0D0F13), Color(0xFF171A20), Color(0xFFF2F3F5),
      Color(0xFF9AA1AE), Color(0xFF2B303A), Color(0xFFFFB627), Color(0xFF1C1917),
      Color(0xFF1E222A));

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

/// Icône du type de tâche : elle dit ce que c'est, le titre n'a plus à le répéter.
const kindIcons = <String, IconData>{
  'rue': Icons.signpost_rounded,
  'paris': Icons.videocam_rounded,
  'montee': Icons.movie_edit,
  'short': Icons.smartphone_rounded,
  'rangement': Icons.inventory_2_rounded,
  'recap': Icons.fact_check_rounded,
  'echauffement': Icons.local_fire_department_rounded,
};

IconData taskIcon(Task t) => kindIcons[t.kindOf] ?? iconOf(t.cat);

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

/// Une boîte fermée : un en-tête, puis des lignes séparées par un filet.
class Panel extends StatelessWidget {
  final Widget? header;
  final List<Widget> children;
  final Color? accent;
  final EdgeInsetsGeometry margin;
  final bool fill; // la dernière ligne prend toute la hauteur restante
  const Panel(
      {this.header,
      this.fill = false,
      required this.children,
      this.accent,
      this.margin = const EdgeInsets.fromLTRB(16, 6, 16, 6),
      super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent ?? p.line, width: accent != null ? 1.5 : 1),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                    color: const Color(0xFF101828).withValues(alpha: .05),
                    blurRadius: 10,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null)
          Container(
            color: accent != null ? Color.alphaBlend(accent!.withValues(alpha: .14), p.card) : p.soft,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: header,
          ),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 || header != null) Container(height: 1, color: p.line),
          if (fill && i == children.length - 1) Expanded(child: children[i]) else children[i],
        ],
      ]),
    );
  }
}

/// En-tête de boîte : icône, titre, sous-titre, compteur, action à droite.
class PanelHead extends StatelessWidget {
  final IconData? icon;
  final Color? color;
  final String title;
  final String? subtitle;
  final String? count;
  final Widget? trailing;
  const PanelHead(this.title,
      {this.icon, this.color, this.subtitle, this.count, this.trailing, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(children: [
      if (icon != null)
        Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
              color: (color ?? p.sub).withValues(alpha: .16),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: color ?? p.sub),
        ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
          if (subtitle != null)
            Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: p.sub)),
        ]),
      ),
      if (count != null) Counter(count!),
      if (trailing != null) trailing!,
    ]);
  }
}

/// Petit compteur gris.
class Counter extends StatelessWidget {
  final String text;
  const Counter(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 8, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(99)),
      child: Text(text,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
    );
  }
}

/// Étiquette de priorité P0 à P4.
class PrioChip extends StatelessWidget {
  final int priority;
  const PrioChip(this.priority, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = prioColors[priority];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: priority == 0 ? 1 : .18),
          borderRadius: BorderRadius.circular(6)),
      child: Text(prioNames[priority],
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: priority == 0 ? Colors.white : Color.lerp(c, Pal.of(context).ink, .45))),
    );
  }
}

/// Titre de section au-dessus des boîtes.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {this.trailing, super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 16, 4),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w800,
                    color: Pal.of(context).sub)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Sélecteur à segments, dans un seul cadre.
class Segmented extends StatelessWidget {
  final Map<String, String> items;
  final String value;
  final ValueChanged<String> onChanged;
  final bool expand;
  const Segmented(this.items, this.value, this.onChanged, {this.expand = false, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget seg(MapEntry<String, String> e) {
      final on = e.key == value;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(e.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? p.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: on
                ? [BoxShadow(color: Colors.black.withValues(alpha: .10), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Text(e.value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: on ? p.ink : p.sub)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
        for (final e in items.entries) expand ? Expanded(child: seg(e)) : seg(e),
      ]),
    );
  }
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
  late final result = TextEditingController(text: widget.task?.result ?? '');
  late int priority = widget.task?.priority ?? 2;
  late String domain = widget.task?.cat ?? 'Mission';
  late bool call = widget.task?.call ?? false;
  late bool more = widget.task != null;
  late String kind = widget.task?.kind ?? '';

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
          result: result.text.trim(),
          kind: kind,
          priority: priority,
          domain: domain,
          call: isCall));
    } else {
      t
        ..title = s
        ..note = note.text.trim()
        ..links = ls
        ..result = result.text.trim()
        ..kind = kind
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
              child: const Text('Descriptif, liens, résultat…')),
        ),
      if (more) ...[
        _label(context, 'POINTS DE VALEUR'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pick('Aucun', kind.isEmpty, () => setState(() => kind = '')),
          for (final k in kinds.entries)
            Pick('${k.value.$1} · ${store.schedule.coef[k.key]}', kind == k.key,
                () => setState(() => kind = k.key)),
        ]),
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
        _label(context, 'RÉSULTAT (FACULTATIF)'),
        TextField(
          controller: result,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              hintText: 'Ex. : 2 venus',
              isDense: true,
              counterText: '',
              hintStyle: TextStyle(color: p.sub)),
        ),
      ],
      const SizedBox(height: 22),
      Row(children: [
        if (t != null)
          IconButton(
              tooltip: 'Dupliquer',
              onPressed: () {
                final c = store.duplicate(t);
                Navigator.pop(context);
                sheet(context, TaskSheet(task: c));
              },
              icon: const Icon(Icons.copy_rounded)),
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
        _label(context, 'APPARENCE'),
        Segmented(const {'system': 'Système', 'light': 'Clair', 'dark': 'Sombre', 'auto': 'Horaire'},
            store.themeMode, store.setThemeMode,
            expand: true),
        if (store.themeMode == 'auto') ...[
          const SizedBox(height: 8),
          Stepper2('Sombre à partir de (h)', store.darkFrom, (v) => store.setThemeHours(dark: v),
              max: 23),
          Stepper2('Clair à partir de (h)', store.lightFrom, (v) => store.setThemeHours(light: v),
              max: 23),
        ],
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
        _label(context, 'WIDGET ANDROID'),
        Stepper2('Opacité du fond (%)', store.widgetOpacity, store.setWidgetOpacity,
            step: 10, max: 100),
        const SizedBox(height: 6),
        Text('Priorités affichées', style: TextStyle(fontSize: 15, color: p.ink)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i <= 4; i++)
            Pick(prioNames[i], store.widgetPrios.contains(i), () => store.toggleWidgetPrio(i),
                color: prioColors[i]),
        ]),
        _label(context, 'POINTS DE VALEUR PAR UNITÉ LIVRÉE'),
        for (final k in kinds.entries)
          Stepper2('${k.value.$1} (par ${k.value.$2.substring(0, k.value.$2.length - 1)})',
              store.schedule.coef[k.key] ?? 0, (v) => store.setCoef(k.key, v)),
        _label(context, 'CIBLE DE POINTS PAR SPRINT'),
        Stepper2('Semaine avec enfants', store.schedule.targetKids,
            (v) => store.setDefaultTarget(kids: true, v: v),
            step: 5),
        Stepper2('Semaine sans enfants', store.schedule.targetFree,
            (v) => store.setDefaultTarget(kids: false, v: v),
            step: 5),
        for (final sp in store.sprints)
          Stepper2('Sprint du ${dateOf(sp).day}/${dateOf(sp).month}', store.targetOf(sp),
              (v) => store.setTarget(sp, v),
              step: 5),
        _label(context, 'SYNCHRONISATION'),
        Text(
            'Le backlog vit dans un fichier d\'un dépôt GitHub privé. Le téléphone, le web et tes sessions Claude lisent et écrivent le même.',
            style: TextStyle(color: p.sub)),
        const SizedBox(height: 14),
        if (store.linked)
          OutlinedButton.icon(
              onPressed: () => sheet(context, const LinkOtherSheet()),
              icon: const Icon(Icons.qr_code_2_rounded),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              label: const Text('Relier un autre appareil',
                  style: TextStyle(fontWeight: FontWeight.w800)))
        else ...[
          FilledButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await sheet<bool>(context, const ReceiveLinkSheet()) == true) nav.pop();
              },
              icon: const Icon(Icons.link_rounded),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              label: const Text('Relier avec un code de liaison',
                  style: TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 6),
          Text('Le code se fait sur un appareil déjà relié : Réglages → Relier un autre appareil. '
              'Ou bien, à la main :',
              style: TextStyle(color: p.sub, fontSize: 13)),
        ],
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
                    notes.sync();
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

/// Une ligne de réglage : un libellé, moins, la valeur, plus.
class Stepper2 extends StatelessWidget {
  final String label;
  final int value, step;
  final int? max;
  final ValueChanged<int> onChanged;
  const Stepper2(this.label, this.value, this.onChanged, {this.step = 1, this.max, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: p.ink))),
      IconButton(
          tooltip: 'Moins',
          visualDensity: VisualDensity.compact,
          onPressed: value <= 0 ? null : () => onChanged(value - step),
          icon: const Icon(Icons.remove_circle_outline)),
      SizedBox(
          width: 38,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink))),
      IconButton(
          tooltip: 'Plus',
          visualDensity: VisualDensity.compact,
          onPressed: max != null && value >= max! ? null : () => onChanged(value + step),
          icon: const Icon(Icons.add_circle_outline)),
    ]);
  }
}

/// Avancement des sous-tâches : « 2/5 » et une petite barre.
class SubProgress extends StatelessWidget {
  final Task task;
  final double width;
  const SubProgress(this.task, {this.width = 44, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = task;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(t.progress,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
      const SizedBox(width: 6),
      SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
              value: t.subsDone / t.subs.length,
              minHeight: 5,
              backgroundColor: p.line,
              color: const Color(0xFF22C55E)),
        ),
      ),
    ]);
  }
}

/// Une case à cocher ronde de sous-tâche.
class SubCheck extends StatelessWidget {
  final Task task;
  final Sub sub;
  final VoidCallback? onChanged;
  const SubCheck(this.task, this.sub, {this.onChanged, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        store.toggleSub(task, sub);
        onChanged?.call();
        // Une prise d'échauffement cochée : on note tout de suite son score.
        if (task.whole && sub.done && !sub.noted) {
          await askPrise(context, task, sub);
          onChanged?.call();
        } else if (task.kindOf == 'rue' && sub.done && sub.data.isEmpty) {
          await askBlock(context, task, sub);
          onChanged?.call();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(sub.done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 22, color: sub.done ? const Color(0xFF22C55E) : p.sub),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(sub.title,
                  style: TextStyle(
                      fontSize: 15,
                      color: sub.done ? p.sub : p.ink,
                      decoration: sub.done ? TextDecoration.lineThrough : null)),
            ),
          ),
          if (task.whole || task.kindOf == 'rue') ScorePill(task, sub, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// Les sous-tâches d'une tâche dépliée : cases à cocher, ajout à la chaîne, duplication.
class SubList extends StatefulWidget {
  final Task task;
  const SubList(this.task, {super.key});
  @override
  State<SubList> createState() => _SubListState();
}

class _SubListState extends State<SubList> {
  final field = TextEditingController();
  final focus = FocusNode();
  final rename = TextEditingController();
  Sub? editing; // sous-tâche en cours de renommage

  void endRename(String v) {
    final s = editing;
    if (s == null) return;
    setState(() => editing = null);
    store.renameSub(widget.task, s, v);
  }

  void add([int count = 1]) {
    final t = widget.task;
    final s = field.text.trim().isEmpty && count > 1 ? t.title : field.text;
    if (s.trim().isEmpty) return;
    store.addSubs(t, s, count);
    field.clear();
    focus.requestFocus(); // le champ reste ouvert pour en saisir plusieurs d'affilée
  }

  @override
  void dispose() {
    field.dispose();
    rename.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.task;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (t.subs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Text('SOUS-TÂCHES',
                style: TextStyle(
                    fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w800, color: p.sub)),
            const Spacer(),
            SubProgress(t, width: 70),
          ]),
        ),
      for (final s in t.subs)
        Row(children: [
          Expanded(
            child: identical(editing, s)
                ? TextField(
                    controller: rename,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (v) => endRename(v),
                    onTapOutside: (_) => endRename(rename.text),
                  )
                : SubCheck(t, s),
          ),
          if (!identical(editing, s))
            IconButton(
                tooltip: 'Renommer la sous-tâche',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                      editing = s;
                      rename.text = s.title;
                      rename.selection =
                          TextSelection(baseOffset: 0, extentOffset: s.title.length);
                    }),
                icon: Icon(Icons.edit_rounded, size: 17, color: p.sub)),
          IconButton(
              tooltip: 'Retirer la sous-tâche',
              visualDensity: VisualDensity.compact,
              onPressed: () => store.removeSub(t, s),
              icon: Icon(Icons.close_rounded, size: 18, color: p.sub)),
        ]),
      Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line)),
        child: Row(children: [
          Icon(Icons.add_rounded, size: 20, color: p.sub),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: field,
              focusNode: focus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                  hintText: 'Ajouter une sous-tâche',
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintStyle: TextStyle(color: p.sub)),
              onSubmitted: (_) => add(),
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'Dupliquer en N sous-tâches',
            onSelected: add,
            itemBuilder: (_) => [
              PopupMenuItem(
                  enabled: false,
                  height: 34,
                  child: Text('Dupliquer en N sous-tâches',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800, color: p.sub))),
              for (final n in const [2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20])
                PopupMenuItem(value: n, height: 38, child: Text('× $n')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.copy_all_rounded, size: 18, color: p.sub),
                const SizedBox(width: 4),
                Text('× N',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: p.sub)),
              ]),
            ),
          ),
        ]),
      ),
    ]);
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
    // Un échauffement est un défi : sa fiche remplace le descriptif.
    if (t.whole) return DefiCard(t, align: align);
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

/// Demande le score d'une prise : les secondes tenues avant le premier « euh ».
Future<void> askScore(BuildContext context, Task t, Sub s) async {
  final c = TextEditingController(text: s.result);
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            labelText: 'Score', hintText: 'Secondes avant le premier « euh »', suffixText: 's'),
        onSubmitted: (x) => Navigator.pop(ctx, x),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Noter')),
      ],
    ),
  );
  if (v != null) store.setSubResult(t, s, v);
}

/// Pastille du score d'une prise ; un appui permet de le corriger.
class ScorePill extends StatelessWidget {
  final Task task;
  final Sub sub;
  final VoidCallback? onChanged;
  const ScorePill(this.task, this.sub, {this.onChanged, super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final rue = task.kindOf == 'rue';
    final has = rue ? sub.data.isNotEmpty : sub.noted;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () async {
        await (rue ? askBlock(context, task, sub) : askPrise(context, task, sub));
        onChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99), border: Border.all(color: p.line)),
        child: Text(
            rue
                ? (has ? (sub.blockSummary.isEmpty ? 'Noté' : sub.blockSummary) : 'Résultat')
                : priseSummary(sub),
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: has ? p.ink : p.sub)),
      ),
    );
  }
}

/// Bilan d'un bloc de rue : des champs à remplir, les chiffres au clavier numérique.
Future<void> askBlock(BuildContext context, Task t, Sub s) async {
  final c = {
    for (final f in blockFields) f.$1: TextEditingController(text: '${s.data[f.$1] ?? ''}')
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in blockFields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: c[f.$1],
                autofocus: f.$1 == blockFields.first.$1,
                keyboardType: f.$3 ? TextInputType.number : TextInputType.text,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                minLines: 1,
                maxLines: f.$3 ? 1 : 3,
                decoration: InputDecoration(labelText: f.$2, isDense: true),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Noter')),
      ],
    ),
  );
  if (ok != true) return;
  final d = <String, dynamic>{};
  for (final f in blockFields) {
    final v = c[f.$1]!.text.trim();
    if (v.isEmpty) continue;
    if (f.$3) {
      final n = int.tryParse(v);
      if (n != null) d[f.$1] = n;
    } else {
      d[f.$1] = v;
    }
  }
  store.setSubData(t, s, d);
}
