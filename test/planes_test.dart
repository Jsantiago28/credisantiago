import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/planes.dart';

const planes = [
  {'id': 'gratis', 'nombre': 'Gratis', 'precio_mensual': 0, 'max_clientes': 10},
  {'id': 'basico', 'nombre': 'Básico', 'precio_mensual': 390, 'max_clientes': 60},
  {'id': 'pro', 'nombre': 'Pro', 'precio_mensual': 690, 'max_clientes': 200},
  {'id': 'premium', 'nombre': 'Premium', 'precio_mensual': 1190, 'max_clientes': null},
];

final hoy = DateTime(2026, 9, 23, 15);

EstadoPlan estado(Map<String, dynamic> perfil, int clientes) =>
    estadoPlan(perfil: perfil, planes: planes, clientes: clientes, hoy: hoy);

void main() {
  test('gratis: 10 clientes; el onceavo no se puede', () {
    final e4 = estado({'plan': 'gratis', 'aprobado': true}, 9);
    expect(e4.limite, 10);
    expect(e4.puedeAgregar, isTrue);
    expect(e4.quedan, 1);
    expect(estado({'plan': 'gratis', 'aprobado': true}, 10).puedeAgregar, isFalse);
  });

  test('plan pagado vigente usa su límite', () {
    final e = estado({'plan': 'pro', 'plan_vence': '2026-10-23', 'aprobado': true}, 40);
    expect(e.planId, 'pro');
    expect(e.limite, 200);
    expect(e.puedeAgregar, isTrue);
    expect(e.vencido, isFalse);
    expect(e.diasParaVencer(hoy), 30);
  });

  test('al vencer quedan 7 días de gracia; después vuelve a Gratis', () {
    // hoy es 23-09-2026.
    expect(planEfectivo({'plan': 'pro', 'plan_vence': '2026-09-23'}, hoy), 'pro');
    final enGracia = estado({'plan': 'pro', 'plan_vence': '2026-09-22', 'aprobado': true}, 40);
    expect(enGracia.planId, 'pro');
    expect(enGracia.vencido, isFalse);
    expect(enGracia.diasDeGraciaQuedan(hoy), 7);
    final ultimoDia = estado({'plan': 'pro', 'plan_vence': '2026-09-16', 'aprobado': true}, 40);
    expect(ultimoDia.planId, 'pro');
    expect(ultimoDia.diasDeGraciaQuedan(hoy), 1);
    final e = estado({'plan': 'pro', 'plan_vence': '2026-09-15', 'aprobado': true}, 40);
    expect(e.planId, 'gratis');
    expect(e.vencido, isTrue);
    expect(e.limite, 10);
    expect(e.puedeAgregar, isFalse); // tiene 40, no puede agregar hasta renovar
  });

  test('premium: sin límite', () {
    final e = estado({'plan': 'premium', 'plan_vence': '2026-12-01', 'aprobado': true}, 5000);
    expect(e.limite, isNull);
    expect(e.puedeAgregar, isTrue);
    expect(e.quedan, isNull);
  });

  test('cuenta sin aprobar: no puede agregar clientes', () {
    final e = estado({'plan': 'gratis', 'aprobado': false}, 0);
    expect(e.limite, 0);
    expect(e.puedeAgregar, isFalse);
  });

  test('antes de la migración (sin "aprobado") se toma como aprobado', () {
    expect(estado({'plan': 'gratis'}, 2).limite, 10);
    expect(estado(<String, dynamic>{}, 2).planId, 'gratis');
  });

  test('renovar suma desde el vencimiento si no ha llegado, si no desde hoy', () {
    expect(nuevaFechaVence(DateTime(2026, 10, 5), hoy), DateTime(2026, 11, 5));
    expect(nuevaFechaVence(DateTime(2026, 9, 1), hoy), DateTime(2026, 10, 23));
    expect(nuevaFechaVence(null, hoy), DateTime(2026, 10, 23));
    expect(nuevaFechaVence(DateTime(2027, 1, 31), hoy), DateTime(2027, 2, 28));
    expect(nuevaFechaVence(null, hoy, meses: 3), DateTime(2026, 12, 23));
  });


  group('Pagar 1, 3 o 12 meses', () {
    const d = DescuentosPlan();

    test('1 mes: precio normal; 3 meses: 10% menos redondeado a RD\$10; 12: dos meses gratis', () {
      expect(precioPeriodo(790, 1, d), 790);
      expect(precioPeriodo(790, 3, d), 2130); // 2,133 → 2,130
      expect(precioPeriodo(1490, 3, d), 4020); // 4,023 → 4,020
      expect(precioPeriodo(2490, 3, d), 6720);
      expect(precioPeriodo(790, 12, d), 7900);
      // Precios nuevos (29-09-2026)
      expect(precioPeriodo(390, 12, d), 3900); // Básico anual
      expect(precioPeriodo(690, 3, d), 1860); // 1,863 → 1,860
      expect(precioPeriodo(1190, 12, d), 11900);
      expect(precioPeriodo(1490, 12, d), 14900);
    });

    test('sin descuento se cobra completo', () {
      const sin = DescuentosPlan(descuento3: 0, mesesGratis12: 0);
      expect(precioPeriodo(790, 3, sin), 2370);
      expect(precioPeriodo(790, 12, sin), 9480);
      expect(sin.etiqueta(3), isNull);
    });

    test('descuentos desde los ajustes y sus etiquetas', () {
      final a = DescuentosPlan.desde({'descuento_3_meses': 15, 'meses_gratis_12': 1});
      expect(a.etiqueta(3), '15% menos');
      expect(a.etiqueta(12), '1 mes gratis');
      expect(a.etiqueta(1), isNull);
      expect(DescuentosPlan.desde(null).etiqueta(12), '2 meses gratis');
    });

    test('mensaje para pedir el plan (la cuenta la manda el admin)', () {
      expect(
        mensajePedidoPlan(prestamista: 'Soluciones Méndez', plan: 'Pro', meses: 12, precio: 14900),
        'Hola, soy Soluciones Méndez. Quiero el plan Pro por 12 meses (RD\$14,900). '
        '¿A qué cuenta te deposito?',
      );
      expect(nombrePeriodoPlan(1), '1 mes');
    });

    test('con las cuentas publicadas, el mensaje manda el comprobante', () {
      expect(
        mensajePedidoPlan(
            prestamista: 'Soluciones Méndez', plan: 'Pro', meses: 3, precio: 1860, yaPago: true),
        'Hola, soy Soluciones Méndez. Elegí el plan Pro por 3 meses (RD\$1,860) y ya pagué. '
        'Te envío el comprobante para que me lo actives.',
      );
    });
  });

  group('Vencimientos', () {
    test('recordatorio según los días que faltan', () {
      String m(DateTime v) => mensajeRecordatorioPlan(
          prestamista: 'Juan Pérez', plan: 'Pro', vence: v, hoy: hoy);
      expect(m(DateTime(2026, 9, 28)), contains('vence en 5 días'));
      expect(m(DateTime(2026, 9, 24)), contains('vence mañana'));
      expect(m(DateTime(2026, 9, 23)), contains('vence hoy'));
      expect(m(DateTime(2026, 9, 22)), contains('venció hace 1 día.'));
      expect(m(DateTime(2026, 9, 20)), startsWith('Hola Juan, tu plan Pro'));
    });

    test('vencen pronto: próximos 7 días y vencidos hasta 30, el más urgente primero', () {
      final lista = vencenPronto([
        {'nombre': 'A', 'plan': 'pro', 'plan_vence': '2026-09-28'},
        {'nombre': 'B', 'plan': 'basico', 'plan_vence': '2026-09-20'},
        {'nombre': 'C', 'plan': 'pro', 'plan_vence': '2026-12-01'}, // falta mucho
        {'nombre': 'D', 'plan': 'pro', 'plan_vence': '2026-07-01'}, // vencido hace mucho
        {'nombre': 'E', 'plan': 'gratis', 'plan_vence': null},
        {'nombre': 'F', 'plan': 'premium', 'plan_vence': '2026-09-24', 'es_admin': true},
      ], hoy);
      expect(lista.map((p) => p['nombre']), ['B', 'A']);
    });
  });
}
