import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/services/sin_conexion.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Un teléfono que no puede guardar (memoria llena, Keystore dañado...).
class _AlmacenQueFalla extends FlutterSecureStorage {
  const _AlmacenQueFalla();

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
  }) async =>
      throw Exception('no hay espacio');
}

CobroPendiente cobro(String id, {double monto = 300}) => CobroPendiente(
    id: id,
    prestamoId: 'p1',
    prestamistaId: 'jefe',
    monto: monto,
    montoMora: 0,
    fecha: DateTime(2026, 10, 15, 9));

void main() {
  setUp(() {
    // Como la app de Android, con un usuario y el almacén de prueba.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SinConexion.usuarioParaPruebas = 'u1';
    FlutterSecureStorage.setMockInitialValues({});
    SinConexion.almacenParaPruebas = const FlutterSecureStorage();
    SinConexion.subirParaPruebas = null;
    SinConexion.sinSenal.value = false;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SinConexion.usuarioParaPruebas = null;
    SinConexion.subirParaPruebas = null;
  });

  test('guarda la cola y la lee de vuelta; el mismo id no se repite', () async {
    await SinConexion.agregar(cobro('a'));
    await SinConexion.agregar(cobro('b'));
    await SinConexion.agregar(cobro('a', monto: 500));
    final cola = await SinConexion.cola();
    expect(cola.map((c) => c.id), ['b', 'a']);
    expect(cola.last.monto, 500);
    expect(SinConexion.pendientes.value, 2);
  });

  test('un cobro guardado MIENTRAS se suben otros no se pierde', () async {
    await SinConexion.agregar(cobro('a'));
    final subiendo = Completer<void>();
    final subidos = <String>[];
    SinConexion.subirParaPruebas = (c) async {
      if (c.id == 'a') await subiendo.future; // la red tarda
      subidos.add(c.id);
    };
    final subida = SinConexion.subir();
    await Future<void>.delayed(Duration.zero);
    await SinConexion.agregar(cobro('nuevo')); // se cobra otro sin señal
    subiendo.complete();
    await subida;
    expect(subidos, ['a']);
    expect((await SinConexion.cola()).map((c) => c.id), ['nuevo']);
  });

  test('el que la base de datos ya tiene (mismo id) se quita; sin señal se para', () async {
    await SinConexion.agregar(cobro('ya'));
    await SinConexion.agregar(cobro('sin-senal'));
    await SinConexion.agregar(cobro('despues'));
    SinConexion.subirParaPruebas = (c) async {
      if (c.id == 'ya') throw const PostgrestException(message: 'duplicate key', code: '23505');
      if (c.id == 'sin-senal') throw Exception('SocketException: Failed host lookup');
    };
    await SinConexion.subir();
    expect((await SinConexion.cola()).map((c) => c.id), ['sin-senal', 'despues']);
    expect(SinConexion.sinSenal.value, isTrue);
  });

  test('si el teléfono no puede guardar el cobro, avisa (no dice "guardado")', () async {
    SinConexion.almacenParaPruebas = const _AlmacenQueFalla();
    await expectLater(SinConexion.agregar(cobro('a')), throwsException);
    // La cola sigue funcionando después del fallo.
    SinConexion.almacenParaPruebas = const FlutterSecureStorage();
    await SinConexion.agregar(cobro('b'));
    expect((await SinConexion.cola()).single.id, 'b');
  });
}
