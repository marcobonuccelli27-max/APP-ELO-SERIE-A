// Schedine: mercati, lettura del testo di una schedina e valutazione.

import 'dart:math' as math;

import 'data.dart' show matchTeam;

enum MarketType {
  esito,
  doppia,
  uo,
  ggng,
  esitoUo,
  doppiaUo,
  esitoGg,
  multigoalSquadre,
  multigoalTotale,
}

const marketNames = {
  MarketType.esito: 'Esito finale 1X2',
  MarketType.doppia: 'Doppia chance',
  MarketType.uo: 'Under/Over',
  MarketType.ggng: 'Goal/No goal',
  MarketType.esitoUo: '1X2 + Under/Over',
  MarketType.doppiaUo: 'Doppia chance + Under/Over',
  MarketType.esitoGg: '1X2 + Goal/No goal',
  MarketType.multigoalSquadre: 'Multigoal casa + ospite',
  MarketType.multigoalTotale: 'Multigoal partita',
};

bool usesS1(MarketType t) =>
    t == MarketType.esito ||
    t == MarketType.doppia ||
    t == MarketType.esitoUo ||
    t == MarketType.doppiaUo ||
    t == MarketType.esitoGg;

bool usesDoubleChance(MarketType t) => t == MarketType.doppia || t == MarketType.doppiaUo;

bool usesLine(MarketType t) => t == MarketType.uo || t == MarketType.esitoUo || t == MarketType.doppiaUo;

bool usesGg(MarketType t) => t == MarketType.ggng || t == MarketType.esitoGg;

bool usesRanges(MarketType t) => t == MarketType.multigoalSquadre || t == MarketType.multigoalTotale;

/// Una giocata della schedina.
class Leg {
  String home;
  String away;
  DateTime? date;
  MarketType type;
  String s1; // 1, X, 2 oppure 1X, X2, 12
  String s2; // O, U oppure GG, NG
  double line; // 0,5 1,5 2,5 …
  int h1, h2; // multigoal: gol della squadra di casa (o della partita), da … a …
  int a1, a2; // multigoal: gol dell'ospite
  bool yes; // multigoal: SI oppure NO
  double odds;
  bool homeKnown;
  bool awayKnown;
  bool marketGuessed; // mercato non letto con certezza

  Leg({
    this.home = '',
    this.away = '',
    this.date,
    this.type = MarketType.esito,
    this.s1 = '1',
    this.s2 = 'O',
    this.line = 2.5,
    this.h1 = 1,
    this.h2 = 3,
    this.a1 = 0,
    this.a2 = 3,
    this.yes = true,
    this.odds = 0,
    this.homeKnown = false,
    this.awayKnown = false,
    this.marketGuessed = false,
  });

  Leg copy() => Leg(
        home: home,
        away: away,
        date: date,
        type: type,
        s1: s1,
        s2: s2,
        line: line,
        h1: h1,
        h2: h2,
        a1: a1,
        a2: a2,
        yes: yes,
        odds: odds,
        homeKnown: homeKnown,
        awayKnown: awayKnown,
        marketGuessed: marketGuessed,
      );

  static String _outcome(int x, int y) => x > y ? '1' : (x == y ? 'X' : '2');

  /// Vero se il risultato x-y fa vincere la giocata.
  bool wins(int x, int y) {
    final t = x + y;
    final gg = x > 0 && y > 0;
    final s1ok = s1.contains(_outcome(x, y));
    final uoOk = s2 == 'O' ? t > line : t < line;
    final ggOk = s2 == 'GG' ? gg : !gg;
    final mgTeams = x >= h1 && x <= h2 && y >= a1 && y <= a2;
    final mgTotal = t >= h1 && t <= h2;
    return switch (type) {
      MarketType.esito || MarketType.doppia => s1ok,
      MarketType.uo => uoOk,
      MarketType.ggng => ggOk,
      MarketType.esitoUo || MarketType.doppiaUo => s1ok && uoOk,
      MarketType.esitoGg => s1ok && ggOk,
      MarketType.multigoalSquadre => yes ? mgTeams : !mgTeams,
      MarketType.multigoalTotale => yes ? mgTotal : !mgTotal,
    };
  }

