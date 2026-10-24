// Motore Elo: punteggi, calibrazione, modello 1X2 e verifica sul passato.
// Tutto qui dentro è puro calcolo, senza interfaccia: gira in un isolate
// separato così l'app non si blocca durante i calcoli.

import 'dart:math' as math;
import 'dart:typed_data';

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

/// I tre parametri del motore Elo.
class EloParams {
  final double k; // quanto si muovono i punteggi dopo ogni partita
  final double home; // punti di vantaggio per chi gioca in casa
  final double regress; // quota (0-1) di riavvicinamento alla media a inizio stagione

  const EloParams(this.k, this.home, this.regress);

  static const standard = EloParams(20, 70, 0.25);

  Map<String, dynamic> toJson() => {'k': k, 'home': home, 'regress': regress};

  factory EloParams.fromJson(Map<String, dynamic> j) => EloParams(
        (j['k'] as num).toDouble(),
        (j['home'] as num).toDouble(),
        (j['regress'] as num).toDouble(),
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

  Map<String, dynamic> toJson() => {'t1': t1, 't2': t2, 'b': b};

  factory DrawModel.fromJson(Map<String, dynamic> j) => DrawModel(
        (j['t1'] as num).toDouble(),
        (j['t2'] as num).toDouble(),
        (j['b'] as num).toDouble(),
      );
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
  final double loss; // errore medio (Brier) escluso il primo anno
  final double baselineEnd; // media delle ultime 3 dell'ultima stagione
  final List<int> lastSeasonTeams;

  _SimOut(this.diffs, this.ratings, this.lastDelta, this.loss, this.baselineEnd,
      this.lastSeasonTeams);
}

/// Fa scorrere il motore Elo su tutte le partite, in ordine.
_SimOut _simulate(_Prepared d, EloParams p) {
  final nt = d.teams.length;
  final r = Float64List(nt)..fillRange(0, nt, 1500);
  final last = Float64List(nt);
  final inPrev = List<bool>.filled(nt, false);
  final inCur = List<bool>.filled(nt, false);
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
      }
      cur = d.season[i];
    }
    final h = d.h[i], a = d.a[i];
    for (final t in [h, a]) {
      if (!inCur[t]) {
        inCur[t] = true;
        if (cur != first && !inPrev[t]) r[t] = baseline; // neopromossa
      }
    }
    final diff = r[h] + p.home - r[a];
    diffs[i] = diff;
    final we = expectedScore(diff);
    final o = d.outc[i];
    final w = o == 0 ? 1.0 : (o == 1 ? 0.5 : 0.0);
    if (cur != first) {
      loss += (w - we) * (w - we);
      count++;
    }
    final delta = p.k * goalMultiplier(d.gd[i]) * (w - we);
    r[h] += delta;
    r[a] -= delta;
    last[h] = delta;
    last[a] = -delta;
  }

  final lastTeams = <int>[];
  for (var t = 0; t < nt; t++) {
    if (inCur[t]) lastTeams.add(t);
  }
  return _SimOut(diffs, r, last, count > 0 ? loss / count : 1, bottom3(), lastTeams);
}

