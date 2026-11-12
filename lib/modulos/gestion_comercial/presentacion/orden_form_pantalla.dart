import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errores.dart';
import '../../../core/formato.dart';
import '../../../core/widgets/vista_async.dart';
import '../../administracion_seguridad/presentacion/auth_providers.dart';
import '../../enrutamiento/presentacion/enrutamiento_providers.dart';
import '../dominio/cotizacion_importada.dart';
import '../dominio/orden_compra.dart';
import '../dominio/producto.dart';
import '../dominio/rentabilidad.dart';
import 'comercial_providers.dart';
import 'foto_producto.dart';

/// Registro / edición de una adjudicación (RF-05, RF-06, RF-09, RF-10).
/// Puede venir precargada con una cotización importada desde PDF. El margen
/// neto se calcula al instante mientras se ingresan costos y precios (RF-07,
/// KPI-03).
class OrdenFormPantalla extends ConsumerWidget {
  final String? ordenId;
  final CotizacionImportada? importada;

  const OrdenFormPantalla({super.key, this.ordenId, this.importada});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productos = ref.watch(productosProvider);
    final usuarios = ref.watch(usuariosProvider);
    final orden = ordenId == null ? null : ref.watch(ordenProvider(ordenId!));

    final cargando = productos.isLoading || usuarios.isLoading || (orden?.isLoading ?? false);
    final error = productos.error ?? usuarios.error ?? orden?.error;

    final titulo = ordenId != null
        ? 'Editar orden'
        : importada != null
            ? 'Orden desde cotización'
            : 'Registrar adjudicación';

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: VistaAsync(
        cargando: cargando,
        error: error,
        onReintentar: () {
          ref.invalidate(productosProvider);
          ref.invalidate(usuariosProvider);
          if (ordenId != null) ref.invalidate(ordenProvider(ordenId!));
        },
        child: cargando || error != null
            ? const SizedBox.shrink()
            : _Formulario(productos: productos.value!, orden: orden?.value, importada: importada),
      ),
    );
  }
}

/// Línea de producto del formulario: del catálogo o nueva (desde cotización).
class _LineaForm implements LineaConMargen {
  Producto? producto;
  TextEditingController? nombreNuevoCtrl;
  Uint8List? foto;
  final cantidadCtrl = TextEditingController(text: '1');
  final costoCtrl = TextEditingController();
  final precioCtrl = TextEditingController();

  _LineaForm();

  _LineaForm.desde(DetalleOrden d, List<Producto> catalogo) {
    producto = catalogo.where((p) => p.id == d.productoId).firstOrNull;
    cantidadCtrl.text = '${d.cantidad}';
    costoCtrl.text = textoMonto(d.costoCompra);
    precioCtrl.text = textoMonto(d.precioVenta);
  }

  /// Desde una línea de cotización: si el producto ya está en el catálogo se
  /// reutiliza (con su costo); si no, queda como producto nuevo.
  _LineaForm.importada(LineaImportada l, List<Producto> catalogo, {this.foto}) {
    final clave = normalizarNombre(l.descripcion);
    producto = catalogo.where((p) => normalizarNombre(p.nombre) == clave).firstOrNull;
    if (producto == null) {
      nombreNuevoCtrl = TextEditingController(text: l.descripcion);
    } else {
      costoCtrl.text = textoMonto(producto!.costoCompra);
    }
    cantidadCtrl.text = '${l.unidades}';
    precioCtrl.text = textoMonto(l.precioUnidad); // precio adjudicado en la cotización
  }

  bool get esNueva => producto == null && nombreNuevoCtrl != null;
  bool get incluida => producto != null || esNueva;
  String get nombre => producto?.nombre ?? nombreNuevoCtrl?.text.trim() ?? '';

  void elegir(Producto p) {
    producto = p;
    nombreNuevoCtrl?.dispose();
    nombreNuevoCtrl = null;
    costoCtrl.text = textoMonto(p.costoCompra);
    precioCtrl.text = textoMonto(p.precioVenta);
  }

