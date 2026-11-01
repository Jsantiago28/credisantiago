import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Los colores de una de las dos formas de ver la app (clara u oscura).
class Paleta {
  final Brightness brillo;
  final Color background;
  final Color surface;

  /// Superficie un poco distinta, para cajas dentro de tarjetas.
  final Color surfaceAlt;

  /// Borde tenue de las tarjetas.
  final Color border;
  final Color green;

  /// Verde suave para fondos de íconos y etiquetas.
  final Color greenDark;
  final Color red;
  final Color redDark;

  /// Ámbar para lo que vence hoy (ni al día ni atrasado todavía).
  final Color amber;
  final Color amberDark;

  /// Letra principal.
  final Color texto;

  /// Letra secundaria (fechas, ayudas, etiquetas).
  final Color grey;

  /// Letra e íconos encima del verde (botones, el círculo de cobrar).
  final Color sobreVerde;

  const Paleta({
    required this.brillo,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.green,
    required this.greenDark,
    required this.red,
    required this.redDark,
    required this.amber,
    required this.amberDark,
    required this.texto,
    required this.grey,
    required this.sobreVerde,
  });

  /// Fondo negro y verde brillante: la de siempre, buena de noche.
  static const oscura = Paleta(
    brillo: Brightness.dark,
    background: Color(0xFF0D0F0E),
    surface: Color(0xFF17191A),
    surfaceAlt: Color(0xFF212524),
    border: Color(0xFF2A2F2D),
    green: Color(0xFF00E676),
    greenDark: Color(0xFF0F3D26),
    red: Color(0xFFFF5252),
    redDark: Color(0xFF4A1C1E),
    amber: Color(0xFFFFC857),
    amberDark: Color(0xFF3F3417),
    texto: Color(0xFFFFFFFF),
    grey: Color(0xFF9E9E9E),
    sobreVerde: Color(0xFF000000),
  );

  /// Fondo claro y tarjetas blancas: se lee mejor en la calle, a pleno sol.
  static const clara = Paleta(
    brillo: Brightness.light,
    background: Color(0xFFF3F5F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF1EF),
    border: Color(0xFFDCE2DF),
    // Verde más oscuro que el de la marca (#16A34A, 3.3:1): sobre blanco da
    // 5:1 y se lee a pleno sol, tanto en letras como con letra blanca encima
    // (botones).
    green: Color(0xFF15803D),
    greenDark: Color(0xFFDCFCE7),
    red: Color(0xFFDC2626),
    redDark: Color(0xFFFEE2E2),
    amber: Color(0xFFB45309),
    amberDark: Color(0xFFFEF3C7),
    texto: Color(0xFF111827),
    grey: Color(0xFF6B7280),
    sobreVerde: Color(0xFFFFFFFF),
  );
}

/// Colores de la app del prestamista y del cobrador. Salen de la paleta
/// que eligió quien usa el teléfono (ver [ModoColor]).
class AppColors {
  static Paleta _p = Paleta.clara;

  static Paleta get paleta => _p;
  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceAlt => _p.surfaceAlt;
  static Color get border => _p.border;
  static Color get green => _p.green;
  static Color get greenDark => _p.greenDark;
  static Color get red => _p.red;
  static Color get redDark => _p.redDark;
  static Color get amber => _p.amber;
  static Color get amberDark => _p.amberDark;
  static Color get texto => _p.texto;
  static Color get grey => _p.grey;
  static Color get sobreVerde => _p.sobreVerde;
}

/// Las dos formas de ver la app. Cada quien elige la suya en Perfil (o en
/// "Yo", el cobrador) y se recuerda en ese teléfono.
enum ModoColor {
  claro('Claro', Paleta.clara),
  oscuro('Oscuro', Paleta.oscura);

  final String nombre;
  final Paleta paleta;
  const ModoColor(this.nombre, this.paleta);

  /// La que ve quien abre la app por primera vez.
  static const deSiempre = ModoColor.claro;

  static const _clave = 'modo_color';

  /// El modo que está puesto ahora. La app se vuelve a dibujar cuando cambia.
  static final actual = ValueNotifier<ModoColor>(deSiempre);

  /// Lee el modo guardado en el teléfono (al abrir la app).
  static Future<void> cargar() async {
    try {
      final guardado = (await SharedPreferences.getInstance()).getString(_clave);
      _poner(ModoColor.values.firstWhere((m) => m.name == guardado, orElse: () => deSiempre));
    } catch (_) {
      _poner(deSiempre); // sin acceso al almacenamiento: el de siempre
    }
  }

  /// Cambia el modo, lo guarda y vuelve a dibujar toda la app.
  static Future<void> elegir(ModoColor modo) async {
    _poner(modo);
    _redibujarTodo();
    try {
      await (await SharedPreferences.getInstance()).setString(_clave, modo.name);
    } catch (_) {
      // Si no se pudo guardar, el cambio vale hasta que se cierre la app.
    }
  }

  static void _poner(ModoColor modo) {
    AppColors._p = modo.paleta;
    actual.value = modo;
  }

  /// Las pantallas leen los colores de [AppColors] al dibujarse: hay que
  /// pedirles a todas (también las de atrás) que se dibujen otra vez.
  static void _redibujarTodo() {
    void marcar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(marcar);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(marcar);
  }
}

class AppTheme {
  /// Tema de la app del prestamista y del cobrador, con la paleta elegida.
  static ThemeData app() {
    final p = AppColors.paleta;
    final oscuro = p.brillo == Brightness.dark;
    final base = oscuro ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      primaryColor: p.green,
      colorScheme: base.colorScheme.copyWith(
        primary: p.green,
        onPrimary: p.sobreVerde,
        secondary: p.green,
        onSecondary: p.sobreVerde,
        surface: p.surface,
        onSurface: p.texto,
        error: p.red,
        outline: p.border,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: p.texto,
        displayColor: p.texto,
      ),
      iconTheme: IconThemeData(color: p.texto),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.texto,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: oscuro ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: p.texto),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.green,
          side: BorderSide(color: p.green),
          minimumSize: const Size.fromHeight(48),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.green),
      ),
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: oscuro ? p.surfaceAlt : p.texto,
        contentTextStyle: TextStyle(color: oscuro ? p.texto : p.surface),
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.green,
          foregroundColor: p.sobreVerde,
          minimumSize: const Size.fromHeight(48),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.greenDark,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((estados) => GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: estados.contains(WidgetState.selected) ? p.green : p.grey,
            )),
        iconTheme: WidgetStateProperty.resolveWith((estados) => IconThemeData(
              color: estados.contains(WidgetState.selected) ? p.green : p.grey,
            )),
      ),
    );
  }

  /// Tema del formulario público del cliente (/s/{slug}): siempre claro y
  /// azul, sin importar lo que eligió el prestamista.
  static ThemeData formulario() {
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      primaryColor: const Color(0xFF1565C0),
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFF1565C0),
        secondary: Paleta.clara.green,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
