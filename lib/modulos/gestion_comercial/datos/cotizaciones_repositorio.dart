import 'dart:convert';
import 'dart:typed_data';

import '../../../core/supabase_client.dart';
import '../dominio/cotizacion_importada.dart';

/// Importación automática de una cotización desde su PDF (Edge Function
/// `importar-cotizacion`). No guarda nada: devuelve los datos para el formulario.
class CotizacionesRepositorio {
  Future<CotizacionImportada> importarPdf(Uint8List pdf) async {
    final res = await supabase.functions.invoke(
      'importar-cotizacion',
      body: {'pdfBase64': base64Encode(pdf)},
    );
    return CotizacionImportada.fromMap(res.data as Map<String, dynamic>);
  }
}