  String get lineLabel => line.toStringAsFixed(1).replaceAll('.', ',');

  String get uoLabel => '${s2 == 'O' ? 'Over' : 'Under'} $lineLabel';

  String get ggLabel => s2 == 'GG' ? 'Goal' : 'No goal';

  /// Descrizione della giocata, per esempio "1 + Over 1,5".
  String get selectionLabel => switch (type) {
        MarketType.esito || MarketType.doppia => s1,
        MarketType.uo => uoLabel,
        MarketType.ggng => ggLabel,
        MarketType.esitoUo || MarketType.doppiaUo => '$s1 + $uoLabel',
        MarketType.esitoGg => '$s1 + $ggLabel',
        MarketType.multigoalSquadre => 'Casa $h1-$h2 gol, ospite $a1-$a2 gol${yes ? '' : ': NO'}',
        MarketType.multigoalTotale => 'Partita $h1-$h2 gol${yes ? '' : ': NO'}',
      };

  /// Vero se la giocata è sull'esito meno probabile: per l'1X2 il meno
  /// probabile dei tre, per gli altri mercati quando succede meno di una
  /// volta su due.
  bool isUnlikely(double p, List<double> p1x2) {
    if (type == MarketType.esito) {
      final k = s1 == '1' ? 0 : (s1 == 'X' ? 1 : 2);
      for (var j = 0; j < 3; j++) {
        if (j != k && p1x2[j] <= p1x2[k]) return false;
      }
      return true;
    }
    return p < 0.5;
  }
}

/// Testo di una schedina convertito in giocate.
class ParsedSlip {
  final List<Leg> legs;
  final double? stake;
  final double? bonus;
  final double? totalOdds;
  ParsedSlip(this.legs, this.stake, this.bonus, this.totalOdds);
}

// ---------------------------------------------------------------------------
// Lettura del testo

final _code = RegExp(r'\b\d{5}\s*[/ ]\s*\d{3,4}\b');
final _money = RegExp(r'(\d{1,4})\s*,\s*(\d{2})(?!\d)');
final _date = RegExp(r'\b(\d{1,2})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{2,4})\b');
final _time = RegExp(r'\b(\d{1,2})\s*[:.]\s*(\d{2})\b');
const _stopWords = ['IMPORTO', 'TOTALE', 'BONUS', 'VINCITA', 'PAGAMENTO', 'EURO', '€', 'POTENZIALE'];

String _normalize(String s) {
  var t = s.toUpperCase();
  const fix = {
    'U/0': 'U/O',
    'U /0': 'U/O',
    'U/ 0': 'U/O',
    '0VER': 'OVER',
    'UNDER/0VER': 'UNDER/OVER',
    'MULTIG0AL': 'MULTIGOAL',
    'MULTI GOAL': 'MULTIGOAL',
    'G0AL': 'GOAL',
    'ESIT0': 'ESITO',
    '–': '-',
    '—': '-',
  };
  fix.forEach((k, v) => t = t.replaceAll(k, v));
  return t;
}

double? _toDouble(Match m) => double.tryParse('${m.group(1)},${m.group(2)}'.replaceAll(',', '.'));

bool _isStopRow(String r) => _stopWords.any(r.contains);

/// Cerca due squadre conosciute separate da un trattino nella riga.
(String, String, String)? _findTeams(String row, List<String> known) {
  final dash = RegExp(r"([A-Z][A-Z'. ]{1,40}?)\s*-\s*([A-Z][A-Z'. ]{1,40})");
  for (final m in dash.allMatches(row)) {
    final leftWords = m.group(1)!.trim().split(RegExp(r'\s+'));
    final rightWords = m.group(2)!.trim().split(RegExp(r'\s+'));
    String? home, away;
    for (var n = math.min(3, leftWords.length); n >= 1 && home == null; n--) {
      home = matchTeam(leftWords.sublist(leftWords.length - n).join(' '), known);
    }
    for (var n = math.min(3, rightWords.length); n >= 1 && away == null; n--) {
      away = matchTeam(rightWords.sublist(0, n).join(' '), known);
    }
    if (home != null && away != null && home != away) return (home, away, m.group(0)!);
  }
  return null;
}

