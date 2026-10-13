import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/contrato.dart';
import 'package:prestamistas_rd/recibos/contrato_pdf.dart';

/// 10,000 al 20% por 30 días semanal desde el 1/9: 5 cuotas, mora 5%
/// diario con 1 día de gracia.
Map<String, dynamic> prestamo() {
  final plan = calcularPlan(
      monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: 'semanal');
  return {
    'monto': 10000.0,
    'tasa_interes': 20.0,
    'cuota': plan.cuota,
    'cantidad_cuotas': plan.cantidadCuotas,
    'monto_total': plan.montoTotal,
    'frecuencia': 'semanal',
    'fecha_desembolso': '2026-09-01',
    'mora_diaria': 5.0,
    'dias_gracia': 1,
  };
}

const cliente = {
  'nombre': 'Juan Pérez',
  'cedula': '001-0000000-1',
  'direccion': 'Calle 5 #12, Los Mina',
};

void main() {
  group('Número en letras', () {
    test('unidades, decenas y centenas', () {
      expect(numeroEnLetras(0), 'cero');
      expect(numeroEnLetras(1), 'un');
      expect(numeroEnLetras(16), 'dieciséis');
      expect(numeroEnLetras(21), 'veintiún');
      expect(numeroEnLetras(30), 'treinta');
      expect(numeroEnLetras(45), 'cuarenta y cinco');
      expect(numeroEnLetras(100), 'cien');
      expect(numeroEnLetras(101), 'ciento un');
      expect(numeroEnLetras(500), 'quinientos');
      expect(numeroEnLetras(999), 'novecientos noventa y nueve');
    });

    test('miles y millones', () {
      expect(numeroEnLetras(1000), 'mil');
      expect(numeroEnLetras(1500), 'mil quinientos');
      expect(numeroEnLetras(21000), 'veintiún mil');
      expect(numeroEnLetras(100000), 'cien mil');
      expect(numeroEnLetras(156250), 'ciento cincuenta y seis mil doscientos cincuenta');
      expect(numeroEnLetras(1000000), 'un millón');
      expect(numeroEnLetras(2300000), 'dos millones trescientos mil');
    });

    test('monto con pesos y centavos', () {
      expect(montoEnLetras(10000), 'DIEZ MIL PESOS DOMINICANOS CON 00/100');
      expect(montoEnLetras(1), 'UN PESO DOMINICANO CON 00/100');
      expect(montoEnLetras(1250.5), 'MIL DOSCIENTOS CINCUENTA PESOS DOMINICANOS CON 50/100');
      expect(montoEnLetras(1000000), 'UN MILLÓN DE PESOS DOMINICANOS CON 00/100');
    });
  });

  test('fecha larga del contrato', () {
    expect(fechaContrato(DateTime(2026, 10, 13)), '13 de octubre de 2026');
  });

  group('Datos del contrato', () {
    test('salen del préstamo, del cliente y del perfil', () {
      final d = datosContrato(
        prestamo: prestamo(),
        cliente: cliente,
        perfil: {
          'nombre': 'Mitchell Castillo',
          'negocio': 'Inversiones MC',
          'recibo_direccion': 'Av. Venezuela 20',
          'contrato_cedula': '001-1234567-8',
          'contrato_ciudad': 'Santo Domingo Este',
        },
        hoy: DateTime(2026, 10, 13),
      );
      expect(d.fecha, DateTime(2026, 9, 1)); // la del desembolso, no la de hoy
      expect(d.prestamista, 'Inversiones MC');
      expect(d.representante, 'Mitchell Castillo');
      expect(d.prestamistaCedula, '001-1234567-8');
      expect(d.ciudad, 'Santo Domingo Este');
      expect(d.cliente, 'Juan Pérez');
      expect(d.clienteDomicilio, 'Calle 5 #12, Los Mina');
      expect(d.tasaTexto, '20% mensual');
      expect(d.frecuenciaTexto, 'Semanal');
      expect(d.moraTexto,
          '5% diario sobre lo que falte de la cuota vencida, después de 1 día de gracia');

      // 30 días semanal = 5 semanas; la primera vence a los 7 días.
      expect(d.cuotas.length, 5);
      expect(d.primerPago, DateTime(2026, 9, 8));
      expect(d.ultimoPago, DateTime(2026, 10, 6));
      expect(d.cuotas.fold<double>(0, (s, c) => s + c.monto), d.montoTotal);
    });

    test('sin negocio no hay representante; lo que falta queda vacío', () {
      final d = datosContrato(
        prestamo: {...prestamo(), 'mora_diaria': 0, 'tasa_interes': 0},
        cliente: cliente,
        perfil: {'nombre': 'Mitchell Castillo'},
        hoy: DateTime(2026, 10, 13),
      );
      expect(d.prestamista, 'Mitchell Castillo');
      expect(d.representante, isNull);
      expect(d.prestamistaCedula, isNull);
      expect(d.ciudad, isNull);
      expect(d.moraTexto, isNull);
      expect(d.tasaTexto, 'No aplica');
    });

    test('préstamo viejo sin cronograma: sin cuotas ni fechas', () {
      final d = datosContrato(
        prestamo: {'monto': 5000.0, 'frecuencia': 'diario'},
        cliente: cliente,
        perfil: null,
        hoy: DateTime(2026, 10, 13),
      );
      expect(d.fecha, DateTime(2026, 10, 13));
      expect(d.cuotas, isEmpty);
      expect(d.cuota, isNull);
      expect(d.primerPago, isNull);
    });
  });

  test('el PDF se genera (y se guarda de muestra si se pide)', () async {
    final d = datosContrato(
      prestamo: prestamo(),
      cliente: cliente,
      perfil: {'nombre': 'Mitchell Castillo', 'negocio': 'Inversiones MC'},
      hoy: DateTime(2026, 10, 13),
    );
    final bytes = await contratoPdf(d);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final muestra = Platform.environment['CONTRATO_MUESTRA'];
    if (muestra != null) File(muestra).writeAsBytesSync(bytes);
  });
}
