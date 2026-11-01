import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/services/sin_conexion.dart';
import 'package:prestamistas_rd/services/supabase_service.dart';

/// Un almacén que cuenta cuántas veces se escribe.
class _AlmacenQueCuenta extends FlutterSecureStorage {
  _AlmacenQueCuenta();

  int escrituras = 0;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    escrituras++;
    return super.write(key: key, value: value);
  }
}

/// Un préstamo como lo devuelve Supabase con lo anidado.
Map<String, dynamic> filaAnidada({String id = 'p1', List<Map<String, dynamic>>? pagos}) => {
      'id': id,
      'prestamista_id': 'jefe',
      'cliente_id': 'c1',
      'monto': 10000,
      'tasa_interes': 20,
      'cuota': 1500,
      'cantidad_cuotas': 8,
      'monto_total': 12000,
      'mora_diaria': 0,
      'dias_gracia': 1,
      'frecuencia': 'semanal',
      'fecha_desembolso': '2026-10-01',
      'proximo_pago': '2026-10-08',
      'estado': 'en_calle',
      'created_at': '2026-10-01T10:00:00Z',
      'clientes': {
        'nombre': 'Juana Pérez',
        'direccion': 'Calle 1',
        'telefono': '8095551234',
        'foto_cara_url': null,
        'lat': 18.4,
        'lng': -69.9,
      },
      'pagos': pagos ??
          [
            {
              'id': 'b',
              'numero_recibo': 2,
              'monto': 1500,
              'monto_mora': 0,
              'fecha_pago': '2026-10-15T14:00:00Z',
              'anulado': false,
              'metodo': 'efectivo',
            },
            {
              'id': 'a',
              'numero_recibo': 1,
              'monto': 1500,
              'monto_mora': 0,
              'fecha_pago': '2026-10-08T14:00:00Z',
              'anulado': false,
              'metodo': 'efectivo',
            },
          ],
      'gestiones': [
        {
          'id': 'g1',
          'prestamo_id': id,
          'created_at': '2026-10-09T10:00:00Z',
          'tipo': 'llamada',
          'resultado': 'no_contesta',
        },
        {
          'id': 'g2',
          'prestamo_id': id,
          'created_at': '2026-10-20T10:00:00Z',
          'tipo': 'visita',
          'resultado': 'promesa',
          'promesa_fecha': '2026-10-25',
          'promesa_monto': 1500,
        },
      ],
    };

