// Le quattro schermate: Giornata, Classifica, Verifica, Impostazioni.

import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'elo.dart';
import 'state.dart';
import 'widgets.dart';

const _pagePadding = EdgeInsets.fromLTRB(20, 16, 20, 40);

/// K lungo la stagione, per esempio "K 30 alla 1ª giornata, 25 alla 10ª, 20 dalla 19ª".
String kCurve(EloParams p) {
  if (p.early == 0) return 'K ${fmt(p.k, 0)} fisso';
  return 'K ${fmt(p.kAt(0), 0)} alla 1ª giornata, ${fmt(p.kAt(9), 0)} alla 10ª, ${fmt(p.k, 0)} dalla 19ª';
}

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
          if (s.provider == 'oddsapi' && app.requestsRemaining != null && !app.busy)
            _QuotaLine(remaining: app.requestsRemaining!, used: app.requestsUsed, at: app.requestsCheckedAt),
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

/// Richieste rimaste nel piano gratuito di The Odds API.
class _QuotaLine extends StatelessWidget {
  final int remaining;
  final int? used;
  final DateTime? at;
  const _QuotaLine({required this.remaining, required this.used, required this.at});

  @override
  Widget build(BuildContext context) {
    final total = used == null ? null : remaining + used!;
    final low = remaining <= 20;
    final frac = total == null || total == 0 ? null : (remaining / total).clamp(0.0, 1.0).toDouble();
    final when = at == null ? '' : ' · controllato ${dateLabel(at)}';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: low ? C.warnTint : C.fill, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              total == null
                  ? 'The Odds API: restano $remaining richieste questo mese'
                  : 'The Odds API: restano $remaining richieste su $total',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: low ? C.warn : C.ink),
            ),
          ),
        ]),
        if (frac != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: C.fill2,
              color: low ? C.warn : C.blue,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '${low ? 'Stanno per finire: ' : ''}ogni “Aggiorna dati” ne usa una. '
          'Il conteggio riparte all’inizio di ogni mese$when.',
          style: const TextStyle(fontSize: 12, height: 1.4, color: C.grey),
        ),
      ]),
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
              Text(
                pred.xgHome != null
                    ? 'Dixon-Coles · gol attesi ${fmt(pred.xgHome!, 1)} – ${fmt(pred.xgAway!, 1)}'
                    : 'Elo ${pred.eloH.round()} contro ${pred.eloA.round()}',
                style: const TextStyle(fontSize: 12, color: C.grey),
              ),
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
              else if (e.hasValue) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: C.blueTint, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    'Gioca ${outcomeLabels[e.pick]} · valore ${fmt(e.ev)} · ${euro(settings.stake)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.blueText),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Secondo il modello questo esito esce il ${pct(pred.p[e.pick])} delle volte: '
                  'perderai comunque circa ${pct(1 - pred.p[e.pick])} delle giocate come questa.',
                  style: const TextStyle(fontSize: 12, height: 1.4, color: C.grey),
                ),
              ] else if (e.overThreshold && e.leastLikely)
                _Discouraged(
                  'Sconsigliata. La quota su ${outcomeLabels[e.pick]} è conveniente (valore ${fmt(e.ev)}), '
                  'ma è l’esito meno probabile: secondo il modello esce solo il ${pct(pred.p[e.pick])} delle volte, '
                  'circa una volta su ${(1 / pred.p[e.pick]).round()}.',
                )
              else if (e.overThreshold && pred.unknownTeam)
                const _Discouraged('Sconsigliata: una squadra non è stata riconosciuta, quindi la stima non è affidabile.')
              else
                Text('Nessun valore (massimo ${fmt(e.ev)})',
                    style: const TextStyle(fontSize: 13, color: C.grey)),
              if (pred.over25 != null) _OuBlock(pred: pred, settings: settings),
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
                if (pred.over25 != null) ...[
                  const SizedBox(height: 16),
                  const Text('Gol', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.ink)),
                  const SizedBox(height: 8),
                  _kv('Gol attesi', '${fmt(pred.xgHome ?? 0, 2)} – ${fmt(pred.xgAway ?? 0, 2)}'),
                  _kv('Over 2,5 (almeno 3 gol)', _ouLine(pred, 0)),
                  _kv('Under 2,5 (al massimo 2 gol)', _ouLine(pred, 1)),
                  _kv('Goal (segnano entrambe)', pct(pred.gg ?? 0, 1)),
                  _kv('No goal', pct(1 - (pred.gg ?? 0), 1)),
                ],
                const SizedBox(height: 10),
                const Text(
                  '“Prob. quota” è la probabilità nascosta nella quota (1 ÷ quota), margine del bookmaker compreso. '
                  'Il valore supera 1 quando il modello stima l’esito più probabile di quanto la quota lasci intendere. '
                  'Una giocata sull’esito meno probabile dei tre viene sempre sconsigliata, anche se la quota è conveniente: '
                  'perderesti nella maggior parte dei casi e il risultato dipenderebbe quasi solo dalla fortuna.',
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

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: C.ink2))),
        Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.ink)),
      ]),
    );

