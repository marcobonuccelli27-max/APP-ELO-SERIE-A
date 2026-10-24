// Stato dell'app: impostazioni, previsioni e azioni (aggiorna, verifica, classifiche).

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'dc.dart';
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
  int calibFrom; // prima stagione usata per calibrare
  int calibTo; // ultima stagione usata per calibrare; 0 = l'ultima completa
  String model; // 'elo' oppure 'dc' (Dixon-Coles)
  double dcHalfLife; // emivita manuale per Dixon-Coles, in giorni
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
    this.calibFrom = firstSeason,
    this.calibTo = 0,
    this.model = 'elo',
    this.dcHalfLife = dcDefaultHalfLife,
    Set<String>? excludedBooks,
  }) : excludedBooks = excludedBooks ?? {'Pinnacle', '1xBet', 'Matchbook'};

  double get stake => budget * stakePct / 100;

  EloParams get manualParams => EloParams(k, home, regress);

  /// Ultima stagione di calibrazione effettiva.
  int calibToFor(int currentSeason) => calibTo == 0 ? currentSeason - 1 : calibTo;

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
        'calibFrom': calibFrom,
        'calibTo': calibTo,
        'model': model,
        'dcHalfLife': dcHalfLife,
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
      calibFrom: j['calibFrom'] as int? ?? firstSeason,
      calibTo: j['calibTo'] as int? ?? 0,
      model: j['model'] as String? ?? 'elo',
      dcHalfLife: n('dcHalfLife', dcDefaultHalfLife),
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
  final bool overThreshold; // il valore supera la soglia
  final bool leastLikely; // la scelta è l'esito meno probabile
  final bool hasValue; // giocata consigliata
  Evaluation(this.pick, this.ev, this.evs, this.overThreshold, this.leastLikely, this.hasValue);
}

class OuEvaluation {
  final int side; // 0 = over 2,5, 1 = under 2,5
  final double prob;
  final double odds;
  final String book;
  final double ev;
  final bool overThreshold;
  final bool minority; // probabilità sotto il 50%: l'esito meno probabile
  bool get hasValue => overThreshold && !minority;
  OuEvaluation(this.side, this.prob, this.odds, this.book, this.ev, this.overThreshold, this.minority);
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
  final String model; // modello che ha prodotto le probabilità
  final double? over25; // solo Dixon-Coles
  final double? gg; // solo Dixon-Coles
  final double? xgHome; // gol attesi (solo Dixon-Coles)
  final double? xgAway;
  final Map<String, List<double>> ouBooks;

  Prediction({
    this.model = 'elo',
    this.over25,
    this.gg,
    this.xgHome,
    this.xgAway,
    Map<String, List<double>>? ouBooks,
    required this.home,
    required this.away,
    required this.date,
    required this.eloH,
    required this.eloA,
    required this.p,
    required this.books,
    required this.unknownTeam,
  }) : ouBooks = ouBooks ?? {};

  /// Over/under 2,5: il lato con più valore tra i bookmaker scelti.
  OuEvaluation? evaluateOu(Settings s) {
    final o = over25;
    if (o == null) return null;
    final probs = [o, 1 - o];
    final best = [0.0, 0.0];
    final names = ['', ''];
    ouBooks.forEach((name, q) {
      if (s.excludedBooks.contains(name)) return;
      for (var k = 0; k < 2; k++) {
        if (q[k] > best[k]) {
          best[k] = q[k];
          names[k] = name;
        }
      }
    });
    if (best[0] <= 1 || best[1] <= 1) return null;
    final side = probs[0] * best[0] >= probs[1] * best[1] ? 0 : 1;
    final ev = probs[side] * best[side];
    return OuEvaluation(side, probs[side], best[side], names[side], ev, ev >= s.threshold && !unknownTeam,
        probs[side] < 0.5);
  }

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
    final over = evs[pick] >= s.threshold;
    final least = isLeastLikely(p, pick);
    return Evaluation(pick, evs[pick], evs, over, least, over && !least && !unknownTeam);
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
        'model': model,
        'over25': over25,
        'gg': gg,
        'xgH': xgHome,
        'xgA': xgAway,
        'ou': ouBooks,
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
        model: j['model'] as String? ?? 'elo',
        over25: (j['over25'] as num?)?.toDouble(),
        gg: (j['gg'] as num?)?.toDouble(),
        xgHome: (j['xgH'] as num?)?.toDouble(),
        xgAway: (j['xgA'] as num?)?.toDouble(),
        ouBooks: (j['ou'] as Map<String, dynamic>?)?.map((k, v) =>
            MapEntry(k, (v as List<dynamic>).map((e) => (e as num).toDouble()).toList())),
      );
}

/// Una riga della classifica Elo di una stagione.
class TeamRow {
  final String name;
  final double rating; // punteggio attuale o di fine stagione
  final double change; // variazione dall'inizio della stagione
  final List<String> form; // ultime 5: V, N, P
  TeamRow(this.name, this.rating, this.change, this.form);
}

