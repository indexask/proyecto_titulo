import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../../administracion_seguridad/presentacion/auth_providers.dart';
import '../../gestion_comercial/dominio/orden_compra.dart';
import '../../gestion_comercial/presentacion/comercial_providers.dart';
import '../../logistico_notificaciones/dominio/estado_despacho.dart';
import '../datos/geocodificacion_repositorio.dart';
import '../dominio/ruta.dart';
import 'enrutamiento_providers.dart';
import 'vista_ruta.dart';

/// Listado de rutas con su ahorro estimado (Administrador, RF-24).
class RutasAdminLista extends ConsumerWidget {
  const RutasAdminLista({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rutasAdminProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(rutasAdminProvider.future),
        child: VistaAsync(
          cargando: async.isLoading,
          error: async.error,
          onReintentar: () => ref.invalidate(rutasAdminProvider),
          child: Builder(builder: (context) {
            final rutas = async.value ?? const <RutaAdmin>[];
            if (rutas.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('Aún no hay rutas.')),
              ]);
            }
            final ahorroTotal = rutas.fold<num>(0, (s, r) => s + (r.ahorro ?? 0));
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.savings),
                    title: Text('Ahorro estimado acumulado: ${formatoClp(ahorroTotal)}'),
                    subtitle: const Text('Combustible y peajes vs. ruta sin optimizar'),
                  ),
                ),
                for (final r in rutas)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.route),
                      title: Text('${formatoFecha(r.fecha)} · ${r.choferNombre ?? 'Sin chofer'}'),
                      subtitle: Text('${r.paradas.length} paradas · ${r.distanciaKm ?? '—'} km · '
                          '${r.duracionMin ?? '—'} min'),
                      trailing: Text('Ahorro\n${formatoClp(r.ahorro)}', textAlign: TextAlign.end),
                      onTap: () => context.push('/admin/rutas/${r.id}'),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/rutas/nueva'),
        icon: const Icon(Icons.add_road),
        label: const Text('Nueva ruta'),
      ),
    );
  }
}

/// Detalle de una ruta para el Administrador: mapa + costos y ahorro.
class RutaAdminPantalla extends ConsumerWidget {
  final String rutaId;

  const RutaAdminPantalla({super.key, required this.rutaId});

  Future<void> _eliminar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar ruta'),
        content: const Text('Los despachos no se modifican; solo se borra la ruta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(rutasRepositorioProvider).eliminar(rutaId);
      ref.invalidate(rutasAdminProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rutaAdminProvider(rutaId));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value == null ? 'Ruta' : 'Ruta del ${formatoFecha(async.value!.fecha)}'),
        actions: [
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
        onReintentar: () => ref.invalidate(rutaAdminProvider(rutaId)),
        child: async.value == null
            ? const SizedBox.shrink()
            : VistaRuta(
                ruta: async.value!,
                encabezado: Column(children: [
                  _CostosRuta(ruta: async.value!),
                  if (async.value!.detalle != null) _ComparacionOptimizacion(detalle: async.value!.detalle!),
                ]),
              ),
      ),
    );
  }
}

class _CostosRuta extends StatelessWidget {
  final RutaAdmin ruta;

  const _CostosRuta({required this.ruta});

  @override
  Widget build(BuildContext context) {
    Widget dato(String etiqueta, String valor) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(children: [
            Text(valor, style: Theme.of(context).textTheme.titleMedium),
            Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          dato('Chofer', ruta.choferNombre ?? 'Sin asignar'),
          dato('Distancia', '${ruta.distanciaKm ?? '—'} km'),
          dato('Duración', '${ruta.duracionMin ?? '—'} min'),
          dato('Peajes (TAG)', ruta.usaPeajes ? 'Sí' : 'No'),
          dato('Costo sin optimizar', formatoClp(ruta.costoSinOptimizar)),
          dato('Costo ruta elegida', formatoClp(ruta.costoOptimizada)),
          dato('Ahorro estimado', formatoClp(ruta.ahorro)),
        ],
      ),
    );
  }
}

/// Comparación de la optimización: tiempo, km, TAG y combustible de cada
/// alternativa, y el motivo de la elección (regla de $500 por 10 min).
class _ComparacionOptimizacion extends StatelessWidget {
  final DetalleOptimizacion detalle;

