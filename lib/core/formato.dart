import 'package:intl/intl.dart';

final _clp = NumberFormat.currency(locale: 'es_CL', symbol: '\$', decimalDigits: 0);
final _fecha = DateFormat('dd-MM-yyyy');
final _fechaHora = DateFormat('dd-MM-yyyy HH:mm');

/// Monto en pesos chilenos, sin decimales (ej. $1.234.567).
String formatoClp(num? valor) => valor == null ? '—' : _clp.format(valor);

String formatoFecha(DateTime? fecha) => fecha == null ? '—' : _fecha.format(fecha);

String formatoFechaHora(DateTime? fecha) =>
    fecha == null ? '—' : _fechaHora.format(fecha.toLocal());

/// Fecha en formato ISO (YYYY-MM-DD) para columnas `date` de PostgreSQL.
String fechaIso(DateTime fecha) => '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// Fecha de hoy sin hora.
DateTime hoy() {
  final ahora = DateTime.now();
  return DateTime(ahora.year, ahora.month, ahora.day);
}

/// Monto como texto editable, compatible con [parsearMonto]: 12500.0 → "12500",
/// 1234.5 → "1234,5".
String textoMonto(num valor) =>
    valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString().replaceAll('.', ',');

/// Interpreta un monto escrito en formato chileno: "$12.500" → 12500,
/// "1.234,5" → 1234.5. Devuelve `null` si no es un número.
num? parsearMonto(String texto) {
  final limpio = texto.replaceAll(RegExp(r'[\s$]'), '').replaceAll('.', '').replaceAll(',', '.');
  return limpio.isEmpty ? null : num.tryParse(limpio);
}
