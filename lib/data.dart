// Scarico e lettura dei dati: risultati storici, partite in arrivo e quote.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'elo.dart';

/// Prima stagione scaricata (2005/06): circa 20 stagioni di storico.
const int firstSeason = 2005;

int currentSeasonStart(DateTime now) => now.month >= 7 ? now.year : now.year - 1;

String seasonCode(int s) =>
    '${(s % 100).toString().padLeft(2, '0')}${((s + 1) % 100).toString().padLeft(2, '0')}';

String seasonLabel(int s) => '$s/${((s + 1) % 100).toString().padLeft(2, '0')}';

/// Una partita in arrivo, con le quote di ogni bookmaker.
class Fixture {
  final DateTime? date;
  final String home;
  final String away;
  final Map<String, List<double>> books; // bookmaker -> [1, X, 2]

  Fixture({required this.date, required this.home, required this.away, required this.books});
}

class OddsFetch {
  final List<Fixture> fixtures;
  final int? remaining; // richieste rimaste (solo The Odds API)
  OddsFetch(this.fixtures, this.remaining);
}

class DataException implements Exception {
  final String message;
  DataException(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Lettura CSV

List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  for (var line in const LineSplitter().convert(text)) {
    line = line.replaceAll('\r', '');
    if (line.trim().isEmpty) continue;
    final cells = <String>[];
    final sb = StringBuffer();
    var inQ = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQ = !inQ;
      } else if (c == ',' && !inQ) {
        cells.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    cells.add(sb.toString().trim());
    rows.add(cells);
  }
  return rows;
}

class _Row {
  final Map<String, int> idx;
  final List<String> cells;
  _Row(this.idx, this.cells);

  String? s(String col) {
    final i = idx[col];
    if (i == null || i >= cells.length) return null;
    final v = cells[i];
    return v.isEmpty ? null : v;
  }

  int? i(String col) => int.tryParse(s(col) ?? '');

  double? d(String col) => double.tryParse(s(col) ?? '');

