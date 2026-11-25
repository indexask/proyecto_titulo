import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// La Maps JavaScript API define `window.google.maps` al cargarse.
bool get mapasDisponibles {
  if (!globalContext.has('google')) return false;
  final google = globalContext['google'];
  return google != null && (google as JSObject).has('maps');
}
