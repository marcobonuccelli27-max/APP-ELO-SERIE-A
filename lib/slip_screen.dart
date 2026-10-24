// Schermata Schedina: foto o screenshot, lettura del testo, correzione e analisi.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'slip.dart';
import 'state.dart';
import 'widgets.dart';

const _pad = EdgeInsets.fromLTRB(20, 16, 20, 40);

/// Legge il testo della foto e lo ricompone per righe, da sinistra a destra.
Future<List<String>> readSlipRows(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    final lines = <_OcrLine>[];
    for (final b in result.blocks) {
      for (final l in b.lines) {
        final r = l.boundingBox;
        lines.add(_OcrLine(l.text, r.top, r.bottom, r.left));
      }
    }
    lines.sort((a, b) => a.cy.compareTo(b.cy));
    final rows = <List<_OcrLine>>[];
    for (final l in lines) {
      if (rows.isNotEmpty) {
        final row = rows.last;
        final ref = row.first;
        final tol = 0.55 * (l.h < ref.h ? l.h : ref.h);
        if ((l.cy - ref.cy).abs() <= tol) {
          row.add(l);
          continue;
        }
      }
      rows.add([l]);
    }
    return [
      for (final row in rows) (row..sort((a, b) => a.left.compareTo(b.left))).map((l) => l.text).join('  ')
    ];
  } finally {
    await recognizer.close();
  }
}

class _OcrLine {
  final String text;
  final double top, bottom, left;
  _OcrLine(this.text, this.top, this.bottom, this.left);
  double get cy => (top + bottom) / 2;
  double get h => bottom - top;
}

String _f(double v, [int d = 2]) => fmt(v, d);

double? _num(String t) => double.tryParse(t.replaceAll(',', '.').replaceAll('€', '').trim());

class SchedinaScreen extends StatefulWidget {
  const SchedinaScreen({super.key});
  @override
  State<SchedinaScreen> createState() => _SchedinaScreenState();
}

class _SchedinaScreenState extends State<SchedinaScreen> {
  List<Leg> legs = [];
  final stakeCtl = TextEditingController(text: '2');
  final bonusCtl = TextEditingController(text: '0');
  bool reading = false;
  bool analyzing = false;
  String? message;
  List<String> rawRows = [];
  SlipAnalysis? analysis;

  @override
  void dispose() {
    stakeCtl.dispose();
    bonusCtl.dispose();
    super.dispose();
  }