  @override
  num get cantidad => int.tryParse(cantidadCtrl.text.trim()) ?? 0;
  @override
  num get costoCompra => parsearMonto(costoCtrl.text) ?? 0;
  @override
  num get precioVenta => parsearMonto(precioCtrl.text) ?? 0;

  bool get completa =>
      incluida &&
      nombre.isNotEmpty &&
      cantidad > 0 &&
      parsearMonto(costoCtrl.text) != null &&
      parsearMonto(precioCtrl.text) != null;

  DetalleOrden aDetalle(String productoId) => DetalleOrden(
        productoId: productoId,
        productoNombre: nombre,
        cantidad: cantidad.toInt(),
        costoCompra: costoCompra,
        precioVenta: precioVenta,
      );

  void dispose() {
    nombreNuevoCtrl?.dispose();
    cantidadCtrl.dispose();
    costoCtrl.dispose();
    precioCtrl.dispose();
  }
}

class _Formulario extends ConsumerStatefulWidget {
  final List<Producto> productos;
  final OrdenCompra? orden;
  final CotizacionImportada? importada;

  const _Formulario({required this.productos, required this.orden, this.importada});

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _formKey = GlobalKey<FormState>();
  final _numeroCtrl = TextEditingController();
  final _numeroCotizacionCtrl = TextEditingController();
  final _clienteCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  late DateTime _fechaComprometida;
  DateTime? _fechaCotizacion;
  String? _responsableId;
  double? _lat;
  double? _lng;
  final _lineas = <_LineaForm>[];
  bool _geocodificando = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final o = widget.orden;
    final c = widget.importada;

    _numeroCtrl.text = o?.numeroOc ?? '';
    _numeroCotizacionCtrl.text = o?.numeroCotizacion ?? c?.numeroCotizacion ?? '';
    _fechaCotizacion = o?.fechaCotizacion ?? c?.fechaCotizacion;
    _clienteCtrl.text = o?.cliente ?? c?.solicitadoPor ?? '';
    _direccionCtrl.text = o?.direccionEntrega ?? c?.direccion ?? '';
    _lat = o?.direccionLat;
    _lng = o?.direccionLng;
    _responsableId = o?.responsableId;

    // Plazo: el de la orden; o, desde una cotización, "N días hábiles" desde hoy.
    _fechaComprometida = o?.fechaComprometida ??
        (c?.plazoDiasHabiles != null
            ? sumarDiasHabiles(hoy(), c!.plazoDiasHabiles!.max)
            : hoy().add(const Duration(days: 7)));

    if (o != null) {
      _lineas.addAll(o.detalles.map((d) => _LineaForm.desde(d, widget.productos)));
    } else if (c != null) {
      for (final (i, l) in c.lineas.indexed) {
        // La cotización trae una foto: corresponde al producto principal.
        _lineas.add(_LineaForm.importada(l, widget.productos, foto: i == 0 ? c.foto : null));
      }
    }
    if (_lineas.isEmpty) _lineas.add(_LineaForm());

