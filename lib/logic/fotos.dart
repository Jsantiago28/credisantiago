/// Bucket privado donde van las fotos de cédula y evidencias de ingresos.
const bucketFotos = 'solicitudes-fotos';

/// Ubicación del archivo dentro del bucket a partir de lo que esté guardado
/// en la base de datos: la ubicación misma ("<prestamista>/archivo.jpg") o
/// un enlace viejo, de cuando el bucket era público. Null si no hay foto.
String? rutaFoto(String? guardado) {
  if (guardado == null || guardado.trim().isEmpty) return null;
  final valor = guardado.trim();
  final enlace = RegExp('/object/(?:public|sign)/$bucketFotos/([^?]+)').firstMatch(valor);
  if (enlace != null) return Uri.decodeComponent(enlace.group(1)!);
  if (valor.startsWith('http')) return null; // enlace de otro lado: no es nuestro
  return valor;
}

/// Carpeta + nombre para una foto nueva. La carpeta es la del prestamista
/// (así solo él puede verla) y el nombre lleva hora y un número al azar
/// para que dos fotos subidas a la vez no choquen.
String rutaNuevaFoto({
  required String prestamistaId,
  required String tipo,
  required DateTime ahora,
  required int azar,
  String extension = 'jpg',
}) =>
    '$prestamistaId/${tipo}_${ahora.millisecondsSinceEpoch}_$azar.$extension';

/// Si lo guardado es un PDF (si no, es una foto).
bool esPdf(String guardado) => guardado.toLowerCase().endsWith('.pdf');
