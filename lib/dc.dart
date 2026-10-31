// Modello Dixon-Coles: stima per ogni squadra una forza d'attacco e una di
// difesa dai gol segnati e subiti, dando più peso alle partite recenti.
// Da queste ricava la probabilità di ogni risultato esatto, e quindi 1X2,
// over/under 2,5 e goal/no goal. Puro calcolo, gira in un isolate.

import 'dart:math' as math;
import 'dart:typed_data';

import 'elo.dart' show MatchResult;

/// Emivite provate dalla calibrazione automatica, in giorni.
const List<double> dcHalfLives = [60, 120, 180, 270, 365, 540];

const double dcDefaultHalfLife = 180;

/// Probabilità ricavate dal modello per una partita.
class DcProbs {
  final List<double> p; // 1, X, 2
  final double over25;
  final double gg; // entrambe segnano
  final double lambda; // gol attesi della squadra di casa
  final double mu; // gol attesi dell'ospite
  DcProbs(this.p, this.over25, this.gg, this.lambda, this.mu);
}

/// Il modello stimato a una certa data.
class DcFit {
  final Map<String, double> att; // 1 = attacco nella media
  final Map<String, double> def; // 1 = difesa nella media; più basso è meglio
  final double g; // gol medi di base
  final double h; // vantaggio casa (moltiplicatore)
  final double rho; // correzione per i risultati bassi
  final double promotedAtt;
  final double promotedDef;

  DcFit(this.att, this.def, this.g, this.h, this.rho, this.promotedAtt, this.promotedDef);

  bool knows(String team) => att.containsKey(team);

  /// Gol segnati e subiti a partita contro una squadra media, in campo neutro.
  double goalsFor(String t) => g * math.sqrt(h) * (att[t] ?? promotedAtt);
  double goalsAgainst(String t) => g * math.sqrt(h) * (def[t] ?? promotedDef);

  DcProbs predict(String home, String away) {
    final lam = g * h * (att[home] ?? promotedAtt) * (def[away] ?? promotedDef);
    final mu = g * (att[away] ?? promotedAtt) * (def[home] ?? promotedDef);
    return scoreProbs(lam, mu, rho);
  }

  /// Probabilità di ogni risultato esatto: [gol casa][gol ospite], da 0 a 10.
  List<List<double>> scoreMatrix(String home, String away) {
    final lam = g * h * (att[home] ?? promotedAtt) * (def[away] ?? promotedDef);
    final mu = g * (att[away] ?? promotedAtt) * (def[home] ?? promotedDef);
    const n = 10;
    final ph = _poisson(lam, n), pa = _poisson(mu, n);
    final m = List.generate(n + 1, (_) => List<double>.filled(n + 1, 0));
    var tot = 0.0;
    for (var x = 0; x <= n; x++) {
      for (var y = 0; y <= n; y++) {
        final v = math.max(_tau(x, y, lam, mu, rho), 1e-6) * ph[x] * pa[y];
        m[x][y] = v;
        tot += v;
      }
    }
    for (final row in m) {
      for (var y = 0; y <= n; y++) {
        row[y] /= tot;
      }
    }
    return m;
  }
}

double _tau(int x, int y, double lam, double mu, double rho) {
  if (x == 0 && y == 0) return 1 - lam * mu * rho;
  if (x == 0 && y == 1) return 1 + lam * rho;
  if (x == 1 && y == 0) return 1 + mu * rho;
  if (x == 1 && y == 1) return 1 - rho;
  return 1;
}

List<double> _poisson(double l, int n) {
  final out = List<double>.filled(n + 1, 0);
  out[0] = math.exp(-l);
  for (var k = 1; k <= n; k++) {
    out[k] = out[k - 1] * l / k;
  }
  return out;
}

