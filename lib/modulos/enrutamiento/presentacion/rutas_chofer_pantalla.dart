import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../../logistico_notificaciones/dominio/estado_despacho.dart';
import '../../logistico_notificaciones/presentacion/logistico_providers.dart';
import '../dominio/ruta.dart';
import 'enrutamiento_providers.dart';
import 'vista_ruta.dart';

/// Rutas asignadas al Chofer (RF-23). Sin costos ni ahorro (RF-03).
class RutasChoferPantalla extends ConsumerWidget {
  const RutasChoferPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rutasChoferProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis rutas')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(rutasChoferProvider.future),
        child: VistaAsync(
          cargando: async.isLoading,
          error: async.error,
          onReintentar: () => ref.invalidate(rutasChoferProvider),
          child: Builder(builder: (context) {
            final rutas = async.value ?? const <Ruta>[];
            if (rutas.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('No tienes rutas asignadas.')),
              ]);
            }
            final hoyIso = fechaIso(hoy());
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rutas.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = rutas[i];
                final esHoy = fechaIso(r.fecha) == hoyIso;
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.route, color: esHoy ? Theme.of(context).colorScheme.primary : null),
                    title: Text('${esHoy ? 'Hoy · ' : ''}${formatoFecha(r.fecha)}'),
                    subtitle: Text('${r.paradas.length} paradas · '
                        '${r.distanciaKm ?? '—'} km · ${r.duracionMin ?? '—'} min'),
                    onTap: () => context.push('/chofer/rutas/${r.id}'),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

class RutaChoferPantalla extends ConsumerWidget {
  final String rutaId;

  const RutaChoferPantalla({super.key, required this.rutaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rutasChoferProvider);
    final ruta = async.value?.where((r) => r.id == rutaId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(ruta == null ? 'Ruta' : 'Ruta del ${formatoFecha(ruta.fecha)}')),
      body: VistaAsync(
        cargando: async.isLoading,
        error: async.error,
        onReintentar: () => ref.invalidate(rutasChoferProvider),
        child: ruta == null
            ? const Center(child: Text('Ruta no encontrada'))
            : VistaRuta(
                ruta: ruta,
                encabezado: _ResumenRuta(ruta: ruta),
                ubicacionEnVivo: true,
                onParadaTap: (p) => context.push('/chofer/despachos/${p.despachoId}'),
              ),
      ),
      bottomNavigationBar: ruta == null ? null : _AccionesRuta(ruta: ruta),
    );
  }
}

/// Acciones del Chofer sobre su ruta (RF-14, RF-16), con el mismo enfoque
/// offline-first de los despachos (RF-15): iniciar la ruta y confirmar la
/// entrega de cada parada en orden.
class _AccionesRuta extends ConsumerStatefulWidget {
  final Ruta ruta;

  const _AccionesRuta({required this.ruta});

  @override
  ConsumerState<_AccionesRuta> createState() => _AccionesRutaState();
}

class _AccionesRutaState extends ConsumerState<_AccionesRuta> {
  bool _guardando = false;

  Future<void> _cambiar(List<ParadaRuta> paradas, EstadoDespacho nuevo) async {
    setState(() => _guardando = true);
    final notificador = ref.read(despachosChoferProvider.notifier);
    try {
      for (final p in paradas) {
        await notificador.cambiarEstado(p.despachoId, nuevo);
      }
      final sinConexion = ref.read(despachosChoferProvider).value?.sinConexion ?? false;
      if (mounted) {
        mostrarMensaje(
          context,
          sinConexion
              ? 'Guardado en el teléfono. Se sincronizará al recuperar la conexión.'
              : nuevo == EstadoDespacho.enRuta
                  ? 'Ruta iniciada'
                  : 'Entrega confirmada',
        );
      }
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _confirmarEntrega(ParadaRuta p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar entrega'),
        content: Text('¿Entregaste el pedido de ${p.cliente}?\n${p.direccion}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) await _cambiar([p], EstadoDespacho.entregado);
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = widget.ruta.paradas.where((p) => p.estado == EstadoDespacho.pendiente).toList();
    final proxima = widget.ruta.proximaParada;

    final Widget boton;
    if (pendientes.isNotEmpty) {
      boton = FilledButton.icon(
        onPressed: _guardando ? null : () => _cambiar(pendientes, EstadoDespacho.enRuta),
        icon: const Icon(Icons.local_shipping),
        label: Text('Iniciar ruta (${pendientes.length} parada${pendientes.length == 1 ? '' : 's'})'),
      );
    } else if (proxima != null) {
      boton = FilledButton.icon(
        onPressed: _guardando ? null : () => _confirmarEntrega(proxima),
        icon: const Icon(Icons.check),
        label: Text('Confirmar entrega · ${proxima.orden + 1}. ${proxima.cliente}', overflow: TextOverflow.ellipsis),
      );
    } else {
      boton = const FilledButton.tonal(onPressed: null, child: Text('Ruta completada ✔'));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 52,
          child: _guardando
              ? const Center(child: CircularProgressIndicator())
              : SizedBox(width: double.infinity, child: boton),
        ),
      ),
    );
  }
}

class _ResumenRuta extends StatelessWidget {
  final Ruta ruta;

  const _ResumenRuta({required this.ruta});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.all(10),
      child: Text(
        'Ruta: ${ruta.distanciaKm ?? '—'} km · ${ruta.duracionMin ?? '—'} min (ida y vuelta a bodega) · '
        '${ruta.paradas.length} paradas · ${ruta.usaPeajes ? 'usa autopistas con TAG' : 'sin TAG'}',
        textAlign: TextAlign.center,
      ),
    );
  }
}
