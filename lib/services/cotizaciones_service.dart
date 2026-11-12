import 'dart:convert';
import 'dart:io';

import '../core/supabase_client.dart';
import '../models/cotizacion.dart';

class CotizacionesService {
  static const _bucket = 'cotizaciones';

  Future<List<Cotizacion>> listar() async {
    final data = await supabase
        .from('cotizaciones')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((m) => Cotizacion.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Cotizaciones que todavía no forman parte de ninguna ruta (candidatas
  /// para armar una ruta nueva).
  Future<List<Cotizacion>> listarSinRuta() async {
    final todas = await listar();
    final usadas = await supabase
        .from('puntos_ruta')
        .select('cotizacion_id')
        .not('cotizacion_id', 'is', null);
    final idsUsados = (usadas as List)
        .map((m) => m['cotizacion_id'] as String)
        .toSet();
    return todas.where((c) => !idsUsados.contains(c.id)).toList();
  }

  /// Envía el PDF a la Edge Function `extract-cotizacion` (Claude) y
  /// devuelve los campos extraídos para que el admin los revise/corrija.
  Future<Map<String, dynamic>> extraerDesdePdf(File pdf) async {
    final bytes = await pdf.readAsBytes();
    final base64Pdf = base64Encode(bytes);
    final res = await supabase.functions.invoke(
      'extract-cotizacion',
      body: {'pdfBase64': base64Pdf},
    );
    if (res.status != 200) {
      throw Exception('No se pudo extraer el PDF (${res.status}): ${res.data}');
    }
    return res.data as Map<String, dynamic>;
  }

  Future<Cotizacion> crear({
    required String titulo,
    required String cliente,
    required num? monto,
    required File pdf,
    required File? foto,
    String? numeroCotizacion,
    DateTime? fechaCotizacion,
    required String direccionEntrega,
    required double direccionLat,
    required double direccionLng,
    String? descripcion,
    num? unidades,
    num? precioUnidad,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final pdfExt = pdf.path.split('.').last;
    final pdfPath = '$userId/pdfs/$stamp.$pdfExt';
    await supabase.storage.from(_bucket).upload(pdfPath, pdf);
    final archivoUrl = await supabase.storage
        .from(_bucket)
        .createSignedUrl(pdfPath, 60 * 60 * 24 * 7);

    String? fotoUrl;
    if (foto != null) {
      final fotoExt = foto.path.split('.').last;
      final fotoPath = '$userId/fotos/$stamp.$fotoExt';
      await supabase.storage.from(_bucket).upload(fotoPath, foto);
      fotoUrl = await supabase.storage
          .from(_bucket)
          .createSignedUrl(fotoPath, 60 * 60 * 24 * 7);
    }

    final data = await supabase
        .from('cotizaciones')
        .insert({
          'titulo': titulo,
          'cliente': cliente,
          'monto': monto,
          'archivo_url': archivoUrl,
          'admin_id': userId,
          'numero_cotizacion': numeroCotizacion,
          'fecha_cotizacion': fechaCotizacion?.toIso8601String().split('T').first,
          'direccion_entrega': direccionEntrega,
          'direccion_lat': direccionLat,
          'direccion_lng': direccionLng,
          'descripcion': descripcion,
          'unidades': unidades,
          'precio_unidad': precioUnidad,
          'foto_url': fotoUrl,
        })
        .select()
        .single();

    return Cotizacion.fromMap(data);
  }
}
