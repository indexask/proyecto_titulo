import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../../logistico_notificaciones/dominio/estado_despacho.dart';
import '../../logistico_notificaciones/presentacion/logistico_providers.dart';
import '../datos/navegacion_repositorio.dart';
import '../dominio/ruta.dart';
import 'enrutamiento_providers.dart';
import 'iconos_mapa.dart';
import 'vista_ruta.dart';

/// Tarjeta de una ruta del Chofer para su pantalla de inicio: estado,
/// avance, paradas en orden y acceso al mapa (RF-13, RF-23). Sin costos (RF-03).
class TarjetaRutaChofer extends StatelessWidget {
  final Ruta ruta;

  const TarjetaRutaChofer({super.key, required this.ruta});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final esHoy = fechaIso(ruta.fecha) == fechaIso(hoy());
    final estado = ruta.estado;
    final (colorEstado, iconoEstado) = switch (estado) {
      EstadoRuta.porIniciar => (tema.colorScheme.outline, Icons.schedule),
      EstadoRuta.enCurso => (Colors.orange.shade800, Icons.local_shipping),
      EstadoRuta.completada => (Colors.green.shade700, Icons.check_circle),
    };
    final total = ruta.paradas.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.route, color: esHoy ? tema.colorScheme.primary : null),
            title: Text('${esHoy ? 'Hoy · ' : ''}${formatoFecha(ruta.fecha)}',
                style: tema.textTheme.titleMedium),
            subtitle: Text('${ruta.distanciaKm ?? '—'} km · ${ruta.duracionMin ?? '—'} min'
                '${ruta.usaPeajes ? ' · usa TAG' : ''}'),
            trailing: Chip(
              avatar: Icon(iconoEstado, color: colorEstado, size: 18),
              label: Text(estado.etiqueta),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : ruta.entregadas / total,
                  color: colorEstado,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Text('${ruta.entregadas} de $total entregadas', style: tema.textTheme.bodySmall),
            ]),
          ),
          const SizedBox(height: 4),
          for (final p in ruta.paradas)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: estado == EstadoRuta.enCurso && p.despachoId == ruta.proximaParada?.despachoId,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: IconosMapa.colorEstado(p.estado),
                foregroundColor: Colors.white,
                child: Text('${p.orden + 1}', style: const TextStyle(fontSize: 12)),
              ),
              title: Text(p.cliente),
              subtitle: Text(p.direccion, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(p.estado.etiqueta, style: tema.textTheme.bodySmall),
              onTap: () => context.push('/chofer/despachos/${p.despachoId}'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: estado == EstadoRuta.completada
                ? OutlinedButton.icon(
                    onPressed: () => context.push('/chofer/rutas/${ruta.id}'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Ver ruta'),
                  )
                : FilledButton.icon(
                    onPressed: () => context.push('/chofer/rutas/${ruta.id}'),
                    icon: Icon(estado == EstadoRuta.porIniciar ? Icons.play_arrow : Icons.navigation),
                    label: Text(estado == EstadoRuta.porIniciar ? 'Abrir ruta e iniciar' : 'Continuar ruta'),
                  ),
          ),
        ],
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
      // Al actualizar un estado los datos se recargan; si ya hay datos se
      // siguen mostrando, para no destruir y recrear el mapa (quedaba gris).
      body: VistaAsync(
        cargando: async.isLoading && !async.hasValue,
        error: async.hasValue ? null : async.error,
        onReintentar: () => ref.invalidate(rutasChoferProvider),
        child: ruta == null
            ? const Center(child: Text('Ruta no encontrada'))
            : VistaRuta(
                key: ValueKey('ruta-$rutaId'),
                ruta: ruta,
                encabezado: _ResumenRuta(ruta: ruta),
                ubicacionEnVivo: true,
                enRuta: ruta.paradas.any((p) => p.estado == EstadoDespacho.enRuta),
                onParadaTap: (p) => context.push('/chofer/despachos/${p.despachoId}'),
              ),
      ),
      bottomNavigationBar: ruta == null ? null : _AccionesRuta(ruta: ruta),
    );
  }
}

/// Acciones del Chofer sobre su ruta (RF-14, RF-16), con el mismo enfoque
/// offline-first de los despachos (RF-15).
///
/// Flujo: "Iniciar ruta" → Google Maps con todo el recorrido (paradas en
/// orden + regreso a bodega) → "Confirmar entrega" en cada parada →
/// "Volver a bodega". "Navegar" vuelve a abrir el recorrido que falta.
class _AccionesRuta extends ConsumerStatefulWidget {
  final Ruta ruta;

