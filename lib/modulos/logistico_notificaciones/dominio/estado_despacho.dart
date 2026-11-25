/// Máquina de estados del despacho (RF-14):
///   Pendiente → En Ruta → Entregado
///   En Ruta → No entregado (requiere motivo)
///   No entregado → En Ruta (reintento) | Entregado
/// La misma regla se valida en la base de datos (transicion_despacho_valida).
enum EstadoDespacho {
  pendiente('pendiente', 'Pendiente'),
  enRuta('en_ruta', 'En Ruta'),
  entregado('entregado', 'Entregado'),
  noEntregado('no_entregado', 'No entregado');

  final String codigo;
  final String etiqueta;

  const EstadoDespacho(this.codigo, this.etiqueta);

  static EstadoDespacho desdeCodigo(String? codigo) =>
      values.firstWhere((e) => e.codigo == codigo, orElse: () => pendiente);

  /// Transiciones permitidas desde este estado (debe coincidir con la BD).
  List<EstadoDespacho> get siguientesPosibles => switch (this) {
        pendiente => const [enRuta],
        enRuta => const [entregado, noEntregado],
        noEntregado => const [enRuta, entregado],
        entregado => const [],
      };

  bool puedeAvanzarA(EstadoDespacho destino) => siguientesPosibles.contains(destino);

  /// Estado "principal" al que lleva el botón de avance (el camino normal).
  /// `null` si el despacho ya fue entregado.
  EstadoDespacho? get siguiente => switch (this) {
        pendiente => enRuta,
        enRuta => entregado,
        noEntregado => entregado,
        entregado => null,
      };

  /// Un estado terminal no admite más cambios desde la app.
  bool get esTerminal => this == entregado;

  /// Este estado exige una justificación (motivo).
  bool get requiereMotivo => this == noEntregado;

  /// Texto de la acción que lleva a este estado (para los botones del Chofer).
  String get accion => switch (this) {
        pendiente => 'Marcar pendiente',
        enRuta => 'Iniciar ruta',
        entregado => 'Confirmar entrega',
        noEntregado => 'No entregado',
      };
}