  /// Tre quote valide (tutte maggiori di 1), oppure null.
  List<double>? odds(String a, String b, String c) {
    final x = d(a), y = d(b), z = d(c);
    if (x == null || y == null || z == null) return null;
    if (x <= 1 || y <= 1 || z <= 1) return null;
    return [x, y, z];
  }
}

Map<String, int> _header(List<String> h) {
  final m = <String, int>{};
  for (var i = 0; i < h.length; i++) {
    var k = h[i].trim();
    if (i == 0) k = k.replaceAll('\uFEFF', ''); // BOM
    m.putIfAbsent(k, () => i);
  }
  return m;
}

DateTime? parseFdDate(String? s, [String? time]) {
  if (s == null) return null;
  final p = s.split('/');
  if (p.length != 3) return null;
  final d = int.tryParse(p[0]), mo = int.tryParse(p[1]);
  var y = int.tryParse(p[2]);
  if (d == null || mo == null || y == null) return null;
  if (y < 100) y += 2000;
  var hh = 15, mm = 0;
  if (time != null && time.contains(':')) {
    final t = time.split(':');
    hh = int.tryParse(t[0]) ?? 15;
    mm = int.tryParse(t[1]) ?? 0;
  }
  // Gli orari di football-data sono in ora del Regno Unito: in Italia è un'ora in più.
  return DateTime(y, mo, d, hh, mm).add(const Duration(hours: 1));
}

List<MatchResult> parseSeason(String text, int season) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return [];
  final idx = _header(rows.first);
  final out = <MatchResult>[];
  for (final cells in rows.skip(1)) {
    final r = _Row(idx, cells);
    final home = r.s('HomeTeam'), away = r.s('AwayTeam');
    final hg = r.i('FTHG'), ag = r.i('FTAG');
    final date = parseFdDate(r.s('Date'), r.s('Time'));
    if (home == null || away == null || hg == null || ag == null || date == null) continue;
    final odds = r.odds('B365H', 'B365D', 'B365A') ??
        r.odds('AvgH', 'AvgD', 'AvgA') ??
        r.odds('BbAvH', 'BbAvD', 'BbAvA') ??
        r.odds('PSH', 'PSD', 'PSA');
    final closing = r.odds('PSCH', 'PSCD', 'PSCA') ??
        r.odds('B365CH', 'B365CD', 'B365CA') ??
        r.odds('AvgCH', 'AvgCD', 'AvgCA');
    out.add(MatchResult(
      season: season,
      date: date,
      home: home,
      away: away,
      hg: hg,
      ag: ag,
      odds: odds,
      closing: closing,
    ));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

// ---------------------------------------------------------------------------
// Bookmaker presenti nei file di football-data

const Map<String, String> _fdBooks = {
  'B365': 'Bet365',
  'BW': 'Bwin',
  'BF': 'Betfair',
  'WH': 'William Hill',
  'PS': 'Pinnacle',
  '1XB': '1xBet',
  'IW': 'Interwetten',
  'LB': 'Ladbrokes',
  'VC': 'Bet Victor',
};

// ---------------------------------------------------------------------------
// Abbinamento dei nomi delle squadre tra fonti diverse

const _stop = {
  'fc', 'ac', 'as', 'ssc', 'bc', 'us', 'calcio', 'cfc', 'afc', 'acf', 'sc', 'ss',
  'usc', 'spa', 'srl', 'club', '1907', '1909', '1913', '1919', '1910', '1905',
};

const _alias = {
  'internazionale': 'inter',
  'inter milan': 'inter',
  'inter milano': 'inter',
  'hellas verona': 'verona',
  'chievo verona': 'chievo',
  'parma calcio': 'parma',
};

String _norm(String s) {
  var t = s.toLowerCase();
  const acc = {'à': 'a', 'á': 'a', 'è': 'e', 'é': 'e', 'ì': 'i', 'í': 'i', 'ò': 'o', 'ó': 'o', 'ù': 'u', 'ú': 'u'};
  acc.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !_stop.contains(w));
  t = words.join(' ');
  return _alias[t] ?? t;
}

/// Trova il nome di football-data che corrisponde a [name], se c'è.
String? matchTeam(String name, Iterable<String> known) {
  final n = _norm(name);
  final list = known.toList();
  for (final k in list) {
    if (_norm(k) == n) return k;
  }
  for (final k in list) {
    final kn = _norm(k);
    if (kn.isEmpty) continue;
    if (' $n '.contains(' $kn ') || ' $kn '.contains(' $n ')) return k;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Scarico e memoria locale

class DataRepo {
  static const _base = 'https://www.football-data.co.uk/mmz4281';

  Future<Directory> _dir() => getApplicationDocumentsDirectory();

  Future<String?> _get(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Carica tutte le stagioni. Le vecchie restano salvate sul telefono;
  /// la stagione in corso e quella precedente vengono riscaricate.
  /// Con [offline] usa solo quello che è già salvato.
  Future<List<MatchResult>> loadHistory({
    required int currentSeason,
    required void Function(String) onProgress,
    bool offline = false,
  }) async {
    final dir = await _dir();
    final all = <MatchResult>[];
    var downloaded = 0, failed = 0;
    for (var s = firstSeason; s <= currentSeason; s++) {
      final file = File('${dir.path}/I1_${seasonCode(s)}.csv');
      final recent = s >= currentSeason - 1;
      String? text;
      if (!offline && (recent || !await file.exists())) {
        onProgress('Scarico la stagione ${seasonLabel(s)}…');
        text = await _get(Uri.parse('$_base/${seasonCode(s)}/I1.csv'));
        if (text != null && text.contains('HomeTeam')) {
          await file.writeAsString(text);
          downloaded++;
        } else {
          text = null;
          if (s < currentSeason) failed++;
        }
      }
      if (text == null && await file.exists()) text = await file.readAsString();
      if (text != null) all.addAll(parseSeason(text, s));
    }
    if (all.isEmpty) {
      throw DataException(offline
          ? 'Nessun dato salvato: premi “Aggiorna dati” nella schermata Giornata.'
          : 'Non riesco a scaricare i risultati. Controlla la connessione e riprova.');
    }
    if (failed > 0 && downloaded == 0 && !offline) {
      onProgress('Alcune stagioni non sono state scaricate: uso quelle salvate.');
    }
    return all;
  }

  /// Partite in arrivo da football-data.co.uk (gratis, senza chiave).
  Future<OddsFetch> fetchFdFixtures() async {
    final text = await _get(Uri.parse('https://www.football-data.co.uk/fixtures.csv'));
    if (text == null) {
      throw DataException('Non riesco a scaricare le prossime partite da football-data.co.uk.');
    }
    final rows = parseCsv(text);
    if (rows.isEmpty) return OddsFetch([], null);
    final idx = _header(rows.first);
    final out = <Fixture>[];
    for (final cells in rows.skip(1)) {
      final r = _Row(idx, cells);
      if (r.s('Div') != 'I1') continue;
      final home = r.s('HomeTeam'), away = r.s('AwayTeam');
      if (home == null || away == null) continue;
      final books = <String, List<double>>{};
      _fdBooks.forEach((code, name) {
        final o = r.odds('${code}H', '${code}D', '${code}A');
        if (o != null) books.putIfAbsent(name, () => o);
      });
      final avg = r.odds('AvgH', 'AvgD', 'AvgA');
      if (books.isEmpty && avg != null) books['Media bookmaker'] = avg;
      out.add(Fixture(date: parseFdDate(r.s('Date'), r.s('Time')), home: home, away: away, books: books));
    }
    return OddsFetch(out, null);
  }

  /// Partite e quote da The Odds API (serve una chiave gratuita).
  Future<OddsFetch> fetchOddsApi(String key) async {
    if (key.trim().isEmpty) {
      throw DataException('Inserisci la chiave di The Odds API nelle Impostazioni.');
    }
    final uri = Uri.parse('https://api.the-odds-api.com/v4/sports/soccer_italy_serie_a/odds/'
        '?apiKey=${Uri.encodeQueryComponent(key.trim())}&regions=eu&markets=h2h&oddsFormat=decimal');
    http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw DataException('Non riesco a contattare The Odds API. Controlla la connessione.');
    }
    if (res.statusCode == 401) throw DataException('La chiave di The Odds API non è valida.');
    if (res.statusCode == 429) {
      throw DataException('Hai finito le richieste gratuite di questo mese su The Odds API.');
    }
    if (res.statusCode != 200) {
      throw DataException('The Odds API ha risposto con un errore (${res.statusCode}).');
    }
    final remaining = int.tryParse(res.headers['x-requests-remaining'] ?? '');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    final out = <Fixture>[];
    for (final e in data) {
      final ev = e as Map<String, dynamic>;
      final home = ev['home_team'] as String? ?? '';
      final away = ev['away_team'] as String? ?? '';
      final books = <String, List<double>>{};
      for (final b in (ev['bookmakers'] as List<dynamic>? ?? [])) {
        final bm = b as Map<String, dynamic>;
        final title = bm['title'] as String? ?? bm['key'] as String? ?? '?';
        for (final mk in (bm['markets'] as List<dynamic>? ?? [])) {
          final market = mk as Map<String, dynamic>;
          if (market['key'] != 'h2h') continue;
          double? o1, ox, o2;
          for (final oc in (market['outcomes'] as List<dynamic>? ?? [])) {
            final o = oc as Map<String, dynamic>;
            final price = (o['price'] as num?)?.toDouble();
            final name = o['name'] as String? ?? '';
            if (name == home) {
              o1 = price;
            } else if (name == away) {
              o2 = price;
            } else if (name.toLowerCase() == 'draw') {
              ox = price;
            }
          }
          if (o1 != null && ox != null && o2 != null && o1 > 1 && ox > 1 && o2 > 1) {
            books[title] = [o1, ox, o2];
          }
        }
      }
      out.add(Fixture(
        date: DateTime.tryParse(ev['commence_time'] as String? ?? '')?.toLocal(),
        home: home,
        away: away,
        books: books,
      ));
    }
    return OddsFetch(out, remaining);
  }

  Future<File> _snapshotFile() async => File('${(await _dir()).path}/snapshot.json');

  Future<void> saveSnapshot(Map<String, dynamic> j) async =>
      (await _snapshotFile()).writeAsString(jsonEncode(j));

  Future<Map<String, dynamic>?> loadSnapshot() async {
    try {
      final f = await _snapshotFile();
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
