import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/fotos.dart';

void main() {
  test('ubicación nueva se deja igual', () {
    expect(rutaFoto('abc-123/cara_1727_55.jpg'), 'abc-123/cara_1727_55.jpg');
  });

  test('enlace público viejo → ubicación del archivo', () {
    expect(
      rutaFoto('https://twhwjttwpliudqkkgzsq.supabase.co/storage/v1/object/public/'
          'solicitudes-fotos/cara_1727000000.jpg'),
      'cara_1727000000.jpg',
    );
  });

  test('enlace firmado (con ?token=) → ubicación, sin el token', () {
    expect(
      rutaFoto('https://x.supabase.co/storage/v1/object/sign/solicitudes-fotos/'
          'abc/cedula_f_1.jpg?token=eyJhbGci'),
      'abc/cedula_f_1.jpg',
    );
  });

  test('sin foto o enlace de otro sitio → null', () {
    expect(rutaFoto(null), isNull);
    expect(rutaFoto(''), isNull);
    expect(rutaFoto('   '), isNull);
    expect(rutaFoto('https://otro-sitio.com/foto.jpg'), isNull);
  });

  test('las fotos nuevas van en la carpeta del prestamista', () {
    expect(
      rutaNuevaFoto(
          prestamistaId: 'abc-123', tipo: 'cara', ahora: DateTime.utc(2026, 9, 24), azar: 42),
      'abc-123/cara_${DateTime.utc(2026, 9, 24).millisecondsSinceEpoch}_42.jpg',
    );
  });
}
