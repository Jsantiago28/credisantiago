import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/instalar/instalar_stub.dart';
import 'package:prestamistas_rd/widgets/instalar_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> mostrar(WidgetTester tester, Instalacion estado,
    {Future<bool> Function()? instalar, DateTime? hoy}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TarjetaInstalar(
        estado: () => estado,
        instalar: instalar ?? () async => false,
        alCambiar: (_) {},
        hoy: hoy,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('con Chrome sale el botón Instalar y lo usa', (tester) async {
    var pidio = false;
    await mostrar(tester, Instalacion.conBoton, instalar: () async => pidio = true);
    expect(find.text('Instala CrediSantiago en tu celular'), findsOneWidget);
    await tester.tap(find.byKey(const Key('instalar-boton')));
    await tester.pumpAndSettle();
    expect(pidio, isTrue);
    expect(find.textContaining('quedó en tu pantalla de inicio'), findsOneWidget);
  });

  testWidgets('en iPhone explica Compartir → Agregar a pantalla de inicio', (tester) async {
    await mostrar(tester, Instalacion.iphone);
    expect(find.textContaining('Toca Compartir'), findsOneWidget);
    expect(find.byKey(const Key('instalar-boton')), findsNothing);
  });

  testWidgets('ya instalada (o APK, o computadora): no sale', (tester) async {
    await mostrar(tester, Instalacion.instalada);
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing);
  });

  testWidgets('"No ahora" la esconde 14 días y después vuelve', (tester) async {
    await mostrar(tester, Instalacion.menuDelNavegador, hoy: DateTime(2026, 11, 2));
    await tester.tap(find.byKey(const Key('instalar-cerrar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing);

    await tester.pumpWidget(const SizedBox()); // se abre la app de nuevo
    await mostrar(tester, Instalacion.menuDelNavegador, hoy: DateTime(2026, 11, 10));
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing, reason: 'a los 8 días');

    await tester.pumpWidget(const SizedBox());
    await mostrar(tester, Instalacion.menuDelNavegador, hoy: DateTime(2026, 11, 17));
    expect(find.byKey(const Key('tarjeta-instalar')), findsOneWidget, reason: 'a los 15 días');
  });
}
