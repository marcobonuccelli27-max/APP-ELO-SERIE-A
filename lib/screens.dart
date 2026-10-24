// Le quattro schermate: Giornata, Classifica, Verifica, Impostazioni.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'elo.dart';
import 'state.dart';
import 'widgets.dart';

const _pagePadding = EdgeInsets.fromLTRB(20, 16, 20, 40);

// ===========================================================================
// Giornata

class GiornataScreen extends StatefulWidget {
  const GiornataScreen({super.key});
  @override
  State<GiornataScreen> createState() => _GiornataScreenState();
}

class _GiornataScreenState extends State<GiornataScreen> {
  int filter = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final evals = app.predictions.map((p) => p.evaluate(s)).toList();
    final valueCount = evals.where((e) => e?.hasValue ?? false).length;
    final shown = <int>[
      for (var i = 0; i < app.predictions.length; i++)
        if (filter == 0 || (evals[i]?.hasValue ?? false)) i
    ];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: _pagePadding,
        children: [
          PageHeader(
            title: 'Prossime partite',
            subtitle: app.lastUpdate == null
                ? 'Serie A · nessun aggiornamento'
                : 'Aggiornato ${dateLabel(app.lastUpdate)}',
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: app.busy ? 'Aggiorno…' : 'Aggiorna dati',
            icon: CupertinoIcons.refresh,
            onPressed: app.busy ? null : app.refresh,
          ),
          if (app.busy)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 10),
                Expanded(child: Text(app.progress, style: const TextStyle(fontSize: 13, color: C.grey))),
              ]),
            ),
          if (app.error != null) Notice(app.error!, tone: Tone.warning),
          if (app.oddsError != null) Notice(app.oddsError!, tone: Tone.warning),
          if (app.predictions.isEmpty && !app.busy && app.error == null && app.oddsError == null)
            const Notice(
              'Al primo avvio scarico circa 20 stagioni di risultati e calibro il modello: '
              'serve circa un minuto. Poi ogni aggiornamento richiede pochi secondi.',
              title: 'Premi “Aggiorna dati” per iniziare',
            ),
          if (app.predictions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: StatCard(label: 'Con valore', value: '$valueCount', sub: 'su ${app.predictions.length}')),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Puntata', value: euro(s.stake), sub: '${fmt(s.stakePct, 0)}% di ${euro(s.budget, 0)}')),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Soglia', value: fmt(s.threshold), sub: 'almeno +${((s.threshold - 1) * 100).round()}%')),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: filter,
                children: const {
                  0: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Tutte')),
                  1: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Solo con valore')),
                },
                onValueChanged: (v) => setState(() => filter = v ?? 0),
              ),
            ),
            const SizedBox(height: 14),
            for (final i in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MatchCard(pred: app.predictions[i], eval: evals[i], settings: s),
              ),
            if (shown.isEmpty) const Notice('Nessuna partita supera la soglia di valore per ora.'),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Valore = probabilità del modello × quota. Sopra la soglia la giocata viene segnalata; '
                'sotto, secondo il modello la quota non ripaga il rischio. Tocca una partita per i dettagli.',
                style: TextStyle(fontSize: 12, height: 1.45, color: C.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MatchCard extends StatelessWidget {
  final Prediction pred;
  final Evaluation? eval;
  final Settings settings;
  const MatchCard({super.key, required this.pred, required this.eval, required this.settings});

  @override
  Widget build(BuildContext context) {
    final best = pred.best(settings.excludedBooks);
    final e = eval;
    return Material(
      color: C.fill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetail(context, best),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('${pred.home} – ${pred.away}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.ink)),
                ),
                Text(dateLabel(pred.date), style: const TextStyle(fontSize: 12, color: C.grey)),
              ]),
              const SizedBox(height: 3),
              Text('Elo ${pred.eloH.round()} contro ${pred.eloA.round()}',
                  style: const TextStyle(fontSize: 12, color: C.grey)),
              if (pred.unknownTeam)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Una squadra non è stata riconosciuta: previsione poco affidabile.',
                      style: TextStyle(fontSize: 12, color: C.warn)),
                ),
              const SizedBox(height: 12),
              ProbBar(pred.p),
              const SizedBox(height: 10),
              Row(children: [
                for (var k = 0; k < 3; k++) ...[
                  if (k > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _OutcomeCell(
                      label: outcomeLabels[k],
                      prob: pred.p[k],
                      odds: best?.odds[k],
                      highlighted: e != null && e.hasValue && e.pick == k,
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              if (e == null)
                const Text('Nessuna quota disponibile per i bookmaker scelti.',
                    style: TextStyle(fontSize: 13, color: C.grey))
              else if (e.hasValue)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: C.blueTint, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    'Gioca ${outcomeLabels[e.pick]} · valore ${fmt(e.ev)} · ${euro(settings.stake)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.blueText),
                  ),
                )
              else
                Text('Nessun valore (massimo ${fmt(e.ev)})',
                    style: const TextStyle(fontSize: 13, color: C.grey)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, BestOdds? best) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        const head = TextStyle(fontSize: 12, color: C.grey);
        const cell = TextStyle(fontSize: 15, color: C.ink, fontWeight: FontWeight.w500);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${pred.home} – ${pred.away}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
                const SizedBox(height: 2),
                Text(dateLabel(pred.date), style: const TextStyle(fontSize: 13, color: C.grey)),
                const SizedBox(height: 18),
                const Row(children: [
                  SizedBox(width: 36, child: Text('Esito', style: head)),
                  Expanded(child: Text('Modello', style: head, textAlign: TextAlign.right)),
                  Expanded(child: Text('Quota', style: head, textAlign: TextAlign.right)),
                  Expanded(child: Text('Prob. quota', style: head, textAlign: TextAlign.right)),
                  Expanded(child: Text('Valore', style: head, textAlign: TextAlign.right)),
                ]),
                const Divider(color: C.line, height: 18),
                for (var k = 0; k < 3; k++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      SizedBox(width: 36, child: Text(outcomeLabels[k], style: cell.copyWith(fontWeight: FontWeight.w700))),
                      Expanded(child: Text(pct(pred.p[k], 1), style: cell, textAlign: TextAlign.right)),
                      Expanded(child: Text(best == null ? '—' : fmt(best.odds[k]), style: cell, textAlign: TextAlign.right)),
                      Expanded(child: Text(best == null ? '—' : pct(1 / best.odds[k], 1), style: cell, textAlign: TextAlign.right)),
                      Expanded(
                        child: Text(
                          best == null ? '—' : fmt(pred.p[k] * best.odds[k]),
                          style: cell.copyWith(
                            color: best != null && pred.p[k] * best.odds[k] >= settings.threshold ? C.blueText : C.ink,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ]),
                  ),
                if (best != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Quote migliori: 1 da ${best.books[0]}, X da ${best.books[1]}, 2 da ${best.books[2]}.',
                    style: const TextStyle(fontSize: 13, color: C.ink2, height: 1.4),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  '“Prob. quota” è la probabilità nascosta nella quota (1 ÷ quota), margine del bookmaker compreso. '
                  'Il valore supera 1 quando il modello stima l’esito più probabile di quanto la quota lasci intendere.',
                  style: TextStyle(fontSize: 12, color: C.grey, height: 1.45),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OutcomeCell extends StatelessWidget {
  final String label;
  final double prob;
  final double? odds;
  final bool highlighted;
  const _OutcomeCell({required this.label, required this.prob, required this.odds, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: highlighted ? C.blueTint : C.white,
        borderRadius: BorderRadius.circular(10),
        border: highlighted ? Border.all(color: C.blue, width: 1.2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: highlighted ? C.blueText : C.grey)),
          const SizedBox(height: 2),
          Text(pct(prob), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: C.ink)),
          Text(odds == null ? 'quota —' : 'quota ${fmt(odds!)}',
              style: const TextStyle(fontSize: 12, color: C.grey)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Classifica

class ClassificaScreen extends StatelessWidget {
  const ClassificaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final rows = app.table;
    final season = app.tableSeason ?? currentSeasonStart(DateTime.now());
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: _pagePadding,
        children: [
          PageHeader(
            title: 'Classifica Elo',
            subtitle: rows.isEmpty ? 'Serie A' : 'Stagione ${seasonLabel(season)} · la media è 1500',
          ),
          if (rows.isEmpty)
            const Notice('Aggiorna i dati dalla schermata Giornata per vedere la classifica.')
          else ...[
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, color: C.line, indent: 50),
                  _TeamTile(rank: i + 1, row: rows[i]),
                ],
              ]),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 12, left: 4),
              child: Text('Ultime 5 partite: V vinta, N pareggiata, P persa. La freccia indica la variazione nell’ultima partita.',
                  style: TextStyle(fontSize: 12, height: 1.45, color: C.grey)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  final int rank;
  final TeamRow row;
  const _TeamTile({required this.rank, required this.row});

  @override
  Widget build(BuildContext context) {
    final frac = ((row.rating - 1350) / 450).clamp(0.03, 1.0).toDouble();
    final d = row.delta.round();
    final deltaText = d == 0 ? '±0' : (d > 0 ? '▲ +$d' : '▼ −${d.abs()}');
    final deltaColor = d == 0 ? C.grey : (d > 0 ? C.blueText : C.warn);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(children: [
        SizedBox(
          width: 26,
          child: Text('$rank', style: const TextStyle(fontSize: 14, color: C.grey)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink)),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(color: C.fill2, borderRadius: BorderRadius.circular(3)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: frac,
                    child: Container(
                      decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              for (final f in row.form) ...[const SizedBox(width: 3), _FormChip(f)],
            ]),
          ]),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${row.rating.round()}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.ink)),
          const SizedBox(height: 3),
          Text(deltaText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: deltaColor)),
        ]),
      ]),
    );
  }
}

