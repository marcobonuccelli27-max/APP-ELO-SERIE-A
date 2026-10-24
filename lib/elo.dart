// Motore Elo: punteggi, calibrazione, modello 1X2, storico e verifica sul passato.
// Tutto qui dentro è puro calcolo, senza interfaccia: gira in un isolate
// separato così l'app non si blocca durante i calcoli.

import 'dart:math' as math;
import 'dart:typed_data';

import 'dc.dart';

/// Una partita giocata, letta dai file di football-data.co.uk.
class MatchResult {
  final int season; // anno di inizio stagione, es. 2024 = 2024/25
  final DateTime date;
  final String home;
  final String away;
  final int hg;
  final int ag;

  /// Quote 1-X-2 a cui si poteva scommettere prima della partita
  /// (Bet365, oppure la media dei bookmaker se manca).
  final List<double>? odds;

  /// Quote 1-X-2 di chiusura (Pinnacle, altrimenti Bet365 o media).
  final List<double>? closing;

  const MatchResult({
    required this.season,
    required this.date,
    required this.home,
    required this.away,
    required this.hg,
    required this.ag,
    this.odds,
    this.closing,
  });

  /// 0 = vince la squadra di casa, 1 = pareggio, 2 = vince l'ospite.
  int get outcome => hg > ag ? 0 : (hg == ag ? 1 : 2);
}

/// I parametri del motore Elo.
class EloParams {
  final double k; // quanto si muovono i punteggi dopo ogni partita (dal girone di ritorno)
  final double home; // punti di vantaggio per chi gioca in casa
  final double regress; // quota (0-1) di riavvicinamento alla media a inizio stagione
  final double early; // aumento di K alla prima giornata (1 = doppio), che scende fino alla 19ª
  final bool curved; // discesa curva (veloce all'inizio, poi più lenta) invece che in linea retta

  const EloParams(this.k, this.home, this.regress, [this.early = 0, this.curved = false]);

  static const standard = EloParams(20, 70, 0.25, 0.5);

  /// Giornate su cui K scende fino al valore normale (il girone d'andata).
  static const earlyRounds = 19;

  /// K effettivo dopo [played] partite giocate nella stagione.
  double kAt(double played) {
    var f = (earlyRounds - played) / earlyRounds;
    if (f < 0) f = 0;
    if (curved) f = f * f;
    return k * (1 + early * f);
  }

  String get key =>
      '${k.toStringAsFixed(2)}|${home.toStringAsFixed(2)}|${regress.toStringAsFixed(3)}|${early.toStringAsFixed(2)}|${curved ? 'c' : 'l'}';

  Map<String, dynamic> toJson() => {'k': k, 'home': home, 'regress': regress, 'early': early, 'curved': curved};

  factory EloParams.fromJson(Map<String, dynamic> j) => EloParams(
        (j['k'] as num).toDouble(),
        (j['home'] as num).toDouble(),
        (j['regress'] as num).toDouble(),
        (j['early'] as num?)?.toDouble() ?? 0,
        j['curved'] as bool? ?? false,
      );
}

double _sig(double z) => 1.0 / (1.0 + math.exp(-z));

/// Punteggio atteso (0-1) per la squadra di casa, data la differenza Elo
/// già comprensiva del vantaggio casa.
double expectedScore(double diff) => 1.0 / (1.0 + math.pow(10, -diff / 400));

/// Moltiplicatore per la differenza reti (come nel World Football Elo).
double goalMultiplier(int goalDiff) {
  final g = goalDiff.abs();
  if (g <= 1) return 1.0;
  if (g == 2) return 1.5;
  return (11 + g) / 8.0;
}

/// Vero se l'esito [k] è il meno probabile dei tre.
bool isLeastLikely(List<double> p, int k) {
  for (var j = 0; j < 3; j++) {
    if (j != k && p[j] <= p[k]) return false;
  }
  return true;
}

/// Modello che trasforma la differenza Elo in probabilità 1, X, 2
/// (regressione logistica ordinale).
class DrawModel {
  final double t1;
  final double t2;
  final double b;