/// Probabilità di 1X2, over 2,5 e goal da gol attesi e correzione [rho].
DcProbs scoreProbs(double lam, double mu, double rho) {
  const n = 10;
  final ph = _poisson(lam, n), pa = _poisson(mu, n);
  var p1 = 0.0, px = 0.0, p2 = 0.0, over = 0.0, gg = 0.0, tot = 0.0;
  for (var x = 0; x <= n; x++) {
    for (var y = 0; y <= n; y++) {
      final v = math.max(_tau(x, y, lam, mu, rho), 1e-6) * ph[x] * pa[y];
      tot += v;
      if (x > y) {
        p1 += v;
      } else if (x == y) {
        px += v;
      } else {
        p2 += v;
      }
      if (x + y >= 3) over += v;
      if (x > 0 && y > 0) gg += v;
    }
  }
  return DcProbs([p1 / tot, px / tot, p2 / tot], over / tot, gg / tot, lam, mu);
}

// ---------------------------------------------------------------------------
// Dati in forma numerica

class DcData {
  final List<String> teams;
  final Int32List h, a, hg, ag, day, season, outc;
  int get n => h.length;

  DcData._(this.teams, this.h, this.a, this.hg, this.ag, this.day, this.season, this.outc);

  factory DcData(List<MatchResult> ms) {
    final ids = <String, int>{};
    final n = ms.length;
    final h = Int32List(n), a = Int32List(n), hg = Int32List(n), ag = Int32List(n);
    final day = Int32List(n), season = Int32List(n), outc = Int32List(n);
    for (var i = 0; i < n; i++) {
      final m = ms[i];
      h[i] = ids.putIfAbsent(m.home, () => ids.length);
      a[i] = ids.putIfAbsent(m.away, () => ids.length);
      hg[i] = m.hg;
      ag[i] = m.ag;
      day[i] = m.date.millisecondsSinceEpoch ~/ 86400000;
      season[i] = m.season;
      outc[i] = m.outcome;
    }
    final teams = List<String>.filled(ids.length, '');
    ids.forEach((k, v) => teams[v] = k);
    return DcData._(teams, h, a, hg, ag, day, season, outc);
  }
}

/// Modello stimato in forma numerica (per id di squadra).
class _NumFit {
  final Float64List att, def;
  final List<bool> known;
  final double g, h, rho, pAtt, pDef;
  _NumFit(this.att, this.def, this.known, this.g, this.h, this.rho, this.pAtt, this.pDef);

  DcProbs predict(int home, int away) {
    final ah = known[home] ? att[home] : pAtt, dh = known[home] ? def[home] : pDef;
    final aa = known[away] ? att[away] : pAtt, da = known[away] ? def[away] : pDef;
    return scoreProbs(g * h * ah * da, g * aa * dh, rho);
  }
}