class _FormChip extends StatelessWidget {
  final String r;
  const _FormChip(this.r);

  @override
  Widget build(BuildContext context) {
    final bg = r == 'V' ? C.ink : (r == 'N' ? C.light : C.white);
    final fg = r == 'V' ? C.white : (r == 'N' ? C.ink : C.ink2);
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: r == 'P' ? Border.all(color: C.mid) : null,
      ),
      child: Text(r, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

// ===========================================================================
// Verifica sul passato

class VerificaScreen extends StatefulWidget {
  const VerificaScreen({super.key});
  @override
  State<VerificaScreen> createState() => _VerificaScreenState();
}

class _VerificaScreenState extends State<VerificaScreen> {
  int seasons = 3;
  double? thr;
  bool running = false;
  BacktestResult? result;
  String? error;

  Future<void> _run(AppState app) async {
    setState(() {
      running = true;
      error = null;
    });
    try {
      final r = await app.runBacktest(seasons, thr ?? app.settings.threshold);
      if (!mounted) return;
      setState(() {
        result = r;
        error = r.error;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = thr ?? app.settings.threshold.clamp(1.0, 1.2).toDouble();
    final r = result;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: _pagePadding,
        children: [
          const PageHeader(title: 'Verifica sul passato', subtitle: 'Come sarebbe andata usando il modello'),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Stagioni di prova', style: TextStyle(fontSize: 13, color: C.grey)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: seasons,
                  backgroundColor: C.fill2,
                  children: const {
                    1: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Ultima')),
                    3: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Ultime 3')),
                    5: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Ultime 5')),
                  },
                  onValueChanged: (v) => setState(() => seasons = v ?? 3),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Soglia di valore', style: TextStyle(fontSize: 13, color: C.grey)),
                const Spacer(),
                Text(fmt(t), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink)),
              ]),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlider(
                  value: t,
                  min: 1.0,
                  max: 1.2,
                  divisions: 20,
                  activeColor: C.blue,
                  onChanged: (v) => setState(() => thr = v),
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                label: running ? 'Calcolo…' : 'Avvia verifica',
                icon: CupertinoIcons.play_fill,
                onPressed: running ? null : () => _run(app),
              ),
            ]),
          ),
          if (running)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Row(children: [
                CupertinoActivityIndicator(),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Calibro il modello sulle stagioni precedenti e simulo le scommesse…',
                      style: TextStyle(fontSize: 13, color: C.grey)),
                ),
              ]),
            ),
          if (error != null) Notice(error!, tone: Tone.warning),
          if (r != null && r.error == null && !running) ..._results(app, r),
        ],
      ),
    );
  }

  List<Widget> _results(AppState app, BacktestResult r) {
    final s = app.settings;
    final modelBetter = r.modelLogLoss < r.bookLogLoss;
    final verdict = _verdict(r);
    return [
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: StatCard(label: 'Scommesse simulate', value: '${r.bets}', sub: 'su ${r.testMatches} partite')),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Risultato',
            value: signedEuro(r.profit),
            valueColor: r.profit < 0 ? C.warn : C.blueText,
            sub: '${signedPct(r.roi)} ± ${fmt(r.roiMargin * 100, 1)}%',
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: StatCard(
            label: 'Quote poi scese',
            value: r.clvChecked == 0 ? '—' : pct(r.clvShare),
            sub: 'serve stare sopra il 50%',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Chi prevede meglio',
            value: modelBetter ? 'Il modello' : 'Bookmaker',
            sub: 'errore ${fmt(r.modelLogLoss, 3)} contro ${fmt(r.bookLogLoss, 3)}',
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Andamento del budget',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink)),
          const SizedBox(height: 2),
          Text('Partenza ${euro(s.budget, 0)} · puntata fissa ${euro(s.stake)}',
              style: const TextStyle(fontSize: 12, color: C.grey)),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: r.bankroll.length < 2
                ? const Center(child: Text('Nessuna scommessa da mostrare', style: TextStyle(fontSize: 13, color: C.grey)))
                : CustomPaint(painter: BankrollPainter(r.bankroll, s.budget)),
          ),
          if (r.dates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              Text(shortDate(r.dates.first), style: const TextStyle(fontSize: 12, color: C.grey)),
              const Spacer(),
              Text(shortDate(r.dates.last), style: const TextStyle(fontSize: 12, color: C.grey)),
            ]),
          ],
        ]),
      ),
      Notice(verdict.$2, title: verdict.$1, tone: verdict.$3),
      Padding(
        padding: const EdgeInsets.only(top: 12, left: 4),
        child: Text(
          'Calibrato su ${seasonLabel(r.trainFrom)}–${seasonLabel(r.trainTo)}: K ${fmt(r.params.k, 0)}, '
          'casa +${fmt(r.params.home, 0)}, riavvicinamento ${fmt(r.params.regress * 100, 0)}%. '
          'Provato su ${seasonLabel(r.testFrom)}–${seasonLabel(r.testTo)} con le quote Bet365 '
          '(o la media dei bookmaker) disponibili prima delle partite. '
          '“Errore” è la log loss: più è basso, meglio si prevede.',
          style: const TextStyle(fontSize: 12, height: 1.45, color: C.grey),
        ),
      ),
    ];
  }

  (String, String, Tone) _verdict(BacktestResult r) {
    if (r.bets < 30) {
      return (
        'Troppe poche scommesse',
        'Con meno di 30 giocate il risultato dipende quasi solo dal caso. '
            'Prova una soglia più bassa o più stagioni.',
        Tone.neutral,
      );
    }
    if (r.roi - r.roiMargin > 0 && r.clvShare > 0.5) {
      return (
        'Segnali positivi',
        'Il modello avrebbe guadagnato oltre il margine d’incertezza e preso spesso quote migliori '
            'di quelle di chiusura. Ricontrolla su altre stagioni prima di fidarti.',
        Tone.positive,
      );
    }
    if (r.roi + r.roiMargin < 0) {
      return (
        'Il modello non batte il mercato',
        'Su queste stagioni avresti perso, anche tenendo conto del caso. '
            'Non usarlo con soldi veri.',
        Tone.warning,
      );
    }
    return (
      'Risultato non distinguibile dal caso',
      'Il risultato sta dentro il margine d’incertezza di ±${fmt(r.roiMargin * 100, 1)}%: '
          'non dimostra né un vantaggio né uno svantaggio. Servono più stagioni per giudicare.',
      Tone.neutral,
    );
  }
}