DateTime? _parseDate(String s) {
  final m = _date.firstMatch(s);
  if (m == null) return null;
  final d = int.tryParse(m.group(1)!), mo = int.tryParse(m.group(2)!);
  var y = int.tryParse(m.group(3)!);
  if (d == null || mo == null || y == null || d > 31 || mo > 12) return null;
  if (y < 100) y += 2000;
  var hh = 15, mm = 0;
  final rest = s.substring(m.end);
  final t = _time.firstMatch(rest);
  if (t != null) {
    hh = int.tryParse(t.group(1)!) ?? 15;
    mm = int.tryParse(t.group(2)!) ?? 0;
    if (hh > 23 || mm > 59) {
      hh = 15;
      mm = 0;
    }
  }
  return DateTime(y, mo, d, hh, mm);
}

/// Riconosce mercato e selezione dal testo di una giocata.
void _parseMarket(String text, Leg leg) {
  var r = ' ${_normalize(text)} ';

  // Multigoal casa + ospite, per esempio "MULTIGOAL 1-3 SQ 1 + 0-3 SQ 2 SI".
  final mgs = RegExp(r'MULTIGOAL\s*(\d)\s*-\s*(\d)\s*SQ\.?\s*1\s*\+\s*(\d)\s*-\s*(\d)\s*SQ\.?\s*2').firstMatch(r);
  if (mgs != null) {
    leg.type = MarketType.multigoalSquadre;
    leg.h1 = int.parse(mgs.group(1)!);
    leg.h2 = int.parse(mgs.group(2)!);
    leg.a1 = int.parse(mgs.group(3)!);
    leg.a2 = int.parse(mgs.group(4)!);
    leg.yes = !RegExp(r'\bNO\b').hasMatch(r.substring(mgs.end));
    return;
  }
  // Multigoal di una sola squadra.
  final mg1 = RegExp(r'MULTIGOAL\s*(\d)\s*-\s*(\d)\s*(?:SQ\.?\s*|SQUADRA\s*)([12])').firstMatch(r);
  if (mg1 != null) {
    leg.type = MarketType.multigoalSquadre;
    final lo = int.parse(mg1.group(1)!), hi = int.parse(mg1.group(2)!);
    if (mg1.group(3) == '1') {
      leg.h1 = lo;
      leg.h2 = hi;
      leg.a1 = 0;
      leg.a2 = 20;
    } else {
      leg.h1 = 0;
      leg.h2 = 20;
      leg.a1 = lo;
      leg.a2 = hi;
    }
    leg.yes = !RegExp(r'\bNO\b').hasMatch(r.substring(mg1.end));
    return;
  }
  // Multigoal della partita.
  final mgt = RegExp(r'MULTIGOAL\s*(\d)\s*-\s*(\d)').firstMatch(r);
  if (mgt != null) {
    leg.type = MarketType.multigoalTotale;
    leg.h1 = int.parse(mgt.group(1)!);
    leg.h2 = int.parse(mgt.group(2)!);
    leg.yes = !RegExp(r'\bNO\b').hasMatch(r.substring(mgt.end));
    return;
  }

  final lineRe = RegExp(r'(?:U\s*/\s*O|UNDER\s*/\s*OVER|UNDER\s*OVER|U\s*-\s*O)\s*(\d)\s*[.,]\s*5');
  final lm = lineRe.firstMatch(r);
  final has1x2 = RegExp(r'1\s*X\s*2|ESITO').hasMatch(r);
  final hasDc = RegExp(r'\bDC\b|DOPPIA').hasMatch(r);
  final hasGg = RegExp(r'GG\s*/\s*NG|GOAL\s*/\s*NO\s*GOAL|GOAL\s*NO\s*GOAL').hasMatch(r);
  if (lm != null) leg.line = int.parse(lm.group(1)!) + 0.5;

  // Tolgo i nomi dei mercati: resta la selezione.
  for (final re in [
    lineRe,
    RegExp(r'ESITO\s*FINALE'),
    RegExp(r'1\s*X\s*2'),
    RegExp(r'DC\s*IN'),
    RegExp(r'\bDC\b'),
    RegExp(r'DOPPIA\s*CHANCE'),
    RegExp(r'GG\s*/\s*NG'),
    RegExp(r'GOAL\s*/?\s*NO\s*GOAL'),
    RegExp(r'\bCALCIO\b|\bCICA\b|\bITA\s*1\b|\bITALIA\b|\bSERIE\s*A\b'),
  ]) {
    r = r.replaceAll(re, ' ');
  }

  final combo = RegExp(r'\b(1X|X2|12|1|X|2)\s*\+\s*(OVER|UNDER|NOGOAL|NO\s*GOAL|GOAL|GG|NG|O|U|0)\b').firstMatch(r);
  String? s1, s2;
  if (combo != null) {
    s1 = combo.group(1);
    final b = combo.group(2)!.replaceAll(' ', '');
    s2 = switch (b) {
      'OVER' || 'O' || '0' => 'O',
      'UNDER' || 'U' => 'U',
      'GG' || 'GOAL' => 'GG',
      _ => 'NG',
    };
  } else {
    s1 = RegExp(r'\b(1X|X2|12|1|X|2)\b').firstMatch(r)?.group(1);
    final uo = RegExp(r'\b(OVER|UNDER|O|U)\b').firstMatch(r)?.group(1);
    if (uo != null) s2 = uo.startsWith('O') ? 'O' : 'U';
    final gg = RegExp(r'\b(NOGOAL|NO\s*GOAL|GOAL|GG|NG)\b').firstMatch(r)?.group(1);
    if (gg != null) s2 = (gg == 'GG' || gg == 'GOAL') ? 'GG' : 'NG';
  }

  if ((has1x2 || hasDc) && lm != null) {
    leg.type = (hasDc || (s1 != null && s1.length == 2)) ? MarketType.doppiaUo : MarketType.esitoUo;
  } else if (has1x2 && hasGg) {
    leg.type = MarketType.esitoGg;
  } else if (hasDc) {
    leg.type = MarketType.doppia;
  } else if (lm != null) {
    leg.type = MarketType.uo;
  } else if (hasGg) {
    leg.type = MarketType.ggng;
  } else if (has1x2) {
    leg.type = MarketType.esito;
  } else {
    leg.marketGuessed = true;
    leg.type = (s1 != null && s1.length == 2) ? MarketType.doppia : MarketType.esito;
  }
  if (s1 != null) {
    if (usesDoubleChance(leg.type) && s1.length == 1) {
      leg.marketGuessed = true;
    } else if (!usesDoubleChance(leg.type) && s1.length == 2) {
      leg.type = leg.type == MarketType.esitoUo ? MarketType.doppiaUo : MarketType.doppia;
    }
    leg.s1 = s1;
  } else if (usesS1(leg.type)) {
    leg.marketGuessed = true;
  }
  if (s2 != null) {
    leg.s2 = s2;
  } else if (usesLine(leg.type) || usesGg(leg.type)) {
    leg.marketGuessed = true;
  }
  if (usesGg(leg.type) && leg.s2 != 'GG' && leg.s2 != 'NG') leg.s2 = 'GG';
  if (usesLine(leg.type) && leg.s2 != 'O' && leg.s2 != 'U') leg.s2 = 'O';
}

