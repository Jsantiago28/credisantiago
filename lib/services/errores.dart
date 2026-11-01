import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'sin_conexion.dart';
import 'supabase_service.dart';

/// Un error que la app esperaba: anota el detalle en la consola y, si no es
/// solo falta de internet, se lo manda al admin (ver [Errores.reportar]).
/// [donde]: qué se estaba haciendo (ej. 'COBRAR'), para encontrarlo rápido.
void registrarError(Object e, StackTrace? pila, String donde) {
  // ignore: avoid_print
  print('ERROR REAL $donde: $e');
  if (SinConexion.esFaltaDeConexion(e)) return; // sin señal no es un error de la app
  Errores.reportar(e, pila, donde: donde);
}

/// Un error que la app conoce y que ya trae un mensaje claro para el
/// usuario (ej. "Ya tienes un cliente con esa cédula").
abstract class AvisoParaUsuario implements Exception {
  const AvisoParaUsuario();

  /// Lo que se le muestra al usuario.
  String get mensaje;

  @override
  String toString() => mensaje;
}

/// Lo que se le dice al usuario cuando algo falla: sin el texto técnico del
/// error (ese va al admin con [registrarError]).
String mensajeError(Object e) {
  if (SinConexion.esFaltaDeConexion(e)) return 'Sin internet. Intenta de nuevo.';
  if (e is AvisoParaUsuario) return e.mensaje;
  if (e is StateError) return e.message;
  return 'Algo salió mal. Intenta de nuevo.';
}

/// Guarda en la base de datos (tabla errores_app) los errores que la app no
/// esperaba, para que el admin se entere sin que nadie avise. No manda datos
/// de clientes: solo el mensaje del error, dónde pasó, la versión y si fue en
/// la web o en Android.
class Errores {
  /// Como mucho tantos reportes por vez que se abre la app (si algo falla en
  /// bucle, no se llena la tabla).
  static const _maximo = 15;
  static int _enviados = 0;
  static final _vistos = <String>{};
  static String _version = '';

  /// Al abrir la app: empieza a escuchar los errores.
  static Future<void> iniciar() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    final anterior = FlutterError.onError;
    FlutterError.onError = (detalles) {
      anterior?.call(detalles);
      reportar(detalles.exception, detalles.stack, donde: detalles.library);
    };
    PlatformDispatcher.instance.onError = (error, pila) {
      reportar(error, pila);
      return true; // ya se reportó: que la app siga
    };
  }

  /// Marca de los reportes que escribe el usuario ("Reportar un problema"),
  /// para que el admin los distinga de los errores automáticos.
  static const pantallaReporte = 'Reporte del usuario';

  /// El usuario cuenta un problema con sus palabras: le llega al admin en
  /// "Errores de la app". [quien]: nombre y correo de quien lo manda.
  /// Este sí falla si no se pudo enviar (para avisarle al usuario).
  static Future<void> reportarProblema(String texto, {required String quien}) async {
    await SupabaseService.instance.client.from('errores_app').insert({
      'mensaje': recortar(texto.trim(), 2000),
      'detalle': recortar('De: $quien', 8000),
      'pantalla': pantallaReporte,
      'version': recortar(_version, 50),
      'plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
    });
  }

  /// Manda un error (sin esperar y sin fallar nunca).
  static void reportar(Object error, StackTrace? pila, {String? donde}) {
    final mensaje = recortar('$error', 2000);
    // El mismo error una sola vez por sesión, y no más de [_maximo].
    if (_enviados >= _maximo || !_vistos.add(mensaje)) return;
    _enviados++;
    unawaited(_enviar(mensaje, pila, donde));
  }

  static Future<void> _enviar(String mensaje, StackTrace? pila, String? donde) async {
    try {
      await SupabaseService.instance.client.from('errores_app').insert({
        'mensaje': mensaje,
        'detalle': pila == null ? null : recortar('$pila', 8000),
        'pantalla': donde,
        'version': _version,
        'plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });
    } catch (_) {
      // Sin internet o sin la tabla todavía: no se puede hacer nada.
    }
  }

  /// [texto] cortado a [largo] caracteres (la tabla no acepta más).
  @visibleForTesting
  static String recortar(String texto, int largo) =>
      texto.length <= largo ? texto : texto.substring(0, largo);
}