String _ouLine(Prediction pred, int side) {
  final p = side == 0 ? pred.over25! : 1 - pred.over25!;
  var best = 0.0;
  pred.ouBooks.forEach((_, q) {
    if (q[side] > best) best = q[side];
  });
  if (best <= 1) return pct(p, 1);
  return '${pct(p, 1)} · quota ${fmt(best)} · valore ${fmt(p * best)}';
}

/// Over/under 2,5 e goal/no goal nella scheda della partita.
class _OuBlock extends StatelessWidget {
  final Prediction pred;
  final Settings settings;
  const _OuBlock({required this.pred, required this.settings});

  @override
  Widget build(BuildContext context) {
    final ou = pred.evaluateOu(settings);
    final o = pred.over25!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1, color: C.line),
        const SizedBox(height: 10),
        Text(
          'Over 2,5 ${pct(o)} · Under ${pct(1 - o)} · Goal ${pct(pred.gg ?? 0)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: C.ink2),
        ),
        if (ou != null) ...[
          const SizedBox(height: 8),
          if (ou.hasValue)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: C.blueTint, borderRadius: BorderRadius.circular(14)),
              child: Text(
                'Gioca ${ou.side == 0 ? 'Over' : 'Under'} 2,5 · quota ${fmt(ou.odds)} · valore ${fmt(ou.ev)} · ${euro(settings.stake)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.blueText),
              ),
            )
          else if (ou.overThreshold && ou.minority)
            _Discouraged(
              'Sconsigliata. La quota ${ou.side == 0 ? 'Over' : 'Under'} 2,5 è conveniente (valore ${fmt(ou.ev)}), '
              'ma secondo il modello succede solo il ${pct(ou.prob)} delle volte: meno di una volta su due.',
            )
          else
            Text('Over/under: nessun valore (massimo ${fmt(ou.ev)})',
                style: const TextStyle(fontSize: 12, color: C.grey)),
        ],
      ]),
    );
  }
}

class _Discouraged extends StatelessWidget {
  final String text;
  const _Discouraged(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.warnTint, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(CupertinoIcons.exclamationmark_triangle, size: 16, color: C.warn),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4, color: C.ink2))),
      ]),
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
// Classifiche: Elo e Serie A

/// Finestra per scegliere una stagione.
Future<int?> pickSeason(BuildContext context, List<int> seasons, int? selected, {String? zeroLabel}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: C.white,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      Widget tile(int value, String label) => ListTile(
            title: Text(label, style: const TextStyle(fontSize: 16, color: C.ink)),
            trailing: selected == value ? const Icon(CupertinoIcons.checkmark_alt, color: C.blue) : null,
            onTap: () => Navigator.pop(ctx, value),
          );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (zeroLabel != null) tile(0, zeroLabel),
              for (final s in seasons) tile(s, 'Stagione ${seasonLabel(s)}'),
            ],
          ),
        ),
      );
    },
  );
}

class ClassificaScreen extends StatefulWidget {
  const ClassificaScreen({super.key});
  @override
  State<ClassificaScreen> createState() => _ClassificaScreenState();
}

