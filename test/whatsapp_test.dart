import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/whatsapp.dart';

/// 10,000 al 20% por 30 días diario desde el 1/9, mora 5% con 1 día de
/// gracia: 30 cuotas de 400; la #k vence el (1 + k)/9.
Map<String, dynamic> prestamo() {
  final plan = calcularPlan(
      monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: 'diario');
  return {
    'monto': 10000.0,
    'cuota': plan.cuota,
    'cantidad_cuotas': plan.cantidadCuotas,
    'monto_total': plan.montoTotal,
    'frecuencia': 'diario',
    'fecha_desembolso': '2026-09-01',
    'mora_diaria': 5.0,
    'dias_gracia': 1,
  };
}

String mensaje(List<PagoRegistrado> pagos, DateTime hoy) => mensajeCobro(
      nombreCliente: 'José Martínez Peña',
      negocio: 'Préstamos Núñez',
      estado: estadoPrestamo(prestamo(), pagos, hoy),
      hoy: hoy,
    );

void main() {
  group('Número para WhatsApp', () {
    test('números de RD de 10 dígitos llevan el 1 delante', () {
      expect(telefonoWhatsApp('809-555-1234'), '18095551234');
      expect(telefonoWhatsApp('(829) 555 1234'), '18295551234');
      expect(telefonoWhatsApp('8495551234'), '18495551234');
    });

    test('si ya trae el código de país se deja igual', () {
      expect(telefonoWhatsApp('+1 809 555 1234'), '18095551234');
      expect(telefonoWhatsApp('18095551234'), '18095551234');
    });

    test('vacío o muy corto no es válido', () {
      expect(telefonoWhatsApp(null), isNull);
      expect(telefonoWhatsApp(''), isNull);
      expect(telefonoWhatsApp('555-1234'), isNull);
    });

    test('el enlace abre wa.me con el mensaje codificado', () {
      final uri = enlaceWhatsApp('809-555-1234', 'Hola José, RD\$400 & gracias')!;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/18095551234');
      expect(uri.queryParameters['text'], 'Hola José, RD\$400 & gracias');
    });
  });

  group('Mensaje de cobro', () {
    test('cuota que vence hoy', () {
      expect(
        mensaje([], DateTime(2026, 9, 2, 9)),
        'Hola José, le saluda Préstamos Núñez. '
        'Le recordamos que hoy vence su cuota de RD\$400. ¡Gracias!',
      );
    });

    test('atrasado: total pendiente con mora y días de atraso', () {
      // El 5/9: #1-#3 vencidas (400+40, 400+20, 400) + #4 vence hoy (400).
      final m = mensaje([], DateTime(2026, 9, 5, 9));
      expect(m, contains('Tiene RD\$1,660 pendiente'));
      expect(m, contains('(incluye RD\$60 de mora)'));
      expect(m, contains('con 3 días de atraso'));
    });

    test('1 día de atraso va en singular', () {
      expect(mensaje([], DateTime(2026, 9, 3, 9)), contains('con 1 día de atraso'));
    });

    test('al día: recuerda la próxima cuota con su fecha', () {
      final pagos = [PagoRegistrado(fecha: DateTime(2026, 9, 2, 9), monto: 800)];
      expect(
        mensaje(pagos, DateTime(2026, 9, 2, 18)),
        'Hola José, le saluda Préstamos Núñez. '
        'Le recordamos que su próxima cuota de RD\$400 vence el 4 sep. ¡Gracias!',
      );
    });

    test('préstamo viejo sin cronograma que debe: recuerda el balance, no dice saldado', () {
      // Como los de prueba de las primeras fases: sin cantidad_cuotas ni fecha.
      final viejo = {'monto': 5000, 'tasa_interes': 20, 'cuota': 600};
      final m = mensajeCobro(
        nombreCliente: 'Aquiles',
        negocio: 'Préstamos Núñez',
        estado: estadoPrestamo(viejo, [], DateTime(2026, 9, 23)),
        hoy: DateTime(2026, 9, 23),
      );
      expect(m, contains('tiene un balance pendiente de RD\$6,000'));
      expect(m, isNot(contains('saldado')));
    });

    test('saldado: agradece', () {
      final pagos = [PagoRegistrado(fecha: DateTime(2026, 9, 2, 9), monto: 12000)];
      expect(mensaje(pagos, DateTime(2026, 9, 3)), contains('Su préstamo está saldado'));
      // Y lo invita a volver.
      expect(mensaje(pagos, DateTime(2026, 9, 3)), contains('necesita otro préstamo'));
    });
  });
}
