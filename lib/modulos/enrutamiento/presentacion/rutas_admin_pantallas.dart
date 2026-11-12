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
    DataColumn columna(String titulo, AlternativaRuta alt) => DataColumn(
          numeric: true,
          label: Text(e == alt ? '$titulo ✓' : titulo, style: e == alt ? negrita : null),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('${detalle.paradasPrioritarias} parada(s) vencen en la jornada y se visitan primero.',
                style: tema.textTheme.bodySmall),
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

class _RutaFormPantallaState extends ConsumerState<RutaFormPantalla> {
  final _origenCtrl = TextEditingController();
  DireccionGeocodificada? _origen;
  DateTime _fecha = hoy();
  String? _choferId;
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
    setState(() => _guardando = true);
    try {
      final creada = await ref.read(rutasRepositorioProvider).crearOptimizada(
            fecha: _fecha,
            choferId: _choferId,
            origenDireccion: _origen!.direccion,
            origenLat: _origen!.lat,
            origenLng: _origen!.lng,
            despachoIds: _seleccion.toList(),
          );
      ref.invalidate(rutasAdminProvider);
      if (!mounted) return;
      if (creada.advertencias.isNotEmpty) {
        mostrarMensaje(context, 'Atención: ${creada.advertencias.join(' · ')}');
      }
      context.pushReplacement('/admin/rutas/${creada.id}');
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
            DropdownButtonFormField<String?>(
              initialValue: _choferId,
              decoration: const InputDecoration(labelText: 'Chofer'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin asignar')),
                for (final c in choferes) DropdownMenuItem(value: c.id, child: Text(c.nombreVisible)),
              ],
              onChanged: (v) => setState(() {
                _choferId = v;
                // Preselecciona los despachos de los que el chofer es responsable.
                if (v != null) {
                  _seleccion
                    ..clear()
                    ..addAll(candidatas
                        .where((o) => o.responsableId == v)
                        .map((o) => o.despacho!.id));
                }
              }),
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
                'Ordenados por plazo. Lo que vence en la jornada se visita primero; '
                'dentro de cada grupo el orden se optimiza automáticamente.',
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
              label: const Text('Calcular ruta óptima'),
            ),
          ],
        ),
      ),
    );
  }
}
