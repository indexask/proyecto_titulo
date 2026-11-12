import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../../logistico_notificaciones/dominio/estado_despacho.dart';
import '../../logistico_notificaciones/presentacion/widgets_despacho.dart';
import '../dominio/orden_compra.dart';
import 'comercial_providers.dart';

/// Adjudicaciones / órdenes de compra (RF-09), ordenadas por plazo.
class OrdenesLista extends ConsumerWidget {
  const OrdenesLista({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordenesProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(ordenesProvider.future),
        child: VistaAsync(
          cargando: async.isLoading,
          error: async.error,
          onReintentar: () => ref.invalidate(ordenesProvider),
          child: Builder(builder: (context) {
            final ordenes = async.value ?? const <OrdenCompra>[];
            if (ordenes.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('Aún no hay órdenes de compra registradas.')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: ordenes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final o = ordenes[i];
                final estado = o.despacho?.estado ?? EstadoDespacho.pendiente;
                return Card(
                  child: ListTile(
                    title: Text(o.titulo),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextoPlazo(
                          fechaComprometida: o.fechaComprometida,
                          entregado: estado == EstadoDespacho.entregado,
                        ),
                        Text('Responsable: ${o.responsableNombre ?? 'sin asignar'}'),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatoClp(o.margenNeto),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: o.margenNeto < 0 ? Colors.red : Colors.green.shade700,
                          ),
                        ),
                        Text(estado.etiqueta, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    onTap: () => context.push('/admin/ordenes/${o.id}'),
                  ),
                );
              },
            );
          }),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'orden-manual',
            tooltip: 'Registrar manualmente',
            onPressed: () => context.push('/admin/ordenes/nueva'),
            child: const Icon(Icons.edit_note),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'subir-cotizacion',
            onPressed: () => subirCotizacion(context, ref),
            icon: const Icon(Icons.upload_file),
            label: const Text('Subir cotización'),
          ),
        ],
      ),
    );
  }
}

/// Elige el PDF de la cotización, lo lee automáticamente y abre el
/// formulario de la orden con los datos completados.
Future<void> subirCotizacion(BuildContext context, WidgetRef ref) async {
  final archivo = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
  if (archivo == null || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        CircularProgressIndicator(),
        SizedBox(width: 16),
        Expanded(child: Text('Leyendo cotización…')),
      ]),
    ),
  );
  try {
    final bytes = await archivo.readAsBytes();
    final datos = await ref.read(cotizacionesRepositorioProvider).importarPdf(bytes);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    context.push('/admin/ordenes/nueva', extra: datos);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    mostrarMensaje(context, 'No se pudo leer la cotización: ${mensajeError(e)}');
  }
}
