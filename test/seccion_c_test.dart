import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/logic/ruta.dart';
import 'package:prestamistas_rd/services/errores.dart';
import 'package:prestamistas_rd/services/recordatorio.dart';
import 'package:prestamistas_rd/widgets/ajuste_recordatorio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_datos;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('los errores largos se cortan a lo que acepta la tabla', () {
    expect(Errores.recortar('corto', 2000), 'corto');
    expect(Errores.recortar('x' * 3000, 2000).length, 2000);
  });

  test('un cobro con ubicación la trae; sin ella, null', () {
    final fila = {
      'fecha_pago': '2026-10-18T14:00:00Z',
      'monto': 500,
      'lat': 19.45,
      'lng': -70.69,
      'prestamos': {'clientes': {'nombre': 'Ana'}},
    };
    expect(CobroCaja.desdeFila(fila).ubicacion, (lat: 19.45, lng: -70.69));
    expect(CobroCaja.desdeFila({...fila, 'lat': null, 'lng': null}).ubicacion, isNull);
    expect(CobroCaja.desdeFila({...fila}..remove('lat')..remove('lng')).ubicacion, isNull);
  });

  test('el enlace del lugar del cobro abre Google Maps en ese punto', () {
    final enlace = enlaceLugar((lat: 19.45, lng: -70.69));
    expect(enlace.host, 'www.google.com');
    expect(enlace.queryParameters['query'], '19.450000,-70.690000');
  });

  test('el recordatorio es hoy si la hora no ha pasado, si no mañana', () {
    tz_datos.initializeTimeZones();
    final rd = tz.getLocation('America/Santo_Domingo');
    const ocho = TimeOfDay(hour: 8, minute: 0);
    final temprano = tz.TZDateTime(rd, 2026, 10, 18, 6, 30);
    final tarde = tz.TZDateTime(rd, 2026, 10, 18, 9, 0);
    expect(Recordatorio.proximaVez(temprano, ocho), tz.TZDateTime(rd, 2026, 10, 18, 8));
    expect(Recordatorio.proximaVez(tarde, ocho), tz.TZDateTime(rd, 2026, 10, 19, 8));
  });

  testWidgets('el ajuste del recordatorio se ve solo en Android', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const pantalla = MaterialApp(home: Scaffold(body: AjusteRecordatorio()));
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(pantalla);
    expect(find.text('Recordatorio de cobros'), findsNothing);
    debugDefaultTargetPlatformOverride = null; // las pruebas corren como Android

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(pantalla);
    await tester.pump();
    expect(find.text('Recordatorio de cobros'), findsOneWidget);
    expect(find.textContaining('Hora del aviso: 8:00'), findsOneWidget);
  });
}
