import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'consignes.dart';
import 'courses.dart';
import 'dictee.dart';
import 'kpi.dart';
import 'panier.dart';
import 'liaison.dart';
import 'liaison_code.dart';
import 'notes.dart';
import 'notes_screen.dart';
import 'screens.dart';
import 'store.dart';
import 'ui.dart';
import 'url_io.dart' if (dart.library.js_interop) 'url_web.dart';

/// Code de liaison reçu dans l'adresse (…/bim/#relier=bim1.…), lu avant que Flutter ne la touche.
String? _liaisonAtStart;

Future<void> main() async {
  _liaisonAtStart = findLiaison(Uri.base.fragment);
  if (_liaisonAtStart != null) clearUrlFragment();
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  await notes.load();
  await courses.load();
  consignes.start();
  runApp(const BimApp());
}

ThemeData _theme(Pal p, Brightness b) => ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: p.accent, brightness: b).copyWith(
        primary: p.accent,
        onPrimary: p.onAccent,
        surface: p.card,
        onSurface: p.ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.ink, width: 1.5)),
      ),
      // Le fond des feuilles suit le thème, même s'il change pendant qu'une feuille est ouverte.
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: p.card,
          modalBackgroundColor: p.card,
          surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      dialogTheme: DialogThemeData(
          backgroundColor: p.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      popupMenuTheme: PopupMenuThemeData(
          color: p.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.line))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: p.ink,
              textStyle: const TextStyle(fontWeight: FontWeight.w700))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: p.ink,
              side: BorderSide(color: p.line, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.card,
        indicatorColor: p.accent,
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
            color: st.contains(WidgetState.selected) ? p.onAccent : p.sub)),
        height: 66,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink)),
      ),
    );

class BimApp extends StatelessWidget {
  const BimApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Bim',
        themeMode: switch (store.themeMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          'auto' => store.darkNow ? ThemeMode.dark : ThemeMode.light,
          _ => ThemeMode.system,
        },
        debugShowCheckedModeBanner: false,
        theme: _theme(Pal.light, Brightness.light),
        darkTheme: _theme(Pal.dark, Brightness.dark),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Shell(),
      ));
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  bool refreshing = false; // le logo synchronise puis recharge
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // Ouvert depuis un lien de liaison (…/bim/#relier=bim1.…) : on demande le code court.
    final code = _liaisonAtStart;
    _liaisonAtStart = null;
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) sheet(context, ReceiveLinkSheet(code: code));
      });
    }
    // Ouvert par l'icône « Bim dictée » : le micro s'ouvre tout de suite.
    DictationLaunch.listen(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openDictation(context);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    _life = AppLifecycleListener(onResume: () {
      store.loadWidgetConfig();
      store.sync();
      notes.sync();
      courses.sync();
      consignes.refresh();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, notes, consignes]),
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Stack(children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
                  child: Row(children: [
                    // Le logo rafraîchit tout : synchro, puis rechargement de la page sur le web.
                    Tooltip(
                      message: 'Rafraîchir Bim',
                      child: GestureDetector(
                        onTap: refreshing
                            ? null
                            : () async {
                                HapticFeedback.mediumImpact();
                                setState(() => refreshing = true);
                                try {
                                  await store.sync();
                                } catch (_) {}
                                reloadPage();
                                if (mounted) setState(() => refreshing = false);
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                              color: p.accent, borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('bim',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -.5,
                                    color: p.onAccent)),
                            const SizedBox(width: 6),
                            refreshing
                                ? SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.4, color: p.onAccent))
                                : Icon(Icons.refresh_rounded, size: 18, color: p.onAccent),
                          ]),
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Dicter une note, une tâche, des courses',
                      onPressed: () => openDictation(context),
                      icon: Icon(Icons.mic_rounded, color: p.ink),
                    ),
                    IconButton(
                      tooltip: 'Tableau de bord',
                      onPressed: () => openKpi(context),
                      icon: Icon(Icons.insights_rounded, color: p.sub),
                    ),
                    if (consignes.all.isNotEmpty)
                      IconButton(
                        tooltip: 'Consignes à l\'agent',
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const ConsignesPage())),
                        icon: Icon(Icons.smart_toy_rounded, color: p.sub),
                      ),
                    if (tab == 3 && notes.unlocked)
                      IconButton(
                        tooltip: 'Nouvelle note',
                        onPressed: () => sheet(context, const NoteSheet()),
                        icon: Icon(Icons.add_circle, color: p.ink, size: 30),
                      ),
                    if (tab == 0)
                      IconButton(
                        tooltip: 'Nouvelle tâche',
                        onPressed: () => sheet(context, const TaskSheet()),
                        icon: Icon(Icons.add_circle, color: p.ink, size: 30),
                      ),
                    IconButton(
                      tooltip: 'Réglages',
                      onPressed: () => sheet(context, const SyncSheet()),
                      icon: Icon(Icons.settings_rounded,
                          color: store.syncState == 'error' ? prioColors[0] : p.sub),
                    ),
                  ]),
                ),
                const ConsignesBanner(),
                Expanded(
                  child: IndexedStack(index: tab, children: [
                    // Non const : chaque écran se redessine quand le store change.
                    NowScreen(key: const ValueKey('now')),
                    BacklogScreen(key: const ValueKey('backlog')),
                    AgendaScreen(key: const ValueKey('agenda')),
                    NotesScreen(key: const ValueKey('notes')),
                  ]),
                ),
              ]),
            ),
          ),
          const Positioned.fill(child: PanierOverlay()),
          ]),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
          child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.bolt_rounded), label: 'Maintenant'),
            NavigationDestination(icon: Icon(Icons.format_list_bulleted_rounded), label: 'Backlog'),
            NavigationDestination(icon: Icon(Icons.calendar_month_rounded), label: 'Agenda'),
            NavigationDestination(icon: Icon(Icons.sticky_note_2_rounded), label: 'Notes'),
          ],
        )),
      ),
    );
  }
}