  const DrawModel(this.t1, this.t2, this.b);

  static const standard = DrawModel(-1.05, 0.25, 0.55);

  /// [diff] = Elo casa + vantaggio casa − Elo ospite.
  List<double> probs(double diff) {
    final d = diff / 100.0;
    final s1 = _sig(t1 - b * d);
    final s2 = _sig(t2 - b * d);
    return [1.0 - s2, s2 - s1, s1];
  }
}

/// Partite convertite in numeri, per calcoli veloci.
class _Prepared {
  final List<String> teams;
  final Int32List h;
  final Int32List a;
  final Int32List gd;
  final Int32List outc;
  final Int32List season;
  int get n => h.length;

  _Prepared._(this.teams, this.h, this.a, this.gd, this.outc, this.season);

  factory _Prepared(List<MatchResult> ms) {
    final ids = <String, int>{};
    final n = ms.length;
    final h = Int32List(n), a = Int32List(n), gd = Int32List(n);
    final o = Int32List(n), s = Int32List(n);
    for (var i = 0; i < n; i++) {
      final m = ms[i];
      h[i] = ids.putIfAbsent(m.home, () => ids.length);
      a[i] = ids.putIfAbsent(m.away, () => ids.length);
      gd[i] = m.hg - m.ag;
      o[i] = m.outcome;
      s[i] = m.season;
    }
    final teams = List<String>.filled(ids.length, '');
    ids.forEach((k, v) => teams[v] = k);
    return _Prepared._(teams, h, a, gd, o, s);
  }
}

class _SimOut {
  final Float64List diffs; // differenza prima di ogni partita
  final Float64List ratings; // punteggi finali
  final Float64List lastDelta; // variazione nell'ultima partita
  final double loss; // errore medio (Brier) nelle stagioni scelte
  final int lossCount;
  final double baselineEnd; // media delle ultime 3 dell'ultima stagione
  final List<int> lastSeasonTeams;

  _SimOut(this.diffs, this.ratings, this.lastDelta, this.loss, this.lossCount, this.baselineEnd,
      this.lastSeasonTeams);
}

/// Fa scorrere il motore Elo su tutte le partite, in ordine.
/// L'errore viene misurato solo sulle stagioni da [lossFrom] a [lossTo].
/// Con [rec] registra il punteggio di ogni squadra dopo ogni partita
/// (indice negativo = punteggio di partenza a inizio stagione).
_SimOut _simulate(
  _Prepared d,
  EloParams p, {
  int lossFrom = 0,
  int lossTo = 1 << 30,
  List<List<int>>? recI,
  List<List<double>>? rec,
}) {
  final nt = d.teams.length;
  final r = Float64List(nt)..fillRange(0, nt, 1500);
  final last = Float64List(nt);
  final inPrev = List<bool>.filled(nt, false);
  final inCur = List<bool>.filled(nt, false);
  final played = Int32List(nt); // partite giocate nella stagione in corso
  final diffs = Float64List(d.n);
  var cur = d.n > 0 ? d.season[0] : 0;
  final first = cur;
  var baseline = 1500.0;
  var loss = 0.0;
  var count = 0;

  double bottom3() {
    final rs = <double>[];
    for (var t = 0; t < nt; t++) {
      if (inCur[t]) rs.add(r[t]);
    }
    if (rs.length < 3) return 1500;
    rs.sort();
    return (rs[0] + rs[1] + rs[2]) / 3;
  }

  for (var i = 0; i < d.n; i++) {
    if (d.season[i] != cur) {
      // Fine stagione: base per le neopromosse e riavvicinamento alla media.
      baseline = bottom3();
      baseline = 1500 + (baseline - 1500) * (1 - p.regress);
      for (var t = 0; t < nt; t++) {
        if (inCur[t]) r[t] = 1500 + (r[t] - 1500) * (1 - p.regress);
        inPrev[t] = inCur[t];
        inCur[t] = false;
        played[t] = 0;
      }
      cur = d.season[i];
    }
    final h = d.h[i], a = d.a[i];
    for (final t in [h, a]) {
      if (!inCur[t]) {
        inCur[t] = true;
        if (cur != first && !inPrev[t]) r[t] = baseline; // neopromossa
        if (rec != null) {
          rec[t].add(r[t]);
          recI![t].add(-(i + 1));
        }
      }
    }
    final diff = r[h] + p.home - r[a];
    diffs[i] = diff;
    final we = expectedScore(diff);
    final o = d.outc[i];
    final w = o == 0 ? 1.0 : (o == 1 ? 0.5 : 0.0);
    if (cur != first && cur >= lossFrom && cur <= lossTo) {
      loss += (w - we) * (w - we);
      count++;
    }
    final kEff = p.early == 0 ? p.k : p.kAt((played[h] + played[a]) / 2);
    final delta = kEff * goalMultiplier(d.gd[i]) * (w - we);
    played[h]++;
    played[a]++;
    r[h] += delta;
    r[a] -= delta;
    last[h] = delta;
    last[a] = -delta;
    if (rec != null) {
      rec[h].add(r[h]);
      recI![h].add(i);
      rec[a].add(r[a]);
      recI![a].add(i);
    }
  }

  final lastTeams = <int>[];
  for (var t = 0; t < nt; t++) {
    if (inCur[t]) lastTeams.add(t);
  }
  return _SimOut(diffs, r, last, count > 0 ? loss / count : 1, count, bottom3(), lastTeams);
}