  const _AccionesRuta({required this.ruta});

  @override
  ConsumerState<_AccionesRuta> createState() => _AccionesRutaState();
}

class _AccionesRutaState extends ConsumerState<_AccionesRuta> {
  final _navegacion = NavegacionRepositorio();
  bool _guardando = false;

  Future<bool> _cambiar(List<ParadaRuta> paradas, EstadoDespacho nuevo) async {
    setState(() => _guardando = true);
    final notificador = ref.read(despachosChoferProvider.notifier);
    try {
      for (final p in paradas) {
        await notificador.cambiarEstado(p.despachoId, nuevo);
      }
      if ((ref.read(despachosChoferProvider).value?.sinConexion ?? false) && mounted) {
        mostrarMensaje(context, 'Guardado en el teléfono. Se sincronizará al recuperar la conexión.');
      }
      return true;
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
      return false;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  PuntoNavegacion get _bodega => PuntoNavegacion(
      direccion: widget.ruta.origenDireccion, lat: widget.ruta.origenLat, lng: widget.ruta.origenLng);

  /// Abre en Google Maps, de una vez, el recorrido que falta: las paradas no
  /// entregadas en el orden de la ruta (con su dirección exacta) y el
  /// regreso a bodega. Así no se abre una pestaña nueva por cada parada.
  Future<void> _navegarRestante() async {
    final restantes = widget.ruta.paradas
        .where((p) => p.estado != EstadoDespacho.entregado)
        .map((p) => PuntoNavegacion(direccion: p.direccion, lat: p.lat, lng: p.lng))
        .toList();
    final ok = await _navegacion.navegarRuta(restantes, _bodega);
    if (!mounted) return;
    if (!ok) {
      mostrarMensaje(context, 'No se pudo abrir Google Maps');
      return;
    }
    final fuera = NavegacionRepositorio.paradasFuera(restantes);
    if (fuera > 0) {
      mostrarMensaje(context,
          'Google Maps admite 10 puntos por recorrido: quedan $fuera parada(s) fuera. Presiona "Navegar" al llegar a la décima.');
    }
  }

  Future<void> _iniciarRuta(List<ParadaRuta> pendientes) async {
    if (!await _cambiar(pendientes, EstadoDespacho.enRuta) || !mounted) return;
    mostrarMensaje(context, 'Ruta iniciada: se abre Google Maps con las ${pendientes.length} parada(s) y el regreso a bodega.');
    await _navegarRestante();
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
    if (ok != true || !await _cambiar([p], EstadoDespacho.entregado) || !mounted) return;

    // Siguiente parada en el orden de la ruta, o regreso a bodega.
    final siguiente = widget.ruta.paradas
        .where((x) => x.orden > p.orden && x.estado != EstadoDespacho.entregado)
        .firstOrNull;
    if (siguiente != null) {
      // Google Maps ya tiene todo el recorrido: no se abre otra pestaña.
      mostrarMensaje(context, 'Entrega confirmada. Siguiente: ${siguiente.orden + 1}. ${siguiente.cliente}');
    } else {
      mostrarMensaje(context, 'Entregas completadas. Puedes volver a la bodega.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruta = widget.ruta;
    final pendientes = ruta.paradas.where((p) => p.estado == EstadoDespacho.pendiente).toList();
    final proxima = ruta.proximaParada;

    final Widget contenido;
    if (_guardando) {
      contenido = const Center(child: CircularProgressIndicator());
    } else if (pendientes.isNotEmpty) {
      contenido = FilledButton.icon(
        onPressed: () => _iniciarRuta(pendientes),
        icon: const Icon(Icons.play_arrow),
        label: Text('Iniciar ruta (${pendientes.length} parada${pendientes.length == 1 ? '' : 's'})'),
      );
    } else if (proxima != null) {
      contenido = Row(children: [
        OutlinedButton.icon(
          onPressed: _navegarRestante,
          icon: const Icon(Icons.navigation),
          label: const Text('Navegar'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _confirmarEntrega(proxima),
            icon: const Icon(Icons.check),
            label: Text('Confirmar entrega · ${proxima.orden + 1}. ${proxima.cliente}',
                overflow: TextOverflow.ellipsis),
          ),
        ),
      ]);
    } else {
      contenido = Row(children: [
        const Expanded(child: Text('Ruta completada ✔', textAlign: TextAlign.center)),
        FilledButton.icon(
          onPressed: () => _navegacion.navegarRuta(const [], _bodega),
          icon: const Icon(Icons.warehouse),
          label: const Text('Volver a bodega'),
        ),
      ]);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(height: 52, width: double.infinity, child: contenido),
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