/// Converte le righe lette dalla foto in giocate.
ParsedSlip parseSlip(List<String> rawRows, List<String> known) {
  final rows = rawRows.map(_normalize).toList();

  // Inizio di ogni giocata: il codice ADM dell'avvenimento oppure due squadre.
  final starts = <int>[];
  final teamsAt = <int, (String, String, String)>{};
  for (var i = 0; i < rows.length; i++) {
    final t = _findTeams(rows[i], known);
    if (t != null) teamsAt[i] = t;
  }
  for (var i = 0; i < rows.length; i++) {
    if (_code.hasMatch(rows[i]) && !_isStopRow(rows[i])) {
      // Il codice vale se una squadra compare in questa riga o nelle due dopo.
      if (teamsAt.containsKey(i) || teamsAt.containsKey(i + 1) || teamsAt.containsKey(i + 2)) {
        starts.add(i);
      }
    }
  }
  if (starts.isEmpty) {
    starts.addAll(teamsAt.keys.toList()..sort());
  } else {
    // Squadre trovate fuori dai blocchi con codice: nuove giocate anche loro.
    for (final i in teamsAt.keys) {
      final covered = starts.any((s) => i >= s && i <= s + 2);
      if (!covered) starts.add(i);
    }
    starts.sort();
  }

  final legs = <Leg>[];
  for (var k = 0; k < starts.length; k++) {
    final from = starts[k];
    var to = k + 1 < starts.length ? starts[k + 1] : rows.length;
    for (var i = from + 1; i < to; i++) {
      if (_isStopRow(rows[i])) {
        to = i;
        break;
      }
    }
    final seg = rows.sublist(from, to);
    (String, String, String)? teams;
    var teamRow = -1;
    for (var j = 0; j < math.min(3, seg.length); j++) {
      teams = teamsAt[from + j];
      if (teams != null) {
        teamRow = j;
        break;
      }
    }
    if (teams == null) continue;

    final leg = Leg(home: teams.$1, away: teams.$2, homeKnown: true, awayKnown: true);
    var text = seg.join('  ');
    leg.date = _parseDate(text);

    // La quota è l'ultimo numero con la virgola della giocata.
    double? odds;
    String? oddsStr;
    for (final m in _money.allMatches(text)) {
      final v = _toDouble(m);
      if (v != null && v >= 1.01 && v <= 999) {
        odds = v;
        oddsStr = m.group(0);
      }
    }
    leg.odds = odds ?? 0;

    // Pulizia prima di leggere il mercato.
    var rest = text;
    if (teamRow >= 0) rest = rest.replaceFirst(teams.$3, ' ');
    rest = rest.replaceAll(_code, ' ').replaceAll(RegExp(r'\(\s*\d+\s*\)'), ' ');
    rest = rest.replaceAll(_date, ' ').replaceAll(_time, ' ');
    if (oddsStr != null) {
      final idx = rest.lastIndexOf(oddsStr);
      if (idx >= 0) rest = rest.replaceRange(idx, idx + oddsStr.length, ' ');
    }
    _parseMarket(rest, leg);
    legs.add(leg);
  }

  double? findMoney(bool Function(String) rowTest) {
    for (final r in rows) {
      if (!rowTest(r)) continue;
      final m = _money.firstMatch(r);
      if (m != null) return _toDouble(m);
    }
    return null;
  }

  final stake = findMoney((r) => r.contains('IMPORTO')) ??
      findMoney((r) =>
          r.contains('€') &&
          !r.contains('VINCITA') &&
          !r.contains('BONUS') &&
          !r.contains('PAGAMENTO') &&
          !r.contains('TOTALE'));
  final bonus = findMoney((r) => r.contains('BONUS'));
  return ParsedSlip(legs, stake, bonus, null);
}

