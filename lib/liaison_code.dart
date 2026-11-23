import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Code de liaison : relier un nouvel appareil (navigateur, PC) depuis un appareil déjà relié,
/// sans recopier le jeton GitHub.
///
/// L'appareil relié chiffre {dépôt, jeton, expiration} avec une clé tirée d'un code court
/// (6 caractères) qu'il affiche à côté. Le code de liaison seul ne révèle rien ; il voyage
/// dans le fragment `#relier=…` d'une adresse, qui n'est jamais envoyé au serveur.
/// Même format que le bureau (bureau/src/lib/liaison.js) :
///   `bim1.` + base64url(sel 16 octets | nonce 12 | chiffré | tag 16), AES-256-GCM, PBKDF2-SHA256.
const liaisonPrefix = 'bim1.';
const liaisonIter = 200000;
const liaisonMinutes = 15;
const liaisonPage = 'https://okhamfriction-png.github.io/bim/';

/// Alphabet du code court : sans 0/O, 1/I/L, pour se lire sans hésiter.
const pinAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

final _aes = AesGcm.with256bits();

String newPin([Random? rnd]) {
  final r = rnd ?? Random.secure();
  return String.fromCharCodes(
      [for (var i = 0; i < 6; i++) pinAlphabet.codeUnitAt(r.nextInt(pinAlphabet.length))]);
}

/// « k7q-m4p » ou « K7QM4P » → « K7QM4P ».
String normPin(String s) => s.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// Affichage en deux groupes : « K7Q-M4P ».
String showPin(String p) => p.length == 6 ? '${p.substring(0, 3)}-${p.substring(3)}' : p;

String _b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');
Uint8List _unb64u(String s) => base64Url.decode(s + '=' * ((4 - s.length % 4) % 4));

Future<SecretKey> _derive(String pin, List<int> salt) async {
  final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: liaisonIter, bits: 256)
      .deriveKeyFromPassword(password: normPin(pin), nonce: salt);
  return SecretKey(await k.extractBytes());
}

/// Fabrique le code de liaison (valable [liaisonMinutes] minutes).
Future<String> makeLiaison(String repo, String token, String pin, {int? nowMs}) async {
  final rnd = Random.secure();
  final salt = [for (var i = 0; i < 16; i++) rnd.nextInt(256)];
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final plain = jsonEncode({'r': repo, 't': token, 'x': now + liaisonMinutes * 60000});
  final box = await _aes.encrypt(utf8.encode(plain), secretKey: await _derive(pin, salt));
  return '$liaisonPrefix${_b64u([...salt, ...box.concatenation()])}';
}

String liaisonLink(String code) => '$liaisonPage#relier=$code';

/// Retrouve le code de liaison dans ce qui a été collé : l'adresse entière, ou le code seul.
String? findLiaison(String text) =>
    RegExp(r'bim1\.[A-Za-z0-9_-]{40,}').firstMatch(text)?.group(0);

class LiaisonError implements Exception {
  final String message;
  LiaisonError(this.message);
  @override
  String toString() => message;
}

/// Déchiffre un code de liaison. Lève [LiaisonError] avec un message à montrer.
Future<({String repo, String token})> readLiaison(String pasted, String pin, {int? nowMs}) async {
  final code = findLiaison(pasted);
  if (code == null) throw LiaisonError('Ce n\'est pas un code de liaison Bim.');
  if (normPin(pin).length != 6) throw LiaisonError('Le code court a 6 caractères.');
  final Uint8List all;
  try {
    all = _unb64u(code.substring(liaisonPrefix.length));
  } catch (_) {
    throw LiaisonError('Code de liaison abîmé : recopie-le en entier.');
  }
  if (all.length < 16 + 12 + 16 + 1) throw LiaisonError('Code de liaison incomplet : recopie-le en entier.');
  final Map<String, dynamic> j;
  try {
    final box = SecretBox.fromConcatenation(all.sublist(16), nonceLength: 12, macLength: 16);
    final plain = await _aes.decrypt(box, secretKey: await _derive(pin, all.sublist(0, 16)));
    j = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  } catch (_) {
    throw LiaisonError('Ce n\'est pas le bon code court, ou le code de liaison est incomplet.');
  }
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  if ((j['x'] as num? ?? 0) < now) {
    throw LiaisonError('Ce code de liaison a expiré : fais-en un nouveau sur l\'appareil déjà relié.');
  }
  final repo = (j['r'] as String? ?? '').trim(), token = (j['t'] as String? ?? '').trim();
  if (repo.isEmpty || token.isEmpty) throw LiaisonError('Code de liaison vide.');
  return (repo: repo, token: token);
}
