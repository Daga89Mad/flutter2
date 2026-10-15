// lib/views/calculatorScreen.dart

import 'package:flutter/material.dart';

/// Calculadora de progresión (martingala) para apuestas al empate.
/// La apuesta se duplica tras cada partido sin empate.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final TextEditingController _oddsCtrl = TextEditingController(text: '2.80');
  final TextEditingController _stakeCtrl = TextEditingController(text: '0.50');
  double _misses = 6;

  static const int _maxMisses = 12;

  @override
  void dispose() {
    _oddsCtrl.dispose();
    _stakeCtrl.dispose();
    super.dispose();
  }

  double _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

  String _money(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    final negative = intPart.startsWith('-');
    final digits = negative ? intPart.substring(1) : intPart;
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return '${negative ? '-' : ''}$buf,${parts[1]} €';
  }

  @override
  Widget build(BuildContext context) {
    final odds = _parse(_oddsCtrl.text);
    final stake = _parse(_stakeCtrl.text);
    final n = _misses.round();

    // Pérdida acumulada tras n fallos: stake * (2^n - 1)
    double lost = 0;
    double next = stake;
    for (int i = 0; i < n; i++) {
      lost += next;
      next *= 2;
    }
    final profitIfHit = next * odds - next - lost;
    final lossIfMiss = lost + next;

    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.7),
    );
    const valueSize = 26.0;

    Widget field(String label, TextEditingController ctrl) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        );

    Widget result(String label, double value, Color? color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 6),
                Text(
                  _money(value),
                  style: TextStyle(
                    fontSize: valueSize,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Calculadora')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    field('Cuota del empate', _oddsCtrl),
                    const SizedBox(width: 16),
                    field('Apuesta inicial (€)', _stakeCtrl),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Partidos consecutivos sin empate',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '$n',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: _misses,
                  min: 0,
                  max: _maxMisses.toDouble(),
                  divisions: _maxMisses,
                  label: '$n',
                  onChanged: (v) => setState(() => _misses = v),
                ),
                const Divider(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    result('Perdido hasta ahora', lost, Colors.red),
                    const SizedBox(width: 16),
                    result('Siguiente apuesta', next, null),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    result('Beneficio si acierta ahora', profitIfHit,
                        profitIfHit >= 0 ? Colors.green : Colors.red),
                    const SizedBox(width: 16),
                    result('Pérdida si vuelve a fallar', lossIfMiss,
                        Colors.red),
                  ],
                ),
                Text(
                  'Simulación matemática con una cuota fija y sin límites '
                  'de apuesta. No constituye una predicción.',
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