/// Stima il modello con le partite di indice minore di [end],
/// pesate in base a quanto sono vecchie rispetto al giorno [refDay].
_NumFit _fit(DcData d, int end, int refDay, double halfLife) {
  final nt = d.teams.length;
  // Partite degli ultimi 4 "mezzi pesi" (oltre contano meno del 6%),
  // al massimo circa cinque stagioni, per tenere veloce il calcolo.
  final minDay = refDay - (4 * halfLife).round();
  var start = end;
  while (start > 0 && end - start < 1900 && d.day[start - 1] >= minDay) {
    start--;
  }
  final idx = <int>[];
  final w = <double>[];
  for (var i = start; i < end; i++) {
    idx.add(i);
    w.add(math.pow(0.5, (refDay - d.day[i]) / halfLife).toDouble());
  }

  final known = List<bool>.filled(nt, false);
  for (final i in idx) {
    known[d.h[i]] = true;
    known[d.a[i]] = true;
  }
  if (idx.length < 60) {
    return _NumFit(Float64List(nt)..fillRange(0, nt, 1), Float64List(nt)..fillRange(0, nt, 1), known, 1.35,
        1.3, -0.05, 0.85, 1.15);
  }

  // Neopromosse: squadre dell'ultima stagione che non c'erano in quella prima.
  final lastSeason = d.season[end - 1];
  final inLast = List<bool>.filled(nt, false), inPrev = List<bool>.filled(nt, false);
  for (final i in idx) {
    final s = d.season[i];
    if (s == lastSeason) {
      inLast[d.h[i]] = true;
      inLast[d.a[i]] = true;
    } else if (s == lastSeason - 1) {
      inPrev[d.h[i]] = true;
      inPrev[d.a[i]] = true;
    }
  }
  final promoted = List<bool>.generate(nt, (t) => inLast[t] && !inPrev[t]);
  final hasPrev = inPrev.any((x) => x);

  final att = Float64List(nt)..fillRange(0, nt, 1);
  final def = Float64List(nt)..fillRange(0, nt, 1);
  final priorA = Float64List(nt)..fillRange(0, nt, 1);
  final priorD = Float64List(nt)..fillRange(0, nt, 1);
  var sw = 0.0, shg = 0.0, sag = 0.0;
  for (var k = 0; k < idx.length; k++) {
    sw += w[k];
    shg += w[k] * d.hg[idx[k]];
    sag += w[k] * d.ag[idx[k]];
  }
  var g = (shg + sag) / (2 * sw);
  var hAdv = sag > 0 ? shg / sag : 1.3;
  const shrink = 3.0;

  final numA = Float64List(nt), denA = Float64List(nt);
  final numD = Float64List(nt), denD = Float64List(nt);

  void iterate(int times) {
    for (var it = 0; it < times; it++) {
      numA.fillRange(0, nt, 0);
      denA.fillRange(0, nt, 0);
      for (var k = 0; k < idx.length; k++) {
        final i = idx[k], hh = d.h[i], aa = d.a[i], wk = w[k];
        numA[hh] += wk * d.hg[i];
        denA[hh] += wk * g * hAdv * def[aa];
        numA[aa] += wk * d.ag[i];
        denA[aa] += wk * g * def[hh];
      }
      for (var t = 0; t < nt; t++) {
        if (known[t]) att[t] = (numA[t] + shrink * priorA[t]) / (denA[t] + shrink);
      }
      numD.fillRange(0, nt, 0);
      denD.fillRange(0, nt, 0);
      for (var k = 0; k < idx.length; k++) {
        final i = idx[k], hh = d.h[i], aa = d.a[i], wk = w[k];
        numD[hh] += wk * d.ag[i];
        denD[hh] += wk * g * att[aa];
        numD[aa] += wk * d.hg[i];
        denD[aa] += wk * g * hAdv * att[hh];
      }
      for (var t = 0; t < nt; t++) {
        if (known[t]) def[t] = (numD[t] + shrink * priorD[t]) / (denD[t] + shrink);
      }
      var eh = 0.0, all = 0.0;
      for (var k = 0; k < idx.length; k++) {
        final i = idx[k], hh = d.h[i], aa = d.a[i], wk = w[k];
        eh += wk * g * att[hh] * def[aa];
        all += wk * (hAdv * att[hh] * def[aa] + att[aa] * def[hh]);
      }
      hAdv = shg / eh;
      g = (shg + sag) / all;
      // Media geometrica di attacco e difesa a 1.
      var la = 0.0, ld = 0.0, c = 0;
      for (var t = 0; t < nt; t++) {
        if (!known[t]) continue;
        la += math.log(att[t]);
        ld += math.log(def[t]);
        c++;
      }
      final ma = math.exp(la / c), md = math.exp(ld / c);
      for (var t = 0; t < nt; t++) {
        if (!known[t]) continue;
        att[t] /= ma;
        def[t] /= md;
      }
      g *= ma * md;
    }
  }

  iterate(25);

  // Le neopromosse partono dal livello medio delle tre più deboli.
  var pAtt = 0.85, pDef = 1.15;
  final ranked = [
    for (var t = 0; t < nt; t++)
      if (known[t] && !promoted[t]) t
  ]..sort((x, y) => (att[x] / def[x]).compareTo(att[y] / def[y]));
  if (ranked.length >= 3) {
    pAtt = (att[ranked[0]] + att[ranked[1]] + att[ranked[2]]) / 3;
    pDef = (def[ranked[0]] + def[ranked[1]] + def[ranked[2]]) / 3;
  }
  if (hasPrev) {
    for (var t = 0; t < nt; t++) {
      if (promoted[t]) {
        priorA[t] = pAtt;
        priorD[t] = pDef;
      }
    }
    iterate(15);
  }

  // Correzione per i risultati bassi (0-0, 1-0, 0-1, 1-1).
  var bestRho = 0.0, bestLl = -double.infinity;
  for (var r = -0.20; r <= 0.101; r += 0.01) {
    var ll = 0.0;
    for (var k = 0; k < idx.length; k++) {
      final i = idx[k];
      final x = d.hg[i], y = d.ag[i];
      if (x > 1 || y > 1) continue;
      final lam = g * hAdv * att[d.h[i]] * def[d.a[i]];
      final mu = g * att[d.a[i]] * def[d.h[i]];
      ll += w[k] * math.log(math.max(_tau(x, y, lam, mu, r), 1e-6));
    }
    if (ll > bestLl) {
      bestLl = ll;
      bestRho = r;
    }
  }

  return _NumFit(att, def, known, g, hAdv, bestRho, pAtt, pDef);
}

