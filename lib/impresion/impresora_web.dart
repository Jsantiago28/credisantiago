import 'dart:js_interop';

@JS('bluetoothDisponible')
external JSBoolean? _bluetoothDisponible();

@JS('imprimirBluetooth')
external JSPromise<JSString> _imprimirBluetooth(JSString base64);

@JS('imprimirRawBT')
external void _imprimirRawBT(JSString base64);

@JS('olvidarImpresora')
external void _olvidarImpresora();

@JS('papelImpresora')
external JSNumber? _papelImpresora();

@JS('guardarPapelImpresora')
external void _guardarPapelImpresora(JSNumber mm);

// Si web/impresora.js no cargó (versión vieja en caché), todo dice que no.

bool bluetoothDisponible() {
  try {
    return _bluetoothDisponible()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> imprimirBluetooth(String base64) async {
  try {
    await _imprimirBluetooth(base64.toJS).toDart;
  } catch (e) {
    throw Exception(_mensaje(e));
  }
}

void imprimirRawBT(String base64) => _imprimirRawBT(base64.toJS);

void olvidarImpresora() {
  try {
    _olvidarImpresora();
  } catch (_) {}
}

int papelImpresora() {
  try {
    return _papelImpresora()?.toDartInt ?? 58;
  } catch (_) {
    return 58;
  }
}

void guardarPapelImpresora(int mm) {
  try {
    _guardarPapelImpresora(mm.toJS);
  } catch (_) {}
}

/// El mensaje de un error de JavaScript, en palabras.
String _mensaje(Object e) {
  final texto = e.toString();
  if (texto.contains('User cancelled') || texto.contains('NotFoundError')) {
    return 'No elegiste impresora.';
  }
  if (texto.contains('NetworkError') || texto.contains('GATT')) {
    return 'No se pudo conectar. ¿La impresora está prendida y cerca?';
  }
  return texto.replaceFirst('Error: ', '');
}
