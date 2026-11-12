import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
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
        'Ruta optimizada: ${ruta.distanciaKm ?? '—'} km · ${ruta.duracionMin ?? '—'} min · '
        '${ruta.paradas.length} paradas · ${ruta.usaPeajes ? 'usa autopistas con TAG' : 'sin TAG'}',
        textAlign: TextAlign.center,
      ),
    );
  }
}
