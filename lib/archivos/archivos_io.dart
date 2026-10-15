import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Abre el selector de archivos del teléfono. Null si no eligió ninguno.
/// [tipos] como en la web: ".xlsx,.csv".
Future<({String nombre, Uint8List bytes})?> elegirArchivo({required String tipos}) async {
  final extensiones = [
    for (final t in tipos.split(',')) t.trim().replaceFirst('.', ''),
  ];
  final elegido = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensiones,
    withData: true,
  );
  final archivo = elegido?.files.single;
  final bytes = archivo?.bytes;
  if (archivo == null || bytes == null) return null;
  return (nombre: archivo.name, bytes: bytes);
}

/// En el teléfono no hay "Descargas" del navegador: el archivo se guarda en
/// la carpeta temporal de la app y se abre el menú de compartir (guardarlo
/// en Drive o en Archivos, mandarlo por WhatsApp, etc.).
void descargarArchivo(String nombre, List<int> bytes) {
  _compartir(nombre, bytes);
}

Future<void> _compartir(String nombre, List<int> bytes) async {
  final carpeta = await getTemporaryDirectory();
  final archivo = File('${carpeta.path}/$nombre');
  await archivo.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(archivo.path)], subject: nombre);
}