  const _ComparacionOptimizacion({required this.detalle});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final negrita = tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);

    final e = detalle.eleccion;
    // El "✓" como carácter se dibuja con otra fuente en web y desborda la
    // columna; se usa un ícono.
    DataColumn columna(String titulo, AlternativaRuta alt) => DataColumn(
          numeric: true,
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(titulo, textAlign: TextAlign.end, style: e == alt ? negrita : null),
            if (e == alt) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle, size: 16, color: tema.colorScheme.primary),
            ],
          ]),
        );
    DataCell celda(String texto, AlternativaRuta alt) => DataCell(Text(texto, style: e == alt ? negrita : null));
    DataRow fila(String etiqueta, String Function(ResumenRecorrido r) valor) => DataRow(cells: [
          DataCell(Text(etiqueta)),
          celda(valor(detalle.sinOptimizar), AlternativaRuta.ordenPorPlazo),
          celda(valor(detalle.conTag), AlternativaRuta.optimizadaConTag),
          celda(valor(detalle.sinTag), AlternativaRuta.optimizadaSinTag),
        ]);

    return ExpansionTile(
      initiallyExpanded: true,
      dense: true,
      leading: const Icon(Icons.compare_arrows),
      title: const Text('Optimización: tiempo, km y TAG'),
      subtitle: Text(detalle.motivo),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 48,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 36,
            columns: [
              const DataColumn(label: Text('')),
              columna('Orden por plazo', AlternativaRuta.ordenPorPlazo),
              columna('Optimizada\npermite TAG', AlternativaRuta.optimizadaConTag),
              columna('Optimizada\nevita TAG', AlternativaRuta.optimizadaSinTag),
            ],
            rows: [
              fila('Tiempo', (r) => '${r.duracionMin} min'),
              fila('Distancia', (r) => '${r.distanciaKm} km'),
              fila('Peajes (TAG)', (r) => formatoClp(r.peajesClp)),
              fila('Combustible', (r) => formatoClp(r.combustibleClp)),
              fila('Costo total', (r) => formatoClp(r.costoClp)),
            ],
          ),
        ),
        if (detalle.paradasPrioritarias > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('${detalle.paradasPrioritarias} parada(s) vencen en la jornada y se visitan primero.',
                style: tema.textTheme.bodySmall),
          ),
        if (detalle.algoritmo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Algoritmo: ${detalle.algoritmo}'
              '${detalle.mejoras2opt != null ? ' · 2-opt aplicó ${detalle.mejoras2opt} mejora(s)' : ''}'
              '${(detalle.mejora2optPct ?? 0) > 0.05 ? ' (${detalle.mejora2optPct!.toStringAsFixed(1)} % menos que solo Vecino Más Cercano)' : ''}',
              style: tema.textTheme.bodySmall,
            ),
          ),
        if ((detalle.totalRutas ?? 1) > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Reparto VRP: ruta ${detalle.lote} de ${detalle.totalRutas} calculadas en conjunto.',
                style: tema.textTheme.bodySmall),
          ),
        if (detalle.peajes != null) _DetallePeajes(peajes: detalle.peajes!),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Pórticos TAG que cruza la ruta elegida, con hora estimada de paso y
/// tarifa aplicada (geocercas sobre pórticos OSM + tarifas MOP 2026).
class _DetallePeajes extends StatelessWidget {
  final PeajesRuta peajes;