class _ClassificaScreenState extends State<ClassificaScreen> {
  int? season;
  int mode = 0; // 0 = Elo, 1 = Serie A

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final seasons = app.seasonsAvailable;
    if (seasons.isEmpty) {
      return const SafeArea(
        bottom: false,
        child: Padding(
          padding: _pagePadding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHeader(title: 'Classifiche', subtitle: 'Serie A'),
            Notice('Aggiorna i dati dalla schermata Giornata per vedere le classifiche.'),
          ]),
        ),
      );
    }
    final sel = (season != null && seasons.contains(season)) ? season! : seasons.first;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: _pagePadding,
        children: [
          const PageHeader(title: 'Classifiche', subtitle: 'Serie A'),
          const SizedBox(height: 16),
          Material(
            color: C.fill,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final s = await pickSeason(context, seasons, sel);
                if (s != null) setState(() => season = s);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(children: [
                  Text('Stagione ${seasonLabel(sel)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.ink)),
                  const Spacer(),
                  const Text('Cambia', style: TextStyle(fontSize: 14, color: C.blue)),
                  const SizedBox(width: 4),
                  const Icon(CupertinoIcons.chevron_down, size: 14, color: C.blue),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: mode,
              children: const {
                0: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Elo')),
                1: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Serie A')),
                2: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Attacco e difesa')),
              },
              onValueChanged: (v) => setState(() => mode = v ?? 0),
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<SeasonView>(
            future: app.seasonView(sel),
            builder: (ctx, snap) {
              if (snap.hasError) return Notice(snap.error.toString(), tone: Tone.warning);
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CupertinoActivityIndicator()),
                );
              }
              final v = snap.data!;
              if (mode == 0) return _EloList(view: v);
              if (mode == 1) return _StandingsTable(view: v);
              return _DcTable(view: v);
            },
          ),
        ],
      ),
    );
  }
}

class _EloList extends StatelessWidget {
  final SeasonView view;
  const _EloList({required this.view});

  @override
  Widget build(BuildContext context) {
    final rows = view.elo;
    final p = view.params;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: C.line, indent: 50),
            _TeamTile(rank: i + 1, row: rows[i], onTap: () => showTeamSheet(context, view, rows[i].name)),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12, left: 4),
        child: Text(
          'La freccia indica la variazione dall’inizio della stagione; le caselle sono le ultime 5 partite '
          '(V vinta, N pareggiata, P persa). Tocca una squadra per vedere l’andamento del punteggio. '
          'Calcolato con ${kCurve(p)}; casa +${fmt(p.home, 0)}, riavvicinamento ${fmt(p.regress * 100, 0)}%.',
          style: const TextStyle(fontSize: 12, height: 1.45, color: C.grey),
        ),
      ),
    ]);
  }
}

class _TeamTile extends StatelessWidget {
  final int rank;
  final TeamRow row;
  final VoidCallback onTap;
  const _TeamTile({required this.rank, required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final frac = ((row.rating - 1350) / 450).clamp(0.03, 1.0).toDouble();
    final d = row.change.round();
    final deltaText = d == 0 ? '±0' : (d > 0 ? '▲ +$d' : '▼ −${d.abs()}');
    final deltaColor = d == 0 ? C.grey : (d > 0 ? C.blueText : C.warn);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(children: [
          SizedBox(width: 26, child: Text('$rank', style: const TextStyle(fontSize: 14, color: C.grey))),
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
      ),
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

class _StandingsTable extends StatelessWidget {
  final SeasonView view;
  const _StandingsTable({required this.view});

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.grey);
    const cell = TextStyle(fontSize: 14, color: C.ink2, fontFeatures: [FontFeature.tabularFigures()]);
    Widget n(String t, TextStyle st, {double w = 26}) =>
        SizedBox(width: w, child: Text(t, style: st, textAlign: TextAlign.right));
    final rows = view.table;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(children: [
              const SizedBox(width: 22, child: Text('#', style: head)),
              const Expanded(child: Text('Squadra', style: head)),
              n('G', head),
              n('V', head),
              n('N', head),
              n('P', head),
              n('DR', head, w: 32),
              n('Pt', head, w: 32),
            ]),
          ),
          const Divider(height: 1, thickness: 1, color: C.line),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: C.line, indent: 12),
            InkWell(
              onTap: () => showTeamSheet(context, view, rows[i].team),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(fontSize: 13, color: C.grey))),
                  Expanded(
                    child: Text(rows[i].team,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.ink)),
                  ),
                  n('${rows[i].played}', cell),
                  n('${rows[i].won}', cell),
                  n('${rows[i].drawn}', cell),
                  n('${rows[i].lost}', cell),
                  n('${rows[i].goalDiff > 0 ? '+' : ''}${rows[i].goalDiff}', cell, w: 32),
                  n('${rows[i].points}', cell.copyWith(fontWeight: FontWeight.w700, color: C.ink), w: 32),
                ]),
              ),
            ),
          ],
        ]),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 12, left: 4),
        child: Text(
          'G giocate, V vinte, N pareggiate, P perse, DR differenza reti, Pt punti. '
          'A parità di punti l’ordine segue differenza reti e gol fatti; il regolamento usa prima gli scontri diretti. '
          'Tocca una squadra per vedere l’andamento del suo punteggio Elo.',
          style: TextStyle(fontSize: 12, height: 1.45, color: C.grey),
        ),
      ),
    ]);
  }
}