// ---------------------------------------------------------------------------
// Valutazione

class LegResult {
  final Leg leg;
  final double? p; // probabilità secondo il modello
  final List<double>? p1x2;
  final String? score; // risultato vero, se la partita è già stata giocata
  final bool? won;
  LegResult(this.leg, this.p, this.p1x2, this.score, this.won);

  double? get value => p == null || leg.odds <= 1 ? null : p! * leg.odds;
  bool get unlikely => p != null && p1x2 != null && leg.isUnlikely(p!, p1x2!);
}

class SlipAnalysis {
  final List<LegResult> legs;
  final double stake;
  final double bonus;
  final String fitNote;
  SlipAnalysis(this.legs, this.stake, this.bonus, this.fitNote);

  bool get complete => legs.isNotEmpty && legs.every((l) => l.p != null && l.leg.odds > 1);

  double get totalOdds => legs.fold(1.0, (a, l) => a * (l.leg.odds > 1 ? l.leg.odds : 1));

  double get modelProb => legs.fold(1.0, (a, l) => a * (l.p ?? 0));

  double get impliedProb => 1 / totalOdds;

  double get payout => stake * totalOdds + bonus;

  /// Quanto torna in media ogni euro giocato, secondo il modello.
  double get expectedReturn => stake <= 0 ? 0 : modelProb * payout / stake;

