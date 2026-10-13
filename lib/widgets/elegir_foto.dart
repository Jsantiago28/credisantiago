import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Máximo que se acepta por foto (ya achicada). Las de iPhone recientes
/// pueden pesar más de 5 MB aun convertidas.
const maxBytesFoto = 10 * 1024 * 1024;

/// Ancho y calidad con que se achican las fotos antes de subirlas. Con
/// 1280 px la cédula se sigue leyendo bien y cada foto pesa como la mitad
/// que con 1600 px y 80% (así rinde más el 1 GB gratis de Supabase).
const anchoFoto = 1280.0;
const calidadFoto = 70;

/// Pide UNA foto (cámara o galería) y devuelve sus bytes, o null si el
/// usuario cancela o algo falla (en ese caso avisa con un mensaje).
///
/// En la web (iPhone/Android desde el navegador) se abre directo el menú del
/// teléfono ("Tomar foto / Fototeca / Elegir archivo"). Tiene que ser en el
/// mismo toque: Safari en iPhone no abre el selector si antes se mostró un
/// menú propio de la app. En Android/iOS nativos sí se muestra el menú.
///
/// [maxWidth] achica la foto a ese ancho (un logo no necesita más de 400).
Future<Uint8List?> elegirFoto(BuildContext context, {double maxWidth = anchoFoto}) async {
  final mensajero = ScaffoldMessenger.of(context);
  try {
    final ImageSource? origen =
        kIsWeb ? ImageSource.gallery : await _preguntarOrigen(context);
    if (origen == null) return null;
    final foto = await ImagePicker().pickImage(
      source: origen,
      imageQuality: calidadFoto,
      maxWidth: maxWidth,
    );
    if (foto == null) return null;
    final bytes = await foto.readAsBytes();
    if (bytes.length > maxBytesFoto) {
      mensajero.showSnackBar(const SnackBar(
          content: Text('La foto pesa más de 10MB. Toma otra o elige una más liviana.')));
      return null;
    }
    return bytes;
  } catch (e) {
    // ignore: avoid_print
    print('ERROR REAL ELEGIR FOTO: $e');
    mensajero.showSnackBar(SnackBar(content: Text('No se pudo cargar la foto: $e')));
    return null;
  }
}

/// Varias fotos a la vez (evidencias). Mismo criterio que [elegirFoto].
Future<List<Uint8List>> elegirVariasFotos(BuildContext context, {required int maximo}) async {
  final mensajero = ScaffoldMessenger.of(context);
  try {
    final ImageSource? origen =
        kIsWeb ? ImageSource.gallery : await _preguntarOrigen(context);
    if (origen == null) return const [];
    final picker = ImagePicker();
    final elegidas = origen == ImageSource.gallery
        ? await picker.pickMultiImage(imageQuality: calidadFoto, maxWidth: anchoFoto, limit: maximo)
        : [
            if (await picker.pickImage(source: origen, imageQuality: calidadFoto, maxWidth: anchoFoto)
                case final foto?)
              foto,
          ];
    final bytes = <Uint8List>[];
    var pesadas = 0;
    for (final f in elegidas.take(maximo)) {
      final b = await f.readAsBytes();
      if (b.length > maxBytesFoto) {
        pesadas++;
      } else {
        bytes.add(b);
      }
    }
    if (pesadas > 0) {
      mensajero.showSnackBar(SnackBar(
          content: Text('$pesadas foto(s) pesan más de 10MB y no se agregaron.')));
    }
    return bytes;
  } catch (e) {
    // ignore: avoid_print
    print('ERROR REAL ELEGIR FOTOS: $e');
    mensajero.showSnackBar(SnackBar(content: Text('No se pudieron cargar las fotos: $e')));
    return const [];
  }
}

Future<ImageSource?> _preguntarOrigen(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}