    // Desde una cotización, la dirección se valida sola (Places).
    if (c != null && _direccionCtrl.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _validarDireccion(silencioso: true));
    }
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _numeroCotizacionCtrl.dispose();
    _clienteCtrl.dispose();
    _direccionCtrl.dispose();
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _validarDireccion({bool silencioso = false}) async {
    if (_direccionCtrl.text.trim().isEmpty) return;
    setState(() => _geocodificando = true);
    try {
      final r = await ref.read(geocodificacionRepositorioProvider).geocodificar(_direccionCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _direccionCtrl.text = r.direccion;
        _lat = r.lat;
        _lng = r.lng;
      });
    } catch (e) {
      if (mounted && !silencioso) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _geocodificando = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final lineas = _lineas.where((l) => l.incluida).toList();
    if (lineas.isEmpty) return mostrarMensaje(context, 'Agrega al menos un producto');
    if (lineas.any((l) => !l.completa)) {
      return mostrarMensaje(context, 'Completa cantidad, costo de compra y precio de cada producto');
    }

    setState(() => _guardando = true);
    final productosRepo = ref.read(productosRepositorioProvider);
    try {
      final detalles = <DetalleOrden>[];
      for (final l in lineas) {
        if (l.esNueva) {
          // Producto nuevo desde la cotización: se agrega al catálogo.
          final id = await productosRepo.guardar(
            nombre: l.nombre,
            costoCompra: l.costoCompra,
            precioVenta: l.precioVenta,
          );
          if (l.foto != null) await productosRepo.subirFoto(id, l.foto!);
          // Si algo falla después, reintentar no vuelve a crear el producto.
          l.elegir(Producto(id: id, nombre: l.nombre, costoCompra: l.costoCompra, precioVenta: l.precioVenta));
        } else if (l.foto != null && l.producto!.fotoPath == null) {
          await productosRepo.subirFoto(l.producto!.id, l.foto!);
        }
        detalles.add(l.aDetalle(l.producto!.id));
      }

      final id = await ref.read(ordenesRepositorioProvider).guardar(
            id: widget.orden?.id,
            numeroOc: _numeroCtrl.text.trim(),
            numeroCotizacion: _numeroCotizacionCtrl.text.trim(),
            fechaCotizacion: _fechaCotizacion,
            cliente: _clienteCtrl.text.trim(),
            direccionEntrega: _direccionCtrl.text.trim(),
            direccionLat: _lat,
            direccionLng: _lng,
            fechaComprometida: _fechaComprometida,
            responsableId: _responsableId,
            detalles: detalles,
          );
      ref.invalidate(ordenesProvider);
      ref.invalidate(ordenProvider(id));
      ref.invalidate(productosProvider);
      if (!mounted) return;
      if (widget.orden == null) {
        context.pushReplacement('/admin/ordenes/$id');
      } else {
        context.pop();
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      mostrarMensaje(
        context,
        e.code == '23505'
            ? 'La cotización ${_numeroCotizacionCtrl.text.trim()} ya fue registrada en otra orden'
            : mensajeError(e),
      );
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<DateTime?> _elegirFecha(DateTime inicial) => showDatePicker(
        context: context,
        initialDate: inicial,
        firstDate: DateTime(2024),
        lastDate: DateTime(2100),
      );

  @override
  Widget build(BuildContext context) {
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    final lineasValidas = _lineas.where((l) => l.incluida);
    final margen = calcularMargenNeto(lineasValidas);
    final venta = calcularVentaTotal(lineasValidas);
    final pct = porcentajeMargen(margen, venta);
    final tema = Theme.of(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.importada != null) _ResumenImportacion(c: widget.importada!, lineas: _lineas),
          Text('Datos de la adjudicación', style: tema.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _numeroCotizacionCtrl,
                decoration: const InputDecoration(labelText: 'N° de cotización'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final f = await _elegirFecha(_fechaCotizacion ?? hoy());
                  if (f != null) setState(() => _fechaCotizacion = f);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Fecha de cotización'),
                  child: Text(formatoFecha(_fechaCotizacion)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _numeroCtrl,
            decoration: const InputDecoration(labelText: 'N° de orden de compra (cuando se emita)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _clienteCtrl,
            decoration: const InputDecoration(labelText: 'Cliente (Solicitado por)'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _direccionCtrl,
            decoration: InputDecoration(
              labelText: 'Dirección de entrega',
              helperText: _geocodificando
                  ? 'Validando dirección…'
                  : _lat == null
                      ? 'Valídala para poder incluirla en una ruta'
                      : 'Dirección validada ✓',
              suffixIcon: _geocodificando
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      tooltip: 'Validar dirección',
                      icon: const Icon(Icons.travel_explore),
                      onPressed: _validarDireccion,
                    ),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            onChanged: (_) => setState(() => _lat = _lng = null),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Plazo de entrega: ${formatoFecha(_fechaComprometida)}'),
            subtitle: widget.importada?.plazoDiasHabiles != null
                ? Text('Propuesto: ${widget.importada!.plazoDiasHabiles!.max} días hábiles desde hoy')
                : null,
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final f = await _elegirFecha(_fechaComprometida);
              if (f != null) setState(() => _fechaComprometida = f);
            },
          ),
          DropdownButtonFormField<String?>(
            initialValue: _responsableId,
            decoration: const InputDecoration(labelText: 'Responsable'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin asignar')),
              for (final u in usuarios)
                DropdownMenuItem(
                  value: u.id,
                  child: Text('${u.nombreVisible} (${u.esAdministrador ? 'Administrador' : 'Chofer'})'),
                ),
            ],
            onChanged: (v) => setState(() => _responsableId = v),
          ),
          const Divider(height: 32),
          Text('Productos, costos y precios adjudicados', style: tema.textTheme.titleMedium),
          for (final (i, linea) in _lineas.indexed) _filaLinea(i, linea),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lineas.add(_LineaForm())),
              icon: const Icon(Icons.add),
              label: const Text('Agregar producto'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: margen < 0 ? tema.colorScheme.errorContainer : tema.colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.trending_up),
              title: Text('Margen neto: ${formatoClp(margen)}',
                  style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              subtitle: Text('Venta total ${formatoClp(venta)}'
                  '${pct == null ? '' : ' · ${pct.toStringAsFixed(1)} % de margen'}'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar orden'),
          ),
        ],
      ),
    );
  }

  Widget _filaLinea(int indice, _LineaForm linea) {
    InputDecoration deco(String etiqueta, {String? ayuda}) =>
        InputDecoration(labelText: etiqueta, helperText: ayuda, isDense: true);
    final faltaCosto = linea.incluida && parsearMonto(linea.costoCtrl.text) == null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (linea.foto != null || linea.producto?.fotoPath != null) ...[
                  FotoProducto(bytes: linea.foto, ruta: linea.producto?.fotoPath, tamano: 64),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: linea.esNueva
                      ? TextFormField(
                          controller: linea.nombreNuevoCtrl,
                          maxLines: null,
                          decoration: deco('Producto', ayuda: 'Nuevo: se agregará al catálogo'),
                          onChanged: (_) => setState(() {}),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: linea.producto?.id,
                          isExpanded: true,
                          decoration: deco('Producto del catálogo'),
                          items: [
                            for (final p in widget.productos)
                              DropdownMenuItem(value: p.id, child: Text(p.nombre, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (id) => setState(
                              () => linea.elegir(widget.productos.firstWhere((p) => p.id == id))),
                        ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _lineas.removeAt(indice).dispose()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: linea.cantidadCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Unidades'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: linea.costoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Costo compra', ayuda: faltaCosto ? 'Ingresa el costo' : null).copyWith(
                      helperStyle: faltaCosto ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: linea.precioCtrl,
                    keyboardType: TextInputType.number,
                    decoration: deco('Precio unidad'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (linea.incluida)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Total ${formatoClp(linea.precioVenta * linea.cantidad)} · '
                      'Margen ${formatoClp(margenDeLinea(linea))}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Resumen de lo leído del PDF: totales de la cotización y avisos.
class _ResumenImportacion extends StatelessWidget {
  final CotizacionImportada c;
  final List<_LineaForm> lineas;

  const _ResumenImportacion({required this.c, required this.lineas});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nuevas = lineas.where((l) => l.esNueva && parsearMonto(l.costoCtrl.text) == null).length;
    return Card(
      color: tema.colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.picture_as_pdf),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Datos leídos de la cotización ${c.numeroCotizacion ?? ''}',
                    style: tema.textTheme.titleSmall),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Total cotización (neto): ${formatoClp(c.subtotal)}'
                '${c.totalConIva != null ? ' · con IVA ${formatoClp(c.totalConIva)}' : ''}'),
            if (nuevas > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Falta el costo de compra de $nuevas producto(s) nuevo(s): no viene en la '
                  'cotización y se necesita para calcular el margen.',
                  style: TextStyle(color: tema.colorScheme.error, fontWeight: FontWeight.w600),
                ),
              ),
            for (final a in c.advertencias)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.warning_amber, size: 16),
                  const SizedBox(width: 4),
                  Expanded(child: Text(a)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
