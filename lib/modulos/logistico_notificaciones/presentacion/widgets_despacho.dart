import 'package:flutter/material.dart';

import '../../../core/formato.dart';
import '../dominio/estado_despacho.dart';

/// Pide al Chofer la justificación de una no entrega (RF-14/RF-16). Devuelve
/// el motivo (no vacío) o `null` si cancela. El botón se habilita solo cuando
/// hay texto.
Future<String?> pedirMotivoNoEntrega(BuildContext context, {String? cliente}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Marcar como NO entregado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cliente == null
              ? 'Indica por qué no se pudo entregar el pedido.'
              : 'Indica por qué no se pudo entregar el pedido a $cliente.'),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: ctrl,
            builder: (context, value, _) => TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Motivo de la no entrega',
                hintText: 'Ej.: cliente ausente, dirección incorrecta, local cerrado…',
                border: const OutlineInputBorder(),
                errorText: value.text.trim().isEmpty ? 'Obligatorio' : null,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ValueListenableBuilder(
          valueListenable: ctrl,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : () => Navigator.pop(context, value.text.trim()),
            child: const Text('Guardar'),
          ),
        ),
      ],
    ),
  );
}

class ChipEstado extends StatelessWidget {
  final EstadoDespacho estado;

  const ChipEstado(this.estado, {super.key});

  @override
  Widget build(BuildContext context) {
    final (color, icono) = switch (estado) {
      EstadoDespacho.pendiente => (Colors.grey, Icons.schedule),
      EstadoDespacho.enRuta => (Colors.orange, Icons.local_shipping),
      EstadoDespacho.entregado => (Colors.green, Icons.check_circle),
      EstadoDespacho.noEntregado => (Colors.red, Icons.cancel),
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
