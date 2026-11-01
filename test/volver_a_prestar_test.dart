import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/volver_a_prestar.dart';
import 'package:prestamistas_rd/logic/whatsapp.dart';
import 'package:prestamistas_rd/widgets/ui.dart';

void main() {
  group('Pagaron todo y no tienen préstamo', () {
    final clientes = [
      {'id': 'c1', 'nombre': 'Pedro'},
      {'id': 'c2', 'nombre': 'ana'},
      {'id': 'c3', 'nombre': 'Luis'},
      {'id': 'c4', 'nombre': 'Marta'},
      {'id': 'c5', 'nombre': 'José', 'archivado_en': '2026-10-01'},
      {'id': 'c6', 'nombre': 'Nuevo'},
      {'id': 'c7', 'nombre': 'Rosa'},
    ];
    final prestamos = [
      {'cliente_id': 'c1', 'estado': 'pagado'},
      {'cliente_id': 'c1', 'estado': 'pagado'},
      {'cliente_id': 'c2', 'estado': 'pagado'},
      {'cliente_id': 'c2', 'estado': 'cancelado'}, // el cancelado no cuenta
      {'cliente_id': 'c3', 'estado': 'pagado'},
      {'cliente_id': 'c3', 'estado': 'en_calle'}, // ya tiene otro en la calle
      {'cliente_id': 'c4', 'estado': 'pagado'},
      {'cliente_id': 'c4', 'estado': 'borrador'}, // ya se le está preparando otro
      {'cliente_id': 'c5', 'estado': 'pagado'}, // eliminado de la lista
      {'cliente_id': 'c7', 'estado': 'cancelado'}, // nunca pagó uno
    ];

    test('solo los que tienen todo pagado y nada vivo, por nombre', () {
      final lista = clientesParaVolverAPrestar(clientes, prestamos);
      expect([for (final c in lista) c['nombre']], ['ana', 'Pedro']);
    });

    test('el mensaje invita a pedir otro con el link', () {
      final m = mensajeVolverAPrestar(
          nombreCliente: 'Pedro Martínez', link: 'https://credisantiago.pages.dev/s/nunez');
      expect(
          m,
          'Hola Pedro, usted cumplió con su préstamo. Si necesita otro, aquí estoy. '
          'Puede pedirlo aquí: https://credisantiago.pages.dev/s/nunez');
    });

    test('sin link, el mensaje sale igual', () {
      expect(mensajeVolverAPrestar(nombreCliente: 'Ana', link: ''),
          'Hola Ana, usted cumplió con su préstamo. Si necesita otro, aquí estoy.');
    });
  });

  group('Resumen del mes para WhatsApp', () {
    test('trae prestado, cobrado, ganancia, mora, en la calle y atrasados', () {
      final m = mensajeResumenMes(
        negocio: 'Préstamos Núñez',
        mes: DateTime(2026, 11),
        prestado: 150000,
        cobrado: 98500.5,
        ganancia: 21000,
        moraCobrada: 1500,
        enLaCalle: 320000,
        atrasados: 1,
      );
      expect(
          m,
          'Resumen de Préstamos Núñez · noviembre 2026\n'
          'Prestado: RD\$150,000\n'
          'Cobrado: RD\$98,500.50\n'
          'Ganancia: RD\$21,000\n'
          'Mora cobrada: RD\$1,500\n'
          'En la calle: RD\$320,000\n'
          'Atrasados: 1 cliente');
    });

    test('varios atrasados en plural', () {
      final m = mensajeResumenMes(
          negocio: '',
          mes: DateTime(2026, 1),
          prestado: 0,
          cobrado: 0,
          ganancia: 0,
          moraCobrada: 0,
          enLaCalle: 0,
          atrasados: 3);
      expect(m, startsWith('Resumen · enero 2026'));
      expect(m, endsWith('Atrasados: 3 clientes'));
    });

    test('compartir abre WhatsApp sin número', () {
      final uri = enlaceCompartirWhatsApp('Hola & chao');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/');
      expect(uri.queryParameters['text'], 'Hola & chao');
    });
  });

  test('recordatorio de mañana con monto y fecha', () {
    expect(
        mensajeRecordatorioManana(
            nombreCliente: 'José Pérez',
            negocio: 'Préstamos Núñez',
            monto: 1500,
            fecha: DateTime(2026, 11, 2)),
        'Hola José, le saluda Préstamos Núñez. Le recordamos que mañana, lunes 2 nov, '
        'le toca su cuota de RD\$1,500. ¡Gracias!');
  });

  group('plural', () {
    test('uno en singular, los demás en plural', () {
      expect(plural(1, 'cobro', 'cobros'), '1 cobro');
      expect(plural(7, 'cobro', 'cobros'), '7 cobros');
      expect(plural(0, 'día', 'días'), '0 días');
    });
  });
}
