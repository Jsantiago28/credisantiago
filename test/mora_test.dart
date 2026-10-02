import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';

/// 10,000 al 20% por 30 días diario, desembolsado el 1/9: 30 cuotas de 400.
/// La cuota #k vence el (1 + k)/9. Mora 5% diario (20 pesos por día sobre
/// una cuota completa) salvo que se indique otra cosa.
Map<String, dynamic> prestamo({double mora = 5, int gracia = 1}) {
  final plan = calcularPlan(
      monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: 'diario');
  return {
    'monto': 10000.0,
    'tasa_interes': 20.0,
    'cuota': plan.cuota,
    'cantidad_cuotas': plan.cantidadCuotas,
    'monto_total': plan.montoTotal,
    'frecuencia': 'diario',
    'fecha_desembolso': '2026-09-01',
    'estado': 'en_calle',
    'mora_diaria': mora,
    'dias_gracia': gracia,
  };
}

DateTime sep(int dia, [int hora = 10]) => DateTime(2026, 9, dia, hora);

/// Registra un cobro como lo hace la app: lo reparte con el estado de ese
/// día y lo agrega a la lista de pagos.
({double cuota, double mora}) cobrar(
    Map<String, dynamic> p, List<PagoRegistrado> pagos, DateTime cuando, double monto) {
  final reparto = repartirPago(estadoPrestamo(p, pagos, cuando), monto);
  pagos.add(PagoRegistrado(fecha: cuando, monto: monto, montoMora: reparto.mora));
  return reparto;
}