/// Cerca i parametri che avrebbero previsto meglio le partite delle stagioni
/// da [from] a [to] (gli anni sono quelli di inizio stagione).
EloParams calibrate(List<MatchResult> ms, {int from = 0, int to = 1 << 30}) {
  final sub = ms.where((m) => m.season <= to).toList();
  if (sub.isEmpty) return EloParams.standard;
  final d = _Prepared(sub);
  if (_simulate(d, EloParams.standard, lossFrom: from, lossTo: to).lossCount < 300) {
    return EloParams.standard;
  }
  EloParams best = EloParams.standard;
  var bestLoss = double.infinity;

  void tryP(EloParams p) {
    final l = _simulate(d, p, lossFrom: from, lossTo: to).loss;
    if (l < bestLoss) {
      bestLoss = l;
      best = p;
    }
  }

  // Prima una ricerca larga...
  for (var k = 10.0; k <= 40; k += 4) {
    for (var h = 20.0; h <= 120; h += 10) {
      for (final reg in [0.1, 0.2, 0.3, 0.4]) {
        tryP(EloParams(k, h, reg, 0));
        for (final e in [0.5, 1.0, 1.5, 2.0, 3.0]) {
          tryP(EloParams(k, h, reg, e, false));
          tryP(EloParams(k, h, reg, e, true));
        }
      }
    }
  }
  // ...poi una più fine intorno al migliore.
  final c = best;
  for (var k = c.k - 3; k <= c.k + 3; k += 1) {
    for (var h = c.home - 8; h <= c.home + 8; h += 2) {
      for (final reg in [c.regress - 0.05, c.regress, c.regress + 0.05]) {
        for (final e in [c.early - 0.25, c.early, c.early + 0.25]) {
          if (k < 4 || reg < 0 || reg > 0.9 || e < 0) continue;
          tryP(EloParams(k, h, reg, e, c.curved));
        }
      }
    }
  }
  return best;
}

