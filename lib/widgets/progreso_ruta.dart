import 'package:flutter/material.dart';

import '../logic/ruta_del_dia.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// "Cobrados 7 de 15 · RD$X de RD$Y" con su barra: cuánto va de la ruta de hoy.
String textoProgresoRuta(ProgresoRuta p) =>
    'Cobrados ${p.cobrados} de ${p.total} · ${rd(p.montoCobrado)} de ${rd(p.montoTotal)}';

/// Barra de avance de la ruta de hoy, arriba de "Cobros del día".
class BarraProgresoRuta extends StatelessWidget {
  final ProgresoRuta progreso;
  const BarraProgresoRuta(this.progreso, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = progreso.completo ? AppColors.green : AppColors.amber;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(progreso.completo ? Icons.check_circle_rounded : Icons.route_rounded,
                  color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(textoProgresoRuta(progreso),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progreso.fraccion,
              minHeight: 10,
              color: AppColors.green,
              backgroundColor: AppColors.surfaceAlt,
            ),
          ),
        ],
      ),
    );
  }
}
