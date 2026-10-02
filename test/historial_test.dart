import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/historial.dart';

CambioCliente cambio(String campo, String? antes, String? despues, DateTime f) =>
    CambioCliente(campo: campo, antes: antes, despues: despues, fecha: f);

void main() {
  final guardado1 = DateTime(2026, 9, 20, 10);
  final guardado2 = DateTime(2026, 9, 24, 16, 30);

  group('Valores legibles', () {
    test('vacío', () {
      expect(valorLegible('telefono', null), '(vacío)');
      expect(valorLegible('direccion', '  '), '(vacío)');
    });

    test('monto en pesos', () {
      expect(valorLegible('ingreso_mensual', '25000'), 'RD\$25,000');
      expect(valorLegible('ingreso_mensual', '25000.50'), 'RD\$25,000.5');
    });

    test('vivienda con su nombre', () {
      expect(valorLegible('tipo_vivienda', 'propia'), 'Casa propia');
      expect(valorLegible('tipo_vivienda', 'alquilada'), 'Alquilada');
    });

    test('evidencias: cuántas fotos', () {
      expect(valorLegible('evidencias_ingresos', '["a/1.jpg", "a/2.jpg"]'), '2 fotos');
      expect(valorLegible('evidencias_ingresos', '["a/1.jpg"]'), '1 foto');
      expect(valorLegible('evidencias_ingresos', '[]'), '(vacío)');
    });

    test('texto normal se deja igual', () {
      expect(valorLegible('telefono', '809-555-1234'), '809-555-1234');
    });

    test('lee la fila de Supabase', () {
      final c = CambioCliente.desdeFila({
        'campo': 'foto_cara_url',
        'antes': 'p1/cara_1.jpg',
        'despues': 'p1/cara_2.jpg',
        'created_at': '2026-09-24T20:30:00Z',
      });
      expect(c.esFoto, isTrue);
      expect(c.nombre, 'Foto de la cara');
    });
  });

  group('Agrupar cambios', () {
    test('un grupo por cada "Guardar", el más reciente primero', () {
      final grupos = agruparCambios([
        cambio('telefono', '809-111-1111', '809-222-2222', guardado1),
        cambio('nombre', 'Jose Perez', 'José Pérez', guardado2),
        cambio('direccion', 'Calle 1', 'Calle 2', guardado2),
      ]);
      expect(grupos.length, 2);
      expect(grupos.first.fecha, guardado2);
      expect(grupos.first.cambios.map((c) => c.campo), ['nombre', 'direccion']);
      expect(grupos.last.cambios.single.campo, 'telefono');
    });

    test('se ordenan como en la ficha', () {
      final grupos = agruparCambios([
        cambio('ref1_nombre', null, 'Ana', guardado1),
        cambio('cedula', '1', '2', guardado1),
        cambio('nombre', 'a', 'b', guardado1),
      ]);
      expect(grupos.single.cambios.map((c) => c.campo), ['nombre', 'cedula', 'ref1_nombre']);
    });

    test('latitud y longitud salen juntas como "Ubicación"', () {
      final primera = agruparCambios([
        cambio('lat', null, '18.47', guardado1),
        cambio('lng', null, '-69.9', guardado1),
      ]).single.cambios.single;
      expect(primera.nombre, 'Ubicación');
      expect(primera.antesTexto, '(vacío)');
      expect(primera.despuesTexto, 'Marcada');

      final corregida = agruparCambios([
        cambio('lat', '18.47', '18.48', guardado2),
        cambio('lng', '-69.9', '-69.8', guardado2),
      ]).single.cambios.single;
      expect(corregida.despuesTexto, 'Corregida');
    });
  });
}