class _DcTable extends StatelessWidget {
  final SeasonView view;
  const _DcTable({required this.view});

  @override
  Widget build(BuildContext context) {
    final rows = view.dc;
    if (rows.isEmpty) return const Notice('Non ci sono abbastanza partite per stimare attacco e difesa.');
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.grey);
    const cell = TextStyle(fontSize: 14, color: C.ink, fontFeatures: [FontFeature.tabularFigures()]);
    final maxGf = rows.map((r) => r.goalsFor).reduce((a, b) => a > b ? a : b);
    final maxGa = rows.map((r) => r.goalsAgainst).reduce((a, b) => a > b ? a : b);
    Widget bar(double v, double max, Color c) => SizedBox(
          width: 44,
          height: 5,
          child: Container(
            decoration: BoxDecoration(color: C.fill2, borderRadius: BorderRadius.circular(3)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (v / max).clamp(0.05, 1.0).toDouble(),
              child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(children: [
              SizedBox(width: 22, child: Text('#', style: head)),
              Expanded(child: Text('Squadra', style: head)),
              SizedBox(width: 92, child: Text('Segna', style: head)),
              SizedBox(width: 92, child: Text('Subisce', style: head)),
            ]),
          ),
          const Divider(height: 1, thickness: 1, color: C.line),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: C.line, indent: 12),
            InkWell(
              onTap: () => showTeamSheet(context, view, rows[i].name),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(fontSize: 13, color: C.grey))),
                  Expanded(
                    child: Text(rows[i].name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.ink)),
                  ),
                  SizedBox(
                    width: 92,
                    child: Row(children: [
                      SizedBox(width: 36, child: Text(fmt(rows[i].goalsFor), style: cell)),
                      bar(rows[i].goalsFor, maxGf, C.blue),
                    ]),
                  ),
                  SizedBox(
                    width: 92,
                    child: Row(children: [
                      SizedBox(width: 36, child: Text(fmt(rows[i].goalsAgainst), style: cell)),
                      bar(rows[i].goalsAgainst, maxGa, C.warn),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12, left: 4),
        child: Text(
          'Stima Dixon-Coles a fine periodo: gol che la squadra segnerebbe e subirebbe in media, a partita, '
          'contro un avversario nella media e in campo neutro. Ordinate per differenza tra i due. '
          'Le partite recenti contano di più: con emivita ${fmt(view.halfLife, 0)} giorni, una partita di '
          '${fmt(view.halfLife, 0)} giorni fa vale la metà di una di oggi.',
          style: const TextStyle(fontSize: 12, height: 1.45, color: C.grey),
        ),
      ),
    ]);
  }
}

void showTeamSheet(BuildContext context, SeasonView view, String team) {
  final series = view.series[team];
  if (series == null) return;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.white,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _TeamSheet(team: team, season: view.season, series: series),
  );
}

