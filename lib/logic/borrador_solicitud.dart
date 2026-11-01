import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Borrador del formulario público de solicitud (/s/{slug}).
///
/// En teléfonos baratos, Chrome de Android a veces recarga la página al
/// abrir la cámara y el cliente perdía todo lo escrito. Por eso se guarda
/// en el navegador (localStorage, vía shared_preferences) lo que va
/// escribiendo: solo textos y opciones, nunca las fotos.

/// Cuánto tiempo se guarda un borrador. Pasado esto se borra solo.
const vigenciaBorrador = Duration(days: 2);

/// Clave del borrador en el navegador: una por link de prestamista.
String claveBorrador(String slug) => 'borrador_solicitud_$slug';

/// Lo que el cliente había escrito.
class BorradorSolicitud {
  /// Textos de los campos, por nombre del campo.
  final Map<String, String> textos;

  /// Opciones elegidas (vivienda, frecuencia, banco...), por nombre.
  final Map<String, Object?> opciones;

  /// En qué paso iba.
  final int paso;

  /// Cuándo se guardó.
  final DateTime guardado;

  const BorradorSolicitud({
    required this.textos,
    this.opciones = const {},
    this.paso = 0,
    required this.guardado,
  });

  /// Tiene algo escrito (las opciones solas no cuentan: vienen marcadas
  /// desde el principio).
  bool get tieneDatos => textos.values.any((t) => t.trim().isNotEmpty);

  String codificar() => jsonEncode({
        'guardado': guardado.toUtc().toIso8601String(),
        'paso': paso,
        'textos': textos,
        'opciones': opciones,
      });

  /// Lee un borrador guardado. Null si no hay, si está dañado, si no tiene
  /// nada escrito o si tiene más de [vigencia].
  static BorradorSolicitud? decodificar(String? texto, DateTime ahora,
      {Duration vigencia = vigenciaBorrador}) {
    if (texto == null || texto.isEmpty) return null;
    try {
      final datos = jsonDecode(texto);
      if (datos is! Map) return null;
      final guardado = DateTime.tryParse('${datos['guardado']}');
      final textos = datos['textos'];
      if (guardado == null || textos is! Map) return null;
      if (ahora.difference(guardado) > vigencia) return null;
      final opciones = datos['opciones'];
      final paso = datos['paso'];
      final borrador = BorradorSolicitud(
        textos: {
          for (final e in textos.entries)
            if (e.value is String) '${e.key}': e.value as String,
        },
        opciones: opciones is Map ? {for (final e in opciones.entries) '${e.key}': e.value} : {},
        paso: paso is int && paso >= 0 ? paso : 0,
        guardado: guardado,
      );
      return borrador.tieneDatos ? borrador : null;
    } catch (_) {
      return null;
    }
  }
}

/// Guarda el borrador (o lo borra si no tiene nada escrito). Si el
/// navegador no deja guardar, sigue sin borrador.
Future<void> guardarBorradorSolicitud(String slug, BorradorSolicitud borrador) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (borrador.tieneDatos) {
      await prefs.setString(claveBorrador(slug), borrador.codificar());
    } else {
      await prefs.remove(claveBorrador(slug));
    }
  } catch (_) {}
}

/// El borrador guardado de este link, si hay uno vigente. Los vencidos o
/// dañados se borran.
Future<BorradorSolicitud?> leerBorradorSolicitud(String slug, {DateTime? ahora}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(claveBorrador(slug));
    final borrador = BorradorSolicitud.decodificar(texto, ahora ?? DateTime.now());
    if (borrador == null && texto != null) await prefs.remove(claveBorrador(slug));
    return borrador;
  } catch (_) {
    return null;
  }
}

/// Borra el borrador (al enviar la solicitud o al empezar de nuevo).
Future<void> borrarBorradorSolicitud(String slug) async {
  try {
    await (await SharedPreferences.getInstance()).remove(claveBorrador(slug));
  } catch (_) {}
}