/// Cerca i parametri che avrebbero previsto meglio le partite passate.
EloParams calibrate(List<MatchResult> ms) {
  if (ms.length < 800) return EloParams.standard;
  final d = _Prepared(ms);
  EloParams best = EloParams.standard;
  var bestLoss = double.infinity;

  void tryP(EloParams p) {
    final l = _simulate(d, p).loss;
    if (l < bestLoss) {
      bestLoss = l;
      best = p;
    }
  }

  // Prima una ricerca larga...
  for (var k = 10.0; k <= 40; k += 4) {
    for (var h = 20.0; h <= 120; h += 10) {
      for (final reg in [0.1, 0.2, 0.3, 0.4]) {
        tryP(EloParams(k, h, reg));
      }
    }
  }
  // ...poi una più fine intorno al migliore.
  final c = best;
  for (var k = c.k - 3; k <= c.k + 3; k += 1) {
    for (var h = c.home - 8; h <= c.home + 8; h += 2) {
      for (final reg in [c.regress - 0.05, c.regress, c.regress + 0.05]) {
        if (k < 4 || reg < 0 || reg > 0.9) continue;
        tryP(EloParams(k, h, reg));
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

/// Il modello pronto per la stagione in corso.
class LiveModel {
  final Map<String, double> ratings;
  final Map<String, double> lastDelta;
  final Map<String, List<String>> form; // ultime 5: V, N, P
  final List<String> seasonTeams;
  final DrawModel draw;
  final EloParams params;
  final double baseline; // punteggio per una squadra sconosciuta (neopromossa)
  final int dataSeason;

  LiveModel({
    required this.ratings,
    required this.lastDelta,
    required this.form,
    required this.seasonTeams,
    required this.draw,
    required this.params,
    required this.baseline,
    required this.dataSeason,
  });
}

LiveModel buildLive(List<MatchResult> ms, EloParams p, int currentSeason) {
  final d = _Prepared(ms);
  final sim = _simulate(d, p);
  final first = ms.first.season;
  final dl = <double>[];
  final ol = <int>[];
  for (var i = 0; i < d.n; i++) {
    if (d.season[i] == first) continue;
    dl.add(sim.diffs[i]);
    ol.add(d.outc[i]);
  }
  final draw = fitDrawModel(dl, ol);

  final ratings = <String, double>{};
  final lastDelta = <String, double>{};
  for (var t = 0; t < d.teams.length; t++) {
    ratings[d.teams[t]] = sim.ratings[t];
    lastDelta[d.teams[t]] = sim.lastDelta[t];
  }
  final lastSeason = ms.last.season;
  final seasonTeams = sim.lastSeasonTeams.map((t) => d.teams[t]).toList();
  final form = <String, List<String>>{};
  var baseline = sim.baselineEnd;

  if (currentSeason > lastSeason) {
    // La nuova stagione non è ancora nei dati: applico il passaggio di stagione.
    for (final t in seasonTeams) {
      ratings[t] = 1500 + (ratings[t]! - 1500) * (1 - p.regress);
      lastDelta[t] = 0;
    }
    baseline = 1500 + (baseline - 1500) * (1 - p.regress);
  } else {
    for (final m in ms) {
      if (m.season != lastSeason) continue;
      final o = m.outcome;
      (form[m.home] ??= []).add(o == 0 ? 'V' : (o == 1 ? 'N' : 'P'));
      (form[m.away] ??= []).add(o == 2 ? 'V' : (o == 1 ? 'N' : 'P'));
    }
    form.updateAll((k, v) => v.length > 5 ? v.sublist(v.length - 5) : v);
  }

  return LiveModel(
    ratings: ratings,
    lastDelta: lastDelta,
    form: form,
    seasonTeams: seasonTeams,
    draw: draw,
    params: p,
    baseline: baseline,
    dataSeason: lastSeason,
  );
}

/// Risultato della verifica sul passato.
class BacktestResult {
  final int bets;
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
  final int trainFrom;
  final int trainTo;
  final int testFrom;
  final int testTo;
  final String? error;

  BacktestResult({
    required this.bets,
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
    required this.trainFrom,
    required this.trainTo,
    required this.testFrom,
    required this.testTo,
    this.error,
  });

  factory BacktestResult.failed(String msg) => BacktestResult(
        bets: 0,
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

/// Simula di aver usato il modello sulle ultime [testSeasons] stagioni
/// complete, calibrandolo solo sulle stagioni precedenti.
BacktestResult backtest(List<MatchResult> ms, int testSeasons, double threshold,
    double stake, double budget) {
  final counts = <int, int>{};
  for (final m in ms) {
    counts[m.season] = (counts[m.season] ?? 0) + 1;
  }
  final complete = counts.keys.where((s) => counts[s]! >= 370).toList()..sort();
  if (complete.length < testSeasons + 3) {
    return BacktestResult.failed(
        'Servono almeno ${testSeasons + 3} stagioni complete: aggiorna i dati.');
  }
  final test = complete.sublist(complete.length - testSeasons);
  final testFrom = test.first, testTo = test.last;
  final train = ms.where((m) => m.season < testFrom).toList();
  final params = calibrate(train);

  final upto = ms.where((m) => m.season <= testTo).toList();
  final d = _Prepared(upto);
  final sim = _simulate(d, params);
  final first = upto.first.season;

  final dl = <double>[];
  final ol = <int>[];
  for (var i = 0; i < d.n; i++) {
    if (d.season[i] == first || d.season[i] >= testFrom) continue;
    dl.add(sim.diffs[i]);
    ol.add(d.outc[i]);
  }
  final draw = fitDrawModel(dl, ol);

  var bets = 0;
  var staked = 0.0, profit = 0.0;
  final returns = <double>[];
  var clvChecked = 0, clvBeaten = 0;
  var llModel = 0.0, llBook = 0.0;
  var nLl = 0;
  var nTest = 0;
  final bankroll = <double>[budget];
  final dates = <DateTime>[];

  for (var i = 0; i < d.n; i++) {
    if (d.season[i] < testFrom) continue;
    final m = upto[i];
    nTest++;
    final p = draw.probs(sim.diffs[i]);
    final o = m.outcome;
    final ref = m.closing ?? m.odds;
    if (ref != null) {
      llModel += -math.log(math.max(p[o], 1e-9));
      llBook += -math.log(math.max(fairProbs(ref)[o], 1e-9));
      nLl++;
    }
    final q = m.odds;
    if (q == null) continue;
    var pick = 0;
    var ev = p[0] * q[0];
    for (var k = 1; k < 3; k++) {
      if (p[k] * q[k] > ev) {
        ev = p[k] * q[k];
        pick = k;
      }
    }
    if (ev < threshold) continue;
    bets++;
    staked += stake;
    final won = pick == o;
    final r = won ? q[pick] - 1 : -1.0;
    returns.add(r);
    profit += stake * r;
    bankroll.add(budget + profit);
    dates.add(m.date);
    final c = m.closing;
    if (c != null) {
      clvChecked++;
      if (q[pick] > c[pick]) clvBeaten++;
    }
  }

  var margin = 0.0;
  if (returns.length > 1) {
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    var v = 0.0;
    for (final r in returns) {
      v += (r - mean) * (r - mean);
    }
    v /= (returns.length - 1);
    margin = 2 * math.sqrt(v) / math.sqrt(returns.length);
  }

  return BacktestResult(
    bets: bets,
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
    trainFrom: train.isEmpty ? 0 : train.first.season,
    trainTo: testFrom - 1,
    testFrom: testFrom,
    testTo: testTo,
  );
}
