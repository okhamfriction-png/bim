import 'package:bim/dictee.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le premier mot décide de la destination', () {
    expect(routeDictation('note code du local vélo 4821'), ('note', 'Code du local vélo 4821'));
    expect(routeDictation('Tâche rappeler le plombier'), ('tache', 'Rappeler le plombier'));
    expect(routeDictation('courses pain de mie et verveine'), ('courses', 'Pain de mie et verveine'));
    expect(routeDictation('liste de courses eau'), ('courses', 'Eau'));
    expect(routeDictation('rappel appeler Karim'), ('tache', 'Appeler Karim'));
    expect(routeDictation('penser à la carte grise'), ('note', 'Penser à la carte grise'));
    // « notebook » n'est pas le mot-clé « note ».
    expect(routeDictation('notebook à acheter'), ('note', 'Notebook à acheter'));
    expect(routeDictation('note'), ('note', ''));
  });
  test('les articles se séparent', () {
    expect(splitArticles('pain, lait et œufs'), ['Pain', 'Lait', 'Œufs']);
    expect(splitArticles('pain de mie'), ['Pain de mie']);
  });
}
