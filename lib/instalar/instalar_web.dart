import 'dart:js_interop';

import 'instalar_stub.dart' show Instalacion;

export 'instalar_stub.dart' show Instalacion;

extension type _Credi._(JSObject _) implements JSObject {
  external JSObject? get aviso;
  external bool? get instalada;
}

@JS('credi')
external _Credi? get _credi;

@JS('crediInstalar')
external JSPromise<JSString> _instalar();

extension type _ConsultaMedia._(JSObject _) implements JSObject {
  external bool get matches;
}

@JS('matchMedia')
external _ConsultaMedia _matchMedia(String consulta);

@JS('navigator.userAgent')
external String get _agente;

@JS('navigator.maxTouchPoints')
external int? get _puntosTactiles;

@JS('navigator.standalone')
external bool? get _standaloneIos;

@JS('window.addEventListener')
external void _escuchar(String evento, JSFunction funcion);

// Si web/index.html es viejo (en caché) y no trae lo de instalar, todo dice
// "ya instalada" y la tarjeta no sale.

Instalacion estadoInstalacion() {
  try {
    if (_matchMedia('(display-mode: standalone)').matches ||
        _standaloneIos == true ||
        _credi?.instalada == true) {
      return Instalacion.instalada;
    }
    if (_credi?.aviso != null) return Instalacion.conBoton;
    final agente = _agente;
    // El iPad se presenta como Mac; se distingue por la pantalla táctil.
    final esIos = RegExp('iPhone|iPad|iPod').hasMatch(agente) ||
        (agente.contains('Macintosh') && (_puntosTactiles ?? 0) > 1);
    if (esIos) return Instalacion.iphone;
    if (agente.contains('Android')) return Instalacion.menuDelNavegador;
    return Instalacion.instalada; // computadora sin botón: no se insiste
  } catch (_) {
    return Instalacion.instalada;
  }
}

Future<bool> instalarApp() async {
  try {
    return (await _instalar().toDart).toDart == 'accepted';
  } catch (_) {
    return false;
  }
}

void alCambiarInstalacion(void Function() alCambiar) {
  try {
    _escuchar('credi-instalacion', alCambiar.toJS);
  } catch (_) {}
}