/// Stima il modello 1X2 dalle differenze Elo e dai risultati reali.
DrawModel fitDrawModel(List<double> diffs, List<int> outc) {
  final n = diffs.length;
  if (n < 200) return DrawModel.standard;
  var t1 = -1.0, t2 = 0.2, b = 0.5;
  const lr = 1.0;
  for (var it = 0; it < 1500; it++) {
    var g1 = 0.0, g2 = 0.0, gb = 0.0;
    for (var i = 0; i < n; i++) {
      final d = diffs[i] / 100.0;
      final s1 = _sig(t1 - b * d);
      final s2 = _sig(t2 - b * d);
      switch (outc[i]) {
        case 2:
          g1 += 1 - s1;
          gb += -d * (1 - s1);
          break;
        case 0:
          g2 += -s2;
          gb += d * s2;
          break;
        default:
          final pr = math.max(s2 - s1, 1e-9);
          final q1 = s1 * (1 - s1), q2 = s2 * (1 - s2);
          g1 += -q1 / pr;
          g2 += q2 / pr;
          gb += -d * (q2 - q1) / pr;
      }
    }
    t1 += lr * g1 / n;
    t2 += lr * g2 / n;
    b += lr * gb / n;
    if (t2 < t1 + 0.05) t2 = t1 + 0.05;
  }
  return DrawModel(t1, t2, b);
}

DrawModel _fitDrawOn(_Prepared d, _SimOut sim, int from, int to) {
  final first = d.n > 0 ? d.season[0] : 0;
  final dl = <double>[];
  final ol = <int>[];
  for (var i = 0; i < d.n; i++) {
    final s = d.season[i];
    if (s == first || s < from || s > to) continue;
    dl.add(sim.diffs[i]);
    ol.add(d.outc[i]);
  }
  return fitDrawModel(dl, ol);
}

/// Il modello pronto per la stagione in corso.
class LiveModel {
  final Map<String, double> ratings;
  final DrawModel draw;
  final EloParams params;
  final double baseline; // punteggio per una squadra sconosciuta (neopromossa)
  final int dataSeason;

  LiveModel({
    required this.ratings,
    required this.draw,
    required this.params,
    required this.baseline,
    required this.dataSeason,
  });
}

LiveModel buildLive(List<MatchResult> ms, EloParams p, int currentSeason,
    {int drawFrom = 0, int drawTo = 1 << 30}) {
  final d = _Prepared(ms);
  final sim = _simulate(d, p);
  final draw = _fitDrawOn(d, sim, drawFrom, drawTo);

  final ratings = <String, double>{};
  for (var t = 0; t < d.teams.length; t++) {
    ratings[d.teams[t]] = sim.ratings[t];
  }
  final lastSeason = ms.last.season;
  var baseline = sim.baselineEnd;
  if (currentSeason > lastSeason) {
    // La nuova stagione non è ancora nei dati: applico il passaggio di stagione.
    for (final t in sim.lastSeasonTeams) {
      final name = d.teams[t];
      ratings[name] = 1500 + (ratings[name]! - 1500) * (1 - p.regress);
    }
    baseline = 1500 + (baseline - 1500) * (1 - p.regress);
  }
  return LiveModel(ratings: ratings, draw: draw, params: p, baseline: baseline, dataSeason: lastSeason);
}

// ---------------------------------------------------------------------------
// Storico dei punteggi e classifiche

/// Andamento del punteggio di una squadra: un punto dopo ogni partita,
/// più un punto di partenza all'inizio di ogni stagione.
class TeamSeries {
  final List<int> t; // data in millisecondi
  final List<double> r; // punteggio
  final List<int> s; // stagione
  TeamSeries(this.t, this.r, this.s);

  List<double> seasonValues(int season) => [
        for (var i = 0; i < r.length; i++)
          if (s[i] == season) r[i]
      ];

  List<int> seasonTimes(int season) => [
        for (var i = 0; i < t.length; i++)
          if (s[i] == season) t[i]
      ];
}

/// Storico completo calcolato con certi parametri.
EloHistoryData buildHistory(List<MatchResult> ms, EloParams p) {
  final d = _Prepared(ms);
  final nt = d.teams.length;
  final recI = List.generate(nt, (_) => <int>[]);
  final rec = List.generate(nt, (_) => <double>[]);
  _simulate(d, p, recI: recI, rec: rec);
  final out = <String, TeamSeries>{};
  for (var t = 0; t < nt; t++) {
    final times = <int>[], seasons = <int>[];
    for (final idx in recI[t]) {
      final i = idx < 0 ? -idx - 1 : idx;
      final m = ms[i];
      final ms0 = m.date.millisecondsSinceEpoch;
      times.add(idx < 0 ? ms0 - const Duration(days: 1).inMilliseconds : ms0);
      seasons.add(m.season);
    }
    out[d.teams[t]] = TeamSeries(times, rec[t], seasons);
  }
  return EloHistoryData(out);
}