/// Tutto quello che serve alla schermata Classifiche per una stagione.
/// Attacco e difesa di una squadra secondo Dixon-Coles.
class DcTeamRow {
  final String name;
  final double goalsFor; // gol segnati a partita contro una squadra media
  final double goalsAgainst; // gol subiti a partita contro una squadra media
  DcTeamRow(this.name, this.goalsFor, this.goalsAgainst);
}

class SeasonView {
  final int season;
  final List<TeamRow> elo;
  final List<StandingRow> table;
  final Map<String, TeamSeries> series;
  final EloParams params;
  final List<DcTeamRow> dc;
  final double halfLife;
  SeasonView(this.season, this.elo, this.table, this.series, this.params, this.dc, this.halfLife);
}

class AppState extends ChangeNotifier {
  final repo = DataRepo();
  Settings settings = Settings();

  List<Prediction> predictions = [];
  Set<String> booksSeen = {};
  DateTime? lastUpdate;
  int? requestsRemaining;
  int? requestsUsed;
  DateTime? requestsCheckedAt;
  EloParams? calibrated;
  String? calibratedKey;
  double? calibratedHl;
  String? calibratedHlKey;

  bool busy = false;
  String progress = '';
  String? error;
  String? oddsError;

  List<MatchResult>? _history;
  int _historyVersion = 0;
  EloHistoryData? _eloHistory;
  String? _eloHistoryKey;
  final Map<int, Future<SeasonView>> _views = {};

  int get currentSeason => currentSeasonStart(DateTime.now());

  String _calibKey(int cur) => '${settings.calibFrom}-${settings.calibToFor(cur)}-$cur';

  EloParams get paramsInUse =>
      settings.autoCalib ? (calibrated ?? EloParams.standard) : settings.manualParams;

  /// Emivita di Dixon-Coles in uso, in giorni.
  double get halfLifeInUse =>
      settings.autoCalib ? (calibratedHl ?? dcDefaultHalfLife) : settings.dcHalfLife;