  const _DetallePeajes({required this.peajes});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final titulo = peajes.cruces.isEmpty
        ? 'TAG estimado: \$0 (la ruta elegida no cruza pórticos)'
        : 'TAG estimado: ${formatoClp(peajes.totalClp)} · ${peajes.cruces.length} pórtico(s)';
    return ExpansionTile(
      dense: true,
      leading: const Icon(Icons.toll),
      title: Text(titulo),
      subtitle: Text('Salida ${peajes.horaSalida} · categoría ${peajes.categoria} · tarifas MOP 2026',
          style: tema.textTheme.bodySmall),
      children: [
        for (final c in peajes.cruces)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Text(c.hora, style: tema.textTheme.labelLarge),
            title: Text('${c.concesion} · ${c.codigo}'),
            subtitle: Text(c.tramo),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatoClp(c.monto), style: tema.textTheme.titleSmall),
                Text(c.tarifa, style: tema.textTheme.bodySmall),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Estimación: la hora de paso se calcula según la distancia recorrida desde la salida '
            '(no incluye el tiempo en cada entrega).',
            style: tema.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Creación de una ruta optimizada para una jornada (RF-21, RF-22).
class RutaFormPantalla extends ConsumerStatefulWidget {
  const RutaFormPantalla({super.key});

  @override
  ConsumerState<RutaFormPantalla> createState() => _RutaFormPantallaState();
}

String _textoHora(TimeOfDay h) =>
    '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';

class _RutaFormPantallaState extends ConsumerState<RutaFormPantalla> {
  final _origenCtrl = TextEditingController();
  DireccionGeocodificada? _origen;
  DateTime _fecha = hoy();
  // Hora de salida de la bodega: define la tarifa TAG (TBFP/TBP/TS) de cada pórtico.
  TimeOfDay _salida = const TimeOfDay(hour: 9, minute: 0);
  final _choferes = <String>{}; // en el orden en que se eligieron
  final _seleccion = <String>{};
  bool _geocodificando = false;
  bool _guardando = false;

  @override
  void dispose() {
    _origenCtrl.dispose();
    super.dispose();
  }

  Future<void> _validarOrigen() async {
    if (_origenCtrl.text.trim().isEmpty) return;
    setState(() => _geocodificando = true);
    try {
      final r = await ref.read(geocodificacionRepositorioProvider).geocodificar(_origenCtrl.text.trim());
      setState(() {
        _origen = r;
        _origenCtrl.text = r.direccion;
      });
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _geocodificando = false);
    }
  }

  Future<void> _crear() async {
    if (_origen == null) return mostrarMensaje(context, 'Valida la dirección de salida');
    if (_seleccion.isEmpty) return mostrarMensaje(context, 'Selecciona al menos un despacho');
    if (_seleccion.length > 24) return mostrarMensaje(context, 'Máximo 24 despachos por cálculo');
    setState(() => _guardando = true);
    try {
      final creadas = await ref.read(rutasRepositorioProvider).crearOptimizada(
            fecha: _fecha,
            horaSalida: _textoHora(_salida),
            choferIds: _choferes.toList(),
            origenDireccion: _origen!.direccion,
            origenLat: _origen!.lat,
            origenLng: _origen!.lng,
            despachoIds: _seleccion.toList(),
          );
      ref.invalidate(rutasAdminProvider);
      if (!mounted) return;
      final avisos = [
        if (creadas.ids.length > 1) 'Se crearon ${creadas.ids.length} rutas (una por chofer)',
        ...creadas.advertencias,
      ];
      if (avisos.isNotEmpty) mostrarMensaje(context, avisos.join(' · '));
      if (creadas.ids.length == 1) {
        context.pushReplacement('/admin/rutas/${creadas.ids.first}');
      } else {
        context.pop();
      }
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordenesAsync = ref.watch(ordenesProvider);
    final choferes = ref.watch(choferesProvider).value ?? const [];

    final candidatas = (ordenesAsync.value ?? const <OrdenCompra>[])
        .where((o) => o.despacho != null && o.despacho!.estado != EstadoDespacho.entregado)
        .toList()
      ..sort((a, b) => a.fechaComprometida.compareTo(b.fechaComprometida));

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva ruta optimizada')),
      body: VistaAsync(
        cargando: ordenesAsync.isLoading,
        error: ordenesAsync.error,
        onReintentar: () => ref.invalidate(ordenesProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Jornada: ${formatoFecha(_fecha)}'),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final f = await showDatePicker(
                  context: context,
                  initialDate: _fecha,
                  firstDate: hoy().subtract(const Duration(days: 30)),
                  lastDate: hoy().add(const Duration(days: 365)),
                );
                if (f != null) setState(() => _fecha = f);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text('Hora de salida de bodega: ${_textoHora(_salida)}'),
              subtitle: const Text('Define la tarifa TAG estimada (fuera de punta, punta o saturación)'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final h = await showTimePicker(context: context, initialTime: _salida);
                if (h != null) setState(() => _salida = h);
              },
            ),
            Text('Choferes disponibles', style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'Con más de un chofer, el sistema reparte los despachos en un lote por chofer (VRP) '
              'y crea una ruta para cada uno.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final c in choferes)
                  FilterChip(
                    label: Text(c.nombreVisible),
                    selected: _choferes.contains(c.id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _choferes.add(c.id);
                        // Preselecciona los despachos de los que el chofer es responsable.
                        _seleccion.addAll(
                            candidatas.where((o) => o.responsableId == c.id).map((o) => o.despacho!.id));
                      } else {
                        _choferes.remove(c.id);
                      }
                    }),
                  ),
              ],
            ),
            if (_choferes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Sin chofer: se creará una ruta sin asignar.', style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _origenCtrl,
              decoration: InputDecoration(
                labelText: 'Dirección de salida (bodega)',
                helperText: _origen == null ? 'Presiona validar para ubicarla en el mapa' : 'Dirección validada ✓',
                suffixIcon: _geocodificando
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(icon: const Icon(Icons.travel_explore), onPressed: _validarOrigen),
              ),
              onChanged: (_) => setState(() => _origen = null),
              onSubmitted: (_) => _validarOrigen(),
            ),
            const Divider(height: 32),
            Text('Despachos de la jornada', style: Theme.of(context).textTheme.titleMedium),
            const Text(
                'Ordenados por plazo. Lo que vence en la jornada se visita primero; dentro de cada '
                'grupo el orden se optimiza con Vecino Más Cercano + 2-opt sobre distancias reales.',
                style: TextStyle(fontSize: 12)),
            if (candidatas.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('No hay despachos pendientes.')),
            for (final o in candidatas)
              CheckboxListTile(
                value: _seleccion.contains(o.despacho!.id),
                // Las direcciones sin validar se validan al calcular la ruta.
                onChanged: (v) => setState(() => v == true
                    ? _seleccion.add(o.despacho!.id)
                    : _seleccion.remove(o.despacho!.id)),
                title: Text(o.titulo),
                subtitle: Text('${o.direccionEntrega}\nPlazo ${formatoFecha(o.fechaComprometida)}'
                    '${o.geocodificada ? '' : ' · se validará al calcular'}'),
                isThreeLine: true,
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _guardando ? null : _crear,
              icon: _guardando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.alt_route),
              label: Text(_choferes.length > 1 ? 'Calcular ${_choferes.length} rutas óptimas' : 'Calcular ruta óptima'),
            ),
          ],
        ),
      ),
    );
  }
}
