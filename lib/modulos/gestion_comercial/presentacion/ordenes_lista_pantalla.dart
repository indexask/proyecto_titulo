import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/ordenes/nueva'),
        icon: const Icon(Icons.add),
        label: const Text('Registrar adjudicación'),
      ),
    );
  }
}
