import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../../logistico_notificaciones/presentacion/logistico_providers.dart';
import '../../logistico_notificaciones/presentacion/widgets_despacho.dart';
import '../dominio/orden_compra.dart';
import '../dominio/rentabilidad.dart';
import 'comercial_providers.dart';
import 'foto_producto.dart';

/// Detalle de una orden para el Administrador: rentabilidad (RF-07) y
/// despacho, con registro de bultos (RF-12).
class OrdenDetallePantalla extends ConsumerWidget {
  final String ordenId;

  const OrdenDetallePantalla({super.key, required this.ordenId});

  Future<void> _eliminar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar orden'),
        content: const Text('Se eliminará la orden con su despacho y alertas. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(ordenesRepositorioProvider).eliminar(ordenId);
      ref.invalidate(ordenesProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _registrarBultos(BuildContext context, WidgetRef ref, DespachoResumen d) async {
    final ctrl = TextEditingController(text: d.cantidadBultos?.toString() ?? '');
    final cantidad = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bultos del despacho'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Cantidad de bultos'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              if (n != null && n > 0) Navigator.pop(context, n);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (cantidad == null) return;
    try {
      await ref.read(ordenesRepositorioProvider).registrarBultos(d.id, cantidad);
      ref.invalidate(ordenProvider(ordenId));
      ref.invalidate(ordenesProvider);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordenProvider(ordenId));
    final alertas = (ref.watch(alertasProvider).value ?? const []).where((a) => a.ordenId == ordenId);
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orden de compra'),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/admin/ordenes/$ordenId/editar'),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _eliminar(context, ref),
          ),
        ],
      ),
      body: VistaAsync(
        cargando: async.isLoading,
        error: async.error,
        onReintentar: () => ref.invalidate(ordenProvider(ordenId)),
        child: Builder(builder: (context) {
          final o = async.value;
          if (o == null) return const SizedBox.shrink();
          final pct = porcentajeMargen(o.margenNeto, o.ventaTotal);
          final d = o.despacho;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(o.cliente, style: tema.textTheme.headlineSmall),
              if (o.numeroCotizacion != null)
                Text('Cotización ${o.numeroCotizacion}'
                    '${o.fechaCotizacion != null ? ' · ${formatoFecha(o.fechaCotizacion)}' : ''}'),
              if (o.numeroOc != null) Text('OC ${o.numeroOc}'),
              const SizedBox(height: 4),
              TextoPlazo(fechaComprometida: o.fechaComprometida, entregado: o.fechaHoraEntrega != null),
              Text('Responsable: ${o.responsableNombre ?? 'sin asignar'}'),
              Text('Entrega: ${o.direccionEntrega}${o.geocodificada ? '' : ' (sin validar)'}'),
              const SizedBox(height: 12),
              Card(
                color: o.margenNeto < 0 ? tema.colorScheme.errorContainer : tema.colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.trending_up),
                  title: Text('Margen neto: ${formatoClp(o.margenNeto)}',
                      style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  subtitle: Text('Venta total ${formatoClp(o.ventaTotal)}'
                      '${pct == null ? '' : ' · ${pct.toStringAsFixed(1)} %'}'),
                ),
              ),
              const SizedBox(height: 8),
              Text('Productos', style: tema.textTheme.titleMedium),
              if (o.detalles.any((d) => d.productoFotoPath != null))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(spacing: 8, children: [
                    for (final d in o.detalles.where((d) => d.productoFotoPath != null))
                      Tooltip(
                        message: d.productoNombre,
                        child: FotoProducto(ruta: d.productoFotoPath, tamano: 120),
                      ),
                  ]),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Producto')),
                    DataColumn(label: Text('Cant.'), numeric: true),
                    DataColumn(label: Text('Costo'), numeric: true),
                    DataColumn(label: Text('Precio'), numeric: true),
                    DataColumn(label: Text('Margen'), numeric: true),
                  ],
                  rows: [
                    for (final det in o.detalles)
                      DataRow(cells: [
                        DataCell(Text(det.productoNombre)),
                        DataCell(Text('${det.cantidad}')),
                        DataCell(Text(formatoClp(det.costoCompra))),
                        DataCell(Text(formatoClp(det.precioVenta))),
                        DataCell(Text(formatoClp(det.margen))),
                      ]),
                  ],
                ),
              ),
              const Divider(height: 32),
              Text('Despacho', style: tema.textTheme.titleMedium),
              if (d == null)
                const Text('Sin despacho')
              else ...[
                Row(children: [ChipEstado(d.estado)]),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2),
                  title: Text('Bultos: ${d.cantidadBultos ?? 'sin registrar'}'),
                  trailing: TextButton(
                    onPressed: () => _registrarBultos(context, ref, d),
                    child: Text(d.cantidadBultos == null ? 'Registrar' : 'Modificar'),
                  ),
                ),
                if (d.fechaHoraEntrega != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available),
                    title: Text('Entregado: ${formatoFechaHora(d.fechaHoraEntrega)}'),
                    subtitle: Text(d.confirmadoEnApp ? 'Confirmado por el chofer en la app' : ''),
                  ),
              ],
              if (alertas.isNotEmpty) ...[
                const Divider(height: 32),
                Text('Alertas emitidas', style: tema.textTheme.titleMedium),
                for (final a in alertas)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_active),
                    title: Text(a.tipo.etiqueta),
                    subtitle: Text(formatoFechaHora(a.fechaEmision)),
                  ),
              ],
            ],
          );
        }),
      ),
    );
  }
}
