import '../../../core/almacen_local.dart';
import '../../../core/errores.dart';
import '../../../core/supabase_client.dart';
import '../dominio/despacho_chofer.dart';
import '../dominio/estado_despacho.dart';

/// Fuente remota de los despachos del Chofer (separada para poder probar la
/// lógica offline sin servidor).
abstract interface class DespachosRemoto {
  Future<List<Map<String, dynamic>>> listar();
  Future<void> cambiarEstado(String despachoId, EstadoDespacho estado, DateTime ocurridoEn);
}

class DespachosRemotoSupabase implements DespachosRemoto {
  @override
  Future<List<Map<String, dynamic>>> listar() =>
      supabase.from('v_despacho_chofer').select().order('fecha_comprometida');

  @override
  Future<void> cambiarEstado(String despachoId, EstadoDespacho estado, DateTime ocurridoEn) =>
      supabase.rpc('cambiar_estado_despacho', params: {
        'p_despacho_id': despachoId,
        'p_estado': estado.codigo,
        'p_ocurrido_en': ocurridoEn.toUtc().toIso8601String(),
      });
}

class ResultadoDespachos {
  final List<DespachoChofer> despachos;
  final int cambiosPendientes;
  final bool sinConexion;

  /// Cambios que el servidor rechazó (p. ej. el despacho fue reasignado).
  final List<String> rechazos;

  const ResultadoDespachos({
    required this.despachos,
    required this.cambiosPendientes,
    required this.sinConexion,
    this.rechazos = const [],
  });
}

/// Despachos del Chofer con enfoque offline-first (RF-13, RF-14, RF-15, RF-16).
///
/// * Los despachos se guardan en el dispositivo cada vez que se descargan.
/// * Un cambio de estado se aplica de inmediato en local y queda en una cola.
/// * La cola se envía en orden (FIFO) al recuperar la conexión, con la hora
///   real del cambio. El servidor es idempotente, así que reintentar es seguro.
/// * Si el servidor rechaza un cambio, se descarta y se informa al Chofer.
class DespachosChoferRepositorio {
  final DespachosRemoto _remoto;
  final AlmacenLocal _local;
  final String _usuarioId;

  Future<({bool sinConexion, List<String> rechazos})>? _sincronizacionEnCurso;
  var _contador = 0;

  DespachosChoferRepositorio(this._remoto, this._local, this._usuarioId);

  static const _claveDespachos = 'despachos';
  static const _claveCola = 'cola_estados';

  Future<List<CambioPendiente>> _leerCola() async {
    final datos = await _local.leerJson(_usuarioId, _claveCola);
    if (datos is! List) return [];
    return datos.map((m) => CambioPendiente.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<void> _guardarCola(List<CambioPendiente> cola) =>
      _local.guardarJson(_usuarioId, _claveCola, cola.map((c) => c.toMap()).toList());

  Future<int> cambiosPendientes() async => (await _leerCola()).length;

  /// Descarga los despachos (si hay conexión) y les aplica los cambios aún no
  /// sincronizados. Sin conexión, trabaja con la copia local.
  Future<ResultadoDespachos> cargar() async {
    final sync = await sincronizar();
    var sinConexion = sync.sinConexion;

    List<Map<String, dynamic>>? filas;
    if (!sinConexion) {
      try {
        filas = await _remoto.listar();
        await _local.guardarJson(_usuarioId, _claveDespachos, filas);
      } catch (e) {
        if (!esErrorDeConexion(e)) rethrow;
        sinConexion = true;
      }
    }
    if (filas == null) {
      final cache = await _local.leerJson(_usuarioId, _claveDespachos);
      if (cache is! List) {
        throw Exception('Sin conexión y sin datos guardados en el dispositivo');
      }
      filas = cache.cast<Map<String, dynamic>>();
    }

    final cola = await _leerCola();
    return ResultadoDespachos(
      despachos: _aplicarCola(filas.map(DespachoChofer.fromMap).toList(), cola),
      cambiosPendientes: cola.length,
      sinConexion: sinConexion,
      rechazos: sync.rechazos,
    );
  }

  /// Registra un cambio de estado (funciona sin conexión) y trata de
  /// sincronizarlo de inmediato.
  Future<ResultadoDespachos> cambiarEstado(String despachoId, EstadoDespacho nuevo) async {
    final actual = await _estadoEfectivo(despachoId);
    if (actual == null) throw Exception('Despacho no encontrado en el dispositivo');
    if (!actual.puedeAvanzarA(nuevo)) {
      throw Exception('No se puede pasar de "${actual.etiqueta}" a "${nuevo.etiqueta}"');
    }

    final cola = await _leerCola();
    cola.add(CambioPendiente(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_contador++}',
      despachoId: despachoId,
      estado: nuevo,
      ocurridoEn: DateTime.now(),
    ));
    await _guardarCola(cola);
    return cargar();
  }

  /// Envía la cola al servidor. Se detiene al primer error de conexión.
  Future<({bool sinConexion, List<String> rechazos})> sincronizar() {
    return _sincronizacionEnCurso ??= _sincronizar().whenComplete(() => _sincronizacionEnCurso = null);
  }

  Future<({bool sinConexion, List<String> rechazos})> _sincronizar() async {
    final cola = await _leerCola();
    final rechazos = <String>[];
    var sinConexion = false;

    while (cola.isNotEmpty) {
      final cambio = cola.first;
      try {
        await _remoto.cambiarEstado(cambio.despachoId, cambio.estado, cambio.ocurridoEn);
      } catch (e) {
        if (esErrorDeConexion(e)) {
          sinConexion = true;
          break;
        }
        rechazos.add('No se aplicó "${cambio.estado.etiqueta}": ${mensajeError(e)}');
      }
      cola.removeAt(0);
      await _guardarCola(cola);
    }
    return (sinConexion: sinConexion, rechazos: rechazos);
  }

  Future<EstadoDespacho?> _estadoEfectivo(String despachoId) async {
    final cache = await _local.leerJson(_usuarioId, _claveDespachos);
    if (cache is! List) return null;
    final despachos = _aplicarCola(
      cache.cast<Map<String, dynamic>>().map(DespachoChofer.fromMap).toList(),
      await _leerCola(),
    );
    for (final d in despachos) {
      if (d.despachoId == despachoId) return d.estado;
    }
    return null;
  }

  static List<DespachoChofer> _aplicarCola(
      List<DespachoChofer> despachos, List<CambioPendiente> cola) {
    if (cola.isEmpty) return despachos;
    final porId = {for (final d in despachos) d.despachoId: d};
    for (final cambio in cola) {
      final d = porId[cambio.despachoId];
      if (d != null && cambio.estado.index > d.estado.index) {
        porId[cambio.despachoId] = d.conEstado(cambio.estado, cambio.ocurridoEn);
      }
    }
    return despachos.map((d) => porId[d.despachoId]!).toList();
  }
}
