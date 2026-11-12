/// `true` si Google Maps puede dibujarse. En web depende de que se haya
/// cargado la Maps JavaScript API (clave en web/maps_config.js); en Android e
/// iOS el SDK es nativo.
export 'mapas_disponibles_nativo.dart' if (dart.library.js_interop) 'mapas_disponibles_web.dart';
