import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../logistico_notificaciones/dominio/estado_despacho.dart';

/// Íconos del mapa dibujados en la app: funcionan igual en web, Android e
/// iOS (en web, Google ignora el color de los marcadores estándar).
class IconosMapa {
  final BitmapDescriptor bodega;
  final BitmapDescriptor ubicacion;
  final Map<String, BitmapDescriptor> _paradas;

  const IconosMapa._(this.bodega, this.ubicacion, this._paradas);

  /// Ícono de una parada: su número y el color de su estado.
  BitmapDescriptor? parada(int numero, EstadoDespacho estado) => _paradas['$numero-${estado.codigo}'];

  static Color colorEstado(EstadoDespacho e) => switch (e) {
        EstadoDespacho.pendiente => const Color(0xFFD32F2F),
        EstadoDespacho.enRuta => const Color(0xFFEF6C00),
        EstadoDespacho.entregado => const Color(0xFF2E7D32),
        EstadoDespacho.noEntregado => const Color(0xFF455A64),
      };

  static Future<IconosMapa> crear(Iterable<({int numero, EstadoDespacho estado})> paradas) async {
    final iconos = <String, BitmapDescriptor>{};
    for (final p in paradas) {
      iconos['${p.numero}-${p.estado.codigo}'] =
          await _circulo(fondo: colorEstado(p.estado), texto: '${p.numero}', diametro: 30);
    }
    return IconosMapa._(
      await _circulo(fondo: const Color(0xFF37474F), texto: 'B', diametro: 30),
      await _circulo(fondo: const Color(0xFF1A73E8), diametro: 18, bordeGrueso: true),
      iconos,
    );
  }

  static Future<BitmapDescriptor> _circulo({
    required Color fondo,
    String? texto,
    required double diametro,
    bool bordeGrueso = false,
  }) async {
    const escala = 3.0;
    final px = diametro * escala;
    final grabador = ui.PictureRecorder();
    final lienzo = Canvas(grabador);
    final centro = Offset(px / 2, px / 2);

    lienzo.drawCircle(centro, px / 2, Paint()..color = Colors.white);
    lienzo.drawCircle(centro, px / 2 - (bordeGrueso ? 3.5 : 2) * escala, Paint()..color = fondo);
    if (texto != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: texto,
          style: TextStyle(color: Colors.white, fontSize: px * 0.48, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(lienzo, centro - Offset(tp.width / 2, tp.height / 2));
    }

    final imagen = await grabador.endRecording().toImage(px.round(), px.round());
    final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(png!.buffer.asUint8List(), width: diametro, height: diametro);
  }
}
