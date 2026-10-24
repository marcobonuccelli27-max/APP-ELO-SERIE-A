// Colori, formati e componenti grafici condivisi.

import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class C {
  static const ink = Color(0xFF1D1D1F);
  static const ink2 = Color(0xFF3A3A3C);
  static const grey = Color(0xFF6E6E73);
  static const fill = Color(0xFFF5F5F7);
  static const fill2 = Color(0xFFE3E3E8);
  static const line = Color(0xFFE5E5EA);
  static const mid = Color(0xFFAEAEB2);
  static const light = Color(0xFFD2D2D7);
  static const blue = Color(0xFF0071E3);
  static const blueText = Color(0xFF0055B3);
  static const blueTint = Color(0xFFE5F0FF);
  static const warn = Color(0xFFA33A00);
  static const warnTint = Color(0xFFFFF4EC);
  static const white = Color(0xFFFFFFFF);
}

const _tab = [FontFeature.tabularFigures()];

// ---------------------------------------------------------------------------
// Formati italiani

String fmt(double v, [int decimals = 2]) => v.toStringAsFixed(decimals).replaceAll('.', ',');

String euro(double v, [int decimals = 2]) => '${fmt(v, decimals)} €';

String signedEuro(double v) => '${v >= 0 ? '+' : '−'}${fmt(v.abs())} €';

String pct(double p, [int decimals = 0]) => '${fmt(p * 100, decimals)}%';

String signedPct(double p) => '${p >= 0 ? '+' : '−'}${fmt(p.abs() * 100, 1)}%';

const _days = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

String _two(int n) => n.toString().padLeft(2, '0');

String dateLabel(DateTime? d) {
  if (d == null) return '';
  return '${_days[d.weekday - 1]} ${d.day}/${d.month} · ${_two(d.hour)}:${_two(d.minute)}';
}

String shortDate(DateTime d) => '${_two(d.month)}/${d.year}';

const outcomeLabels = ['1', 'X', '2'];

// ---------------------------------------------------------------------------
// Componenti

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const PageHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subtitle != null)
          Text(subtitle!, style: const TextStyle(fontSize: 13, color: C.grey)),
        const SizedBox(height: 2),
        Text(title,
            style: const TextStyle(
                fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: C.ink)),
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: C.blue,
          disabledBackgroundColor: C.fill2,
          foregroundColor: C.white,
          disabledForegroundColor: C.grey,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
            Text(label),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  const StatCard({super.key, required this.label, required this.value, this.sub, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: C.grey)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: valueColor ?? C.ink,
                    fontFeatures: _tab)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: const TextStyle(fontSize: 12, color: C.grey)),
          ],
        ],
      ),
    );
  }
}

enum Tone { neutral, warning, positive }

class Notice extends StatelessWidget {
  final String? title;
  final String text;
  final Tone tone;
  const Notice(this.text, {super.key, this.title, this.tone = Tone.neutral});

  @override
  Widget build(BuildContext context) {
    final bg = switch (tone) {
      Tone.warning => C.warnTint,
      Tone.positive => C.blueTint,
      Tone.neutral => C.fill,
    };
    final fg = switch (tone) {
      Tone.warning => C.warn,
      Tone.positive => C.blueText,
      Tone.neutral => C.grey,
    };
    final icon = switch (tone) {
      Tone.warning => CupertinoIcons.exclamationmark_circle,
      Tone.positive => CupertinoIcons.checkmark_circle,
      Tone.neutral => CupertinoIcons.info_circle,
    };
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink)),
                  const SizedBox(height: 3),
                ],
                Text(text, style: const TextStyle(fontSize: 13, height: 1.45, color: C.ink2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra divisa in tre parti: probabilità di 1, X e 2.
class ProbBar extends StatelessWidget {
  final List<double> p;
  const ProbBar(this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    const colors = [C.blue, C.mid, C.ink];
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            for (var k = 0; k < 3; k++) ...[
              if (k > 0) const SizedBox(width: 2),
              Expanded(
                flex: (p[k] * 1000).round().clamp(1, 1000).toInt(),
                child: Container(color: colors[k]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gruppo di righe in stile Impostazioni di iOS.
class Group extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  final String? footer;
  const Group({super.key, required this.title, required this.rows, this.footer});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const Divider(height: 1, thickness: 1, color: C.line, indent: 16));
      children.add(rows[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 8),
            child: Text(title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.grey)),
          ),
          Container(
            decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(12)),
            child: Column(children: children),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(footer!, style: const TextStyle(fontSize: 12, height: 1.4, color: C.grey)),
            ),
        ],
      ),
    );
  }
}

class SettingRow extends StatelessWidget {
  final String label;
  final String? sub;
  final Widget? trailing;
  const SettingRow({super.key, required this.label, this.sub, this.trailing});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 15, color: C.ink)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!, style: const TextStyle(fontSize: 12, color: C.grey)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class SmallField extends StatelessWidget {
  final TextEditingController controller;
  final double width;
  final bool numeric;
  final bool obscure;
  final String? suffix;
  final ValueChanged<String> onChanged;
  final bool enabled;
  const SmallField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.width = 96,
    this.numeric = true,
    this.obscure = false,
    this.suffix,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: CupertinoTextField(
        controller: controller,
        onChanged: onChanged,
        enabled: enabled,
        obscureText: obscure,
        autocorrect: false,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: TextStyle(fontSize: 15, color: enabled ? C.ink : C.grey),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        suffix: suffix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(suffix!, style: const TextStyle(fontSize: 15, color: C.grey)),
              ),
        decoration: BoxDecoration(
          color: C.white,
          border: Border.all(color: C.light),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Grafico dell'andamento del budget.
class BankrollPainter extends CustomPainter {
  final List<double> values;
  final double start;
  BankrollPainter(this.values, this.start);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (start < lo) lo = start;
    if (start > hi) hi = start;
    final pad = (hi - lo) * 0.1 + 1;
    lo -= pad;
    hi += pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    final dash = Paint()
      ..color = C.light
      ..strokeWidth = 1;
    final yb = y(start);
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, yb), Offset(x + 4, yb), dash);
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      if (i == 0) {
        path.moveTo(x, y(values[i]));
      } else {
        path.lineTo(x, y(values[i]));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = C.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant BankrollPainter old) => old.values != values || old.start != start;
}
