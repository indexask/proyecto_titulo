/// Los dos únicos roles del sistema (RF-02).
enum Rol { administrador, chofer }

Rol rolDesdeTexto(String? valor) =>
    valor == 'administrador' ? Rol.administrador : Rol.chofer;

class Usuario {
  final String id;
  final String? nombre;
  final Rol rol;

  const Usuario({required this.id, required this.rol, this.nombre});

  bool get esAdministrador => rol == Rol.administrador;

  String get nombreVisible => (nombre == null || nombre!.isEmpty) ? 'Sin nombre' : nombre!;

  factory Usuario.fromMap(Map<String, dynamic> map) => Usuario(
        id: map['id'] as String,
        nombre: map['nombre'] as String?,
        rol: rolDesdeTexto(map['rol'] as String?),
      );

  Map<String, dynamic> toMap() => {'id': id, 'nombre': nombre, 'rol': rol.name};
}
