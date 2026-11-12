import 'package:flutter/material.dart';

import '../../../core/formato.dart';
import '../dominio/estado_despacho.dart';

class ChipEstado extends StatelessWidget {
  final EstadoDespacho estado;

  const ChipEstado(this.estado, {super.key});

  @override
  Widget build(BuildContext context) {
    final (color, icono) = switch (estado) {
      EstadoDespacho.pendiente => (Colors.grey, Icons.schedule),
      EstadoDespacho.enRuta => (Colors.orange, Icons.local_shipping),
      EstadoDespacho.entregado => (Colors.green, Icons.check_circle),
    };
    return Chip(
      avatar: Icon(icono, color: color, size: 18),
      label: Text(estado.etiqueta),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Texto y color del plazo de entrega, relativo a hoy.
class TextoPlazo extends StatelessWidget {
  final DateTime fechaComprometida;
  final bool entregado;

  const TextoPlazo({super.key, required this.fechaComprometida, this.entregado = false});

  @override
  Widget build(BuildContext context) {
    final dias = fechaComprometida.difference(hoy()).inDays;
    final fecha = formatoFecha(fechaComprometida);
    if (entregado) return Text('Plazo: $fecha');

    final (texto, color) = switch (dias) {
      < 0 => ('Vencida ($fecha)', Colors.red),
      0 => ('Vence HOY ($fecha)', Colors.red),
      <= 3 => ('Vence en $dias día(s) ($fecha)', Colors.orange.shade800),
      _ => ('Plazo: $fecha', null),
    };
    return Text(texto,
        style: TextStyle(color: color, fontWeight: color != null ? FontWeight.w600 : null));
  }
}
