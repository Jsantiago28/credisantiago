// Elegir un archivo del teléfono o la computadora y descargar uno. En la web
// usa el navegador; en el APK, el selector de archivos y el menú de compartir.
export 'archivos_stub.dart'
    if (dart.library.js_interop) 'archivos_web.dart'
    if (dart.library.io) 'archivos_io.dart';
