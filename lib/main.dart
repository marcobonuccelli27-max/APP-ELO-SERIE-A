// Elo Serie A: punto di partenza dell'app.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens.dart';
import 'slip_screen.dart';
import 'state.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  state.init();
  runApp(AppScope(state: state, child: const EloApp()));
}

class EloApp extends StatelessWidget {
  const EloApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: C.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    return MaterialApp(
      title: 'Elo Serie A',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: C.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: C.blue,
          primary: C.blue,
          surface: C.white,
          onSurface: C.ink,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x0F000000),
        textTheme: Typography.blackCupertino.apply(bodyColor: C.ink, displayColor: C.ink),
        cupertinoOverrideTheme: const CupertinoThemeData(primaryColor: C.blue),
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {

  static const _screens = [
    GiornataScreen(),
    ClassificaScreen(),
    SchedinaScreen(),
    VerificaScreen(),
    ImpostazioniScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: IndexedStack(index: app.tab, children: _screens),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: app.tab,
        onTap: app.goToTab,
        activeColor: C.blue,
        inactiveColor: C.grey,
        backgroundColor: const Color(0xF2F9F9F9),
        border: const Border(top: BorderSide(color: C.line, width: 0.5)),
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.calendar), label: 'Giornata'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar), label: 'Classifica'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.camera), label: 'Schedina'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.arrow_counterclockwise), label: 'Verifica'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.gear), label: 'Impostazioni'),
        ],
      ),
    );
  }
}
