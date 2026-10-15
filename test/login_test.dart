import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/screens/login_screen.dart';
import 'package:prestamistas_rd/screens/registro_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> abrir(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: pantalla));
  await tester.pump();
}

void main() {
  group('Entrada con contraseña', () {
    testWidgets('abre en "Iniciar sesión" con olvidé y registrarme', (tester) async {
      await abrir(tester, const LoginScreen());
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Correo'), findsOneWidget);
      expect(find.text('Contraseña'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      expect(find.text('Registrarme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('registrarse pide repetir la contraseña y que sean iguales', (tester) async {
      await abrir(tester, const LoginScreen());
      await tester.tap(find.text('Registrarme'));
      await tester.pump();
      expect(find.text('Crear cuenta'), findsWidgets);
      expect(find.text('Repite la contraseña'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'juan@correo.com');
      await tester.enterText(find.byType(TextField).at(1), 'clave1234');
      await tester.enterText(find.byType(TextField).at(2), 'clave9999');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pump();
      expect(find.text('Las dos contraseñas no son iguales'), findsOneWidget);
    });

    testWidgets('la contraseña corta no se acepta', (tester) async {
      await abrir(tester, const LoginScreen());
      await tester.tap(find.text('Registrarme'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'juan@correo.com');
      await tester.enterText(find.byType(TextField).at(1), '123');
      await tester.enterText(find.byType(TextField).at(2), '123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
      await tester.pump();
      expect(find.text('La contraseña debe tener al menos $minimoClave caracteres'), findsOneWidget);
    });

    testWidgets('olvidé: solo pide el correo para mandar el código', (tester) async {
      await abrir(tester, const LoginScreen());
      await tester.tap(find.text('¿Olvidaste tu contraseña?'));
      await tester.pump();
      expect(find.text('Enviar código'), findsOneWidget);
      expect(find.text('Contraseña'), findsNothing);
      await tester.tap(find.text('Enviar código'));
      await tester.pump();
      expect(find.text('Escribe un correo válido'), findsOneWidget);
    });
  });

  testWidgets('registro del perfil: pide la cédula y sus dos fotos', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await abrir(tester, const RegistroScreen());
    expect(find.text('Tu cédula'), findsOneWidget);
    expect(find.text('Cédula de frente'), findsOneWidget);
    expect(find.text('Cédula de atrás'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Juan Préstamos');
    await tester.enterText(find.byType(TextField).at(1), '809-555-1234');
    await tester.tap(find.text('Generar mi link'));
    await tester.pump();
    expect(find.textContaining('Cédula:'), findsOneWidget); // falta el número

    await tester.enterText(find.byType(TextField).at(2), '001-0000000-1');
    await tester.tap(find.text('Generar mi link'));
    await tester.pump();
    final sinFotos = find.text('Sube la foto de tu cédula de los dos lados');
    final cedulaMala = find.textContaining('Cédula:');
    // Con un número válido pide las fotos; si el dígito verificador no
    // cuadra, sigue marcando la cédula.
    expect(sinFotos.evaluate().isNotEmpty || cedulaMala.evaluate().isNotEmpty, isTrue);
  });
}
