import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'errores.dart';
import 'supabase_service.dart';

/// Aviso de "hay una versión nueva" en la app de Android (mientras no esté
/// en Google Play, que actualiza solo). El admin pone la última versión y el
/// enlace para bajarla en Admin → Ajustes.
class VersionNueva {
  static bool _yaAviso = false;

  /// true si [disponible] (ej. "1.0.7") es más nueva que [instalada] ("1.0.6").
  @visibleForTesting
  static bool esMasNueva(String disponible, String instalada) {
    List<int> partes(String v) =>
        v.trim().split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = partes(disponible);
    final b = partes(instalada);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Al entrar: si hay una versión más nueva, lo dice una vez por sesión.
  static Future<void> revisar(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || _yaAviso) return;
    try {
      final ajustes = await SupabaseService.instance.obtenerAjustes();
      final disponible = (ajustes?['apk_version'] as String?)?.trim() ?? '';
      final enlace = (ajustes?['apk_enlace'] as String?)?.trim() ?? '';
      if (disponible.isEmpty || enlace.isEmpty) return;
      final instalada = (await PackageInfo.fromPlatform()).version;
      if (!esMasNueva(disponible, instalada) || !context.mounted) return;
      _yaAviso = true;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hay una versión nueva'),
          content: Text('Tienes la $instalada y ya salió la $disponible, con arreglos y '
              'cosas nuevas. Bájala e instálala encima: no se pierde nada.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Después')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                launchUrl(Uri.parse(enlace), mode: LaunchMode.externalApplication);
              },
              child: const Text('Bajar ahora'),
            ),
          ],
        ),
      );
    } catch (e, pila) {
      registrarError(e, pila, 'VERSION NUEVA');
    }
  }
}
