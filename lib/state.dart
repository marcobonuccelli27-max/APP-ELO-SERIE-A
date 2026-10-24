// Stato dell'app: impostazioni, previsioni e azioni (aggiorna, verifica).

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'elo.dart';

class Settings {
  String provider; // 'fd' = football-data.co.uk, 'oddsapi' = The Odds API
  String apiKey;
  double budget;
  double stakePct;
  double threshold;
  bool autoCalib;
  double k;
  double home;
  double regress;
  Set<String> excludedBooks;

  Settings({
    this.provider = 'fd',
    this.apiKey = '',
    this.budget = 200,
    this.stakePct = 2,
    this.threshold = 1.05,
    this.autoCalib = true,
    this.k = 20,
    this.home = 70,
    this.regress = 0.25,
    Set<String>? excludedBooks,
  }) : excludedBooks = excludedBooks ?? {'Pinnacle', '1xBet', 'Matchbook'};

  double get stake => budget * stakePct / 100;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'apiKey': apiKey,
        'budget': budget,
        'stakePct': stakePct,
        'threshold': threshold,
        'autoCalib': autoCalib,
        'k': k,
        'home': home,
        'regress': regress,
        'excludedBooks': excludedBooks.toList(),
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    double n(String key, double def) => (j[key] as num?)?.toDouble() ?? def;
    return Settings(
      provider: j['provider'] as String? ?? 'fd',
      apiKey: j['apiKey'] as String? ?? '',
      budget: n('budget', 200),
      stakePct: n('stakePct', 2),
      threshold: n('threshold', 1.05),
      autoCalib: j['autoCalib'] as bool? ?? true,
      k: n('k', 20),
      home: n('home', 70),
      regress: n('regress', 0.25),
      excludedBooks: (j['excludedBooks'] as List<dynamic>?)?.map((e) => e as String).toSet(),
    );
  }
}

class BestOdds {
  final List<double> odds;
  final List<String> books;
  BestOdds(this.odds, this.books);
}

class Evaluation {
  final int pick; // 0 = 1, 1 = X, 2 = 2
  final double ev; // valore della scelta migliore
  final List<double> evs;
  final bool hasValue;
  Evaluation(this.pick, this.ev, this.evs, this.hasValue);
}

class Prediction {
  final String home;
  final String away;
  final DateTime? date;
  final double eloH;
  final double eloA;
  final List<double> p;
  final Map<String, List<double>> books;
  final bool unknownTeam;

  Prediction({
    required this.home,
    required this.away,
    required this.date,
    required this.eloH,
    required this.eloA,
    required this.p,
    required this.books,
    required this.unknownTeam,
  });

  /// Quota migliore per ogni esito tra i bookmaker scelti.
  BestOdds? best(Set<String> excluded) {
    final odds = [0.0, 0.0, 0.0];
    final names = ['', '', ''];
    books.forEach((name, o) {
      if (excluded.contains(name)) return;
      for (var k = 0; k < 3; k++) {
        if (o[k] > odds[k]) {
          odds[k] = o[k];
          names[k] = name;
        }
      }
    });
    if (odds.any((o) => o <= 1)) return null;
    return BestOdds(odds, names);
  }

  Evaluation? evaluate(Settings s) {
    final b = best(s.excludedBooks);
    if (b == null) return null;
    final evs = List<double>.generate(3, (k) => p[k] * b.odds[k]);
    var pick = 0;
    for (var k = 1; k < 3; k++) {
      if (evs[k] > evs[pick]) pick = k;
    }
    return Evaluation(pick, evs[pick], evs, evs[pick] >= s.threshold && !unknownTeam);
  }

  Map<String, dynamic> toJson() => {
        'home': home,
        'away': away,
        'date': date?.toIso8601String(),
        'eloH': eloH,
        'eloA': eloA,
        'p': p,
        'books': books,
        'unknown': unknownTeam,
      };

