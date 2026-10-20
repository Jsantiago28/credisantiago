import 'package:flutter/material.dart';

import '../services/sin_conexion.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Arriba del Inicio: si no hay señal (y desde cuándo es la ruta que se ve)
/// y cuántos cobros faltan por subir. No se ve si todo está al día.
class AvisoSinConexion extends StatelessWidget {
  const AvisoSinConexion({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [SinConexion.sinSenal, SinConexion.pendientes, SinConexion.rutaGuardadaDe]),
      builder: (context, _) {
        final sinSenal = SinConexion.sinSenal.value;
        final pendientes = SinConexion.pendientes.value;
        final ruta = SinConexion.rutaGuardadaDe.value;
        if (!sinSenal && pendientes == 0) return const SizedBox.shrink();
        final lineas = [
          if (sinSenal)
            ruta == null
                ? 'Sin señal.'
                : 'Sin señal: ves la ruta guardada a las ${_hora(ruta)}'
                    '${_esHoy(ruta) ? '' : ' del ${fechaCorta(ruta)}'}.',
          if (pendientes > 0)
            '$pendientes cobro${pendientes == 1 ? '' : 's'} sin subir: '
                '${sinSenal ? 'se suben solos cuando vuelva la señal' : 'subiendo…'}.',
          if (sinSenal) 'Solo se puede cobrar. Prestar, anular o saldar esperan al internet.',
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            borde: AppColors.amber.withValues(alpha: 0.6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(sinSenal ? Icons.cloud_off_rounded : Icons.cloud_upload_rounded,
                    color: AppColors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(lineas.join('\n'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _hora(DateTime f) {
    final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
    return '$h:${f.minute.toString().padLeft(2, '0')} ${f.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  static bool _esHoy(DateTime f) {
    final hoy = DateTime.now();
    return f.year == hoy.year && f.month == hoy.month && f.day == hoy.day;
  }
}
