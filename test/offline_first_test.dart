import 'package:flutter_test/flutter_test.dart';
import 'package:gygtrack/core/almacen_local.dart';
import 'package:gygtrack/modulos/logistico_notificaciones/datos/despachos_chofer_repositorio.dart';
import 'package:gygtrack/modulos/logistico_notificaciones/dominio/estado_despacho.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servidor simulado: se puede "cortar la conexión" y registra los cambios
/// recibidos.
class RemotoFalso implements DespachosRemoto {
  bool conectado = true;
  final estados = <String, String>{'d1': 'pendiente', 'd2': 'pendiente'};
  final recibidos = <(String, EstadoDespacho, DateTime)>[];
  final rechazar = <String>{};

  @override
  Future<List<Map<String, dynamic>>> listar() async {
    if (!conectado) throw Exception('Failed host lookup');
    return [
      for (final e in estados.entries)
        {
          'despacho_id': e.key,
          'orden_id': 'o-${e.key}',
          'estado': e.value,
          'cantidad_bultos': 3,
          'fecha_hora_entrega': null,
          'numero_oc': null,
          'cliente': 'Cliente ${e.key}',
          'direccion_entrega': 'Calle 123',
          'direccion_lat': -33.4,
          'direccion_lng': -70.6,
          'fecha_comprometida': '2026-11-20',
          'productos': [
            {'producto': 'Notebook', 'cantidad': 2},
          ],
        },
    ];
  }

  @override
  Future<void> cambiarEstado(String despachoId, EstadoDespacho estado, DateTime ocurridoEn) async {
    if (!conectado) throw Exception('Failed host lookup');
    if (rechazar.contains(despachoId)) {
      throw const PostgrestException(message: 'Despacho no encontrado o sin permiso');
    }
    recibidos.add((despachoId, estado, ocurridoEn));
    estados[despachoId] = estado.codigo;
  }
}

void main() {
  late RemotoFalso remoto;
  late DespachosChoferRepositorio repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    remoto = RemotoFalso();
    repo = DespachosChoferRepositorio(remoto, AlmacenLocal(), 'chofer-1');
  });

  test('con conexión, el cambio de estado se envía de inmediato', () async {
    await repo.cargar();
    final r = await repo.cambiarEstado('d1', EstadoDespacho.enRuta);
    expect(remoto.estados['d1'], 'en_ruta');
    expect(r.cambiosPendientes, 0);
    expect(r.sinConexion, isFalse);
  });

  test('sin conexión: se guarda local, se ve aplicado y se sincroniza al volver (RF-15)', () async {
    await repo.cargar(); // primera carga con conexión: queda copia local
    remoto.conectado = false;

    var r = await repo.cambiarEstado('d1', EstadoDespacho.enRuta);
    r = await repo.cambiarEstado('d1', EstadoDespacho.entregado);

    expect(r.sinConexion, isTrue);
    expect(r.cambiosPendientes, 2);
    final d1 = r.despachos.firstWhere((d) => d.despachoId == 'd1');
    expect(d1.estado, EstadoDespacho.entregado);
    expect(d1.pendienteDeSincronizar, isTrue);
    expect(d1.fechaHoraEntrega, isNotNull);
    expect(remoto.estados['d1'], 'pendiente'); // el servidor aún no sabe nada

    remoto.conectado = true;
    r = await repo.cargar();

    expect(r.cambiosPendientes, 0);
    expect(remoto.estados['d1'], 'entregado');
    // Se envían en orden y con la hora real del cambio (RF-16).
    expect(remoto.recibidos.map((c) => c.$2), [EstadoDespacho.enRuta, EstadoDespacho.entregado]);
    expect(remoto.recibidos.last.$3.isBefore(DateTime.now()), isTrue);
  });

  test('sin conexión y sin copia local informa el error', () async {
    remoto.conectado = false;
    expect(repo.cargar(), throwsA(isA<Exception>()));
  });

  test('no permite saltarse estados aunque esté offline', () async {
    await repo.cargar();
    remoto.conectado = false;
    expect(() => repo.cambiarEstado('d2', EstadoDespacho.entregado), throwsA(isA<Exception>()));
  });

  test('si el servidor rechaza un cambio, se descarta y se informa', () async {
    await repo.cargar();
    remoto.conectado = false;
    await repo.cambiarEstado('d2', EstadoDespacho.enRuta);
    remoto
      ..conectado = true
      ..rechazar.add('d2');

    final r = await repo.cargar();
    expect(r.cambiosPendientes, 0);
    expect(r.rechazos, hasLength(1));
    expect(r.despachos.firstWhere((d) => d.despachoId == 'd2').estado, EstadoDespacho.pendiente);
  });

  test('la copia local no contiene datos financieros (RF-03)', () async {
    await repo.cargar();
    final prefs = await SharedPreferences.getInstance();
    final todo = prefs.getKeys().map((k) => prefs.get(k).toString()).join();
    for (final campo in ['costo_compra', 'precio_venta', 'margen_neto', 'ahorro']) {
      expect(todo.contains(campo), isFalse, reason: campo);
    }
  });
}
