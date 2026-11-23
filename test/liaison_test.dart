import 'package:bim/liaison_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aller-retour', () async {
    final code = await makeLiaison('compte/bim-data', 'github_pat_secret', 'K7QM4P');
    expect(code.startsWith('bim1.'), isTrue);
    expect(code.contains('secret'), isFalse);
    final r = await readLiaison('https://x/bim/#relier=$code', 'k7q-m4p');
    expect(r.repo, 'compte/bim-data');
    expect(r.token, 'github_pat_secret');
  });

  test('mauvais code court, expiré, abîmé', () async {
    final code = await makeLiaison('a/b', 't', 'K7QM4P');
    expect(() => readLiaison(code, 'AAAAAA'), throwsA(isA<LiaisonError>()));
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(() => readLiaison(code, 'K7QM4P', nowMs: now + 16 * 60000), throwsA(isA<LiaisonError>()));
    expect(() => readLiaison('bonjour', 'K7QM4P'), throwsA(isA<LiaisonError>()));
    expect(() => readLiaison(code.substring(0, code.length - 5), 'K7QM4P'), throwsA(isA<LiaisonError>()));
  });

  test('code court', () {
    final p = newPin();
    expect(p.length, 6);
    expect(p.split('').every(pinAlphabet.contains), isTrue);
    expect(showPin('K7QM4P'), 'K7Q-M4P');
    expect(normPin(' k7q-m4p '), 'K7QM4P');
  });
}
