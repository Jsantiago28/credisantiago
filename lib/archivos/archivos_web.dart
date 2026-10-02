// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Abre el selector de archivos. Null si no eligió ninguno.
Future<({String nombre, Uint8List bytes})?> elegirArchivo({required String tipos}) async {
  final entrada = html.FileUploadInputElement()..accept = tipos;
  final elegido = Completer<html.File?>();
  entrada.onChange.first.then((_) {
    final lista = entrada.files;
    elegido.complete(lista == null || lista.isEmpty ? null : lista.first);
  });
  entrada.click();
  final archivo = await elegido.future;
  if (archivo == null) return null;
  final lector = html.FileReader()..readAsArrayBuffer(archivo);
  await lector.onLoadEnd.first;
  final resultado = lector.result;
  final bytes = resultado is ByteBuffer
      ? resultado.asUint8List()
      : Uint8List.fromList(resultado as List<int>);
  return (nombre: archivo.name, bytes: bytes);
}

/// Descarga un archivo con ese nombre.
void descargarArchivo(String nombre, List<int> bytes) {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes]));
  html.AnchorElement(href: url)
    ..setAttribute('download', nombre)
    ..click();
  html.Url.revokeObjectUrl(url);
}