  bool? get won {
    if (legs.any((l) => l.won == false)) return false;
    if (legs.every((l) => l.won == true)) return true;
    return null;
  }
}

// ---------------------------------------------------------------------------
// Storico delle schedine salvate

Map<String, dynamic> legToJson(Leg l) => {
      'home': l.home,
      'away': l.away,
      'date': l.date?.toIso8601String(),
      'type': l.type.name,
      's1': l.s1,
      's2': l.s2,
      'line': l.line,
      'h1': l.h1,
      'h2': l.h2,
      'a1': l.a1,
      'a2': l.a2,
      'yes': l.yes,
      'odds': l.odds,
    };

Leg legFromJson(Map<String, dynamic> j) => Leg(
      home: j['home'] as String? ?? '',
      away: j['away'] as String? ?? '',
      date: j['date'] == null ? null : DateTime.tryParse(j['date'] as String),
      type: MarketType.values.firstWhere((t) => t.name == j['type'], orElse: () => MarketType.esito),
      s1: j['s1'] as String? ?? '1',
      s2: j['s2'] as String? ?? 'O',
      line: (j['line'] as num?)?.toDouble() ?? 2.5,
      h1: j['h1'] as int? ?? 1,
      h2: j['h2'] as int? ?? 3,
      a1: j['a1'] as int? ?? 0,
      a2: j['a2'] as int? ?? 3,
      yes: j['yes'] as bool? ?? true,
      odds: (j['odds'] as num?)?.toDouble() ?? 0,
      homeKnown: true,
      awayKnown: true,
    );

enum SlipStatus { pending, won, lost }

class SavedSlip {
  final String id;
  final DateTime savedAt;
  final List<Leg> legs;
  final double stake;
  final double bonus;
  final double? modelProb; // probabilità di vincerla secondo il modello
  final double? expectedReturn; // ritorno medio per euro secondo il modello
  bool inCalendar;

  SavedSlip({
    required this.id,
    required this.savedAt,
    required this.legs,
    required this.stake,
    required this.bonus,
    this.modelProb,
    this.expectedReturn,
    this.inCalendar = false,
  });

  double get totalOdds => legs.fold(1.0, (a, l) => a * (l.odds > 1 ? l.odds : 1));

  double get payout => stake * totalOdds + bonus;

  DateTime? get firstDate {
    DateTime? d;
    for (final l in legs) {
      final x = l.date;
      if (x != null && (d == null || x.isBefore(d))) d = x;
    }
    return d;
  }

  DateTime? get lastDate {
    DateTime? d;
    for (final l in legs) {
      final x = l.date;
      if (x != null && (d == null || x.isAfter(d))) d = x;
    }
    return d;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'savedAt': savedAt.toIso8601String(),
        'legs': legs.map(legToJson).toList(),
        'stake': stake,
        'bonus': bonus,
        'modelProb': modelProb,
        'expectedReturn': expectedReturn,
        'inCalendar': inCalendar,
      };

  factory SavedSlip.fromJson(Map<String, dynamic> j) => SavedSlip(
        id: j['id'] as String,
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
        legs: (j['legs'] as List<dynamic>).map((e) => legFromJson(e as Map<String, dynamic>)).toList(),
        stake: (j['stake'] as num?)?.toDouble() ?? 0,
        bonus: (j['bonus'] as num?)?.toDouble() ?? 0,
        modelProb: (j['modelProb'] as num?)?.toDouble(),
        expectedReturn: (j['expectedReturn'] as num?)?.toDouble(),
        inCalendar: j['inCalendar'] as bool? ?? false,
      );
}
