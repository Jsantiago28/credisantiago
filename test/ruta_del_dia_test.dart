import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/ruta_del_dia.dart';
import 'package:prestamistas_rd/screens/recordar_manana_screen.dart';
import 'package:prestamistas_rd/widgets/progreso_ruta.dart';

/// 10,000 al 20% por 30 días diario desde el 1/9: 30 cuotas de 400; la #k
/// vence el (1 + k)/9. Sin mora.
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
    'mora_diaria': 0.0, // sin mora: así los pagos tardíos van completos a cuotas
    'dias_gracia': 1,
  };
}

PagoRegistrado pago(int dia, double monto, {bool anulado = false, bool importado = false}) =>
    PagoRegistrado(
        fecha: DateTime(2026, 9, dia, 9), monto: monto, anulado: anulado, importado: importado);

void main() {
  group('Progreso de la ruta de hoy', () {
    test('cuenta los que pagaron todo y suma lo cobrado y lo que falta', () {
      final p = progresoRuta([
        (aCobrar: 0, cobradoHoy: 400), // ya pagó lo de hoy
        (aCobrar: 500, cobradoHoy: 0), // falta
        (aCobrar: 200, cobradoHoy: 300), // dio una parte: no cuenta como cobrado
        (aCobrar: 0, cobradoHoy: 0), // no le toca hoy: no entra
      ]);
      expect(p.total, 3);
      expect(p.cobrados, 1);
      expect(p.montoCobrado, 700);
      expect(p.montoTotal, 1400);
      expect(p.fraccion, 0.5);
      expect(p.completo, isFalse);
      expect(textoProgresoRuta(p), 'Cobrados 1 de 3 · RD\$700 de RD\$1,400');
    });

    test('sin nada que cobrar hoy la barra queda en cero', () {
      final p = progresoRuta(const []);
      expect(p.total, 0);
      expect(p.fraccion, 0);
    });

    test('lo cobrado hoy no cuenta anulados ni importados', () {
      final hoy = DateTime(2026, 9, 9, 15);
      final pagos = [
        pago(9, 400),
        pago(9, 100, anulado: true),
        pago(9, 2000, importado: true),
        pago(8, 400),
      ];
      expect(cobradoEnDia(pagos, hoy), 400);
    });

    testWidgets('la barra muestra "Cobrados X de Y"', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: BarraProgresoRuta(ProgresoRuta(
              cobrados: 7, total: 15, montoCobrado: 2800, montoTotal: 6000)),
        ),
      ));
      expect(find.text('Cobrados 7 de 15 · RD\$2,800 de RD\$6,000'), findsOneWidget);
      final barra = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(barra.value, closeTo(2800 / 6000, 0.0001));
    });
  });

  group('Los de mañana', () {
    final hoy = DateTime(2026, 9, 9, 15);

    test('sale el que tiene cuota mañana, con su monto y la fecha', () {
      // Al día hasta hoy: pagó las cuotas del 2/9 al 9/9.
      final alDia = estadoPrestamo(prestamo(), [pago(9, 3200)], hoy);
      // Ya pagó también la de mañana por adelantado.
      final adelantado = estadoPrestamo(prestamo(), [pago(9, 3600)], hoy);
      final lista = pagosDeManana([('Ana', alDia), ('Luis', adelantado)], (x) => x.$2, hoy);
      expect(lista, hasLength(1));
      expect(lista.single.item.$1, 'Ana');
      expect(lista.single.monto, 400);
      expect(lista.single.fecha, DateTime(2026, 9, 10));
    });

    test('un préstamo que ya terminó no sale', () {
      final saldado = estadoPrestamo(prestamo(), [pago(9, 12000)], hoy);
      expect(pagosDeManana([saldado], (e) => e, hoy), isEmpty);
    });

    testWidgets('recorre uno por uno: abrir WhatsApp y Siguiente', (tester) async {
      final abiertos = <String>[];
      final fecha = DateTime(2026, 9, 10);
      await tester.pumpWidget(MaterialApp(
        home: RecordarMananaScreen(
          negocio: 'Préstamos Núñez',
          alAbrir: (tel, mensaje) => abiertos.add(mensaje),
          clientes: [
            (nombre: 'Ana Pérez', telefono: '809-555-1234', monto: 400, fecha: fecha),
            (nombre: 'Luis Gómez', telefono: null, monto: 1000, fecha: fecha),
          ],
        ),
      ));
      expect(find.text('1 de 2'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('RD\$400'), findsOneWidget);

      await tester.tap(find.text('Abrir WhatsApp'));
      await tester.pump();
      expect(abiertos.single, contains('mañana, jueves 10 sep'));
      expect(abiertos.single, contains('RD\$400'));

      await tester.tap(find.text('Siguiente'));
      await tester.pump();
      expect(find.text('2 de 2'), findsOneWidget);
      // Sin teléfono: no hay botón, se avisa.
      expect(find.text('Abrir WhatsApp'), findsNothing);
      expect(find.textContaining('no tiene un teléfono válido'), findsOneWidget);

      await tester.tap(find.text('Terminar'));
      await tester.pump();
      expect(find.textContaining('Abriste WhatsApp para 1 cliente de 2'), findsOneWidget);
    });
  });

  group('La semana', () {
    test('de lunes a domingo, aunque hoy sea miércoles o domingo', () {
      final dias = diasDeLaSemana(DateTime(2026, 9, 9, 15)); // miércoles
      expect(dias.first, DateTime(2026, 9, 7));
      expect(dias.last, DateTime(2026, 9, 13));
      expect(diasDeLaSemana(DateTime(2026, 9, 13)).first, DateTime(2026, 9, 7));
    });

    test('lo que vence cada día y lo que se cobró', () {
      final hoy = DateTime(2026, 9, 9, 15);
      final pagosA = [pago(4, 1200), pago(7, 400), pago(9, 400)];
      final pagosB = [pago(9, 800)];
      final cartera = [
        (estado: estadoPrestamo(prestamo(), pagosA, hoy), pagos: pagosA),
        (estado: estadoPrestamo(prestamo(), pagosB, hoy), pagos: pagosB),
      ];
      final semana = totalesDeLaSemana(cartera, (x) => x.estado, (x) => x.pagos, hoy);
      expect(semana, hasLength(7));

      final lunes = semana[0];
      expect(lunes.dia, DateTime(2026, 9, 7));
      expect(lunes.programado, 800); // 400 de cada uno
      expect(lunes.clientes, 2);
      expect(lunes.cobrado, 400);

      final martes = semana[1];
      expect(martes.cobrado, 0);

      final miercoles = semana[2];
      expect(miercoles.programado, 800);
      expect(miercoles.cobrado, 1200);
    });

    test('lo programado es la cuota completa; lo pendiente baja con lo cobrado', () {
      final hoy = DateTime(2026, 9, 9, 15);
      final e = estadoPrestamo(prestamo(), [pago(9, 3000)], hoy);
      final dia = DateTime(2026, 9, 9);
      expect(programadoDelDia(e, dia), 400);
      expect(pendienteDelDia(e, dia), 200); // 3000 cubre 7 cuotas y 200 de la 8.ª
    });
  });
}
