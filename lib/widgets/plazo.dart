import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Días que dura un plazo escrito en días o en meses (1 mes = 30 días,
/// igual que el interés).
int diasDelPlazo(int valor, {required bool enMeses}) => enMeses ? valor * 30 : valor;

/// Cambia el número escrito al pasar de días a meses o al revés (90 días ↔
/// 3 meses), para que el plazo siga siendo el mismo.
String convertirPlazo(String texto, {required bool aMeses}) {
  final valor = int.tryParse(texto);
  if (valor == null || valor <= 0) return texto;
  return aMeses ? '${(valor / 30).round().clamp(1, 1200)}' : '${valor * 30}';
}

/// Elegir si el plazo se escribe en días o en meses.
class SelectorUnidadPlazo extends StatelessWidget {
  final bool enMeses;
  final ValueChanged<bool> onCambio;
  const SelectorUnidadPlazo({super.key, required this.enMeses, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('Días')),
        ButtonSegment(value: true, label: Text('Meses')),
      ],
      selected: {enMeses},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onCambio(s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.greenDark,
        selectedForegroundColor: AppColors.green,
        foregroundColor: AppColors.grey,
        side: BorderSide(color: AppColors.border),
      ),
    );
  }
}

/// Tabla de amortización de un plan: fecha, cuota, interés, capital y lo
/// que queda debiendo después de cada cuota. Con muchas cuotas (ej. diario)
/// muestra las primeras y deja ver todas con un botón.
class TablaAmortizacion extends StatefulWidget {
  final PlanPrestamo plan;
  final String frecuencia;

  /// Día del préstamo: la primera cuota vence un período después.
  final DateTime desde;

  const TablaAmortizacion(
      {super.key, required this.plan, required this.frecuencia, required this.desde});

  @override
  State<TablaAmortizacion> createState() => _TablaAmortizacionState();
}

class _TablaAmortizacionState extends State<TablaAmortizacion> {
  static const _primeras = 12;
  bool _todas = false;

  @override
  Widget build(BuildContext context) {
    final filas = widget.plan.filas;
    final visibles = _todas || filas.length <= _primeras ? filas : filas.take(_primeras).toList();
    final chico = TextStyle(fontSize: 12, color: AppColors.texto);
    final titulo = TextStyle(fontSize: 11, color: AppColors.grey, fontWeight: FontWeight.w700);

    DataCell celda(String texto, {bool fuerte = false}) => DataCell(Text(texto,
        style: fuerte ? chico.copyWith(fontWeight: FontWeight.w800) : chico));

    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tabla de amortización', style: TextStyle(fontWeight: FontWeight.w800)),
          Text(
            'Interés ${widget.plan.tipo.nombre}. Cada cuota paga primero el interés y el '
            'resto baja lo que se debe.',
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          // De lado: en el teléfono la tabla se desliza a la izquierda.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 32,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 32,
              columnSpacing: 16,
              horizontalMargin: 4,
              columns: [
                for (final c in ['#', 'Fecha', 'Cuota', 'Interés', 'Capital', 'Debe'])
                  DataColumn(label: Text(c, style: titulo), numeric: c != 'Fecha'),
              ],
              rows: [
                for (final f in visibles)
                  DataRow(cells: [
                    celda('${f.numero}'),
                    celda(fechaLarga(fechaCuota(widget.desde, widget.frecuencia, f.numero))),
                    celda(rd(f.cuota), fuerte: true),
                    celda(rd(f.interes)),
                    celda(rd(f.capital)),
                    celda(rd(f.saldo)),
                  ]),
              ],
            ),
          ),
          if (filas.length > _primeras)
            TextButton(
              onPressed: () => setState(() => _todas = !_todas),
              child: Text(_todas ? 'Ver menos' : 'Ver las ${filas.length} cuotas'),
            ),
          const Divider(),
          Text(
            'Total: ${rd(widget.plan.montoTotal)} · interés ${rd(widget.plan.interesTotal)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