class _TeamSheet extends StatefulWidget {
  final String team;
  final int season;
  final TeamSeries series;
  const _TeamSheet({required this.team, required this.season, required this.series});
  @override
  State<_TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends State<_TeamSheet> {
  bool all = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    final vals = all ? s.r : s.seasonValues(widget.season);
    final times = all ? s.t : s.seasonTimes(widget.season);
    final hasData = vals.length >= 2;
    final hi = hasData ? vals.reduce((a, b) => a > b ? a : b) : 0.0;
    final lo = hasData ? vals.reduce((a, b) => a < b ? a : b) : 0.0;
    final firstSeasonOfTeam = s.s.isEmpty ? widget.season : s.s.first;
    final seasonsPlayed = s.s.toSet().length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.team, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink)),
            const SizedBox(height: 2),
            Text(
              all
                  ? '$seasonsPlayed stagioni in Serie A dal ${seasonLabel(firstSeasonOfTeam)}'
                  : 'Stagione ${seasonLabel(widget.season)}',
              style: const TextStyle(fontSize: 13, color: C.grey),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<bool>(
                groupValue: all,
                children: const {
                  false: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Questa stagione')),
                  true: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Tutte le stagioni')),
                },
                onValueChanged: (v) => setState(() => all = v ?? false),
              ),
            ),
            const SizedBox(height: 14),
            if (!hasData)
              const Notice('Non ci sono abbastanza partite per disegnare l’andamento.')
            else ...[
              Row(children: [
                Expanded(child: StatCard(label: all ? 'Ultimo' : 'Fine periodo', value: '${vals.last.round()}')),
                const SizedBox(width: 10),
                Expanded(child: StatCard(label: 'Massimo', value: '${hi.round()}')),
                const SizedBox(width: 10),
                Expanded(child: StatCard(label: 'Minimo', value: '${lo.round()}')),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                height: 190,
                width: double.infinity,
                child: CustomPaint(painter: LineChartPainter(vals, 1500)),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text(shortDate(DateTime.fromMillisecondsSinceEpoch(times.first)),
                    style: const TextStyle(fontSize: 12, color: C.grey)),
                const Spacer(),
                Text(shortDate(DateTime.fromMillisecondsSinceEpoch(times.last)),
                    style: const TextStyle(fontSize: 12, color: C.grey)),
              ]),
              const SizedBox(height: 10),
              Text(
                all
                    ? 'Punteggio dopo ogni partita di Serie A; gli anni fuori dalla Serie A non compaiono. '
                        'La linea tratteggiata è la media del campionato (1500).'
                    : 'Il primo punto è il punteggio di partenza della stagione, poi uno dopo ogni partita. '
                        'La linea tratteggiata è la media del campionato (1500).',
                style: const TextStyle(fontSize: 12, height: 1.45, color: C.grey),
              ),
            ],
          ],
        ),
      ),
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
  String? model;
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
      final r = await app.runBacktest(seasons, thr ?? app.settings.threshold, model ?? app.settings.model);
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
    final m = model ?? app.settings.model;
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
              const Text('Modello', style: TextStyle(fontSize: 13, color: C.grey)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: m,
                  backgroundColor: C.fill2,
                  children: const {
                    'elo': Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Elo')),
                    'dc': Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Dixon-Coles')),
                  },
                  onValueChanged: (v) => setState(() => model = v ?? 'elo'),
                ),
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 4),
              Text(
                (app.settings.autoCalib
                        ? 'Calibrazione automatica sulle stagioni scelte nelle Impostazioni '
                            '(dal ${seasonLabel(app.settings.calibFrom)}), fermandosi prima delle stagioni di prova.'
                        : m == 'dc'
                            ? 'Usa la tua emivita: ${fmt(app.settings.dcHalfLife, 0)} giorni.'
                            : 'Usa i tuoi valori: ${kCurve(app.settings.manualParams)}; casa +${fmt(app.settings.home, 0)}, '
                                'riavvicinamento ${fmt(app.settings.regress * 100, 0)}%.') +
                    (m == 'dc' ? ' Con Dixon-Coles la verifica può richiedere fino a un paio di minuti.' : ''),
                style: const TextStyle(fontSize: 12, height: 1.4, color: C.grey),
              ),
              const SizedBox(height: 12),
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
                : CustomPaint(painter: LineChartPainter(r.bankroll, s.budget)),
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
      if (r.sweep.isNotEmpty)
        _BestThresholds(
          r: r,
          current: thr ?? app.settings.threshold,
          onUse: (t) {
            setState(() => thr = t);
            app.settings.threshold = t;
            app.saveSettings();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Soglia impostata a ${fmt(t)}: vale anche per la schermata Giornata. '
                  'Premi “Avvia verifica” per rivedere i risultati.'),
            ));
          },
        ),
      Padding(
        padding: const EdgeInsets.only(top: 12, left: 4),
        child: Text(
          '${r.model == 'dc' ? 'Dixon-Coles' : 'Elo'}, '
          '${r.manual ? 'con i tuoi valori' : 'calibrato su ${seasonLabel(r.trainFrom)}–${seasonLabel(r.trainTo)}'}: '
          '${r.model == 'dc' ? 'emivita ${fmt(r.halfLife, 0)} giorni' : '${kCurve(r.params)}; casa +${fmt(r.params.home, 0)}, riavvicinamento ${fmt(r.params.regress * 100, 0)}%'}. '
          'Provato su ${seasonLabel(r.testFrom)}–${seasonLabel(r.testTo)} con le quote Bet365 '
          '(o la media dei bookmaker) disponibili prima delle partite. '
          '${r.skippedLeastLikely > 0 ? 'Scartate ${r.skippedLeastLikely} giocate perché sull’esito meno probabile.' : ''}',
          style: const TextStyle(fontSize: 12, height: 1.45, color: C.grey),
        ),
      ),
      const Group(
        title: 'Come leggere i risultati',
        rows: [
          _Explain(
            'Risultato e percentuale',
            'La percentuale è il guadagno o la perdita rispetto al totale puntato. '
                'Con −4% avresti perso 4 € ogni 100 € giocati.',
          ),
          _Explain(
            'Il ± dopo la percentuale',
            'È il margine dovuto al caso. Il risultato vero cade in questo intervallo circa 95 volte su 100: '
                'se l’intervallo comprende lo zero (per esempio −4% ± 9%), non si può dire se il modello guadagna o perde.',
          ),
          _Explain(
            'Quote poi scese',
            'Quante volte la quota presa era più alta di quella di chiusura, la più precisa. '
                'Sopra il 50% vuol dire che il modello anticipa il mercato: è il segnale più affidabile.',
          ),
          _Explain(
            'Errore',
            'Misura quanto sono buone le previsioni: per ogni partita conta la probabilità data al risultato uscito davvero. '
                'Più è basso meglio è. Chi dà sempre 33% a ogni esito ottiene 1,099; se il modello ha un errore più alto '
                'del bookmaker, prevede peggio delle quote.',
          ),
        ],
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

/// Le soglie migliori per ciascun criterio, più la tabella di tutte le soglie.
class _BestThresholds extends StatelessWidget {
  final BacktestResult r;
  final double current;
  final ValueChanged<double> onUse;
  const _BestThresholds({required this.r, required this.current, required this.onUse});

  static const minBets = 30;

  ThresholdRow? _best(bool Function(ThresholdRow) ok, double Function(ThresholdRow) score) {
    ThresholdRow? b;
    for (final row in r.sweep) {
      if (!ok(row)) continue;
      if (b == null || score(row) > score(b)) b = row;
    }
    return b;
  }

  @override
  Widget build(BuildContext context) {
    final byProfit = _best((x) => x.bets > 0, (x) => x.profit);
    final byRoi = _best((x) => x.bets >= minBets, (x) => x.roi);
    final byClv = _best((x) => x.clvChecked >= minBets, (x) => x.clvShare);
    final bySafe = _best((x) => x.bets >= minBets, (x) => x.lowerBound);
    final picks = <(String, String, ThresholdRow?, String Function(ThresholdRow))>[
      ('Guadagno totale', 'Quella che avrebbe fatto guadagnare (o perdere meno) più euro.', byProfit,
          (x) => '${signedEuro(x.profit)} con ${x.bets} giocate'),
      ('ROI', 'Quella con il miglior guadagno in percentuale sul puntato, con almeno $minBets giocate.', byRoi,
          (x) => '${signedPct(x.roi)} su ${x.bets} giocate'),
      ('Quote poi scese', 'Quella in cui il modello ha anticipato più spesso il mercato, con almeno $minBets giocate.',
          byClv, (x) => '${pct(x.clvShare)} di ${x.clvChecked} giocate'),
      ('Più prudente', 'Quella con il risultato migliore anche nel caso sfavorevole (ROI meno il margine dovuto al caso).',
          bySafe, (x) => 'nel caso sfavorevole ${signedPct(x.lowerBound)}'),
    ];
    final allNegative = byProfit != null && byProfit.profit < 0;
    final distinct = {for (final p in picks) if (p.$3 != null) p.$3!.threshold}.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 22),
      const Text('Soglia migliore', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
      const SizedBox(height: 4),
      const Text('Provate tutte le soglie da 1,00 a 1,20 sulle stesse stagioni.',
          style: TextStyle(fontSize: 13, color: C.grey)),
      const SizedBox(height: 10),
      for (final p in picks)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.$1, style: const TextStyle(fontSize: 13, color: C.grey)),
                const SizedBox(height: 2),
                Text(
                  p.$3 == null ? 'Troppe poche giocate' : fmt(p.$3!.threshold),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink),
                ),
                if (p.$3 != null)
                  Text(p.$4(p.$3!), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: C.ink2)),
                const SizedBox(height: 3),
                Text(p.$2, style: const TextStyle(fontSize: 12, height: 1.35, color: C.grey)),
              ]),
            ),
            if (p.$3 != null)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                onPressed: (p.$3!.threshold - current).abs() < 0.001 ? null : () => onUse(p.$3!.threshold),
                child: Text((p.$3!.threshold - current).abs() < 0.001 ? 'In uso' : 'Usa',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      if (allNegative)
        const Notice(
          'Con nessuna soglia il modello avrebbe guadagnato su queste stagioni: la soglia “migliore” è solo quella che perde meno.',
          tone: Tone.warning,
        ),
      Notice(
        'Scegliere la soglia guardando le stesse stagioni su cui la misuri fa sembrare i risultati migliori di quanto siano: '
        'provando 21 soglie, una fortunata salta fuori quasi sempre. Per controllare, cambia le stagioni di prova '
        '(per esempio “Ultima” invece di “Ultime 3”) e guarda se la soglia resta buona. '
        '${distinct >= 3 ? 'Qui i criteri indicano soglie molto diverse: è un segno che nessuna è davvero migliore delle altre. ' : ''}'
        'L’errore non compare perché non dipende dalla soglia: misura le probabilità, non quali scommesse fai.',
        title: 'Attenzione al caso',
      ),
      const SizedBox(height: 14),
      const Text('Tutte le soglie', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink)),
      const SizedBox(height: 8),
      _SweepTable(rows: r.sweep, current: current),
    ]);
  }
}