  Future<void> _pick(AppState app, ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 95, maxWidth: 2400);
    if (x == null) return;
    setState(() {
      reading = true;
      message = null;
      analysis = null;
    });
    try {
      await app.ensureHistoryLoaded();
      final known = app.knownTeams;
      if (known.isEmpty) {
        setState(() => message = 'Prima premi “Aggiorna dati” nella schermata Giornata: servono i dati delle squadre.');
        return;
      }
      final rows = await readSlipRows(x.path);
      final parsed = parseSlip(rows, known);
      setState(() {
        rawRows = rows;
        legs = parsed.legs;
        if (parsed.stake != null) stakeCtl.text = _f(parsed.stake!);
        bonusCtl.text = _f(parsed.bonus ?? 0);
        message = parsed.legs.isEmpty
            ? 'Non ho trovato partite di Serie A nella foto. Prova con una foto più dritta e illuminata, '
                'oppure inserisci le giocate a mano.'
            : 'Ho letto ${parsed.legs.length} giocate. Controllale e correggi quello che serve, poi premi “Analizza”.';
      });
    } catch (e) {
      setState(() => message = 'Non riesco a leggere la foto: $e');
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  Future<void> _analyze(AppState app) async {
    setState(() {
      analyzing = true;
      message = null;
    });
    try {
      final a = await app.analyzeSlip(legs, _num(stakeCtl.text) ?? 0, _num(bonusCtl.text) ?? 0);
      if (mounted) setState(() => analysis = a);
    } catch (e) {
      if (mounted) setState(() => message = 'Analisi non riuscita: $e');
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Future<void> _edit(AppState app, int? index) async {
    await app.ensureHistoryLoaded();
    if (!mounted) return;
    final leg = index == null ? Leg() : legs[index].copy();
    final res = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LegEditor(leg: leg, teams: app.recentTeams, isNew: index == null),
    );
    if (res == null) return;
    setState(() {
      analysis = null;
      if (res.delete) {
        if (index != null) legs.removeAt(index);
      } else if (index == null) {
        legs.add(res.leg);
      } else {
        legs[index] = res.leg;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final busy = reading || analyzing;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: _pad,
        children: [
          const PageHeader(title: 'Controlla una schedina', subtitle: 'Foto, screenshot o a mano'),
          const SizedBox(height: 18),
          PrimaryButton(
            label: reading ? 'Leggo la schedina…' : 'Fotografa la schedina',
            icon: CupertinoIcons.camera,
            onPressed: busy ? null : () => _pick(app, ImageSource.camera),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Dalla galleria',
                icon: CupertinoIcons.photo,
                onPressed: busy ? null : () => _pick(app, ImageSource.gallery),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SecondaryButton(
                label: 'Aggiungi a mano',
                icon: CupertinoIcons.add,
                onPressed: busy ? null : () => _edit(app, null),
              ),
            ),
          ]),
          if (message != null) Notice(message!),
          if (legs.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Giocate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
            const SizedBox(height: 4),
            const Text('Tocca una giocata per correggerla.', style: TextStyle(fontSize: 13, color: C.grey)),
            const SizedBox(height: 10),
            for (var i = 0; i < legs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LegCard(
                  leg: legs[i],
                  result: analysis != null && i < analysis!.legs.length ? analysis!.legs[i] : null,
                  threshold: app.settings.threshold,
                  onTap: busy ? null : () => _edit(app, i),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Expanded(child: Text('Importo giocato', style: TextStyle(fontSize: 15, color: C.ink))),
                SmallField(controller: stakeCtl, suffix: '€', onChanged: (_) => setState(() => analysis = null)),
                const SizedBox(width: 14),
                const Text('Bonus', style: TextStyle(fontSize: 15, color: C.ink)),
                const SizedBox(width: 8),
                SmallField(controller: bonusCtl, width: 80, suffix: '€', onChanged: (_) => setState(() => analysis = null)),
              ]),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: analyzing ? 'Analizzo…' : 'Analizza la schedina',
              icon: CupertinoIcons.chart_bar_alt_fill,
              onPressed: busy ? null : () => _analyze(app),
            ),
            if (analysis != null) _Summary(a: analysis!),
            if (rawRows.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Testo letto dalla foto', style: TextStyle(fontSize: 14, color: C.grey)),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(12)),
                      child: SelectableText(rawRows.join('\n'),
                          style: const TextStyle(fontSize: 12, height: 1.4, color: C.ink2)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const _SecondaryButton({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: C.blue,
          side: const BorderSide(color: C.light),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _LegCard extends StatelessWidget {
  final Leg leg;
  final LegResult? result;
  final double threshold;
  final VoidCallback? onTap;
  const _LegCard({required this.leg, required this.result, required this.threshold, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = result;
    final missing = leg.home.isEmpty || leg.away.isEmpty || leg.odds <= 1;
    return Material(
      color: C.fill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  leg.home.isEmpty ? 'Partita da scegliere' : '${leg.home} – ${leg.away}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink),
                ),
              ),
              Text(leg.odds > 1 ? _f(leg.odds) : 'quota ?',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.ink)),
            ]),
            const SizedBox(height: 3),
            Text('${marketNames[leg.type]}: ${leg.selectionLabel}',
                style: const TextStyle(fontSize: 13, color: C.ink2)),
            if (leg.marketGuessed || missing)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Da controllare: tocca per correggere.', style: TextStyle(fontSize: 12, color: C.warn)),
              ),
            if (r != null && r.p != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _chip('Modello ${pct(r.p!, 1)}', C.white, C.ink),
                if (leg.odds > 1) _chip('Quota ${pct(1 / leg.odds, 1)}', C.white, C.ink),
                if (r.value != null)
                  _chip(
                    'Valore ${_f(r.value!)}',
                    r.value! >= threshold && !r.unlikely ? C.blueTint : C.white,
                    r.value! >= threshold && !r.unlikely ? C.blueText : C.ink,
                  ),
              ]),
              const SizedBox(height: 8),
              Text(_verdict(r), style: TextStyle(fontSize: 12.5, height: 1.4, color: _verdictColor(r))),
              if (r.score != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Finita ${r.score}: giocata ${r.won == true ? 'vinta' : 'persa'}.',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: r.won == true ? C.blueText : C.warn),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  String _verdict(LegResult r) {
    final p = r.p!;
    final v = r.value;
    if (v == null) return 'Manca la quota: inseriscila per calcolare il valore.';
    if (r.unlikely) {
      return 'Sconsigliata: secondo il modello succede solo il ${pct(p)} delle volte, '
          'circa una volta su ${(1 / p).round()}${v >= threshold ? ', anche se la quota è conveniente' : ''}.';
    }
    if (v >= threshold) return 'Ha valore: il modello la stima più probabile di quanto dica la quota.';
    if (v >= 1) return 'Valore appena sopra 1, sotto la tua soglia: vantaggio troppo piccolo.';
    return 'Senza valore: la quota paga meno di quanto servirebbe per il rischio.';
  }

  Color _verdictColor(LegResult r) {
    if (r.value == null) return C.grey;
    if (r.unlikely) return C.warn;
    if (r.value! >= threshold) return C.blueText;
    return C.grey;
  }
}

Widget _chip(String t, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );

class _Summary extends StatelessWidget {
  final SlipAnalysis a;
  const _Summary({required this.a});

  @override
  Widget build(BuildContext context) {
    if (!a.complete) {
      return const Notice('Completa partite e quote di tutte le giocate per avere il riepilogo della schedina.',
          tone: Tone.warning);
    }
    final p = a.modelProb;
    final back = a.expectedReturn * 100;
    final oneIn = p > 0 ? (1 / p).round() : 0;
    final won = a.won;
    final good = a.expectedReturn > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),
      const Text('La schedina intera', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: StatCard(label: 'Quota totale', value: _f(a.totalOdds), sub: 'vincita ${euro(a.payout)}')),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Probabilità di vincerla',
            value: pct(p, p < 0.1 ? 2 : 1),
            sub: 'circa 1 volta su $oneIn',
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: StatCard(
            label: 'Secondo le quote',
            value: pct(a.impliedProb, a.impliedProb < 0.1 ? 2 : 1),
            sub: 'margine compreso',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Su 100 € giocati così',
            value: euro(back, 0),
            valueColor: good ? C.blueText : C.warn,
            sub: 'tornano in media',
          ),
        ),
      ]),
      Notice(
        good
            ? 'Secondo il modello questa schedina ha un valore atteso positivo: in media ti tornerebbero '
                '${euro(back, 0)} ogni 100 € giocati. È una stima: anche un modello buono sbaglia, e la '
                'probabilità di vincerla resta di circa una su $oneIn.'
            : 'In media, su 100 € giocati in schedine come questa te ne tornerebbero ${euro(back, 0)}: '
                'perderesti ${euro(100 - back, 0)}. Ogni partita aggiunta moltiplica anche il margine del bookmaker. '
                'Per la stessa cifra, le giocate singole con valore rendono di più.',
        title: good ? 'Valore atteso positivo' : 'Valore atteso negativo',
        tone: good ? Tone.positive : Tone.warning,
      ),
      if (won != null)
        Notice(
          won ? 'Tutte le partite sono già finite e la schedina è vincente.' : 'Almeno una giocata è già persa: la schedina è perdente.',
          title: won ? 'Schedina vinta' : 'Schedina persa',
          tone: won ? Tone.positive : Tone.neutral,
        ),
      Padding(
        padding: const EdgeInsets.only(top: 12, left: 4),
        child: Text(
          '${a.fitNote} “Secondo le quote” è la probabilità che il bookmaker ti paga (1 ÷ quota totale). '
          'Se il modello stima meno di quella, la schedina è svantaggiosa.',
          style: const TextStyle(fontSize: 12, height: 1.45, color: C.grey),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Modifica di una giocata

class _EditResult {
  final Leg leg;
  final bool delete;
  _EditResult(this.leg, {this.delete = false});
}

Future<String?> _pickTeam(BuildContext context, List<String> teams, String current) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: C.white,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: ListView(shrinkWrap: true, children: [
          for (final t in teams)
            ListTile(
              title: Text(t),
              trailing: t == current ? const Icon(CupertinoIcons.checkmark_alt, color: C.blue) : null,
              onTap: () => Navigator.pop(ctx, t),
            ),
        ]),
      ),
    ),
  );
}

class _LegEditor extends StatefulWidget {
  final Leg leg;
  final List<String> teams;
  final bool isNew;
  const _LegEditor({required this.leg, required this.teams, required this.isNew});
  @override
  State<_LegEditor> createState() => _LegEditorState();
}

class _LegEditorState extends State<_LegEditor> {
  late final Leg leg = widget.leg;
  late final odds = TextEditingController(text: leg.odds > 1 ? _f(leg.odds) : '');

  @override
  void dispose() {
    odds.dispose();
    super.dispose();
  }

  Widget _seg<T extends Object>(Map<T, String> items, T value, ValueChanged<T> onChanged) => SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: items.containsKey(value) ? value : null,
          backgroundColor: C.fill2,
          children: {
            for (final e in items.entries)
              e.key: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Text(e.value)),
          },
          onValueChanged: (v) {
            if (v != null) setState(() => onChanged(v));
          },
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 13, color: C.grey)),
      );

  Widget _stepper(String title, int value, ValueChanged<int> onChanged) => Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15, color: C.ink))),
        CupertinoButton(
          padding: const EdgeInsets.all(6),
          onPressed: value > 0 ? () => setState(() => onChanged(value - 1)) : null,
          child: const Icon(CupertinoIcons.minus_circle, size: 26),
        ),
        SizedBox(
          width: 28,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: C.ink)),
        ),
        CupertinoButton(
          padding: const EdgeInsets.all(6),
          onPressed: value < 9 ? () => setState(() => onChanged(value + 1)) : null,
          child: const Icon(CupertinoIcons.plus_circle, size: 26),
        ),
      ]);

  Widget _teamButton(String label, String value, ValueChanged<String> onPicked) => Expanded(
        child: Material(
          color: C.fill,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final t = await _pickTeam(context, widget.teams, value);
              if (t != null) setState(() => onPicked(t));
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12, color: C.grey)),
                const SizedBox(height: 2),
                Text(value.isEmpty ? 'Scegli' : value,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: value.isEmpty ? C.blue : C.ink)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = leg.type;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.isNew ? 'Nuova giocata' : 'Modifica giocata',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
            _label('Partita'),
            Row(children: [
              _teamButton('Casa', leg.home, (v) => leg.home = v),
              const SizedBox(width: 10),
              _teamButton('Ospite', leg.away, (v) => leg.away = v),
            ]),
            _label('Mercato'),
            Material(
              color: C.fill,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showModalBottomSheet<MarketType>(
                    context: context,
                    backgroundColor: C.white,
                    showDragHandle: true,
                    builder: (ctx) => SafeArea(
                      child: ListView(shrinkWrap: true, children: [
                        for (final m in MarketType.values)
                          ListTile(
                            title: Text(marketNames[m]!),
                            trailing: m == leg.type ? const Icon(CupertinoIcons.checkmark_alt, color: C.blue) : null,
                            onTap: () => Navigator.pop(ctx, m),
                          ),
                      ]),
                    ),
                  );
                  if (picked == null) return;
                  setState(() {
                    leg.type = picked;
                    leg.marketGuessed = false;
                    if (usesDoubleChance(picked) && leg.s1.length == 1) leg.s1 = '1X';
                    if (!usesDoubleChance(picked) && leg.s1.length == 2) leg.s1 = '1';
                    if (usesGg(picked) && leg.s2 != 'GG' && leg.s2 != 'NG') leg.s2 = 'GG';
                    if (usesLine(picked) && leg.s2 != 'O' && leg.s2 != 'U') leg.s2 = 'O';
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                      child: Text(marketNames[t]!,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink)),
                    ),
                    const Icon(CupertinoIcons.chevron_down, size: 14, color: C.blue),
                  ]),
                ),
              ),
            ),
            if (usesS1(t)) ...[
              _label('Esito'),
              usesDoubleChance(t)
                  ? _seg<String>(const {'1X': '1X', 'X2': 'X2', '12': '12'}, leg.s1, (v) => leg.s1 = v)
                  : _seg<String>(const {'1': '1', 'X': 'X', '2': '2'}, leg.s1, (v) => leg.s1 = v),
            ],
            if (usesLine(t)) ...[
              _label('Under o over'),
              _seg<String>(const {'U': 'Under', 'O': 'Over'}, leg.s2, (v) => leg.s2 = v),
              _label('Soglia gol'),
              _seg<double>({0.5: '0,5', 1.5: '1,5', 2.5: '2,5', 3.5: '3,5', 4.5: '4,5'}, leg.line,
                  (v) => leg.line = v),
            ],
            if (usesGg(t)) ...[
              _label('Goal o no goal'),
              _seg<String>(const {'GG': 'Goal', 'NG': 'No goal'}, leg.s2, (v) => leg.s2 = v),
            ],
            if (usesRanges(t)) ...[
              _label(t == MarketType.multigoalSquadre ? 'Gol della squadra di casa' : 'Gol totali della partita'),
              _stepper('Da', leg.h1, (v) => leg.h1 = v > leg.h2 ? leg.h2 : v),
              _stepper('A', leg.h2 > 9 ? 9 : leg.h2, (v) => leg.h2 = v < leg.h1 ? leg.h1 : v),
              if (t == MarketType.multigoalSquadre) ...[
                _label('Gol della squadra ospite'),
                _stepper('Da', leg.a1, (v) => leg.a1 = v > leg.a2 ? leg.a2 : v),
                _stepper('A', leg.a2 > 9 ? 9 : leg.a2, (v) => leg.a2 = v < leg.a1 ? leg.a1 : v),
              ],
              _label('Giocata'),
              _seg<bool>(const {true: 'Sì', false: 'No'}, leg.yes, (v) => leg.yes = v),
            ],
            _label('Quota'),
            SmallField(controller: odds, width: 120, onChanged: (_) {}),
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Salva',
              onPressed: () {
                leg.odds = _num(odds.text) ?? 0;
                leg.homeKnown = leg.home.isNotEmpty;
                leg.awayKnown = leg.away.isNotEmpty;
                Navigator.pop(context, _EditResult(leg));
              },
            ),
            if (!widget.isNew)
              Center(
                child: CupertinoButton(
                  onPressed: () => Navigator.pop(context, _EditResult(leg, delete: true)),
                  child: const Text('Elimina giocata', style: TextStyle(color: C.warn, fontSize: 15)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
