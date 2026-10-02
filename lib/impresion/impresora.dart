// Impresora de tickets: en la web usa web/impresora.js; fuera de la web
// (pruebas, y el APK hasta que se haga su versión) dice que no hay.
export 'impresora_stub.dart' if (dart.library.js_interop) 'impresora_web.dart';
