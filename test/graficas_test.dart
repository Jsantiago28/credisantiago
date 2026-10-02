import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/graficas.dart';

CobroGrafica cobro(DateTime f, double monto, {double mora = 0, bool anulado = false, String p = 'p1'}) =>
    CobroGrafica(prestamoId: p, fecha: f, monto: monto, montoMora: mora, anulado: anulado);

void main() {
  final hoy = DateTime(2026, 9, 24, 15);

  group('Cobrado por día', () {
    test('30 días, el más viejo primero, días vacíos en cero', () {
      final d = cobradoPorDia([], hoy);
      expect(d.length, 30);
      expect(d.first.dia, DateTime(2026, 8, 26));
      expect(d.last.dia, DateTime(2026, 9, 24));
      expect(d.every((x) => x.cuotas == 0 && x.mora == 0), isTrue);
    });

    test('separa cuota y mora, suma el día, ignora anulados y días fuera', () {
      final d = cobradoPorDia([
        cobro(DateTime(2026, 9, 24, 9), 440, mora: 40),
        cobro(DateTime(2026, 9, 24, 17), 400),
        cobro(DateTime(2026, 9, 24, 18), 4000, anulado: true),
        cobro(DateTime(2026, 7, 1), 999),
      ], hoy);
      expect(d.last.cuotas, 800);
      expect(d.last.mora, 40);
      expect(d.fold<double>(0, (s, x) => s + x.cuotas + x.mora), 840);
    });
  });

  group('Ganancia por mes', () {
    // 10,000 que se devuelven en 12,000: 1/6 de cada peso de cuota es interés.
    final prestamos = {
      'p1': {'monto': 10000, 'monto_total': 12000},
    };

    test('parte de interés de un préstamo', () {
      expect(parteInteres(prestamos['p1']!), closeTo(1 / 6, 1e-9));
      expect(parteInteres({'monto': 0}), 0);
    });

    test('6 meses; interés proporcional de las cuotas + la mora aparte', () {
      final g = gananciaPorMes([
        cobro(DateTime(2026, 9, 2), 1200),
        cobro(DateTime(2026, 9, 10), 650, mora: 50),
        cobro(DateTime(2026, 8, 15), 600),
        cobro(DateTime(2026, 9, 11), 6000, anulado: true),
      ], prestamos, hoy);
      expect(g.map((x) => x.mes), [
        DateTime(2026, 4), DateTime(2026, 5), DateTime(2026, 6),
        DateTime(2026, 7), DateTime(2026, 8), DateTime(2026, 9),
      ]);
      expect(g.last.interes, closeTo(1800 / 6, 1e-9)); // 300
      expect(g.last.mora, 50);
      expect(g[4].interes, closeTo(100, 1e-9));
    });

    test('meses que cruzan el año', () {
      expect(ultimosMeses(DateTime(2027, 2, 5), 3), [DateTime(2026, 12), DateTime(2027, 1), DateTime(2027, 2)]);
    });
  });

  group('Prestado contra cobrado', () {
    test('prestado por fecha de desembolso, sin cancelados; cobrado con mora, sin anulados', () {
      final r = prestadoVsCobrado([
        {'monto': 10000, 'estado': 'en_calle', 'fecha_desembolso': '2026-09-01'},
        {'monto': 5000, 'estado': 'pagado', 'fecha_desembolso': '2026-08-10'},
        {'monto': 7000, 'estado': 'cancelado', 'fecha_desembolso': '2026-09-03'},
        {'monto': 3000, 'estado': 'en_calle', 'fecha_desembolso': '2025-01-01'},
      ], [
        cobro(DateTime(2026, 9, 5), 440, mora: 40),
        cobro(DateTime(2026, 9, 6), 400, anulado: true),
      ], hoy);
      expect(r.last.prestado, 10000);
      expect(r.last.cobrado, 440);
      expect(r[4].prestado, 5000);
      expect(r.fold<double>(0, (s, x) => s + x.prestado), 15000);
    });
  });

  group('Cartera por estado', () {
    test('al día + vence hoy + atrasado = lo que hay en la calle', () {
      // 10,000 al 20% por 30 días diario desde el 1/9: cuotas de 400, la #k
      // vence el (1 + k)/9. Al 5/9 sin pagar: #1-#3 atrasadas, #4 vence hoy.
      final plan = calcularPlan(monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: 'diario');
      final p = {
        'monto': 10000.0,
        'cuota': plan.cuota,
        'cantidad_cuotas': plan.cantidadCuotas,
        'monto_total': plan.montoTotal,
        'frecuencia': 'diario',
        'fecha_desembolso': '2026-09-01',
        'mora_diaria': 5.0,
        'dias_gracia': 1,
      };
      final dia = DateTime(2026, 9, 5, 9);
      final e = estadoPrestamo(p, [], dia);
      final c = carteraPorEstado([e], dia);
      expect(c.atrasado, 1260); // 1,200 + 60 de mora
      expect(c.venceHoy, 400);
      expect(c.alDia + c.venceHoy + c.atrasado, closeTo(e.balance, 0.01));
    });
  });
}
