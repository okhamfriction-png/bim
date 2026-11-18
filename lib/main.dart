import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens.dart';
import 'store.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
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
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: p.ink,
              textStyle: const TextStyle(fontWeight: FontWeight.w700))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: p.ink, side: BorderSide(color: p.line, width: 1.5))),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.card,
        indicatorColor: p.accent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink)),
      ),
    );

class BimApp extends StatelessWidget {
  const BimApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bim',
        debugShowCheckedModeBanner: false,
        theme: _theme(Pal.light, Brightness.light),
        darkTheme: _theme(Pal.dark, Brightness.dark),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: store.sync);
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
      listenable: store,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                          color: p.accent, borderRadius: BorderRadius.circular(10)),
                      child: Text('bim',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.5,
                              color: p.onAccent)),
                    ),
                    const Spacer(),
                    if (tab == 0)
                      IconButton(
                        tooltip: 'Nouvelle tâche',
                        onPressed: () => sheet(context, const TaskSheet()),
                        icon: Icon(Icons.add_circle, color: p.ink, size: 30),
                      ),
                    IconButton(
                      tooltip: 'Synchronisation',
                      onPressed: () => sheet(context, const SyncSheet()),
                      icon: Icon(
                          switch (store.syncState) {
                            'ok' => Icons.cloud_done_outlined,
                            'sync' => Icons.cloud_sync_outlined,
                            'error' => Icons.cloud_off_outlined,
                            _ => Icons.cloud_outlined,
                          },
                          color: store.syncState == 'error' ? prioColors[0] : p.sub),
                    ),
                  ]),
                ),
                Expanded(
                  child: IndexedStack(index: tab, children: [
                    // Non const : chaque écran se redessine quand le store change.
                    NowScreen(key: const ValueKey('now')),
                    BacklogScreen(key: const ValueKey('backlog')),
                    WeekScreen(key: const ValueKey('week')),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        floatingActionButton: tab != 1
            ? null
            : FloatingActionButton(
                tooltip: 'Nouvelle tâche',
                backgroundColor: p.ink,
                foregroundColor: p.bg,
                onPressed: () => sheet(context, const TaskSheet()),
                child: const Icon(Icons.add, size: 30),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.bolt_rounded), label: 'Maintenant'),
            NavigationDestination(icon: Icon(Icons.format_list_bulleted_rounded), label: 'Backlog'),
            NavigationDestination(icon: Icon(Icons.calendar_view_week_rounded), label: 'Semaine'),
          ],
        ),
      ),
    );
  }
}
