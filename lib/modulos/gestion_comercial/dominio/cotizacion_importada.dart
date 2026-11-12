import 'dart:convert';
import 'dart:typed_data';

/// Producto leído de la tabla de la cotización.
class LineaImportada {
  final String descripcion;
  final int unidades;
  final num precioUnidad;
  final num total;

  const LineaImportada({
    required this.descripcion,
    required this.unidades,
    required this.precioUnidad,
    required this.total,
  });

  factory LineaImportada.fromMap(Map<String, dynamic> m) => LineaImportada(
        descripcion: m['descripcion'] as String,
        unidades: (m['unidades'] as num).toInt(),
        precioUnidad: m['precioUnidad'] as num,
        total: m['total'] as num,
      );
}

/// Datos extraídos automáticamente del PDF de una cotización de GyG
/// (Edge Function `importar-cotizacion`).
class CotizacionImportada {
  final DateTime? fechaCotizacion;
  final String? solicitadoPor;
  final String? direccion;
  final String? numeroCotizacion;
  final List<LineaImportada> lineas;
  final num? subtotal;
  final num? iva;
  final num? totalConIva;
  final ({int min, int max})? plazoDiasHabiles;
  final Uint8List? foto;
  final List<String> advertencias;

  const CotizacionImportada({
    required this.lineas,
    required this.advertencias,
    this.fechaCotizacion,
    this.solicitadoPor,
    this.direccion,
    this.numeroCotizacion,
    this.subtotal,
    this.iva,
    this.totalConIva,
    this.plazoDiasHabiles,
    this.foto,
  });

  factory CotizacionImportada.fromMap(Map<String, dynamic> m) {
    final plazo = m['plazoDiasHabiles'] as Map<String, dynamic>?;
    final foto = m['foto'] as Map<String, dynamic>?;
    return CotizacionImportada(
      fechaCotizacion:
          m['fechaCotizacion'] == null ? null : DateTime.parse(m['fechaCotizacion'] as String),
      solicitadoPor: m['solicitadoPor'] as String?,
      direccion: m['direccion'] as String?,
      numeroCotizacion: m['numeroCotizacion'] as String?,
      lineas: ((m['lineas'] as List?) ?? const [])
          .map((l) => LineaImportada.fromMap(l as Map<String, dynamic>))
          .toList(),
      subtotal: m['subtotal'] as num?,
      iva: m['iva'] as num?,
      totalConIva: m['totalConIva'] as num?,
      plazoDiasHabiles: plazo == null
          ? null
          : (min: (plazo['min'] as num).toInt(), max: (plazo['max'] as num).toInt()),
      foto: foto == null ? null : base64Decode(foto['base64'] as String),
      advertencias: ((m['advertencias'] as List?) ?? const []).cast<String>(),
    );
  }
}

/// Suma días hábiles (lunes a viernes) a una fecha. No considera feriados.
DateTime sumarDiasHabiles(DateTime desde, int dias) {
  var fecha = DateTime(desde.year, desde.month, desde.day);
  var restantes = dias;
  while (restantes > 0) {
    fecha = fecha.add(const Duration(days: 1));
    if (fecha.weekday != DateTime.saturday && fecha.weekday != DateTime.sunday) restantes--;
  }
  return fecha;
}

/// Normaliza un nombre de producto para compararlo con el catálogo
/// (sin mayúsculas, tildes ni espacios repetidos).
String normalizarNombre(String texto) {
  const conTilde = 'áéíóúüñ';
  const sinTilde = 'aeiouun';
  final minuscula = texto.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final c in minuscula.split('')) {
    final i = conTilde.indexOf(c);
    buffer.write(i >= 0 ? sinTilde[i] : c);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}