void main() {
  group('Días de gracia', () {
    final p = prestamo();

    test('el día que vence la cuota no hay mora', () {
      expect(estadoPrestamo(p, [], sep(2)).moraPendiente, 0);
    });

    test('1 día de gracia: vence el 2/9, el 3/9 no genera mora', () {
      expect(estadoPrestamo(p, [], sep(3)).moraPendiente, 0);
    });

    test('el 4/9 es el primer día con recargo: 5% de 400 = 20', () {
      final e = estadoPrestamo(p, [], sep(4));
      expect(e.cuotas[0].moraPendiente, 20);
      expect(e.cuotas[1].moraPendiente, 0); // #2 venció el 3/9, está en gracia
      expect(e.moraPendiente, 20);
    });

    test('el 5/9: #1 lleva 2 días (40), #2 lleva 1 día (20)', () {
      final e = estadoPrestamo(p, [], sep(5));
      expect(e.cuotas[0].moraPendiente, 40);
      expect(e.cuotas[1].moraPendiente, 20);
      expect(e.moraPendiente, 60);
      expect(e.balance, 12000 + 60);
    });

    test('sin gracia (0 días): el recargo empieza el día siguiente al vencimiento', () {
      final e = estadoPrestamo(prestamo(gracia: 0), [], sep(3));
      expect(e.cuotas[0].moraPendiente, 20);
      expect(e.moraPendiente, 20);
    });

    test('3 días de gracia: vence el 2/9, primer recargo el 6/9', () {
      final p3 = prestamo(gracia: 3);
      expect(estadoPrestamo(p3, [], sep(5)).cuotas[0].moraPendiente, 0);
      expect(estadoPrestamo(p3, [], sep(6)).cuotas[0].moraPendiente, 20);
    });
  });

  group('Cobro de cuota y mora al mismo tiempo', () {
    test('paga cuota + mora juntas: el reparto las detalla y queda al día', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final r = cobrar(p, pagos, sep(4), 420);
      expect(r.cuota, 400);
      expect(r.mora, 20);
      final e = estadoPrestamo(p, pagos, sep(4));
      expect(e.moraPendiente, 0);
      expect(e.cuotas[0].porCobrar, 0);
      expect(e.balance, 11600);
    });

    test('pago corto → abono a la cuota, la mora queda pendiente', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final r = cobrar(p, pagos, sep(4), 300);
      expect(r.cuota, 300);
      expect(r.mora, 0);
      final e = estadoPrestamo(p, pagos, sep(4));
      expect(e.cuotas[0].pendiente, 100);
      expect(e.cuotas[0].moraPendiente, 20);
    });

    test('después de un abono, la mora se calcula sobre lo que falta de la cuota', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      cobrar(p, pagos, sep(4), 300); // #1 queda con 100 pendientes
      final e = estadoPrestamo(p, pagos, sep(6));
      // #1: 4/9 sobre 400 (20) + 5/9 y 6/9 sobre 100 (5 + 5)
      expect(e.cuotas[0].moraGenerada, 30);
      // #2 (vence 3/9): 5/9 y 6/9 sobre 400
      expect(e.cuotas[1].moraGenerada, 40);
      // #3 (vence 4/9): 6/9
      expect(e.cuotas[2].moraGenerada, 20);
      expect(e.cuotas[3].moraGenerada, 0);
      expect(e.moraPendiente, 90);
    });

    test('con varias cuotas vencidas, cubre en orden: cuota #1, su mora, cuota #2...', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      // El 5/9 debe: #1 400 + 40 de mora, #2 400 + 20 de mora.
      final r = cobrar(p, pagos, sep(5), 500);
      expect(r.cuota, 460); // 400 de #1 + 60 abonados a #2
      expect(r.mora, 40); // la mora de #1
      final e = estadoPrestamo(p, pagos, sep(5));
      expect(e.cuotas[0].porCobrar, 0);
      expect(e.cuotas[1].pendiente, 340);
      expect(e.cuotas[1].moraPendiente, 20);
    });

    test('mora de una cuota ya cubierta se cobra antes que la cuota siguiente', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      cobrar(p, pagos, sep(4), 400); // cubre #1, queda debiendo 20 de mora
      final r = cobrar(p, pagos, sep(4, 15), 30);
      expect(r.mora, 20);
      expect(r.cuota, 10);
    });

    test('dos cobros el mismo día no cobran ese día de mora dos veces', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      cobrar(p, pagos, sep(4, 9), 100);
      cobrar(p, pagos, sep(4, 18), 100);
      final e = estadoPrestamo(p, pagos, sep(4, 20));
      expect(e.cuotas[0].moraGenerada, 20);
    });

    test('lo guardado en cada pago (monto_mora) cuadra con la mora cobrada', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      cobrar(p, pagos, sep(4), 300);
      cobrar(p, pagos, sep(6), 700);
      cobrar(p, pagos, sep(9), 1500);
      final e = estadoPrestamo(p, pagos, sep(9));
      final moraGuardada = pagos.fold<double>(0, (s, x) => s + x.montoMora);
      expect(e.moraCobrada, moraGuardada);
      expect(e.cobradoCuotas + e.moraCobrada, 2500);
      expect(e.balance, closeTo(12000 + e.moraGenerada - 2500, 0.001));
    });
  });

  group('Saldar con mora', () {
    test('pagar solo los 12,000 no salda si hay mora: queda debiendo la mora', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final r = cobrar(p, pagos, sep(5), 12000);
      expect(r.mora, 60);
      final e = estadoPrestamo(p, pagos, sep(5));
      expect(e.saldado, isFalse);
      expect(e.balance, 60);
      cobrar(p, pagos, sep(5, 12), 60);
      expect(estadoPrestamo(p, pagos, sep(5, 12)).saldado, isTrue);
    });

    test('cobrando lo que sugiere Cobrar cada día (al día), nunca hay mora', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      for (var dia = 2; dia <= 31; dia++) {
        final cuando = DateTime(2026, 9, 1).add(Duration(days: dia - 1, hours: 10));
        final e = estadoPrestamo(p, pagos, cuando);
        cobrar(p, pagos, cuando, e.cuotas.firstWhere((c) => c.porCobrar > 0).porCobrar);
      }
      final fin = estadoPrestamo(p, pagos, DateTime(2026, 10, 5));
      expect(fin.moraGenerada, 0);
      expect(fin.saldado, isTrue);
    });

    test('sin tope: la mora sigue creciendo después de la última cuota', () {
      final p = prestamo();
      // La #30 vence el 1/10 y sale de gracia el 2/10: desde el 3/10 todas
      // generan recargo.
      final antes = estadoPrestamo(p, [], DateTime(2026, 10, 11)).moraPendiente;
      final despues = estadoPrestamo(p, [], DateTime(2026, 10, 21)).moraPendiente;
      // 30 cuotas vencidas × 20 por día × 10 días más.
      expect(despues - antes, 30 * 20 * 10);
    });
  });

  group('Cobros del día (Inicio)', () {
    test('la cuota de hoy va en "por cobrar hoy", no en atrasados', () {
      final c = cobroDelDia(estadoPrestamo(prestamo(), [], sep(2)), sep(2));
      expect(c.venceHoy, 400);
      expect(c.atrasado, 0);
      expect(c.diasAtraso, 0);
    });

    test('el 5/9 sin pagos: atrasadas #1-#3 con su mora, vence hoy la #4', () {
      final e = estadoPrestamo(prestamo(), [], sep(5));
      final c = cobroDelDia(e, sep(5));
      // #1 400+40, #2 400+20, #3 400 (en gracia)
      expect(c.atrasado, 1260);
      expect(c.venceHoy, 400);
      expect(c.diasAtraso, 3); // desde la #1, que venció el 2/9
    });

    test('al día (pagó hasta la cuota de hoy): nada que cobrar hoy', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      cobrar(p, pagos, sep(2), 400);
      cobrar(p, pagos, sep(3), 400);
      final c = cobroDelDia(estadoPrestamo(p, pagos, sep(3, 18)), sep(3, 18));
      expect(c.atrasado, 0);
      expect(c.venceHoy, 0);
    });

    test('cuota cubierta pero con mora pendiente sigue como atrasada', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      cobrar(p, pagos, sep(4), 400); // cubre #1, deja 20 de mora
      final c = cobroDelDia(estadoPrestamo(p, pagos, sep(4, 18)), sep(4, 18));
      // mora de #1 (20) + #2 (400, vencida el 3/9, en gracia)
      expect(c.atrasado, 420);
      expect(c.venceHoy, 400); // #3 vence el 4/9
    });
  });

  group('Préstamos sin mora', () {
    test('préstamos de antes de la mora (sin mora_diaria) no generan recargo', () {
      final viejo = {...prestamo()}..remove('mora_diaria')..remove('dias_gracia');
      final e = estadoPrestamo(viejo, [], DateTime(2026, 12, 1));
      expect(e.moraPendiente, 0);
      expect(e.balance, 12000);
      expect(repartirPago(e, 500).mora, 0);
    });

    test('0% de mora: igual que antes, y el próximo pago coincide con el cálculo sin mora', () {
      final p = prestamo(mora: 0);
      final pagos = [PagoRegistrado(fecha: sep(3), monto: 1000)];
      final e = estadoPrestamo(p, pagos, sep(20));
      expect(e.moraPendiente, 0);
      expect(e.balance, 11000);
      expect(e.proximoPago, proximoPago(p, 1000));
      expect(e.proximoPago, DateTime(2026, 9, 4)); // #3, con 200 abonados
    });

    test('pagos viejos (sin monto_mora) cuentan todo como cuota', () {
      final pago = PagoRegistrado.desdeFila({'monto': 400, 'fecha_pago': '2026-09-02T14:00:00Z'});
      expect(pago.montoMora, 0);
      expect(pago.montoCuota, 400);
    });
  });
}
