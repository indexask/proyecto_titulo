import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../dominio/despacho_chofer.dart';
import '../dominio/estado_despacho.dart';
import 'logistico_providers.dart';
import 'widgets_despacho.dart';

/// Detalle de un despacho para el Chofer: carga a subir, datos del cliente
/// y avance de estado (RF-13, RF-14, RF-15, RF-16).
class DespachoChoferPantalla extends ConsumerStatefulWidget {
  final String despachoId;

  const DespachoChoferPantalla({super.key, required this.despachoId});

  @override
  ConsumerState<DespachoChoferPantalla> createState() => _DespachoChoferPantallaState();
}

class _DespachoChoferPantallaState extends ConsumerState<DespachoChoferPantalla> {
  bool _guardando = false;

  Future<void> _avanzar(DespachoChofer d, EstadoDespacho nuevo) async {
    if (nuevo == EstadoDespacho.entregado) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar entrega'),
          content: Text('¿Confirmas que entregaste el pedido a ${d.cliente}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _guardando = true);
    try {
      await ref.read(despachosChoferProvider.notifier).cambiarEstado(d.despachoId, nuevo);
      final resultado = ref.read(despachosChoferProvider).value;
      if (mounted) {
        mostrarMensaje(
          context,
          resultado?.sinConexion ?? false
              ? 'Guardado en el teléfono. Se sincronizará al recuperar la conexión.'
              : 'Estado actualizado: ${nuevo.etiqueta}',
        );
      }
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(despachosChoferProvider);
    final despacho = async.value?.despachos.where((d) => d.despachoId == widget.despachoId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Despacho')),
      body: VistaAsync(
        cargando: async.isLoading && !async.hasValue,
        error: async.hasValue ? null : async.error,
        child: despacho == null
            ? const Center(child: Text('Despacho no encontrado'))
            : _detalle(context, despacho),
      ),
    );
  }

  Widget _detalle(BuildContext context, DespachoChofer d) {
    final siguiente = d.estado.siguiente;
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text(d.cliente, style: tema.textTheme.headlineSmall)),
            ChipEstado(d.estado),
          ],
        ),
        if (d.numeroOc != null) Text('OC ${d.numeroOc}'),
        const SizedBox(height: 8),
        TextoPlazo(fechaComprometida: d.fechaComprometida, entregado: d.estado == EstadoDespacho.entregado),
        if (d.pendienteDeSincronizar)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.cloud_upload, size: 18),
              SizedBox(width: 6),
              Text('Cambio guardado en el teléfono, pendiente de sincronizar'),
            ]),
          ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.place),
          title: Text(d.direccionEntrega),
          subtitle: const Text('Dirección de entrega'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2),
          title: Text('${d.cantidadBultos ?? 'Por registrar'}'),
          subtitle: const Text('Bultos a cargar'),
        ),
        if (d.fechaHoraEntrega != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available),
            title: Text(formatoFechaHora(d.fechaHoraEntrega)),
            subtitle: const Text('Fecha y hora de entrega'),
          ),
        const SizedBox(height: 8),
        Text('Productos', style: tema.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (d.productos.isEmpty) const Text('Sin productos registrados'),
        for (final item in d.productos)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(item.producto),
            trailing: Text('× ${item.cantidad}', style: tema.textTheme.titleMedium),
          ),
        const SizedBox(height: 24),
        if (siguiente != null)
          FilledButton.icon(
            onPressed: _guardando ? null : () => _avanzar(d, siguiente),
            icon: Icon(siguiente == EstadoDespacho.entregado ? Icons.check : Icons.local_shipping),
            label: Text(siguiente.accion),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
      ],
    );
  }
}
