import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/vista_async.dart';
import '../../administracion_seguridad/presentacion/cerrar_sesion.dart';
import '../../enrutamiento/dominio/ruta.dart';
import '../../enrutamiento/presentacion/enrutamiento_providers.dart';
import '../../enrutamiento/presentacion/rutas_chofer_pantalla.dart';
import '../datos/despachos_chofer_repositorio.dart';
import '../dominio/despacho_chofer.dart';
import '../dominio/estado_despacho.dart';
import 'logistico_providers.dart';
import 'widgets_despacho.dart';

/// Inicio del Chofer, "Mi jornada" (RF-13, RF-23): sus despachos organizados
/// por ruta, en el orden de visita, con el avance de cada una. Sin información
/// financiera (RF-03). Funciona sin conexión con los datos guardados (RF-15).
class ChoferInicioPantalla extends ConsumerWidget {
  const ChoferInicioPantalla({super.key});

  Future<void> _recargar(WidgetRef ref) async {
    await ref.read(despachosChoferProvider.notifier).recargar();
    ref.invalidate(rutasChoferProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final despachosAsync = ref.watch(despachosChoferProvider);
    final rutasAsync = ref.watch(rutasChoferProvider);
    final resultado = despachosAsync.value;

    ref.listen(despachosChoferProvider, (_, siguiente) {
      for (final rechazo in siguiente.value?.rechazos ?? const <String>[]) {
        mostrarMensaje(context, rechazo);
      }
    });

    final cargando = (despachosAsync.isLoading && !despachosAsync.hasValue) ||
        (rutasAsync.isLoading && !rutasAsync.hasValue);
    final error = despachosAsync.hasValue ? (rutasAsync.hasValue ? null : rutasAsync.error) : despachosAsync.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi jornada'),
        actions: [
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
              onRefresh: () => _recargar(ref),
              child: VistaAsync(
                cargando: cargando,
                error: error,
                onReintentar: () => _recargar(ref),
                child: _Jornada(
                  rutas: rutasAsync.value ?? const [],
                  despachos: resultado?.despachos ?? const [],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Jornada extends StatelessWidget {
  final List<Ruta> rutas;
  final List<DespachoChofer> despachos;

  const _Jornada({required this.rutas, required this.despachos});

  @override
  Widget build(BuildContext context) {
    // Rutas activas: la más próxima primero (hoy antes que mañana).
    final activas = rutas.where((r) => r.estado != EstadoRuta.completada).toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
    // Historial: la más reciente primero.
    final completadas = rutas.where((r) => r.estado == EstadoRuta.completada).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));

    // Despachos aún no incluidos en ninguna ruta (lo que viene).
    final enRutas = {for (final r in rutas) for (final p in r.paradas) p.despachoId};
    final sinRuta = despachos
        .where((d) => !enRutas.contains(d.despachoId) && d.estado != EstadoDespacho.entregado)
        .toList()
      ..sort((a, b) => a.fechaComprometida.compareTo(b.fechaComprometida));

    final tema = Theme.of(context);
    Widget titulo(String texto, {String? detalle}) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(children: [
            Text(texto, style: tema.textTheme.titleMedium),
            if (detalle != null) ...[
              const SizedBox(width: 8),
              Text(detalle, style: tema.textTheme.bodySmall),
            ],
          ]),
        );

    if (rutas.isEmpty && sinRuta.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        Center(child: Text('No tienes rutas ni despachos asignados.')),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        titulo('Rutas', detalle: activas.isEmpty ? 'sin rutas pendientes' : null),
        for (final r in activas) ...[
          TarjetaRutaChofer(ruta: r),
          const SizedBox(height: 8),
        ],
        if (sinRuta.isNotEmpty) ...[
          titulo('Despachos sin ruta asignada', detalle: '${sinRuta.length}'),
          for (final d in sinRuta)
            Card(
              child: ListTile(
                title: Text(d.cliente),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.direccionEntrega),
                    TextoPlazo(fechaComprometida: d.fechaComprometida),
                    Text('Bultos: ${d.cantidadBultos ?? 'por registrar'}'),
                  ],
                ),
                isThreeLine: true,
                trailing: ChipEstado(d.estado),
                onTap: () => context.push('/chofer/despachos/${d.despachoId}'),
              ),
            ),
        ],
        if (completadas.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 16),
            child: ExpansionTile(
              leading: const Icon(Icons.history),
              title: Text('Rutas completadas (${completadas.length})'),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                for (final r in completadas) ...[
                  TarjetaRutaChofer(ruta: r),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
      ],
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
