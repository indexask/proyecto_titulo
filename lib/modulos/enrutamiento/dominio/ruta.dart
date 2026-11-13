import '../../logistico_notificaciones/dominio/estado_despacho.dart';

/// Parada de una ruta lista para dibujarse en el mapa. No contiene datos
/// financieros, por lo que sirve para ambas vistas.
class ParadaRuta {
  final int orden;
  final String despachoId;
  final String cliente;
  final String direccion;
  final double? lat;
  final double? lng;
  final EstadoDespacho estado;

  const ParadaRuta({
    required this.orden,
    required this.despachoId,
    required this.cliente,
    required this.direccion,
    required this.lat,
    required this.lng,
    required this.estado,
  });
}

/// Datos de la ruta comunes a Administrador y Chofer (RF-23).
class Ruta {
  final String id;
  final DateTime fecha;
  final String origenDireccion;
  final double origenLat;
  final double origenLng;
  final num? distanciaKm;
  final int? duracionMin;
  final String? polilinea;
  final List<ParadaRuta> paradas;

  /// La ruta pasa por autopistas con TAG (dato operativo, sin montos).
  final bool usaPeajes;

  const Ruta({
    required this.id,
    required this.fecha,
    required this.origenDireccion,
    required this.origenLat,
    required this.origenLng,
    required this.paradas,
    this.distanciaKm,
    this.duracionMin,
    this.polilinea,
    this.usaPeajes = false,
  });

  /// Primera parada aún no entregada (la próxima a visitar).
  ParadaRuta? get proximaParada =>
      paradas.where((p) => p.estado != EstadoDespacho.entregado).firstOrNull;

  int get entregadas => paradas.where((p) => p.estado == EstadoDespacho.entregado).length;

  /// Avance de la ruta según sus paradas.
  EstadoRuta get estado {
    if (paradas.isNotEmpty && entregadas == paradas.length) return EstadoRuta.completada;
    if (paradas.any((p) => p.estado != EstadoDespacho.pendiente)) return EstadoRuta.enCurso;
    return EstadoRuta.porIniciar;
  }
}

/// Estado de una ruta, derivado del estado de sus despachos (RF-14).
enum EstadoRuta {
  porIniciar('Por iniciar'),
  enCurso('En curso'),
  completada('Completada');

  final String etiqueta;

  const EstadoRuta(this.etiqueta);
}

/// Tiempo, km, TAG y combustible de una alternativa de recorrido.
class ResumenRecorrido {
  final num distanciaKm;
  final int duracionMin;
  final num peajesClp;
  final num combustibleClp;
  final num costoClp;

  const ResumenRecorrido({
    required this.distanciaKm,
    required this.duracionMin,
    required this.peajesClp,
    required this.combustibleClp,
    required this.costoClp,
  });

  factory ResumenRecorrido.fromMap(Map<String, dynamic> m) => ResumenRecorrido(
        distanciaKm: m['distanciaKm'] as num,
        duracionMin: (m['duracionMin'] as num).toInt(),
        peajesClp: m['peajesClp'] as num,
        combustibleClp: m['combustibleClp'] as num,
        costoClp: m['costoClp'] as num,
      );
}

/// Alternativa elegida por la optimización.
enum AlternativaRuta { ordenPorPlazo, optimizadaConTag, optimizadaSinTag }

/// Comparación que hizo la optimización (RF-22, RF-24): orden por plazo,
/// optimizada permitiendo TAG y optimizada evitando TAG, y por qué se eligió
/// la final (menor costo + $50/min, regla de $500 por cada 10 minutos).
class DetalleOptimizacion {
  final ResumenRecorrido sinOptimizar;
  final ResumenRecorrido conTag;
  final ResumenRecorrido sinTag;
  final AlternativaRuta eleccion;
  final String motivo;
  final int paradasPrioritarias;

  const DetalleOptimizacion({
    required this.sinOptimizar,
    required this.conTag,
    required this.sinTag,
    required this.eleccion,
    required this.motivo,
    required this.paradasPrioritarias,
  });

