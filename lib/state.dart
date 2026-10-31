// Stato dell'app: impostazioni, previsioni e azioni (aggiorna, verifica, classifiche).

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'dc.dart';
import 'elo.dart';
import 'slip.dart';

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
  double early; // aumento di K a inizio stagione (1 = doppio)
  bool curved; // discesa di K curva invece che lineare
  int calibFrom; // prima stagione usata per calibrare
  int calibTo; // ultima stagione usata per calibrare; 0 = l'ultima completa
  String model; // 'elo' oppure 'dc' (Dixon-Coles)
  double marketWeight; // peso delle quote nelle probabilità: 0 = solo modello
  double recentHalf; // peso delle stagioni recenti in calibrazione (emivita in stagioni, 0 = uguale)
  double dcHalfLife; // emivita manuale per Dixon-Coles, in giorni
  Set<String> excludedBooks;
  bool introSeen; // scheda di benvenuto già vista
  Map<String, double> testedLl; // errore delle verifiche: "modello@stagioni" -> log loss

  Settings({
    this.introSeen = false,
    Map<String, double>? testedLl,
    this.provider = 'fd',
    this.apiKey = '',
    this.budget = 200,
    this.stakePct = 2,
    this.threshold = 1.05,
    this.autoCalib = true,
    this.k = 20,
    this.home = 70,
    this.regress = 0.25,
    this.early = 0.5,
    this.curved = false,
    this.calibFrom = firstSeason,
    this.calibTo = 0,
    this.model = 'elo',
    this.marketWeight = 0,
    this.recentHalf = 5,
    this.dcHalfLife = dcDefaultHalfLife,
    Set<String>? excludedBooks,
  })  : excludedBooks = excludedBooks ?? {'Pinnacle', '1xBet', 'Matchbook'},
        testedLl = testedLl ?? {};

  double get stake => budget * stakePct / 100;

  EloParams get manualParams => EloParams(k, home, regress, early, curved);

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
        'early': early,
        'curved': curved,
        'calibFrom': calibFrom,
        'calibTo': calibTo,
        'model': model,
        'marketWeight': marketWeight,
        'recentHalf': recentHalf,
        'dcHalfLife': dcHalfLife,
        'excludedBooks': excludedBooks.toList(),
        'introSeen': introSeen,
        'testedLl': testedLl,
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
      early: n('early', 0.5),
      curved: j['curved'] as bool? ?? false,
      calibFrom: j['calibFrom'] as int? ?? firstSeason,
      calibTo: j['calibTo'] as int? ?? 0,
      model: j['model'] as String? ?? 'elo',
      marketWeight: n('marketWeight', 0),
      recentHalf: n('recentHalf', 5),
      dcHalfLife: n('dcHalfLife', dcDefaultHalfLife),
      excludedBooks: (j['excludedBooks'] as List<dynamic>?)?.map((e) => e as String).toSet(),
      introSeen: j['introSeen'] as bool? ?? false,
      testedLl: (j['testedLl'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

/// Valori consigliati per un uso corretto dell'app.
class Recommended {
  static const calibFrom = 2012;
  static const model = 'dc';
  static const marketWeight = 0.5;
  static const threshold = 1.05;
  static const stakePct = 2.0;
  static const recentHalf = 5.0;
  static const nonAdm = ['Pinnacle', '1xBet', 'Matchbook'];
}

enum AdviceLevel { warning, tip }

/// Un consiglio sulle impostazioni, con l'eventuale correzione.
class Advice {
  final String title;
  final String text;
  final AdviceLevel level;
  final String? actionLabel;
  final void Function()? action;
  Advice(this.title, this.text, this.level, [this.actionLabel, this.action]);
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
  final List<double> used; // probabilità usate: modello, eventualmente mescolato con il mercato
  final List<double> market; // probabilità delle quote migliori, senza margine
  Evaluation(this.pick, this.ev, this.evs, this.overThreshold, this.leastLikely, this.hasValue, this.used,
      this.market);
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
  final int? hg; // risultato, se la partita è già stata giocata
  final int? ag;

  bool get played => hg != null && ag != null;

  Prediction({
    this.hg,
    this.ag,
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
    if (s.marketWeight > 0) {
      final fair = fairProbs(best);
      for (var k = 0; k < 2; k++) {
        probs[k] = (1 - s.marketWeight) * probs[k] + s.marketWeight * fair[k];
      }
    }
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
    final market = fairProbs(b.odds);
    final used = s.marketWeight > 0 ? blendProbs(p, market, s.marketWeight) : p;
    final evs = List<double>.generate(3, (k) => used[k] * b.odds[k]);
    var pick = 0;
    for (var k = 1; k < 3; k++) {
      if (evs[k] > evs[pick]) pick = k;
    }
    final over = evs[pick] >= s.threshold;
    final least = isLeastLikely(used, pick);
    return Evaluation(pick, evs[pick], evs, over, least, over && !least && !unknownTeam, used, market);
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
/// Una giornata di campionato.
class RoundInfo {
  final String label; // "9ª giornata" oppure "Recuperi"
  final List<Prediction> matches;
  RoundInfo(this.label, this.matches);

  bool get allPlayed => matches.every((m) => m.played);
  bool get anyUpcoming => matches.any((m) => !m.played);
}

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

  List<SavedSlip> savedSlips = [];

  List<MatchResult>? _history;
  int _historyVersion = 0;
  Map<String, List<MatchResult>> _byTeams = {};
  EloHistoryData? _eloHistory;
  String? _eloHistoryKey;
  final Map<int, Future<SeasonView>> _views = {};
  final Map<int, Future<List<RoundInfo>>> _rounds = {};

  int get currentSeason => currentSeasonStart(DateTime.now());

  /// Schermata aperta nella barra in basso.
  int tab = 0;

  void goToTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// Applica tutte le impostazioni consigliate.
  Future<void> applyRecommended() async {
    final s = settings;
    s.autoCalib = true;
    s.calibFrom = Recommended.calibFrom;
    s.calibTo = 0;
    s.model = _betterModel() ?? Recommended.model;
    s.marketWeight = Recommended.marketWeight;
    s.threshold = Recommended.threshold;
    s.stakePct = Recommended.stakePct;
    s.recentHalf = Recommended.recentHalf;
    s.excludedBooks.addAll(Recommended.nonAdm);
    s.introSeen = true;
    await saveSettings();
  }

  /// Il modello che ha avuto l'errore più basso nelle verifiche fatte
  /// sulle stesse stagioni, se ce ne sono per entrambi.
  String? _betterModel() {
    final t = settings.testedLl;
    for (final n in [3, 5, 1]) {
      final e = t['elo@$n'], d = t['dc@$n'];
      if (e != null && d != null) return d <= e ? 'dc' : 'elo';
    }
    return null;
  }

  /// Ricorda l'errore di una verifica fatta con il solo modello.
  Future<void> recordTest(BacktestResult r, int seasons) async {
    if (r.error != null || r.marketWeight > 0) return;
    settings.testedLl['${r.model}@$seasons'] = r.modelLogLoss;
    await saveSettings();
  }

  bool modelTested(String model) => settings.testedLl.keys.any((k) => k.startsWith('$model@'));

  /// Controllo delle impostazioni: cosa si discosta da un uso corretto.
  List<Advice> checkSettings() {
    final s = settings;
    final out = <Advice>[];
    final cur = currentSeason;
    if (!s.autoCalib) {
      out.add(Advice(
        'Calibrazione manuale',
        'Stai usando valori scelti a mano. La calibrazione automatica prova migliaia di combinazioni '
            'sui dati e quasi sempre prevede meglio.',
        AdviceLevel.warning,
        'Attiva',
        () {
          s.autoCalib = true;
          saveSettings();
        },
      ));
    }
    final to = s.calibToFor(cur);
    if (to - s.calibFrom + 1 < 4) {
      out.add(Advice(
        'Poche stagioni di calibrazione',
        'Con meno di 4 stagioni i parametri dipendono troppo dal caso.',
        AdviceLevel.warning,
        'Dal ${seasonLabel(Recommended.calibFrom)}',
        () {
          s.calibFrom = Recommended.calibFrom;
          s.calibTo = 0;
          saveSettings();
        },
      ));
    } else if (s.calibFrom < 2010) {
      out.add(Advice(
        'Stagioni molto vecchie',
        'Il calcio di 15–20 anni fa era diverso: meglio calibrare dal ${seasonLabel(Recommended.calibFrom)}.',
        AdviceLevel.tip,
        'Correggi',
        () {
          s.calibFrom = Recommended.calibFrom;
          saveSettings();
        },
      ));
    }
    if (s.recentHalf == 0) {
      out.add(Advice(
        'Tutte le stagioni pesano uguale',
        'Il calcio cambia nel tempo: dare più peso alle stagioni recenti rende la calibrazione più adatta a oggi.',
        AdviceLevel.tip,
        'Usa moderato',
        () {
          s.recentHalf = Recommended.recentHalf;
          saveSettings();
        },
      ));
    }
    if (s.marketWeight == 0) {
      out.add(Advice(
        'Solo il modello',
        'Senza peso del mercato i valori molto alti, che spesso sono errori del modello, restano tali. '
            'Con il 50% si ridimensionano da soli.',
        AdviceLevel.tip,
        'Usa 50%',
        () {
          s.marketWeight = Recommended.marketWeight;
          saveSettings();
        },
      ));
    } else if (s.marketWeight >= 0.75) {
      out.add(Advice(
        'Il modello conta poco',
        'Con il 75% di mercato le probabilità sono quasi quelle delle quote: l’app troverà pochissimo valore.',
        AdviceLevel.tip,
        'Usa 50%',
        () {
          s.marketWeight = Recommended.marketWeight;
          saveSettings();
        },
      ));
    }
    if (s.threshold < 1.03) {
      out.add(Advice(
        'Soglia troppo bassa',
        'Sotto 1,03 il vantaggio stimato è così piccolo che è solo rumore: perderesti il margine del bookmaker.',
        AdviceLevel.warning,
        'Usa 1,05',
        () {
          s.threshold = Recommended.threshold;
          saveSettings();
        },
      ));
    } else if (s.threshold > 1.12) {
      out.add(Advice(
        'Soglia molto alta',
        'Sopra 1,12 restano poche giocate, e spesso sono quelle dove il modello sbaglia di più.',
        AdviceLevel.tip,
        'Usa 1,05',
        () {
          s.threshold = Recommended.threshold;
          saveSettings();
        },
      ));
    }
    if (s.stakePct > 2) {
      out.add(Advice(
        'Puntata alta',
        'Con il 3% del budget a giocata, una serie negativa normale può dimezzare il budget.',
        AdviceLevel.tip,
        'Usa 2%',
        () {
          s.stakePct = Recommended.stakePct;
          saveSettings();
        },
      ));
    }
    final active = Recommended.nonAdm.where((b) => booksSeen.contains(b) && !s.excludedBooks.contains(b)).toList();
    if (active.isNotEmpty) {
      out.add(Advice(
        'Bookmaker non giocabili in Italia',
        '${active.join(', ')} non ha licenza ADM: le sue quote fanno sembrare convenienti giocate che non puoi fare.',
        AdviceLevel.warning,
        'Escludi',
        () {
          s.excludedBooks.addAll(Recommended.nonAdm);
          saveSettings();
        },
      ));
    }
    if (s.provider == 'oddsapi' && s.apiKey.trim().isEmpty) {
      out.add(Advice('Manca la chiave API', 'Senza chiave The Odds API non scarica le quote.', AdviceLevel.warning,
          'Usa football-data', () {
        s.provider = 'fd';
        saveSettings();
      }));
    }
    final better = _betterModel();
    if (better != null && better != s.model) {
      out.add(Advice(
        'C’è un modello migliore',
        'Nelle tue verifiche ${better == 'dc' ? 'Dixon-Coles' : 'Elo'} ha previsto meglio, con un errore più basso.',
        AdviceLevel.tip,
        'Usalo',
        () {
          s.model = better;
          saveSettings();
        },
      ));
    } else if (!modelTested('elo') || !modelTested('dc')) {
      out.add(Advice(
        'Confronta i due modelli',
        'Fai una verifica con Elo e una con Dixon-Coles, con peso del mercato 0% e le stesse stagioni: '
            'l’app ricorderà quale prevede meglio e te lo consiglierà.',
        AdviceLevel.tip,
        'Vai alla verifica',
        () => goToTab(3),
      ));
    }
    return out;
  }

  // "k2": la calibrazione include anche il K variabile a inizio stagione.
  String _calibKey(int cur) =>
      'k4-${settings.calibFrom}-${settings.calibToFor(cur)}-$cur-${settings.recentHalf.toStringAsFixed(1)}';

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
      savedSlips = (await repo.loadSlips())
          .map((e) => SavedSlip.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    try {
      _setHistory(await repo.loadHistory(currentSeason: currentSeason, onProgress: (_) {}, offline: true));
    } catch (_) {}
    notifyListeners();
  }

  void _setHistory(List<MatchResult> h) {
    _history = h;
    _historyVersion++;
    _views.clear();
    _rounds.clear();
    final idx = <String, List<MatchResult>>{};
    for (final m in h) {
      (idx['${m.home}|${m.away}'] ??= []).add(m);
    }
    _byTeams = idx;
  }

  /// Risultato vero di una giocata, se la partita è già nei dati.
  MatchResult? resultFor(Leg leg, DateTime savedAt) {
    final list = _byTeams['${leg.home}|${leg.away}'];
    if (list == null) return null;
    final d = leg.date;
    for (final m in list) {
      if (d != null) {
        if (m.date.difference(d).inHours.abs() <= 72) return m;
      } else {
        final diff = m.date.difference(savedAt).inDays;
        if (diff >= -1 && diff <= 60) return m;
      }
    }
    return null;
  }

  /// Stato della schedina ed esito di ogni giocata (null = non ancora giocata).
  (SlipStatus, List<bool?>) statusOf(SavedSlip s) {
    final res = <bool?>[];
    for (final l in s.legs) {
      final m = resultFor(l, s.savedAt);
      res.add(m == null ? null : l.wins(m.hg, m.ag));
    }
    if (res.any((r) => r == false)) return (SlipStatus.lost, res);
    if (res.every((r) => r == true)) return (SlipStatus.won, res);
    return (SlipStatus.pending, res);
  }

  Future<void> saveSlip(SavedSlip s) async {
    savedSlips.removeWhere((x) => x.id == s.id);
    savedSlips.insert(0, s);
    await repo.saveSlips(savedSlips.map((x) => x.toJson()).toList());
    notifyListeners();
  }

  Future<void> deleteSlip(String id) async {
    savedSlips.removeWhere((x) => x.id == id);
    await repo.saveSlips(savedSlips.map((x) => x.toJson()).toList());
    notifyListeners();
  }

  Future<void> saveSettings() async {
    _views.clear();
    _rounds.clear();
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
        calibrated = await _calibrateInBackground(history, from, to, settings.recentHalf);
        calibratedKey = _calibKey(cur);
      }

      _progress('Calcolo i punteggi Elo…');
      final params = paramsInUse;
      final live = await _buildLiveInBackground(history, params, cur, from, to, settings.recentHalf);
      DcFit? dcFit;
      if (settings.model == 'dc') {
        if (settings.autoCalib && (calibratedHl == null || calibratedHlKey != _calibKey(cur))) {
          _progress('Calibro Dixon-Coles: può richiedere qualche decina di secondi…');
          calibratedHl = await _calibrateDcInBackground(history, from, to, settings.recentHalf);
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
      _rounds.clear();
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

  /// Tutte le squadre presenti nei dati.
  List<String> get knownTeams {
    final h = _history;
    if (h == null) return [];
    final set = <String>{};
    for (final m in h) {
      set.add(m.home);
      set.add(m.away);
    }
    return set.toList()..sort();
  }

  /// Squadre delle ultime tre stagioni, per scegliere a mano una partita.
  List<String> get recentTeams {
    final h = _history;
    if (h == null || h.isEmpty) return [];
    final last = h.last.season;
    final set = <String>{};
    for (final m in h) {
      if (m.season < last - 2) continue;
      set.add(m.home);
      set.add(m.away);
    }
    return set.toList()..sort();
  }

  Future<void> ensureHistoryLoaded() async {
    await _ensureHistory();
    notifyListeners();
  }

  /// Valuta una schedina con Dixon-Coles, usando solo le partite giocate
  /// prima del giorno della prima giocata.
  Future<SlipAnalysis> analyzeSlip(List<Leg> legs, double stake, double bonus) async {
    final h = await _ensureHistory();
    DateTime? first;
    for (final l in legs) {
      final d = l.date;
      if (d != null && (first == null || d.isBefore(first))) first = d;
    }
    final before = first == null ? null : DateTime(first.year, first.month, first.day);
    final fit = await _fitDcSlipInBackground(h, halfLifeInUse, before);
    final out = <LegResult>[];
    for (final leg in legs) {
      if (leg.home.isEmpty || leg.away.isEmpty || leg.home == leg.away) {
        out.add(LegResult(leg, null, null, null, null));
        continue;
      }
      final m = fit.scoreMatrix(leg.home, leg.away);
      var p = 0.0, p1 = 0.0, px = 0.0, p2 = 0.0;
      for (var x = 0; x < m.length; x++) {
        for (var y = 0; y < m[x].length; y++) {
          final v = m[x][y];
          if (leg.wins(x, y)) p += v;
          if (x > y) {
            p1 += v;
          } else if (x == y) {
            px += v;
          } else {
            p2 += v;
          }
        }
      }
      String? score;
      bool? won;
      final d = leg.date;
      if (d != null) {
        for (final r in h) {
          if (r.home == leg.home && r.away == leg.away && r.date.difference(d).inHours.abs() <= 72) {
            score = '${r.hg}-${r.ag}';
            won = leg.wins(r.hg, r.ag);
            break;
          }
        }
      }
      out.add(LegResult(leg, p, [p1, px, p2], score, won));
    }
    final unknown = legs.where((l) => l.home.isNotEmpty && (!fit.knows(l.home) || !fit.knows(l.away))).length;
    var note = before == null
        ? 'Stima Dixon-Coles con tutte le partite giocate finora'
        : 'Stima Dixon-Coles con le sole partite giocate prima del ${before.day}/${before.month}/${before.year}';
    note += ' (emivita ${halfLifeInUse.round()} giorni). Le giocate sono trattate come indipendenti.';
    if (unknown > 0) {
      note += ' Per $unknown partite una squadra non ha dati recenti in Serie A: è stimata come una neopromossa.';
    }
    return SlipAnalysis(out, stake, bonus, note);
  }

  Future<BacktestResult> runBacktest(int seasons, double threshold, String model, double marketWeight) async {
    final h = await _ensureHistory();
    final args = BacktestArgs(
      marketWeight: marketWeight,
      recentHalf: settings.recentHalf,
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

  /// Giornate di una stagione: partite giocate con la previsione di allora,
  /// più quelle in arrivo per la stagione in corso.
  Future<List<RoundInfo>> roundsFor(int season) => _rounds.putIfAbsent(season, () => _makeRounds(season));

  Future<List<RoundInfo>> _makeRounds(int season) async {
    final h = await _ensureHistory();
    final cur = currentSeason;
    final args = PastArgs(season, settings.model, paramsInUse, halfLifeInUse, settings.calibFrom,
        settings.calibToFor(cur), settings.recentHalf);
    final past = await _pastInBackground(h, args);
    final all = <Prediction>[
      for (final m in past)
        Prediction(
          home: m.home,
          away: m.away,
          date: m.date,
          eloH: 0,
          eloA: 0,
          p: m.p,
          books: m.odds == null ? {} : {'Quote dell’epoca': m.odds!},
          unknownTeam: false,
          model: settings.model,
          over25: m.over25,
          gg: m.gg,
          xgHome: m.xgHome,
          xgAway: m.xgAway,
          hg: m.hg,
          ag: m.ag,
        ),
    ];
    if (season == cur) {
      for (final p in predictions) {
        final d = p.date;
        final dup = all.any((x) =>
            x.home == p.home && x.away == p.away && (d == null || x.date == null || x.date!.difference(d).inDays.abs() <= 3));
        if (!dup) all.add(p);
      }
    }
    if (all.isEmpty) return [];
    final far = DateTime(2100);
    final groups = groupRounds(
      [for (final p in all) p.date ?? far],
      [for (final p in all) p.home],
      [for (final p in all) p.away],
    );
    final out = <RoundInfo>[];
    var n = 0;
    for (final g in groups) {
      final ms = [for (final i in g) all[i]];
      if (ms.length >= 6) {
        n++;
        out.add(RoundInfo('${n}ª giornata', ms));
      } else {
        out.add(RoundInfo(n == 0 ? 'Partite isolate' : 'Recuperi dopo la ${n}ª', ms));
      }
    }
    return out;
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

Future<EloParams> _calibrateInBackground(List<MatchResult> h, int from, int to, double rh) =>
    Isolate.run(() => calibrate(h, from: from, to: to, recentHalf: rh));

Future<LiveModel> _buildLiveInBackground(
        List<MatchResult> h, EloParams p, int cur, int from, int to, double rh) =>
    Isolate.run(() => buildLive(h, p, cur, drawFrom: from, drawTo: to, recentHalf: rh));

Future<List<PastMatch>> _pastInBackground(List<MatchResult> h, PastArgs a) =>
    Isolate.run(() => pastMatches(h, a));

Future<BacktestResult> _backtestInBackground(List<MatchResult> h, BacktestArgs args) =>
    Isolate.run(() => backtest(h, args));

Future<double> _calibrateDcInBackground(List<MatchResult> h, int from, int to, double rh) =>
    Isolate.run(() => calibrateDc(h, from: from, to: to, recentHalf: rh));

Future<DcFit> _fitDcInBackground(List<MatchResult> h, double hl, int? untilSeason) =>
    Isolate.run(() => fitDcNow(h, hl, untilSeason: untilSeason));

Future<DcFit> _fitDcSlipInBackground(List<MatchResult> h, double hl, DateTime? before) =>
    Isolate.run(() => fitDcNow(h, hl, before: before));

Future<EloHistoryData> _historyInBackground(List<MatchResult> h, EloParams p) =>
    Isolate.run(() => buildHistory(h, p));

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
