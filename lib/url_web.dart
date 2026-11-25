import 'package:web/web.dart' as web;

/// Retire le fragment (#relier=…) de l'adresse affichée, sans recharger la page.
/// L'état d'historique est gardé tel quel : Flutter y range le sien.
void clearUrlFragment() {
  final h = web.window.history, l = web.window.location;
  h.replaceState(h.state, '', '${l.pathname}${l.search}');
}

/// Recharge toute la page (bouton du logo).
void reloadPage() => web.window.location.reload();
