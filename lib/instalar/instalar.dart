// Poner la web en la pantalla de inicio del celular, como una app: en la
// web usa lo que guarda web/index.html; en el APK no hay nada que ofrecer.
export 'instalar_stub.dart' if (dart.library.js_interop) 'instalar_web.dart';
