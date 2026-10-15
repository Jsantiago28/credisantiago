// Impresora de tickets: en la web usa web/impresora.js (Bluetooth directo o
// RawBT); en el APK, la app RawBT.
export 'impresora_stub.dart'
    if (dart.library.js_interop) 'impresora_web.dart'
    if (dart.library.io) 'impresora_io.dart';
