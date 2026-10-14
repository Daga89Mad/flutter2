// lib/core/numberUtils.dart

import 'package:flutter/services.dart';

/// Convierte el texto de un campo numérico a double.
///
/// - Acepta tanto '.' como ',' como separador DECIMAL (el teclado de Android
///   puede mostrar uno u otro según el idioma / fabricante).
/// - NO admite separador de miles: "1.000" se interpreta como 1,0 y no 1000.
///   Por eso el campo usa [DecimalTextInputFormatter], que impide escribir
///   más de un separador.
/// - Devuelve null si el texto no es un número válido.
double? parseDecimal(String text) {
  var t = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  if (t.startsWith('.')) t = '0$t'; // ".5" -> "0.5"
  if (t.endsWith('.')) t = '${t}0'; // "5."  -> "5.0"
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
  return double.tryParse(t);
}

/// Redondea a [decimals] decimales (por defecto 2) para evitar
/// arrastrar errores de coma flotante hasta Firestore (p.ej. 20.000000000004).
double roundTo(double value, [int decimals = 2]) {
  var factor = 1.0;
  for (var i = 0; i < decimals; i++) {
    factor *= 10;
  }
  return (value * factor).roundToDouble() / factor;
}

/// Formatea un double para mostrarlo en un campo de texto editable,
/// siempre con '.' como separador decimal.
String formatDecimal(double value, [int decimals = 2]) {
  return value.toStringAsFixed(decimals);
}

/// Formatter para campos de cantidad / cuota:
/// - Solo permite dígitos y UN separador decimal.
/// - Convierte la ',' en '.' mientras se escribe, para que el valor sea
///   siempre homogéneo.
/// - Limita el número de decimales a [decimalDigits].
class DecimalTextInputFormatter extends TextInputFormatter {
  final int decimalDigits;

  DecimalTextInputFormatter({this.decimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Sustituimos ',' por '.' (misma longitud, la selección sigue siendo válida)
    final text = newValue.text.replaceAll(',', '.');
    final regex = RegExp('^\\d*(\\.\\d{0,$decimalDigits})?\$');

    if (!regex.hasMatch(text)) {
      // Entrada no válida (segundo separador, letras, demasiados decimales...)
      return oldValue;
    }

    return newValue.copyWith(text: text);
  }
}