// ===========================================================================
// Impostazioni

class ImpostazioniScreen extends StatefulWidget {
  const ImpostazioniScreen({super.key});
  @override
  State<ImpostazioniScreen> createState() => _ImpostazioniScreenState();
}

class _ImpostazioniScreenState extends State<ImpostazioniScreen> {
  final apiKey = TextEditingController();
  final budget = TextEditingController();
  final threshold = TextEditingController();
  final k = TextEditingController();
  final home = TextEditingController();
  final regress = TextEditingController();
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final s = AppScope.of(context).settings;
    apiKey.text = s.apiKey;
    budget.text = fmt(s.budget, 0);
    threshold.text = fmt(s.threshold);
    k.text = fmt(s.k, 0);
    home.text = fmt(s.home, 0);
    regress.text = fmt(s.regress * 100, 0);
    _ready = true;
  }

  @override
  void dispose() {
    for (final c in [apiKey, budget, threshold, k, home, regress]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String t) => double.tryParse(t.replaceAll(',', '.').trim());

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final p = app.paramsInUse;
    final books = app.booksSeen.toList()..sort();

    void save() => app.saveSettings();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: _pagePadding,
        children: [
          const PageHeader(title: 'Impostazioni'),
          Group(
            title: 'Fonte delle quote',
            footer: s.provider == 'fd'
                ? 'football-data.co.uk è gratuito e non serve nessuna chiave: le quote si aggiornano un paio di volte a settimana.'
                : 'Chiave gratuita su the-odds-api.com. Ogni “Aggiorna dati” usa una richiesta.',
            rows: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: s.provider,
                    backgroundColor: C.fill2,
                    children: const {
                      'fd': Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('football-data (gratis)')),
                      'oddsapi': Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('The Odds API')),
                    },
                    onValueChanged: (v) {
                      s.provider = v ?? 'fd';
                      save();
                    },
                  ),
                ),
              ),
              if (s.provider == 'oddsapi') ...[
                SettingRow(
                  label: 'Chiave API',
                  sub: app.requestsRemaining == null ? null : 'Richieste rimaste: ${app.requestsRemaining}',
                  trailing: SmallField(
                    controller: apiKey,
                    width: 170,
                    numeric: false,
                    obscure: true,
                    onChanged: (v) {
                      s.apiKey = v.trim();
                      save();
                    },
                  ),
                ),
              ],
            ],
          ),
          Group(
            title: 'Bookmaker',
            footer: 'Tieni attivi solo i bookmaker su cui puoi davvero giocare: in Italia, quelli con licenza ADM.',
            rows: books.isEmpty
                ? [const SettingRow(label: 'Aggiorna i dati per vedere l’elenco')]
                : [
                    for (final b in books)
                      SettingRow(
                        label: b,
                        trailing: CupertinoSwitch(
                          value: !s.excludedBooks.contains(b),
                          activeColor: C.blue,
                          onChanged: (on) {
                            if (on) {
                              s.excludedBooks.remove(b);
                            } else {
                              s.excludedBooks.add(b);
                            }
                            save();
                          },
                        ),
                      ),
                  ],
          ),
          Group(
            title: 'Budget e puntate',
            footer: 'Solo giocate singole: nelle multiple il margine del bookmaker si moltiplica a ogni partita.',
            rows: [
              SettingRow(
                label: 'Budget dedicato',
                trailing: SmallField(
                  controller: budget,
                  suffix: '€',
                  width: 110,
                  onChanged: (v) {
                    final n = _num(v);
                    if (n != null && n > 0) {
                      s.budget = n;
                      save();
                    }
                  },
                ),
              ),
              SettingRow(
                label: 'Puntata per giocata',
                sub: euro(s.stake),
                trailing: CupertinoSlidingSegmentedControl<int>(
                  groupValue: s.stakePct.round(),
                  backgroundColor: C.fill2,
                  children: const {
                    1: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('1%')),
                    2: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('2%')),
                    3: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('3%')),
                  },
                  onValueChanged: (v) {
                    s.stakePct = (v ?? 2).toDouble();
                    save();
                  },
                ),
              ),
              SettingRow(
                label: 'Soglia di valore',
                sub: 'Consigliata 1,05: almeno +5%',
                trailing: SmallField(
                  controller: threshold,
                  onChanged: (v) {
                    final n = _num(v);
                    if (n != null && n >= 1 && n <= 2) {
                      s.threshold = n;
                      save();
                    }
                  },
                ),
              ),
            ],
          ),
          Group(
            title: 'Modello',
            footer: s.autoCalib
                ? 'La calibrazione automatica prova centinaia di combinazioni sulle stagioni passate e tiene quella che prevede meglio.'
                : 'Dopo aver cambiato i valori, premi “Ricalcola con questi valori”.',
            rows: [
              SettingRow(
                label: 'Calibrazione automatica',
                sub: 'Sceglie i valori dai dati storici',
                trailing: CupertinoSwitch(
                  value: s.autoCalib,
                  activeColor: C.blue,
                  onChanged: (v) {
                    s.autoCalib = v;
                    save();
                  },
                ),
              ),
              if (!s.autoCalib) ...[
                SettingRow(
                  label: 'Fattore K',
                  sub: 'Di solito tra 15 e 30',
                  trailing: SmallField(
                    controller: k,
                    onChanged: (v) {
                      final n = _num(v);
                      if (n != null && n > 0 && n <= 100) {
                        s.k = n;
                        save();
                      }
                    },
                  ),
                ),
                SettingRow(
                  label: 'Vantaggio casa',
                  sub: 'Punti Elo, di solito tra 50 e 90',
                  trailing: SmallField(
                    controller: home,
                    onChanged: (v) {
                      final n = _num(v);
                      if (n != null && n >= 0 && n <= 300) {
                        s.home = n;
                        save();
                      }
                    },
                  ),
                ),
                SettingRow(
                  label: 'Riavvicinamento estivo',
                  sub: 'Verso la media a inizio stagione',
                  trailing: SmallField(
                    controller: regress,
                    suffix: '%',
                    onChanged: (v) {
                      final n = _num(v);
                      if (n != null && n >= 0 && n <= 90) {
                        s.regress = n / 100;
                        save();
                      }
                    },
                  ),
                ),
              ],
              SettingRow(
                label: 'Valori in uso',
                trailing: Text(
                  'K ${fmt(p.k, 0)} · casa +${fmt(p.home, 0)} · ${fmt(p.regress * 100, 0)}%',
                  style: const TextStyle(fontSize: 14, color: C.grey),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    onPressed: app.busy ? null : (s.autoCalib ? app.recalibrate : app.refresh),
                    child: Text(
                      app.busy ? 'Sto calcolando…' : (s.autoCalib ? 'Ricalibra ora' : 'Ricalcola con questi valori'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.blue),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Group(
            title: 'Informazioni',
            rows: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Risultati e quote storiche: football-data.co.uk. Le probabilità sono stime del modello, '
                  'non certezze: gioca solo cifre che puoi permetterti di perdere. Se il gioco diventa un problema, '
                  'il Telefono Verde Nazionale per il gioco d’azzardo risponde gratis allo 800 558 822.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: C.ink2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