class EloHistoryData {
  final Map<String, TeamSeries> series;
  EloHistoryData(this.series);
}

class StandingRow {
  final String team;
  int played = 0, won = 0, drawn = 0, lost = 0, gf = 0, ga = 0;
  final List<String> form = [];
  StandingRow(this.team);
  int get points => won * 3 + drawn;
  int get goalDiff => gf - ga;
}

/// Classifica della Serie A di una stagione, dai risultati.
List<StandingRow> standings(List<MatchResult> ms, int season) {
  final rows = <String, StandingRow>{};
  for (final m in ms) {
    if (m.season != season) continue;
    final h = rows.putIfAbsent(m.home, () => StandingRow(m.home));
    final a = rows.putIfAbsent(m.away, () => StandingRow(m.away));
    h.played++;
    a.played++;
    h.gf += m.hg;
    h.ga += m.ag;
    a.gf += m.ag;
    a.ga += m.hg;
    switch (m.outcome) {
      case 0:
        h.won++;
        a.lost++;
        h.form.add('V');
        a.form.add('P');
        break;
      case 1:
        h.drawn++;
        a.drawn++;
        h.form.add('N');
        a.form.add('N');
        break;
      default:
        a.won++;
        h.lost++;
        a.form.add('V');
        h.form.add('P');
    }
  }
  final list = rows.values.toList()
    ..sort((x, y) {
      if (y.points != x.points) return y.points - x.points;
      if (y.goalDiff != x.goalDiff) return y.goalDiff - x.goalDiff;
      if (y.gf != x.gf) return y.gf - x.gf;
      return x.team.compareTo(y.team);
    });
  return list;
}

// ---------------------------------------------------------------------------
// Verifica sul passato

class BacktestArgs {
  final int testSeasons;
  final double threshold;
  final double stake;
  final double budget;
  final EloParams? fixed; // parametri manuali; null = calibrazione automatica
  final int calibFrom;
  final int calibTo;
  final String model; // 'elo' oppure 'dc'
  final double? fixedHalfLife; // emivita manuale per Dixon-Coles

  const BacktestArgs({
    this.model = 'elo',
    this.fixedHalfLife,
    required this.testSeasons,
    required this.threshold,
    required this.stake,
    required this.budget,
    required this.fixed,
    required this.calibFrom,
    required this.calibTo,
  });
}

/// Risultato della verifica sul passato.
class BacktestResult {
  final int bets;
  final int skippedLeastLikely; // giocate scartate perché sull'esito meno probabile
  final double staked;
  final double profit;
  final double roi; // profitto / puntato
  final double roiMargin; // incertezza (2 deviazioni standard)
  final int clvChecked;
  final int clvBeaten; // quote prese più alte di quelle di chiusura
  final double modelLogLoss;
  final double bookLogLoss;
  final int testMatches;
  final List<double> bankroll;
  final List<DateTime> dates;
  final EloParams params;
  final String model;
  final double halfLife;
  final bool manual;
  final int trainFrom;
  final int trainTo;
  final int testFrom;
  final int testTo;
  final List<ThresholdRow> sweep; // risultati con ogni soglia da 1,00 a 1,20
  final String? error;

  BacktestResult({
    this.sweep = const [],
    required this.bets,
    required this.skippedLeastLikely,
    required this.staked,
    required this.profit,
    required this.roi,
    required this.roiMargin,
    required this.clvChecked,
    required this.clvBeaten,
    required this.modelLogLoss,
    required this.bookLogLoss,
    required this.testMatches,
    required this.bankroll,
    required this.dates,
    required this.params,
    this.model = 'elo',
    this.halfLife = 0,
    required this.manual,
    required this.trainFrom,
    required this.trainTo,
    required this.testFrom,
    required this.testTo,
    this.error,
  });

