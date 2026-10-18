import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/logic/caja.dart';
import 'package:prestamistas_rd/logic/calculo_prestamo.dart';
import 'package:prestamistas_rd/logic/gastos.dart';
import 'package:prestamistas_rd/screens/caja_screen.dart';
import 'package:prestamistas_rd/screens/calculadora_screen.dart';
import 'package:prestamistas_rd/screens/nuevo_cliente_screen.dart';
import 'package:prestamistas_rd/screens/prestar_screen.dart';
import 'package:prestamistas_rd/screens/solicitud_publica_screen.dart';
import 'package:prestamistas_rd/theme/app_theme.dart';
import 'package:prestamistas_rd/widgets/ui.dart';

/// Dibuja en un teléfono angosto (360 px). Si algo no cabe, Flutter marca
/// un error de desborde y la prueba falla.
Future<void> enTelefono(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Tema sin Google Fonts: en pruebas no hay internet para bajar la fuente.
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [hijo])),
  ));
}

void main() {
  test('montos en formato RD\$ con separador de miles', () {
    expect(rd(156000), 'RD\$156,000');
    expect(rd(144.44), 'RD\$144.44');
    expect(rd(0), 'RD\$0');
  });

  test('fechas en español', () {
    expect(fechaLarga(DateTime(2026, 9, 23)), '23 sep 2026');
    expect(fechaCorta(DateTime(2026, 12, 1)), '1 dic');
  });

  testWidgets('las 3 tarjetas de totales caben con montos grandes', (tester) async {
    Widget tarjeta(String titulo, String valor) => Expanded(
          child: TarjetaTotal(
            icono: Icons.account_balance_wallet_rounded,
            titulo: titulo,
            valor: valor,
            detalle: '128 préstamo(s)',
            color: AppColors.green,
            fondoIcono: AppColors.greenDark,
          ),
        );
    await enTelefono(
      tester,
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tarjeta('EN LA CALLE', rd(12345678)),
            const SizedBox(width: 8),
            tarjeta('POR COBRAR HOY', rd(850000)),
            const SizedBox(width: 8),
            tarjeta('ATRASADOS', rd(1230000.5)),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('POR COBRAR HOY'), findsOneWidget);
  });

  testWidgets('calculadora: muestra las 4 opciones y cabe en un teléfono', (tester) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const CalculadoraScreen(prestamistaId: 'prueba'),
    ));

    // 10,000 al 20% por 30 días (valores por defecto).
    expect(find.text('Diario'), findsOneWidget);
    expect(find.text('Quincenal'), findsOneWidget);
    expect(find.text('Mensual'), findsOneWidget);
    // Interés sobre saldo: la cuota sale de la misma fórmula que usa la app.
    String cuota(String f) => rd(calcularPlan(
            monto: 10000, tasaInteresMensual: 20, diasPlazo: 30, frecuencia: f, tipo: TipoInteres.saldo)
        .cuota);
    expect(find.text(cuota('diario')), findsWidgets);
    expect(find.text(cuota('quincenal')), findsWidgets);
    expect(find.text('RD\$12,000'), findsWidgets); // 1 mes: 10,000 + 20%

    // Monto grande: nada se desborda.
    await tester.enterText(find.byType(TextField).first, '1250000');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Prestar: escribir el monto número por número no rompe la pantalla', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const PrestarScreen(
        cliente: {'nombre': 'José Pérez'},
        prestamo: {'id': 'x', 'monto': 0},
        diasInicial: 45,
        frecuenciaInicial: 'semanal', // 7 cuotas: "1" peso no alcanza
      ),
    ));

    final monto = find.byType(TextField).first;
    for (final texto in ['1', '15', '150', '1500', '15000']) {
      await tester.enterText(monto, texto);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'con monto "$texto"');
    }
    expect(find.textContaining('muy bajo'), findsNothing);
    // 45 días semanal = 7 semanas, interés sobre saldo.
    final plan = calcularPlan(
        monto: 15000, tasaInteresMensual: 20, diasPlazo: 45, frecuencia: 'semanal', tipo: TipoInteres.saldo);
    expect(find.text('RD\$ ${plan.cuota.toStringAsFixed(0)}'), findsOneWidget);
  });

  testWidgets('Prestar: con "1" peso avisa que el monto es muy bajo', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const PrestarScreen(
        cliente: {'nombre': 'José Pérez'},
        prestamo: {'id': 'x', 'monto': 0},
        diasInicial: 45,
        frecuenciaInicial: 'semanal',
      ),
    ));
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('El monto es muy bajo para 7 cuotas semanales.'), findsOneWidget);
  });

  testWidgets('Nuevo cliente: fotos, ingreso, vivienda y supervisor caben en un teléfono',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const NuevoClienteScreen(prestamistaId: 'x'),
    ));
    await tester.pump(); // deja terminar la búsqueda de clientes (aquí sin conexión)
    expect(tester.takeException(), isNull);
    expect(find.text('Cédula frente'), findsOneWidget);
    expect(find.text('Cédula atrás'), findsOneWidget);
    expect(find.text('Propia'), findsOneWidget);
    expect(find.text('Alquilada'), findsOneWidget);
    expect(find.text('¿Cuánto gana al mes? (RD\$)'), findsOneWidget);
    expect(find.text('Nombre del supervisor o de Recursos Humanos'), findsOneWidget);
    expect(find.text('Evidencia de ingresos (opcional)'), findsOneWidget);
    expect(find.text('Agregar'), findsOneWidget);

    await tester.tap(find.text('Alquilada'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final ancho in [360.0, 412.0, 1280.0]) {
    testWidgets('link público, último paso: tarjetas de fotos caben a $ancho px', (tester) async {
      tester.view.physicalSize = Size(ancho, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const MaterialApp(home: SolicitudPublicaScreen(slug: 'prueba', pasoInicial: 4)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Foto de tu cara'), findsOneWidget);
      expect(find.text('Cédula - Frente'), findsOneWidget);
      expect(find.text('Cédula - Reverso'), findsOneWidget);
      expect(find.text('Tomar foto'), findsNWidgets(3));
      expect(find.text('Galería'), findsNWidgets(3));
      expect(find.text('Paso 5 de 5 - Fotos'), findsOneWidget);
      expect(find.text('Datos seguros y privados'), findsOneWidget);
      // En pantallas anchas no se estira: máximo 560 px.
      if (ancho > 560) {
        expect(tester.getSize(find.text('Enviar solicitud').first).width, lessThan(560));
      }
    });
  }

  testWidgets('link público: empieza por los datos y las fotos van de último', (tester) async {
    tester.view.physicalSize = const Size(412, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SolicitudPublicaScreen(slug: 'prueba')));
    await tester.pump();
    expect(find.text('Paso 1 de 5 - Datos'), findsOneWidget);
    expect(find.text('Tomar foto'), findsNothing);
    expect(find.text('5 Fotos'), findsOneWidget); // en la barra de pasos
  });

  test('nombre del día en la caja', () {
    final hoy = DateTime(2026, 9, 23, 15);
    expect(nombreDia(DateTime(2026, 9, 23), hoy: hoy), 'Hoy');
    expect(nombreDia(DateTime(2026, 9, 22), hoy: hoy), 'Ayer');
    expect(nombreDia(DateTime(2026, 9, 21), hoy: hoy), 'lun 21 sep');
  });

  testWidgets('caja del día: totales y cobros caben en un teléfono', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dia = cajaPorDia([
      CobroCaja(
          numeroRecibo: 12,
          fecha: DateTime(2026, 9, 23, 8, 5),
          monto: 125460,
          cliente: 'María Altagracia Rosario de los Santos'),
      CobroCaja(
          numeroRecibo: 13,
          fecha: DateTime(2026, 9, 23, 9),
          monto: 460,
          montoMora: 60,
          cliente: 'José Pérez'),
      CobroCaja(
          numeroRecibo: 14,
          fecha: DateTime(2026, 9, 23, 10),
          monto: 4000,
          anulado: true,
          cliente: 'Luis Guzmán'),
    ]).single;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: CajaDiaScreen(prestamistaId: 'x', dia: dia, cierre: null, gastos: [
        Gasto(fecha: DateTime(2026, 9, 23), monto: 500, categoria: 'gasolina'),
        Gasto(fecha: DateTime(2026, 9, 23), monto: 1500, categoria: 'cobrador', nota: 'Juan, la semana'),
      ]),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('RD\$125,920'), findsOneWidget); // sin el anulado
    expect(find.text('Cerrar caja'), findsOneWidget);
    expect(find.textContaining('ANULADO'), findsOneWidget);
    // Gastos del día y lo que queda: 125,920 − 2,000.
    expect(find.text('− RD\$2,000'), findsOneWidget);
    expect(find.text('RD\$123,920'), findsOneWidget);
    expect(find.text('Pago al cobrador · Juan, la semana'), findsOneWidget);
  });

  testWidgets('fila de cobro con nombre y dirección largos no se desborda', (tester) async {
    await enTelefono(
      tester,
      Panel(
        child: Row(
          children: [
            const AvatarIniciales(nombre: 'María Altagracia Rosario de los Santos'),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('María Altagracia Rosario de los Santos',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('Av. Independencia 44, Ensanche La Julia • 12 día(s) atrasado',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(rd(125460)),
                const SizedBox(height: 6),
                const EtiquetaEstado(EstadoCobro.atrasado),
              ],
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('MA'), findsOneWidget); // iniciales
    expect(find.text('ATRASADO'), findsOneWidget);
  });
}