  factory Prediction.fromJson(Map<String, dynamic> j) => Prediction(
        home: j['home'] as String,
        away: j['away'] as String,
        date: j['date'] == null ? null : DateTime.tryParse(j['date'] as String),
        eloH: (j['eloH'] as num).toDouble(),
        eloA: (j['eloA'] as num).toDouble(),
        p: (j['p'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        books: (j['books'] as Map<String, dynamic>).map((k, v) =>
            MapEntry(k, (v as List<dynamic>).map((e) => (e as num).toDouble()).toList())),
        unknownTeam: j['unknown'] as bool? ?? false,
      );
}

class TeamRow {
  final String name;
  final double rating;
  final double delta;
  final List<String> form;
  TeamRow(this.name, this.rating, this.delta, this.form);

  Map<String, dynamic> toJson() => {'n': name, 'r': rating, 'd': delta, 'f': form};

  factory TeamRow.fromJson(Map<String, dynamic> j) => TeamRow(
        j['n'] as String,
        (j['r'] as num).toDouble(),
        (j['d'] as num).toDouble(),
        (j['f'] as List<dynamic>).map((e) => e as String).toList(),
      );
}

class AppState extends ChangeNotifier {
  final repo = DataRepo();
  Settings settings = Settings();

  List<Prediction> predictions = [];
  List<TeamRow> table = [];
  Set<String> booksSeen = {};
  DateTime? lastUpdate;
  int? requestsRemaining;
  int? tableSeason;
  EloParams? calibrated;
  int? calibratedSeason;

  bool busy = false;
  String progress = '';
  String? error;
  String? oddsError;

  List<MatchResult>? _history;

  EloParams get paramsInUse => settings.autoCalib
      ? (calibrated ?? EloParams.standard)
      : EloParams(settings.k, settings.home, settings.regress);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('settings');
      if (raw != null) settings = Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    final snap = await repo.loadSnapshot();
    if (snap != null) {
      try {
        predictions = (snap['predictions'] as List<dynamic>)
            .map((e) => Prediction.fromJson(e as Map<String, dynamic>))
            .toList();
        table = (snap['table'] as List<dynamic>)
            .map((e) => TeamRow.fromJson(e as Map<String, dynamic>))
            .toList();
        booksSeen = (snap['books'] as List<dynamic>).map((e) => e as String).toSet();
        lastUpdate = snap['lastUpdate'] == null ? null : DateTime.tryParse(snap['lastUpdate'] as String);
        requestsRemaining = snap['remaining'] as int?;
        tableSeason = snap['tableSeason'] as int?;
        if (snap['calibrated'] != null) {
          calibrated = EloParams.fromJson(snap['calibrated'] as Map<String, dynamic>);
        }
        calibratedSeason = snap['calibratedSeason'] as int?;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveSettings() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(settings.toJson()));
  }

  Future<void> _saveSnapshot() => repo.saveSnapshot({
        'predictions': predictions.map((p) => p.toJson()).toList(),
        'table': table.map((t) => t.toJson()).toList(),
        'books': booksSeen.toList(),
        'lastUpdate': lastUpdate?.toIso8601String(),
        'remaining': requestsRemaining,
        'tableSeason': tableSeason,
        'calibrated': calibrated?.toJson(),
        'calibratedSeason': calibratedSeason,
      });

  void _progress(String t) {
    progress = t;
    notifyListeners();
  }

  /// Scarica risultati e quote, aggiorna l'Elo e ricalcola le previsioni.
  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    error = null;
    oddsError = null;
    _progress('Scarico i risultati…');
    try {
      final cur = currentSeasonStart(DateTime.now());
      final history = await repo.loadHistory(currentSeason: cur, onProgress: _progress);
      _history = history;

      if (settings.autoCalib && (calibrated == null || calibratedSeason != cur)) {
        _progress('Calibro il modello sulle stagioni passate…');
        calibrated = await _calibrateInBackground(history);
        calibratedSeason = cur;
      }

      _progress('Calcolo i punteggi Elo…');
      final params = paramsInUse;
      final live = await _buildLiveInBackground(history, params, cur);

      table = live.seasonTeams
          .map((t) => TeamRow(t, live.ratings[t]!, live.lastDelta[t] ?? 0, live.form[t] ?? const []))
          .toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
      tableSeason = cur > live.dataSeason ? live.dataSeason : cur;

      _progress('Scarico le quote…');
      try {
        final fetch = settings.provider == 'oddsapi'
            ? await repo.fetchOddsApi(settings.apiKey)
            : await repo.fetchFdFixtures();
        if (fetch.remaining != null) requestsRemaining = fetch.remaining;
        final known = live.ratings.keys.toList();
        final now = DateTime.now().subtract(const Duration(hours: 2));
        final preds = <Prediction>[];
        for (final f in fetch.fixtures) {
          if (f.date != null && f.date!.isBefore(now)) continue;
          final hName = matchTeam(f.home, known);
          final aName = matchTeam(f.away, known);
          final eh = hName != null ? live.ratings[hName]! : live.baseline;
          final ea = aName != null ? live.ratings[aName]! : live.baseline;
          booksSeen.addAll(f.books.keys);
          preds.add(Prediction(
            home: hName ?? f.home,
            away: aName ?? f.away,
            date: f.date,
            eloH: eh,
            eloA: ea,
            p: live.draw.probs(eh + params.home - ea),
            books: f.books,
            unknownTeam: hName == null || aName == null,
          ));
        }
        preds.sort((a, b) => (a.date ?? DateTime(2100)).compareTo(b.date ?? DateTime(2100)));
        predictions = preds;
        if (preds.isEmpty) {
          oddsError = 'Nessuna partita in arrivo con quote disponibili. '
              'Di solito le quote compaiono qualche giorno prima della giornata.';
        }
      } catch (e) {
        oddsError = e.toString();
      }

      lastUpdate = DateTime.now();
      await _saveSnapshot();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      progress = '';
      notifyListeners();
    }
  }

  /// Rifà la calibrazione e ricalcola tutto.
  Future<void> recalibrate() async {
    calibrated = null;
    calibratedSeason = null;
    await refresh();
  }

  Future<BacktestResult> runBacktest(int seasons, double threshold) async {
    final cur = currentSeasonStart(DateTime.now());
    var h = _history;
    if (h == null) {
      try {
        h = await repo.loadHistory(currentSeason: cur, onProgress: (_) {}, offline: true);
      } catch (_) {
        h = await repo.loadHistory(currentSeason: cur, onProgress: (_) {});
      }
      _history = h;
    }
    return _backtestInBackground(h!, seasons, threshold, settings.stake, settings.budget);
  }
}

// I calcoli pesanti girano in un isolate separato, così l'app resta fluida.
// Sono funzioni di primo livello perché l'isolate riceva solo i dati necessari.

Future<EloParams> _calibrateInBackground(List<MatchResult> h) =>
    Isolate.run(() => calibrate(h));

Future<LiveModel> _buildLiveInBackground(List<MatchResult> h, EloParams p, int cur) =>
    Isolate.run(() => buildLive(h, p, cur));

Future<BacktestResult> _backtestInBackground(
        List<MatchResult> h, int seasons, double thr, double stake, double budget) =>
    Isolate.run(() => backtest(h, seasons, thr, stake, budget));

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
