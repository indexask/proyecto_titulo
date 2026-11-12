/// Máquina de estados del despacho (RF-14): Pendiente → En Ruta → Entregado.
/// La misma regla se valida en la base de datos (trigger despacho_transicion).
enum EstadoDespacho {
  pendiente('pendiente', 'Pendiente'),
  enRuta('en_ruta', 'En Ruta'),
  entregado('entregado', 'Entregado');

  final String codigo;
  final String etiqueta;

  const EstadoDespacho(this.codigo, this.etiqueta);

  static EstadoDespacho desdeCodigo(String? codigo) =>
      values.firstWhere((e) => e.codigo == codigo, orElse: () => pendiente);

  /// Siguiente estado permitido, o `null` si el despacho ya fue entregado.
  EstadoDespacho? get siguiente => switch (this) {
        pendiente => enRuta,
        enRuta => entregado,
        entregado => null,
      };

  bool puedeAvanzarA(EstadoDespacho destino) => siguiente == destino;

  /// Texto de la acción que lleva a este estado (para los botones del Chofer).
  String get accion => switch (this) {
        pendiente => 'Marcar pendiente',
        enRuta => 'Iniciar ruta',
        entregado => 'Confirmar entrega',
      };
}
