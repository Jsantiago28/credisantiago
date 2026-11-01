import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/services/sin_conexion.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const prestamo = {'id': 'p1', 'prestamista_id': 'jefe', 'cliente_id': 'c1'};

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SinConexion.usuarioParaPruebas = 'u1';
    FlutterSecureStorage.setMockInitialValues({});
    SinConexion.almacenParaPruebas = const FlutterSecureStorage();
    SinConexion.subirParaPruebas = null;
    SinConexion.subirVisitaParaPruebas = null;
    SinConexion.sinSenal.value = false;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SinConexion.usuarioParaPruebas = null;
    SinConexion.subirVisitaParaPruebas = null;
  });

  test('"No estaba" sin señal se guarda y sube con su id; luego se quita', () async {
    await SinConexion.agregarVisita(prestamo);
    final guardadas = await SinConexion.visitas();
    expect(guardadas, hasLength(1));
    expect(guardadas.single['prestamo_id'], 'p1');
    expect(guardadas.single['cliente_id'], 'c1');

    final subidas = <Map<String, dynamic>>[];
    SinConexion.subirVisitaParaPruebas = (v) async => subidas.add(v);
    await SinConexion.subir();
    expect(subidas.single['id'], guardadas.single['id']);
    expect(await SinConexion.visitas(), isEmpty);
  });

  test('la que ya subió (mismo id) se quita; sin señal se queda', () async {
    await SinConexion.agregarVisita(prestamo);
    await SinConexion.agregarVisita(prestamo);
    var vez = 0;
    SinConexion.subirVisitaParaPruebas = (v) async {
      vez++;
      if (vez == 1) throw const PostgrestException(message: 'duplicada', code: '23505');
      throw Exception('Failed host lookup: SocketException');
    };
    await SinConexion.subir();
    expect(await SinConexion.visitas(), hasLength(1));
    expect(SinConexion.sinSenal.value, isTrue);
  });
}