  factory BacktestResult.failed(String msg) => BacktestResult(
        bets: 0,
        skippedLeastLikely: 0,
        staked: 0,
        profit: 0,
        roi: 0,
        roiMargin: 0,
        clvChecked: 0,
        clvBeaten: 0,
        modelLogLoss: 0,
        bookLogLoss: 0,
        testMatches: 0,
        bankroll: const [],
        dates: const [],
        params: EloParams.standard,
        manual: false,
        trainFrom: 0,
        trainTo: 0,
        testFrom: 0,
        testTo: 0,
        error: msg,
      );

  double get clvShare => clvChecked == 0 ? 0 : clvBeaten / clvChecked;
}

/// Toglie il margine del bookmaker: probabilità che sommano a 1.
List<double> fairProbs(List<double> odds) {
  final inv = odds.map((o) => 1 / o).toList();
  final s = inv.reduce((a, b) => a + b);
  return inv.map((x) => x / s).toList();
}

/// Simula di aver usato il modello sulle ultime stagioni complete, calibrandolo
/// solo su stagioni precedenti a quelle provate.
BacktestResult backtest(List<MatchResult> ms, BacktestArgs args) {
  final counts = <int, int>{};
  for (final m in ms) {
    counts[m.season] = (counts[m.season] ?? 0) + 1;
  }
  final complete = counts.keys.where((s) => counts[s]! >= 370).toList()..sort();
  if (complete.length < args.testSeasons + 2) {
    return BacktestResult.failed(
        'Servono almeno ${args.testSeasons + 2} stagioni complete: aggiorna i dati.');
  }
  final test = complete.sublist(complete.length - args.testSeasons);
  final testFrom = test.first, testTo = test.last;
  final dataFirst = ms.first.season;

  final trainFrom = math.max(args.calibFrom, dataFirst);
  final trainTo = math.min(args.calibTo, testFrom - 1);
  if (trainTo - trainFrom < 1) {
    return BacktestResult.failed(
        'Le stagioni di calibrazione devono venire prima di quelle di prova '
        '(che iniziano dal $testFrom) ed essere almeno due. Cambiale nelle Impostazioni.');
  }

  final upto = ms.where((m) => m.season <= testTo).toList();
  final isDc = args.model == 'dc';
  var params = args.fixed ?? EloParams.standard;
  var halfLife = 0.0;
  var testStart = 0;
  while (testStart < upto.length && upto[testStart].season < testFrom) {
    testStart++;
  }
  late final List<List<double>> testProbs;
  if (isDc) {
    halfLife = args.fixedHalfLife ?? calibrateDc(ms, from: trainFrom, to: trainTo);
    final dd = DcData(upto);
    testProbs = rollingProbs(dd, testStart, dd.n, halfLife).map((x) => x.p).toList();
  } else {
    params = args.fixed ?? calibrate(ms, from: trainFrom, to: trainTo);
    final d = _Prepared(upto);
    final sim = _simulate(d, params);
    final draw = _fitDrawOn(d, sim, trainFrom, trainTo);
    testProbs = [for (var i = testStart; i < d.n; i++) draw.probs(sim.diffs[i])];
  }

  // Partite di prova con quote, per simulare le scommesse.
  final picks = <_TestMatch>[];
  var llModel = 0.0, llBook = 0.0;
  var nLl = 0;
  var nTest = 0;
  for (var i = testStart; i < upto.length; i++) {
    final m = upto[i];
    nTest++;
    final p = testProbs[i - testStart];
    final o = m.outcome;
    final ref = m.closing ?? m.odds;
    if (ref != null) {
      llModel += -math.log(math.max(p[o], 1e-9));
      llBook += -math.log(math.max(fairProbs(ref)[o], 1e-9));
      nLl++;
    }
    if (m.odds != null) picks.add(_TestMatch(p, o, m.odds!, m.closing, m.date));
  }

  final chosen = _runBets(picks, args.threshold, args.stake, args.budget, true);
  final sweep = <ThresholdRow>[
    for (var t = 100; t <= 120; t++) _runBets(picks, t / 100, args.stake, args.budget, false).row(t / 100)
  ];
  final bets = chosen.bets, skipped = chosen.skipped, staked = chosen.staked, profit = chosen.profit;
  final margin = chosen.margin, clvChecked = chosen.clvChecked, clvBeaten = chosen.clvBeaten;
  final bankroll = chosen.bankroll, dates = chosen.dates;

  return BacktestResult(
    bets: bets,
    skippedLeastLikely: skipped,
    staked: staked,
    profit: profit,
    roi: staked > 0 ? profit / staked : 0,
    roiMargin: margin,
    clvChecked: clvChecked,
    clvBeaten: clvBeaten,
    modelLogLoss: nLl > 0 ? llModel / nLl : 0,
    bookLogLoss: nLl > 0 ? llBook / nLl : 0,
    testMatches: nTest,
    bankroll: bankroll,
    dates: dates,
    params: params,
    model: args.model,
    halfLife: halfLife,
    manual: isDc ? args.fixedHalfLife != null : args.fixed != null,
    trainFrom: trainFrom,
    trainTo: trainTo,
    testFrom: testFrom,
    testTo: testTo,
    sweep: sweep,
  );
}