/// Probabilità di ogni partita da [from] a [to] (esclusa), stimando il modello
/// di nuovo ogni 3 giorni con le sole partite già giocate.
List<DcProbs> rollingProbs(DcData d, int from, int to, double halfLife) {
  final out = <DcProbs>[];
  _NumFit? fit;
  var lastFit = -1 << 30;
  for (var i = from; i < to; i++) {
    if (fit == null || d.day[i] - lastFit >= 3) {
      fit = _fit(d, i, d.day[i], halfLife);
      lastFit = d.day[i];
    }
    out.add(fit.predict(d.h[i], d.a[i]));
  }
  return out;
}

double _logLoss(DcData d, int from, List<DcProbs> probs, {double recentHalf = 0, int refSeason = 0}) {
  var s = 0.0, w = 0.0;
  for (var k = 0; k < probs.length; k++) {
    final wk = recentHalf > 0 ? math.pow(0.5, (refSeason - d.season[from + k]) / recentHalf).toDouble() : 1.0;
    s += wk * -math.log(math.max(probs[k].p[d.outc[from + k]], 1e-9));
    w += wk;
  }
  return probs.isEmpty || w == 0 ? 1e9 : s / w;
}

/// Sceglie l'emivita che prevede meglio le stagioni da [from] a [to]
/// (al massimo le ultime tre, per non rendere il calcolo troppo lungo).
double calibrateDc(List<MatchResult> ms, {int from = 0, int to = 1 << 30, double recentHalf = 0}) {
  final sub = ms.where((m) => m.season <= to).toList();
  if (sub.isEmpty) return dcDefaultHalfLife;
  final d = DcData(sub);
  final first = sub.first.season;
  final seasons = sub.map((m) => m.season).toSet().where((s) => s >= from && s > first + 1).toList()..sort();
  if (seasons.isEmpty) return dcDefaultHalfLife;
  final evalFrom = seasons.length > 3 ? seasons[seasons.length - 3] : seasons.first;
  var a = 0;
  while (a < d.n && d.season[a] < evalFrom) {
    a++;
  }
  final b = d.n;
  if (b - a < 200) return dcDefaultHalfLife;
  var best = dcDefaultHalfLife, bestLl = double.infinity;
  for (final hl in dcHalfLives) {
    final ll = _logLoss(d, a, rollingProbs(d, a, b, hl), recentHalf: recentHalf, refSeason: sub.last.season);
    if (ll < bestLl) {
      bestLl = ll;
      best = hl;
    }
  }
  return best;
}

/// Modello stimato con tutte le partite, pronto per le prossime.
DcFit fitDcNow(List<MatchResult> ms, double halfLife, {int? untilSeason, DateTime? before}) {
  final sub = ms
      .where((m) => (untilSeason == null || m.season <= untilSeason) && (before == null || m.date.isBefore(before)))
      .toList();
  final d = DcData(sub);
  final refDay = d.n == 0 ? 0 : d.day[d.n - 1] + 1;
  final f = _fit(d, d.n, refDay, halfLife);
  final att = <String, double>{}, def = <String, double>{};
  for (var t = 0; t < d.teams.length; t++) {
    if (!f.known[t]) continue;
    att[d.teams[t]] = f.att[t];
    def[d.teams[t]] = f.def[t];
  }
  return DcFit(att, def, f.g, f.h, f.rho, f.pAtt, f.pDef);
}
