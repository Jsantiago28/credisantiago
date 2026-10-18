import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'supabase_service.dart';

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
