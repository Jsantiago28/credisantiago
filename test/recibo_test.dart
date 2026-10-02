import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/recibos/recibo_pdf.dart';

/// 10,000 al 20% por 30 días diario desde el 1/9: 30 cuotas de 400, mora
/// 5% diario con 1 día de gracia. La cuota #k vence el (1 + k)/9.
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

/// Cobra como la app: reparte con el estado de ese momento y numera.
PagoRegistrado cobrar(
    Map<String, dynamic> p, List<PagoRegistrado> pagos, DateTime cuando, double monto) {
  final r = repartirPago(estadoPrestamo(p, pagos, cuando), monto);
  final pago = PagoRegistrado(
      id: 'p${pagos.length + 1}',
      numeroRecibo: pagos.length + 1,
      fecha: cuando,
      monto: monto,
      montoMora: r.mora);
  pagos.add(pago);
  return pago;
}

DateTime sep(int dia, [int hora = 10]) => DateTime(2026, 9, dia, hora);

void main() {
  group('Datos del recibo', () {
    test('cuota + mora: detalla el reparto, lo que cubre y el próximo pago', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      // El 5/9 debe #1 (400 + 40 mora) y #2 (400 + 20 mora). Paga 500.
      final pago = cobrar(p, pagos, sep(5), 500);
      final r = datosRecibo(p, pagos, pago);

      expect(r.numero, 1);
      expect(r.monto, 500);
      expect(r.aCuota, 460);
      expect(r.aMora, 40);
      expect(r.cubre, ['Cuota #1 (2/9/2026)', 'Abono a la cuota #2: RD\$ 60']);
      // Debía 12,000 + 60 de mora; pagó 500.
      expect(r.balanceDespues, 11560);
      expect(r.moraPendienteDespues, 20);
      // #2 sigue vencida: faltan 340 + 20 de mora.
      expect(r.proximoPagoFecha, DateTime(2026, 9, 3));
      expect(r.proximoPagoMonto, 360);
      expect(r.saldado, isFalse);
    });

    test('un recibo reenviado días después dice lo mismo que el día del cobro', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final primero = cobrar(p, pagos, sep(2), 400);
      final alCobrar = datosRecibo(p, pagos, primero);
      // Siguen más cobros (y pasa el tiempo): el recibo #1 no cambia.
      cobrar(p, pagos, sep(6), 1000);
      cobrar(p, pagos, sep(9), 800);
      final reenviado = datosRecibo(p, pagos, primero);

      expect(reenviado.cubre, alCobrar.cubre);
      expect(reenviado.balanceDespues, alCobrar.balanceDespues);
      expect(reenviado.balanceDespues, 11600);
      expect(reenviado.proximoPagoFecha, DateTime(2026, 9, 3));
      expect(reenviado.proximoPagoMonto, 400);
    });

    test('el último pago dice PRÉSTAMO SALDADO y no tiene próximo pago', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final pago = cobrar(p, pagos, sep(2), 12000);
      final r = datosRecibo(p, pagos, pago);
      expect(r.saldado, isTrue);
      expect(r.balanceDespues, 0);
      expect(r.proximoPagoFecha, isNull);
      expect(r.cubre.length, 30);
    });

    test('dos cobros el mismo día se ordenan por número de recibo', () {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final a = cobrar(p, pagos, sep(2, 9), 400);
      final b = cobrar(p, pagos, sep(2, 9), 400); // misma hora
      expect(datosRecibo(p, pagos, a).cubre, ['Cuota #1 (2/9/2026)']);
      expect(datosRecibo(p, pagos, b).cubre, ['Cuota #2 (3/9/2026)']);
    });
  });

  test('mora cobrada del mes: solo cobros de este mes', () {
    final pagos = [
      PagoRegistrado(fecha: DateTime(2026, 8, 30), monto: 460, montoMora: 60),
      PagoRegistrado(fecha: DateTime(2026, 9, 4), monto: 420, montoMora: 20),
      PagoRegistrado(fecha: DateTime(2026, 9, 20), monto: 400),
    ];
    expect(moraCobradaEnMes(pagos, DateTime(2026, 9, 22)), 20);
  });

  group('PDF', () {
    test('número de recibo con 6 dígitos', () {
      expect(numeroReciboTexto(12), '#000012');
      expect(numeroReciboTexto(null), 'S/N');
    });

    test('genera un PDF válido con acentos y montos grandes', () async {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      cobrar(p, pagos, sep(2), 400);
      final pago = cobrar(p, pagos, sep(5), 500);
      final bytes = await reciboPdf(
        r: datosRecibo(p, pagos, pago),
        negocio: const NegocioRecibo(nombre: 'Préstamos Núñez', telefono: '809-555-1234'),
        cliente: 'José Martínez Peña',
        cedula: '001-1234567-8',
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      // Muestra para revisarla a ojo.
      File('${Directory.systemTemp.path}/recibo_muestra.pdf').writeAsBytesSync(bytes);
    });

    test('con logo, dirección y mensaje propio (y un emoji que no rompe el PDF)', () async {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final pago = cobrar(p, pagos, sep(2), 400);
      final bytes = await reciboPdf(
        r: datosRecibo(p, pagos, pago),
        negocio: const NegocioRecibo(
          nombre: 'Inversiones Castillo 💰',
          telefono: '809-555-1234',
          direccion: 'C/ Duarte #12, Santiago',
          mensaje: 'Pague a tiempo y evite mora 🙏',
        ),
        logo: File('web/favicon.png').readAsBytesSync(),
        cobradoPor: 'Juan Pérez',
        cliente: 'José “El Flaco” Martínez',
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      File('${Directory.systemTemp.path}/recibo_muestra_logo.pdf').writeAsBytesSync(bytes);
    });

    test('un logo dañado no impide el recibo', () async {
      final p = prestamo();
      final pagos = <PagoRegistrado>[];
      final pago = cobrar(p, pagos, sep(2), 400);
      final bytes = await reciboPdf(
        r: datosRecibo(p, pagos, pago),
        negocio: const NegocioRecibo(nombre: 'Préstamos Núñez'),
        logo: Uint8List.fromList([1, 2, 3, 4]),
        cliente: 'José',
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('Mi recibo', () {
    test('lo vacío toma el valor de siempre', () {
      final n = NegocioRecibo.dePerfil({
        'nombre': 'Mitchell Castillo',
        'negocio': '  ',
        'phone': 'humano@correo.com',
        'whatsapp': '809-555-1234',
        'recibo_mensaje': '',
      });
      expect(n.nombre, 'Mitchell Castillo');
      expect(n.telefono, '809-555-1234');
      expect(n.direccion, isNull);
      expect(n.mensaje, 'Gracias por su pago.');
      expect(n.logo, isNull);
      expect(NegocioRecibo.dePerfil(null).nombre, 'Prestamista');
    });

    test('lo que el prestamista puso gana', () {
      final n = NegocioRecibo.dePerfil({
        'nombre': 'Mitchell Castillo',
        'negocio': 'Inversiones Castillo',
        'whatsapp': '809-555-1234',
        'recibo_telefono': '829-000-1111',
        'recibo_direccion': 'Santiago',
        'recibo_mensaje': 'Pague a tiempo',
        'recibo_logo': 'abc/logo_1.jpg',
      });
      expect(n.nombre, 'Inversiones Castillo');
      expect(n.telefono, '829-000-1111');
      expect(n.direccion, 'Santiago');
      expect(n.mensaje, 'Pague a tiempo');
      expect(n.logo, 'abc/logo_1.jpg');
    });

    test('texto para el PDF: sin emojis y con comillas rectas', () {
      expect(textoPdf('Préstamos Núñez 💰'), 'Préstamos Núñez');
      expect(textoPdf('José “El Flaco” – ¡gracias!'), 'José "El Flaco" - ¡gracias!');
      expect(textoPdf('Línea 1\nLínea 2'), 'Línea 1\nLínea 2');
    });
  });
}
