import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestamistas_rd/theme/app_theme.dart';
import 'package:prestamistas_rd/widgets/selector_colores.dart';
import 'package:prestamistas_rd/widgets/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ModoColor.elegir(ModoColor.deSiempre));

  test('la primera vez la app sale clara', () async {
    await ModoColor.cargar();
    expect(ModoColor.actual.value, ModoColor.claro);
    expect(AppColors.background, Paleta.clara.background);
    expect(AppColors.paleta.brillo, Brightness.light);
  });

  test('el modo elegido se guarda y se recuerda al abrir otra vez', () async {
    await ModoColor.elegir(ModoColor.oscuro);
    expect(AppColors.texto, Paleta.oscura.texto);
    expect(AppColors.paleta.brillo, Brightness.dark);

    // Como si se cerrara la app: vuelve al de siempre y luego lee el guardado.
    await ModoColor.elegir(ModoColor.claro);
    SharedPreferences.setMockInitialValues({'modo_color': 'oscuro'});
    await ModoColor.cargar();
    expect(ModoColor.actual.value, ModoColor.oscuro);
  });

  test('las etiquetas de estado toman los colores del modo', () async {
    await ModoColor.elegir(ModoColor.claro);
    expect(EstadoCobro.atrasado.color, Paleta.clara.red);
    await ModoColor.elegir(ModoColor.oscuro);
    expect(EstadoCobro.atrasado.color, Paleta.oscura.red);
  });

  testWidgets('las tarjetas tienen sombra suave solo en el modo claro', (tester) async {
    List<BoxShadow>? sombra() => (tester
            .widget<DecoratedBox>(find
                .ancestor(of: find.text('tarjeta'), matching: find.byType(DecoratedBox))
                .last)
            .decoration as BoxDecoration)
        .boxShadow;

    await ModoColor.elegir(ModoColor.claro);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Panel(child: Text('tarjeta')))));
    expect(sombra(), isNotEmpty);

    await ModoColor.elegir(ModoColor.oscuro);
    await tester.pumpAndSettle();
    expect(sombra(), isNull);
  });

  testWidgets('el selector cambia de claro a oscuro y redibuja', (tester) async {
    await ModoColor.elegir(ModoColor.claro);
    await tester.pumpWidget(ValueListenableBuilder<ModoColor>(
      valueListenable: ModoColor.actual,
      builder: (_, __, ___) => MaterialApp(
        // Sin AppTheme.app(): su letra se baja de internet y en las pruebas no hay.
        theme: ThemeData(brightness: AppColors.paleta.brillo),
        home: Scaffold(
          body: Column(children: [
            const SelectorColores(),
            Builder(builder: (_) => ColoredBox(color: AppColors.surface, child: const Text('caja'))),
          ]),
        ),
      ),
    ));
    ColoredBox caja() => tester.widget<ColoredBox>(find.ancestor(
        of: find.text('caja'), matching: find.byType(ColoredBox)).first);
    expect(caja().color, Paleta.clara.surface);

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(ModoColor.actual.value, ModoColor.oscuro);
    expect(caja().color, Paleta.oscura.surface);
  });
}
