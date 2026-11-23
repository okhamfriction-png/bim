import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import 'courses.dart';
import 'liaison_code.dart';
import 'notes.dart';
import 'store.dart';
import 'ui.dart';

/// Sur l'appareil déjà relié : un QR code et un lien chiffrés, plus un code court à taper.
/// Le jeton n'apparaît jamais à l'écran.
class LinkOtherSheet extends StatefulWidget {
  const LinkOtherSheet({super.key});
  @override
  State<LinkOtherSheet> createState() => _LinkOtherSheetState();
}

class _LinkOtherSheetState extends State<LinkOtherSheet> {
  String pin = '';
  String link = '';
  int expires = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _make();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _make() async {
    setState(() => link = '');
    final p = newPin();
    final code = await makeLiaison(store.repo, store.token, p);
    if (!mounted) return;
    setState(() {
      pin = p;
      link = liaisonLink(code);
      expires = DateTime.now().millisecondsSinceEpoch + liaisonMinutes * 60000;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final left = ((expires - DateTime.now().millisecondsSinceEpoch) / 60000).ceil();
    final expired = link.isNotEmpty && left <= 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('Relier un autre appareil',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
          'Sur le nouvel appareil, scanne ce QR code avec l\'appareil photo, ou ouvre le lien que '
          'tu t\'envoies. Bim te demandera alors le code court ci-dessous.',
          style: TextStyle(color: p.sub, height: 1.35)),
      const SizedBox(height: 16),
      if (link.isEmpty)
        const Padding(
            padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
      else ...[
        Center(
          child: Opacity(
            opacity: expired ? .25 : 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration:
                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: QrView(link, size: 220),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('CODE COURT', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.sub)),
        SelectableText(showPin(pin),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4, fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Text(
            expired
                ? 'Ce code a expiré.'
                : 'Valable encore $left min. Tape-le à la main : ne l\'envoie jamais avec le lien.',
            textAlign: TextAlign.center,
            style: TextStyle(color: expired ? prioColors[0] : p.sub, fontSize: 13.5)),
        const SizedBox(height: 16),
        if (expired)
          FilledButton(
              onPressed: _make,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Nouveau code', style: TextStyle(fontWeight: FontWeight.w800)))
        else
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                  onPressed: () => SharePlus.instance
                      .share(ShareParams(text: link, subject: 'Relier Bim'))
                      .catchError((_) => ShareResult.unavailable),
                  icon: const Icon(Icons.share_rounded),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  label: const Text('Envoyer le lien', style: TextStyle(fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Lien copié'), duration: Duration(seconds: 1)));
                  },
                  icon: const Icon(Icons.copy_rounded),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  label: const Text('Copier le lien')),
            ),
          ]),
        const SizedBox(height: 12),
        Text(
            'Le lien est chiffré : sans le code court, il ne dit rien. Ensuite, le coffre de notes '
            's\'ouvre sur le nouvel appareil avec ton code habituel.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.35)),
      ],
    ]);
  }
}

/// Sur l'appareil à relier : coller le lien (ou l'ouvrir depuis le QR code) et taper le code court.
class ReceiveLinkSheet extends StatefulWidget {
  final String? code;
  const ReceiveLinkSheet({this.code, super.key});
  @override
  State<ReceiveLinkSheet> createState() => _ReceiveLinkSheetState();
}

class _ReceiveLinkSheetState extends State<ReceiveLinkSheet> {
  late final code = TextEditingController(text: widget.code ?? '');
  final pin = TextEditingController();
  String error = '';
  bool busy = false;

  Future<void> go() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await readLiaison(code.text, pin.text);
      await store.setLink(r.repo, r.token);
      await notes.sync();
      courses.sync();
      if (store.syncState != 'ok') {
        setState(() => error = store.syncError);
        return;
      }
      nav.pop(true);
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Relié : ${store.backlog.length} tâches dans le Backlog. '
              '${notes.exists ? 'Le coffre de notes s\'ouvre avec ton code habituel.' : ''}')));
    } on LiaisonError catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final given = widget.code != null && findLiaison(widget.code!) != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('Relier cet appareil', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
          given
              ? 'Tape le code court affiché sur l\'appareil déjà relié.'
              : 'Sur ton téléphone (déjà relié) : Réglages → Relier un autre appareil. Scanne le QR '
                  'code, ou colle ici le lien qu\'il t\'envoie, puis tape le code court.',
          style: TextStyle(color: p.sub, height: 1.35)),
      const SizedBox(height: 16),
      if (!given) ...[
        TextField(
            controller: code,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Lien ou code de liaison')),
        const SizedBox(height: 10),
      ],
      TextField(
          controller: pin,
          autofocus: given,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 22, letterSpacing: 3, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(labelText: 'Code court (6 caractères)'),
          onSubmitted: (_) => go()),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(error, style: TextStyle(color: prioColors[0], fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 16),
      FilledButton(
          onPressed: busy ? null : go,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: Text(busy ? 'Un instant…' : 'Relier',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
    ]);
  }
}

/// Un QR code dessiné en noir sur blanc.
class QrView extends StatelessWidget {
  final String data;
  final double size;
  const QrView(this.data, {this.size = 200, super.key});
  @override
  Widget build(BuildContext context) {
    final img = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L));
    return CustomPaint(size: Size.square(size), painter: _QrPainter(img));
  }
}

class _QrPainter extends CustomPainter {
  final QrImage img;
  _QrPainter(this.img);
  @override
  void paint(Canvas canvas, Size size) {
    final n = img.moduleCount;
    final cell = size.width / n;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (img.isDark(y, x)) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + .5, cell + .5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.img != img;
}