class _SweepTable extends StatelessWidget {
  final List<ThresholdRow> rows;
  final double current;
  const _SweepTable({required this.rows, required this.current});

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.grey);
    const cell = TextStyle(fontSize: 13, color: C.ink, fontFeatures: [FontFeature.tabularFigures()]);
    Widget c(String t, TextStyle st, double w) => SizedBox(width: w, child: Text(t, style: st, textAlign: TextAlign.right));
    return Container(
      decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(children: [
            c('Soglia', head, 46),
            const Spacer(),
            c('Giocate', head, 52),
            c('Risultato', head, 76),
            c('ROI', head, 58),
            c('Scese', head, 46),
          ]),
        ),
        const Divider(height: 1, color: C.line),
        for (final x in rows)
          Container(
            color: (x.threshold - current).abs() < 0.001 ? C.blueTint : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(children: [
              c(fmt(x.threshold), cell.copyWith(fontWeight: FontWeight.w600), 46),
              const Spacer(),
              c('${x.bets}', cell, 52),
              c(x.bets == 0 ? '—' : signedEuro(x.profit), cell.copyWith(color: x.profit < 0 ? C.warn : C.ink), 76),
              c(x.bets == 0 ? '—' : signedPct(x.roi), cell, 58),
              c(x.clvChecked == 0 ? '—' : pct(x.clvShare), cell, 46),
            ]),
          ),
      ]),
    );
  }
}

