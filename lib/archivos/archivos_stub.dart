import 'dart:typed_data';

/// Abre el selector de archivos. Null si no eligió ninguno.
Future<({String nombre, Uint8List bytes})?> elegirArchivo({required String tipos}) async =>
    throw UnsupportedError('Elegir archivos solo funciona en la web por ahora');

/// Descarga un archivo con ese nombre.
void descargarArchivo(String nombre, List<int> bytes) =>
    throw UnsupportedError('Descargar archivos solo funciona en la web por ahora');
