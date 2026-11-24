import 'package:bim/rappels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Mardi 24 novembre 2026, 15 h.
  final now = DateTime(2026, 11, 24, 15);
  (String, String?, int?) p(String s) {
    final r = parseReminder(s, now);
    return (r.text, r.day?.toIso8601String().substring(0, 10), r.minutes);
  }

  test('le jour et l\'heure sortent de la phrase', () {
    expect(p('préparer la tablette destiny apk dimanche 11h'),
        ('Préparer la tablette destiny apk', '2026-11-29', 660));
    expect(p('appeler Karim demain à 9 h 30'), ('Appeler Karim', '2026-11-25', 570));
    expect(p('sortir les poubelles ce soir'), ('Sortir les poubelles', '2026-11-24', 1200));
    expect(p('stage impro le 5 décembre à 14 heures'), ('Stage impro', '2026-12-05', 840));
    expect(p('payer la cantine le 3'), ('Payer la cantine', '2026-12-03', null));
    expect(p('rendez-vous 12/01 à 8:15'), ('Rendez-vous', '2027-01-12', 495));
    expect(p('après-demain midi déjeuner avec Sam'), ('Déjeuner avec Sam', '2026-11-26', 720));
    expect(p('d\'acheter du pain'), ('Acheter du pain', null, null));
  });
  test('un jour de la semaine déjà passé aujourd\'hui part à la semaine suivante', () {
    expect(p('réviser mardi 10h'), ('Réviser', '2026-12-01', 600));
    expect(p('réviser mardi 18h'), ('Réviser', '2026-11-24', 1080));
    expect(p('réviser mardi prochain'), ('Réviser', '2026-12-01', null));
  });
  test('les chiffres qui ne sont pas une heure restent dans le texte', () {
    expect(p('acheter 2 housses'), ('Acheter 2 housses', null, null));
    expect(p('relire le chapitre 12'), ('Relire le chapitre 12', null, null));
  });
}
