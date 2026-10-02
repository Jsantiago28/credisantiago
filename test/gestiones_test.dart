import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/gestiones.dart';

/// Visita el 22/9 a las 10 am: promete pagar RD$2,000 el viernes 25/9.
Gestion promesa({double? monto = 2000, DateTime? fecha, DateTime? para}) => Gestion(
      prestamoId: 'p1',
      fecha: fecha ?? DateTime(2026, 9, 22, 10),
      tipo: 'visita',
      resultado: 'promesa',
      acuerdo: 'Paga el viernes 2,000 y el resto el lunes',
      promesaFecha: para ?? DateTime(2026, 9, 25),
      promesaMonto: monto,
    );

PagoRegistrado pago(DateTime f, double monto, {bool anulado = false}) =>
    PagoRegistrado(fecha: f, monto: monto, anulado: anulado);

void main() {
  group('Estado de una promesa', () {
    test('antes del día prometido y sin pagar: pendiente, sin aviso', () {
      final i = estadoPromesa(promesa(), [], DateTime(2026, 9, 24, 9));
      expect(i.estado, EstadoPromesa.pendiente);
      expect(i.esAviso, isFalse);
    });

    test('el día prometido sin pagar: vence hoy, con aviso', () {
      final i = estadoPromesa(promesa(), [], DateTime(2026, 9, 25, 18));
      expect(i.estado, EstadoPromesa.venceHoy);
      expect(i.esAviso, isTrue);
    });

    test('pasó el día sin pagar: no cumplida, con aviso', () {
      final i = estadoPromesa(promesa(), [], DateTime(2026, 9, 26, 8));
      expect(i.estado, EstadoPromesa.incumplida);
      expect(i.esAviso, isTrue);
    });

    test('pagó lo prometido (en uno o varios pagos): cumplida', () {
      final pagos = [pago(DateTime(2026, 9, 23, 9), 500), pago(DateTime(2026, 9, 25, 9), 1500)];
      final i = estadoPromesa(promesa(), pagos, DateTime(2026, 9, 26));
      expect(i.estado, EstadoPromesa.cumplida);
      expect(i.pagado, 2000);
      expect(i.esAviso, isFalse);
    });

    test('pagó solo una parte: sigue sin cumplir y dice cuánto dio', () {
      final i = estadoPromesa(promesa(), [pago(DateTime(2026, 9, 25, 9), 800)], DateTime(2026, 9, 25, 20));
      expect(i.estado, EstadoPromesa.venceHoy);
      expect(i.pagado, 800);
    });

    test('los pagos de antes de la promesa no cuentan', () {
      // Pagó 2,000 en la misma visita, antes de prometer el resto.
      final i = estadoPromesa(promesa(), [pago(DateTime(2026, 9, 22, 9, 55), 2000)], DateTime(2026, 9, 26));
      expect(i.estado, EstadoPromesa.incumplida);
      expect(i.pagado, 0);
    });

    test('un cobro anulado no cumple la promesa', () {
      final i = estadoPromesa(
          promesa(), [pago(DateTime(2026, 9, 24), 2000, anulado: true)], DateTime(2026, 9, 26));
      expect(i.estado, EstadoPromesa.incumplida);
    });

    test('sin monto prometido: cualquier pago la cumple', () {
      final i = estadoPromesa(promesa(monto: null), [pago(DateTime(2026, 9, 25), 300)], DateTime(2026, 9, 26));
      expect(i.estado, EstadoPromesa.cumplida);
    });

    test('pagó tarde pero completo: cuenta como cumplida', () {
      final i = estadoPromesa(promesa(), [pago(DateTime(2026, 9, 27), 2000)], DateTime(2026, 9, 28));
      expect(i.estado, EstadoPromesa.cumplida);
    });
  });

  group('Última promesa del préstamo', () {
    Gestion otra(DateTime f) => Gestion(prestamoId: 'p1', fecha: f, tipo: 'llamada', resultado: 'no_estaba');

    test('sin promesas: null', () {
      expect(ultimaPromesa([otra(DateTime(2026, 9, 22))], [], DateTime(2026, 9, 26)), isNull);
    });

    test('toma la promesa más reciente', () {
      final vieja = promesa(fecha: DateTime(2026, 9, 10), para: DateTime(2026, 9, 12));
      final nueva = promesa();
      final i = ultimaPromesa([nueva, vieja], [], DateTime(2026, 9, 24))!;
      expect(i.gestion, same(nueva));
      expect(i.estado, EstadoPromesa.pendiente);
    });

    test('no cumplida sin seguimiento: se avisa', () {
      final i = ultimaPromesa([promesa(), otra(DateTime(2026, 9, 24))], [], DateTime(2026, 9, 27))!;
      expect(i.estado, EstadoPromesa.incumplida);
      expect(i.esAviso, isTrue);
    });

    test('no cumplida pero ya se anotó otra gestión después del día: no se avisa más', () {
      final i = ultimaPromesa([promesa(), otra(DateTime(2026, 9, 26, 9))], [], DateTime(2026, 9, 27))!;
      expect(i.estado, EstadoPromesa.incumplida);
      expect(i.conSeguimiento, isTrue);
      expect(i.esAviso, isFalse);
    });

    test('lee la fila de Supabase', () {
      final g = Gestion.desdeFila({
        'id': 'g1',
        'prestamo_id': 'p1',
        'created_at': '2026-09-22T14:00:00Z',
        'tipo': 'llamada',
        'resultado': 'promesa',
        'acuerdo': 'el viernes',
        'promesa_fecha': '2026-09-25',
        'promesa_monto': 2000,
      });
      expect(g.esPromesa, isTrue);
      expect(g.promesaFecha, DateTime(2026, 9, 25));
      expect(g.promesaMonto, 2000);
      expect(g.nombreTipo, 'Llamada');
      expect(g.nombreResultado, 'Prometió pagar');
    });
  });
}
