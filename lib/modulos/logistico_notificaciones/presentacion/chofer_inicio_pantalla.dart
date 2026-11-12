import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/vista_async.dart';
import '../../administracion_seguridad/presentacion/cerrar_sesion.dart';
import '../datos/despachos_chofer_repositorio.dart';
import '../dominio/estado_despacho.dart';
import 'logistico_providers.dart';
import 'widgets_despacho.dart';

/// Inicio del Chofer (app móvil): inventario de despachos a cargar y datos
/// del cliente (RF-13). Sin información financiera (RF-03).
class ChoferInicioPantalla extends ConsumerWidget {
  const ChoferInicioPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(despachosChoferProvider);
    final resultado = async.value;

    ref.listen(despachosChoferProvider, (_, siguiente) {
      for (final rechazo in siguiente.value?.rechazos ?? const <String>[]) {
        mostrarMensaje(context, rechazo);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis despachos'),
        actions: [
          IconButton(
            tooltip: 'Mis rutas',
            icon: const Icon(Icons.map),
            onPressed: () => context.push('/chofer/rutas'),
          ),
          IconButton(
            tooltip: 'Alertas',
            icon: const Icon(Icons.notifications),
            onPressed: () => context.push('/chofer/alertas'),
          ),
          BotonCerrarSesion(cambiosPendientes: resultado?.cambiosPendientes ?? 0),
        ],
      ),
      body: Column(
        children: [
          if (resultado != null) _BannerSincronizacion(resultado: resultado),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(despachosChoferProvider.notifier).recargar(),
              child: VistaAsync(
                cargando: async.isLoading && !async.hasValue,
                error: async.hasValue ? null : async.error,
                onReintentar: () => ref.invalidate(despachosChoferProvider),
                child: _ListaDespachos(resultado: resultado),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerSincronizacion extends ConsumerWidget {
  final ResultadoDespachos resultado;

  const _BannerSincronizacion({required this.resultado});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!resultado.sinConexion && resultado.cambiosPendientes == 0) return const SizedBox.shrink();
    final colores = Theme.of(context).colorScheme;
    return Material(
      color: resultado.sinConexion ? colores.errorContainer : colores.tertiaryContainer,
      child: ListTile(
        dense: true,
        leading: Icon(resultado.sinConexion ? Icons.cloud_off : Icons.sync),
        title: Text(resultado.sinConexion
            ? 'Sin conexión: trabajando con los datos guardados'
            : 'Sincronizando cambios…'),
        subtitle: resultado.cambiosPendientes > 0
            ? Text('${resultado.cambiosPendientes} cambio(s) de estado por sincronizar')
            : null,
        trailing: TextButton(
          onPressed: () => ref.read(despachosChoferProvider.notifier).recargar(),
          child: const Text('Reintentar'),
        ),
      ),
    );
  }
}

class _ListaDespachos extends StatelessWidget {
  final ResultadoDespachos? resultado;

  const _ListaDespachos({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final despachos = [...?resultado?.despachos]..sort((a, b) {
        final entregadoA = a.estado == EstadoDespacho.entregado ? 1 : 0;
        final entregadoB = b.estado == EstadoDespacho.entregado ? 1 : 0;
        return entregadoA != entregadoB
            ? entregadoA - entregadoB
            : a.fechaComprometida.compareTo(b.fechaComprometida);
      });

    if (despachos.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        Center(child: Text('No tienes despachos asignados.')),
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: despachos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final d = despachos[i];
        return Card(
          child: ListTile(
            title: Text(d.cliente),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.direccionEntrega),
                TextoPlazo(
                    fechaComprometida: d.fechaComprometida,
                    entregado: d.estado == EstadoDespacho.entregado),
                Text('Bultos: ${d.cantidadBultos ?? 'por registrar'}'),
              ],
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ChipEstado(d.estado),
                if (d.pendienteDeSincronizar)
                  const Icon(Icons.cloud_upload, size: 16, semanticLabel: 'Por sincronizar'),
              ],
            ),
            onTap: () => context.push('/chofer/despachos/${d.despachoId}'),
          ),
        );
      },
    );
  }
}