void main() {
  group('juntarPaginas', () {
    test('pide páginas hasta que una venga incompleta', () async {
      final todas = [for (var i = 0; i < 2350; i++) <String, dynamic>{'n': i}];
      final pedidos = <(int, int)>[];
      final filas = await SupabaseService.juntarPaginas((desde, hasta) async {
        pedidos.add((desde, hasta));
        return todas.sublist(desde, hasta + 1 > todas.length ? todas.length : hasta + 1);
      });
      expect(filas.length, 2350);
      expect(filas.last['n'], 2349);
      expect(pedidos, [(0, 999), (1000, 1999), (2000, 2999)]);
    });

    test('si justo son 1,000, pide una más (vacía) para saber que no hay más', () async {
      var pedidos = 0;
      final filas = await SupabaseService.juntarPaginas((desde, hasta) async {
        pedidos++;
        return desde == 0 ? [for (var i = 0; i < 1000; i++) <String, dynamic>{'n': i}] : [];
      });
      expect(filas.length, 1000);
      expect(pedidos, 2);
    });

    test('pocas filas: una sola consulta', () async {
      var pedidos = 0;
      final filas = await SupabaseService.juntarPaginas((desde, hasta) async {
        pedidos++;
        return [<String, dynamic>{'n': 1}];
      });
      expect(filas.length, 1);
      expect(pedidos, 1);
    });
  });

  group('PrestamoConDatos.desdeFilaAnidada', () {
    test('separa préstamo, cliente, pagos (por fecha) y gestiones (reciente primero)', () {
      final d = PrestamoConDatos.desdeFilaAnidada(filaAnidada());
      expect(d.prestamo.containsKey('clientes'), isFalse);
      expect(d.prestamo.containsKey('pagos'), isFalse);
      expect(d.prestamo.containsKey('gestiones'), isFalse);
      expect(d.prestamo['id'], 'p1');
      expect(d.nombre, 'Juana Pérez');
      expect(d.direccion, 'Calle 1');
      expect(d.cliente!['lat'], 18.4);
      expect(d.pagos.map((p) => p.id), ['a', 'b']);
      expect(d.pagos.first.numeroRecibo, 1);
      expect(d.gestiones.map((g) => g.id), ['g2', 'g1']);
    });

    test('sin cliente visible (permisos) ni pagos ni gestiones', () {
      final fila = filaAnidada(pagos: [])
        ..['clientes'] = null
        ..remove('gestiones');
      final d = PrestamoConDatos.desdeFilaAnidada(fila);
      expect(d.cliente, isNull);
      expect(d.nombre, '...');
      expect(d.pagos, isEmpty);
      expect(d.gestiones, isEmpty);
    });

    test('lee descuento, anulados e importados igual que obtenerPagos', () {
      final d = PrestamoConDatos.desdeFilaAnidada(filaAnidada(pagos: [
        {
          'id': 'x',
          'numero_recibo': 5,
          'monto': 900,
          'monto_mora': 50,
          'descuento': 300,
          'fecha_pago': '2026-10-10T14:00:00Z',
          'anulado': true,
          'anulado_en': '2026-10-10T15:00:00Z',
          'motivo_anulacion': 'mal digitado',
          'cobrador_id': 'cob1',
          'metodo': 'importado',
        },
      ]));
      final p = d.pagos.single;
      expect(p.descuento, 300);
      expect(p.montoMora, 50);
      expect(p.anulado, isTrue);
      expect(p.motivoAnulacion, 'mal digitado');
      expect(p.cobradorId, 'cob1');
      expect(p.importado, isTrue);
    });
  });

  test('filaDeReporte conserva las llaves que usa Reportes', () {
    final fila = filaAnidada()
      ..['clientes'] = {
        'nombre': 'Juana Pérez',
        'telefono': '8095551234',
        'direccion': 'Calle 1',
        'jefe_nombre': 'Don Pedro',
        'jefe_telefono': '8095550000',
        'ref1_nombre': 'Ana',
        'ref1_telefono': '8095551111',
      };
    final r = SupabaseService.filaDeReporte(fila, DateTime(2026, 10, 16));
    for (final llave in [
      'id',
      'monto',
      'estado',
      'cliente_nombre',
      'cliente_telefono',
      'cliente_direccion',
      'cliente_jefe',
      'cliente_jefe_telefono',
      'cliente_ref1',
      'cliente_ref1_telefono',
      'monto_total',
      'total_pagado',
      'total_descuento',
      'mora_cobrada',
      'mora_cobrada_mes',
      'fecha_ultimo_pago',
      'mora_pendiente',
      'balance',
      'estado_calculado',
      'proximo_pago',
    ]) {
      expect(r.containsKey(llave), isTrue, reason: llave);
    }
    expect(r.containsKey('clientes'), isFalse);
    expect(r.containsKey('pagos'), isFalse);
    expect(r['cliente_jefe'], 'Don Pedro');
    expect(r['total_pagado'], 3000);
    expect(r['balance'], 9000);
    expect(r['fecha_ultimo_pago'], DateTime.parse('2026-10-15T14:00:00Z').toLocal());
  });

  group('guardarRuta', () {
    late _AlmacenQueCuenta almacen;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SinConexion.usuarioParaPruebas = 'u1';
      FlutterSecureStorage.setMockInitialValues({});
      almacen = _AlmacenQueCuenta();
      SinConexion.almacenParaPruebas = almacen;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      SinConexion.usuarioParaPruebas = null;
    });

    test('la misma ruta antes de 3 minutos no se reescribe', () async {
      final cartera = [PrestamoConDatos.desdeFilaAnidada(filaAnidada())];
      final t0 = DateTime(2026, 11, 1, 9);
      await SinConexion.guardarRuta(cartera, ahora: t0);
      await SinConexion.guardarRuta(cartera, ahora: t0.add(const Duration(minutes: 1)));
      expect(almacen.escrituras, 1);
      // Pasados los 3 minutos, sí.
      await SinConexion.guardarRuta(cartera, ahora: t0.add(const Duration(minutes: 4)));
      expect(almacen.escrituras, 2);
    });

    test('si cambió algo, se escribe enseguida', () async {
      final t0 = DateTime(2026, 11, 1, 9);
      await SinConexion.guardarRuta([PrestamoConDatos.desdeFilaAnidada(filaAnidada())], ahora: t0);
      await SinConexion.guardarRuta(
          [PrestamoConDatos.desdeFilaAnidada(filaAnidada(pagos: []))],
          ahora: t0.add(const Duration(seconds: 10)));
      expect(almacen.escrituras, 2);
    });

    test('después de salir de la cuenta se vuelve a guardar', () async {
      final cartera = [PrestamoConDatos.desdeFilaAnidada(filaAnidada())];
      await SinConexion.guardarRuta(cartera);
      await SinConexion.olvidarDatos();
      await SinConexion.guardarRuta(cartera);
      expect(almacen.escrituras, 2);
      expect((await SinConexion.ruta())?.cartera.length, 1);
    });
  });
}