  /// Stagioni presenti nei dati scaricati, dalla più recente.
  List<int> get seasonsAvailable {
    final h = _history;
    if (h == null) return [];
    return (h.map((m) => m.season).toSet().toList()..sort()).reversed.toList();
  }

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
        booksSeen = (snap['books'] as List<dynamic>).map((e) => e as String).toSet();
        lastUpdate = snap['lastUpdate'] == null ? null : DateTime.tryParse(snap['lastUpdate'] as String);
        requestsRemaining = snap['remaining'] as int?;
        requestsUsed = snap['used'] as int?;
        requestsCheckedAt =
            snap['checkedAt'] == null ? null : DateTime.tryParse(snap['checkedAt'] as String);
        if (snap['calibrated'] != null) {
          calibrated = EloParams.fromJson(snap['calibrated'] as Map<String, dynamic>);
        }
        calibratedKey = snap['calibratedKey'] as String?;
        calibratedHl = (snap['calibratedHl'] as num?)?.toDouble();
        calibratedHlKey = snap['calibratedHlKey'] as String?;
      } catch (_) {}
    }
    try {
      _setHistory(await repo.loadHistory(currentSeason: currentSeason, onProgress: (_) {}, offline: true));
    } catch (_) {}
    notifyListeners();
  }

  void _setHistory(List<MatchResult> h) {
    _history = h;
    _historyVersion++;
    _views.clear();
  }

  Future<void> saveSettings() async {
    _views.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(settings.toJson()));
  }

  Future<void> _saveSnapshot() => repo.saveSnapshot({
        'predictions': predictions.map((p) => p.toJson()).toList(),
        'books': booksSeen.toList(),
        'lastUpdate': lastUpdate?.toIso8601String(),
        'remaining': requestsRemaining,
        'used': requestsUsed,
        'checkedAt': requestsCheckedAt?.toIso8601String(),
        'calibrated': calibrated?.toJson(),
        'calibratedKey': calibratedKey,
        'calibratedHl': calibratedHl,
        'calibratedHlKey': calibratedHlKey,
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
      final cur = currentSeason;
      final history = await repo.loadHistory(currentSeason: cur, onProgress: _progress);
      _setHistory(history);
      final from = settings.calibFrom;
      final to = settings.calibToFor(cur);

      if (settings.autoCalib && (calibrated == null || calibratedKey != _calibKey(cur))) {
        _progress('Calibro il modello sulle stagioni scelte…');
        calibrated = await _calibrateInBackground(history, from, to);
        calibratedKey = _calibKey(cur);
      }

      _progress('Calcolo i punteggi Elo…');
      final params = paramsInUse;
      final live = await _buildLiveInBackground(history, params, cur, from, to);
      DcFit? dcFit;
      if (settings.model == 'dc') {
        if (settings.autoCalib && (calibratedHl == null || calibratedHlKey != _calibKey(cur))) {
          _progress('Calibro Dixon-Coles: può richiedere qualche decina di secondi…');
          calibratedHl = await _calibrateDcInBackground(history, from, to);
          calibratedHlKey = _calibKey(cur);
        }
        _progress('Stimo attacco e difesa delle squadre…');
        dcFit = await _fitDcInBackground(history, halfLifeInUse, null);
      }
      _views.clear();

      _progress('Scarico le quote…');
      try {
        final fetch = settings.provider == 'oddsapi'
            ? await repo.fetchOddsApi(settings.apiKey)
            : await repo.fetchFdFixtures();
        if (fetch.remaining != null) {
          requestsRemaining = fetch.remaining;
          requestsUsed = fetch.used;
          requestsCheckedAt = DateTime.now();
        }
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
          booksSeen.addAll(f.ouBooks.keys);
          final dcP = dcFit?.predict(hName ?? f.home, aName ?? f.away);
          preds.add(Prediction(
            home: hName ?? f.home,
            away: aName ?? f.away,
            date: f.date,
            eloH: eh,
            eloA: ea,
            p: dcP?.p ?? live.draw.probs(eh + params.home - ea),
            books: f.books,
            unknownTeam: hName == null || aName == null,
            model: dcP == null ? 'elo' : 'dc',
            over25: dcP?.over25,
            gg: dcP?.gg,
            xgHome: dcP?.lambda,
            xgAway: dcP?.mu,
            ouBooks: f.ouBooks,
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
    calibratedKey = null;
    calibratedHl = null;
    calibratedHlKey = null;
    await refresh();
  }

  Future<List<MatchResult>> _ensureHistory() async {
    final h = _history;
    if (h != null) return h;
    List<MatchResult> loaded;
    try {
      loaded = await repo.loadHistory(currentSeason: currentSeason, onProgress: (_) {}, offline: true);
    } catch (_) {
      loaded = await repo.loadHistory(currentSeason: currentSeason, onProgress: (_) {});
    }
    _setHistory(loaded);
    return loaded;
  }

  Future<BacktestResult> runBacktest(int seasons, double threshold, String model) async {
    final h = await _ensureHistory();
    final args = BacktestArgs(
      model: model,
      fixedHalfLife: settings.autoCalib ? null : settings.dcHalfLife,
      testSeasons: seasons,
      threshold: threshold,
      stake: settings.stake,
      budget: settings.budget,
      fixed: settings.autoCalib ? null : settings.manualParams,
      calibFrom: settings.calibFrom,
      calibTo: settings.calibToFor(currentSeason),
    );
    return _backtestInBackground(h, args);
  }

  /// Classifica Elo, classifica Serie A e andamenti di una stagione.
  /// Il risultato resta in memoria finché non cambiano dati o parametri.
  Future<SeasonView> seasonView(int season) => _views.putIfAbsent(season, () => _makeView(season));

  Future<SeasonView> _makeView(int season) async {
    final h = await _ensureHistory();
    final params = paramsInUse;
    final key = '${params.key}#$_historyVersion';
    var hist = _eloHistory;
    if (hist == null || _eloHistoryKey != key) {
      hist = await _historyInBackground(h, params);
      _eloHistory = hist;
      _eloHistoryKey = key;
    }
    final table = standings(h, season);
    final rows = <TeamRow>[];
    for (final st in table) {
      final s = hist.series[st.team];
      if (s == null) continue;
      final vals = s.seasonValues(season);
      if (vals.isEmpty) continue;
      final form = st.form.length > 5 ? st.form.sublist(st.form.length - 5) : st.form;
      rows.add(TeamRow(st.team, vals.last, vals.last - vals.first, form));
    }
    rows.sort((a, b) => b.rating.compareTo(a.rating));
    final hl = halfLifeInUse;
    final fit = await _fitDcInBackground(h, hl, season);
    final dcRows = [
      for (final st in table)
        if (fit.knows(st.team)) DcTeamRow(st.team, fit.goalsFor(st.team), fit.goalsAgainst(st.team))
    ]..sort((a, b) => (b.goalsFor - b.goalsAgainst).compareTo(a.goalsFor - a.goalsAgainst));
    return SeasonView(season, rows, table, hist.series, params, dcRows, hl);
  }
}

// I calcoli pesanti girano in un isolate separato, così l'app resta fluida.
// Sono funzioni di primo livello perché l'isolate riceva solo i dati necessari.

Future<EloParams> _calibrateInBackground(List<MatchResult> h, int from, int to) =>
    Isolate.run(() => calibrate(h, from: from, to: to));

Future<LiveModel> _buildLiveInBackground(
        List<MatchResult> h, EloParams p, int cur, int from, int to) =>
    Isolate.run(() => buildLive(h, p, cur, drawFrom: from, drawTo: to));

Future<BacktestResult> _backtestInBackground(List<MatchResult> h, BacktestArgs args) =>
    Isolate.run(() => backtest(h, args));

Future<double> _calibrateDcInBackground(List<MatchResult> h, int from, int to) =>
    Isolate.run(() => calibrateDc(h, from: from, to: to));

Future<DcFit> _fitDcInBackground(List<MatchResult> h, double hl, int? untilSeason) =>
    Isolate.run(() => fitDcNow(h, hl, untilSeason: untilSeason));

Future<EloHistoryData> _historyInBackground(List<MatchResult> h, EloParams p) =>
    Isolate.run(() => buildHistory(h, p));

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
