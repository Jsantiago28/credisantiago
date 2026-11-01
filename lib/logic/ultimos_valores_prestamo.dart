import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'calculo_prestamo.dart' show TipoInteres;

/// Los valores que el prestamista usó en su último préstamo (interés,
/// plazo, frecuencia, mora y gracia), para no escribirlos cada vez. El
/// método de interés se guarda aparte (ver [guardarUltimoTipoInteres]): lo
/// cambian tanto Prestar como la Calculadora.

const _clave = 'ultimos_valores_prestamo';
const _claveTipo = 'ultimo_tipo_interes';
const _frecuencias = {'diario', 'semanal', 'quincenal', 'mensual'};

class UltimosValoresPrestamo {
  /// Interés mensual (%).
  final double tasa;

  /// El número del plazo tal como se escribió (en días o en meses).
  final int plazo;
  final bool enMeses;
  final String frecuencia;

  /// Mora diaria (%).
  final double mora;
  final int gracia;

  const UltimosValoresPrestamo({
    required this.tasa,
    required this.plazo,
    required this.enMeses,
    required this.frecuencia,
    required this.mora,
    required this.gracia,
  });

  String codificar() => jsonEncode({
        'tasa': tasa,
        'plazo': plazo,
        'en_meses': enMeses,
        'frecuencia': frecuencia,
        'mora': mora,
        'gracia': gracia,
      });

  /// Null si no hay nada guardado o si algo no tiene sentido.
  static UltimosValoresPrestamo? decodificar(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    try {
      final d = jsonDecode(texto);
      if (d is! Map) return null;
      final tasa = d['tasa'], plazo = d['plazo'], mora = d['mora'], gracia = d['gracia'];
      final frecuencia = d['frecuencia'];
      if (tasa is! num || tasa < 0) return null;
      if (plazo is! int || plazo < 1) return null;
      if (mora is! num || mora < 0) return null;
      if (gracia is! int || gracia < 0) return null;
      if (frecuencia is! String || !_frecuencias.contains(frecuencia)) return null;
      return UltimosValoresPrestamo(
        tasa: tasa.toDouble(),
        plazo: plazo,
        enMeses: d['en_meses'] == true,
        frecuencia: frecuencia,
        mora: mora.toDouble(),
        gracia: gracia,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Número sin ".0" si es entero (20 en vez de 20.0).
String numeroCorto(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

Future<UltimosValoresPrestamo?> leerUltimosValoresPrestamo() async {
  try {
    return UltimosValoresPrestamo.decodificar(
        (await SharedPreferences.getInstance()).getString(_clave));
  } catch (_) {
    return null;
  }
}

Future<void> guardarUltimosValoresPrestamo(UltimosValoresPrestamo v) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_clave, v.codificar());
  } catch (_) {}
}

/// El último método de interés que eligió el prestamista (al prestar o en
/// la calculadora). Null si nunca eligió o lo guardado no se entiende.
Future<TipoInteres?> leerUltimoTipoInteres() async {
  try {
    return TipoInteres.desdeValor((await SharedPreferences.getInstance()).getString(_claveTipo));
  } catch (_) {
    return null;
  }
}

Future<void> guardarUltimoTipoInteres(TipoInteres tipo) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_claveTipo, tipo.valor);
  } catch (_) {}
}