class _TestMatch {
  final List<double> p;
  final int outcome;
  final List<double> odds;
  final List<double>? closing;
  final DateTime date;
  _TestMatch(this.p, this.outcome, this.odds, this.closing, this.date);
}

class _BetStats {
  int bets = 0, skipped = 0, clvChecked = 0, clvBeaten = 0;
  double staked = 0, profit = 0, margin = 0;
  final List<double> bankroll = [];
  final List<DateTime> dates = [];

  ThresholdRow row(double t) => ThresholdRow(
        threshold: t,
        bets: bets,
        profit: profit,
        roi: staked > 0 ? profit / staked : 0,
        margin: margin,
        clvChecked: clvChecked,
        clvBeaten: clvBeaten,
      );
}

/// Simula le scommesse con una certa soglia di valore.
_BetStats _runBets(List<_TestMatch> ms, double threshold, double stake, double budget, bool series) {
  final st = _BetStats();
  if (series) st.bankroll.add(budget);
  final returns = <double>[];
  for (final m in ms) {
    final p = m.p, q = m.odds;
    var pick = 0;
    var ev = p[0] * q[0];
    for (var k = 1; k < 3; k++) {
      if (p[k] * q[k] > ev) {
        ev = p[k] * q[k];
        pick = k;
      }
    }
    if (ev < threshold) continue;
    if (isLeastLikely(p, pick)) {
      st.skipped++;
      continue;
    }
    st.bets++;
    st.staked += stake;
    final r = pick == m.outcome ? q[pick] - 1 : -1.0;
    returns.add(r);
    st.profit += stake * r;
    if (series) {
      st.bankroll.add(budget + st.profit);
      st.dates.add(m.date);
    }
    final c = m.closing;
    if (c != null) {
      st.clvChecked++;
      if (q[pick] > c[pick]) st.clvBeaten++;
    }
  }
  if (returns.length > 1) {
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    var v = 0.0;
    for (final r in returns) {
      v += (r - mean) * (r - mean);
    }
    v /= (returns.length - 1);
    st.margin = 2 * math.sqrt(v) / math.sqrt(returns.length);
  }
  return st;
}

/// Risultato della verifica con una certa soglia.
class ThresholdRow {
  final double threshold;
  final int bets;
  final double profit;
  final double roi;
  final double margin;
  final int clvChecked;
  final int clvBeaten;

  const ThresholdRow({
    required this.threshold,
    required this.bets,
    required this.profit,
    required this.roi,
    required this.margin,
    required this.clvChecked,
    required this.clvBeaten,
  });

  double get clvShare => clvChecked == 0 ? 0 : clvBeaten / clvChecked;
  double get lowerBound => roi - margin; // caso sfavorevole: ROI meno il margine
}