class _Explain extends StatelessWidget {
  final String title;
  final String text;
  const _Explain(this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.ink)),
        const SizedBox(height: 3),
        Text(text, style: const TextStyle(fontSize: 13, height: 1.45, color: C.ink2)),
      ]),
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
  final early = TextEditingController();
  final halfLife = TextEditingController();
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
    early.text = fmt(s.early * 100, 0);
    halfLife.text = fmt(s.dcHalfLife, 0);
    _ready = true;
  }

  @override
  void dispose() {
    for (final c in [apiKey, budget, threshold, k, home, regress, early, halfLife]) {
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
    final calibSeasons = [for (var y = app.currentSeason - 1; y >= firstSeason; y--) y];

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
                  sub: app.requestsRemaining == null
                      ? null
                      : app.requestsUsed == null
                          ? 'Richieste rimaste: ${app.requestsRemaining}'
                          : 'Richieste rimaste: ${app.requestsRemaining} su ${app.requestsRemaining! + app.requestsUsed!}',
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
            footer: (s.autoCalib
                    ? 'La calibrazione automatica prova centinaia di combinazioni sulle stagioni scelte e tiene quella che prevede meglio. '
                    : 'Dopo aver cambiato i valori, premi “Ricalcola con questi valori”. ') +
                'Dixon-Coles stima attacco e difesa di ogni squadra dai gol, dando più peso alle partite recenti, '
                'e calcola anche over/under 2,5 e goal/no goal. La classifica Elo resta sempre disponibile. '
                'Le stagioni scelte servono anche a stimare la probabilità dei pareggi. La prima stagione dei dati '
                '(${seasonLabel(firstSeason)}) serve solo ad avviare i punteggi. Nella verifica sul passato la calibrazione '
                'si ferma comunque prima delle stagioni di prova.',
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
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: s.model,
                    backgroundColor: C.fill2,
                    children: const {
                      'elo': Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Previsioni con Elo')),
                      'dc': Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Con Dixon-Coles')),
                    },
                    onValueChanged: (v) {
                      s.model = v ?? 'elo';
                      save();
                    },
                  ),
                ),
              ),
              _SeasonRow(
                label: 'Calibra dalla stagione',
                value: seasonLabel(s.calibFrom),
                onTap: () async {
                  final picked = await pickSeason(context, calibSeasons, s.calibFrom);
                  if (picked == null || picked == 0) return;
                  s.calibFrom = picked;
                  if (s.calibTo != 0 && s.calibTo < picked) s.calibTo = picked;
                  save();
                },
              ),
              _SeasonRow(
                label: 'Fino alla stagione',
                value: s.calibTo == 0 ? 'Ultima completa' : seasonLabel(s.calibTo),
                onTap: () async {
                  final picked = await pickSeason(context, calibSeasons, s.calibTo, zeroLabel: 'Ultima completa');
                  if (picked == null) return;
                  s.calibTo = picked;
                  if (picked != 0 && s.calibFrom > picked) s.calibFrom = picked;
                  save();
                },
              ),
              if (!s.autoCalib) ...[
                SettingRow(
                  label: 'Fattore K',
                  sub: 'Dal girone di ritorno; di solito tra 15 e 30',
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
                  label: 'K in più a inizio stagione',
                  sub: 'Alla 1ª giornata, poi scende fino alla 19ª. 0% = K fisso',
                  trailing: SmallField(
                    controller: early,
                    suffix: '%',
                    onChanged: (v) {
                      final n = _num(v);
                      if (n != null && n >= 0 && n <= 400) {
                        s.early = n / 100;
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
              if (!s.autoCalib && s.model == 'dc')
                SettingRow(
                  label: 'Emivita Dixon-Coles',
                  sub: 'Giorni dopo cui una partita conta la metà',
                  trailing: SmallField(
                    controller: halfLife,
                    suffix: 'gg',
                    onChanged: (v) {
                      final n = _num(v);
                      if (n != null && n >= 20 && n <= 2000) {
                        s.dcHalfLife = n;
                        save();
                      }
                    },
                  ),
                ),
              SettingRow(
                label: 'Valori in uso',
                sub: '${kCurve(p)}. Vantaggio casa +${fmt(p.home, 0)}, riavvicinamento estivo ${fmt(p.regress * 100, 0)}%.'
                    '${s.model == 'dc' ? ' Emivita Dixon-Coles: ${fmt(app.halfLifeInUse, 0)} giorni.' : ''}',
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

class _SeasonRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _SeasonRow({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SettingRow(
        label: label,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: const TextStyle(fontSize: 15, color: C.blue)),
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_right, size: 14, color: C.mid),
        ]),
      ),
    );
  }
}