  ResumenRecorrido get elegida => switch (eleccion) {
        AlternativaRuta.ordenPorPlazo => sinOptimizar,
        AlternativaRuta.optimizadaConTag => conTag,
        AlternativaRuta.optimizadaSinTag => sinTag,
      };

  static DetalleOptimizacion? fromMap(Object? datos) {
    if (datos is! Map<String, dynamic>) return null;
    return DetalleOptimizacion(
      sinOptimizar: ResumenRecorrido.fromMap(datos['sinOptimizar'] as Map<String, dynamic>),
      conTag: ResumenRecorrido.fromMap(datos['conTag'] as Map<String, dynamic>),
      sinTag: ResumenRecorrido.fromMap(datos['sinTag'] as Map<String, dynamic>),
      eleccion: switch (datos['elegida']) {
        'sin_optimizar' => AlternativaRuta.ordenPorPlazo,
        'con_tag' => AlternativaRuta.optimizadaConTag,
        _ => AlternativaRuta.optimizadaSinTag,
      },
      motivo: datos['motivo'] as String? ?? '',
      paradasPrioritarias: (datos['paradasPrioritarias'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Vista completa del Administrador: agrega costos y ahorro (RF-24).
class RutaAdmin extends Ruta {
  final String? choferId;
  final String? choferNombre;
  final num? costoSinOptimizar;
  final num? costoOptimizada;
  final num? ahorro;
  final DetalleOptimizacion? detalle;

  const RutaAdmin({
    required super.id,
    required super.fecha,
    required super.origenDireccion,
    required super.origenLat,
    required super.origenLng,
    required super.paradas,
    super.distanciaKm,
    super.duracionMin,
    super.polilinea,
    super.usaPeajes,
    this.choferId,
    this.choferNombre,
    this.costoSinOptimizar,
    this.costoOptimizada,
    this.ahorro,
    this.detalle,
  });

  factory RutaAdmin.fromMap(Map<String, dynamic> map) {
    final paradas = ((map['ruta_parada'] as List?) ?? const []).map((p) {
      final despacho = p['despacho'] as Map<String, dynamic>;
      final orden = despacho['orden_compra'] as Map<String, dynamic>;
      return ParadaRuta(
        orden: p['orden'] as int,
        despachoId: despacho['id'] as String,
        cliente: orden['cliente'] as String,
        direccion: orden['direccion_entrega'] as String,
        lat: (orden['direccion_lat'] as num?)?.toDouble(),
        lng: (orden['direccion_lng'] as num?)?.toDouble(),
        estado: EstadoDespacho.desdeCodigo(despacho['estado'] as String?),
      );
    }).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));

    return RutaAdmin(
      id: map['id'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      origenDireccion: map['origen_direccion'] as String,
      origenLat: (map['origen_lat'] as num).toDouble(),
      origenLng: (map['origen_lng'] as num).toDouble(),
      distanciaKm: map['distancia_km'] as num?,
      duracionMin: map['duracion_min'] as int?,
      polilinea: map['polilinea'] as String?,
      paradas: paradas,
      choferId: map['chofer_id'] as String?,
      choferNombre: (map['chofer'] as Map<String, dynamic>?)?['nombre'] as String?,
      usaPeajes: map['usa_peajes'] as bool? ?? false,
      costoSinOptimizar: map['costo_ruta_sin_optimizar'] as num?,
      costoOptimizada: map['costo_ruta_optimizada'] as num?,
      ahorro: map['ahorro'] as num?,
      detalle: DetalleOptimizacion.fromMap(map['detalle_optimizacion']),
    );
  }
}

/// Fila de la vista v_ruta_chofer: solo el orden de las paradas; los datos
/// de cada parada se completan con los despachos del Chofer.
class RutaChoferFila {
  final Map<String, dynamic> datos;

  const RutaChoferFila(this.datos);

  String get id => datos['id'] as String;
  DateTime get fecha => DateTime.parse(datos['fecha'] as String);

  List<({String despachoId, int orden})> get paradas =>
      ((datos['paradas'] as List?) ?? const [])
          .map((p) => (despachoId: p['despacho_id'] as String, orden: p['orden'] as int))
          .toList();
}
