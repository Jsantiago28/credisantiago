import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui.dart';

// Colores de las series (validados contra el fondo de la app para
// daltonismo y contraste). Cada cosa tiene siempre el mismo color en
// todas las gráficas: cuotas/cobrado azul, mora naranja, prestado aqua.
// El verde, ámbar y rojo quedan para los estados (al día, hoy, atrasado).
const colorCuotas = Color(0xFF3987E5);
const colorMora = Color(0xFFD95926);
const colorPrestado = Color(0xFF199E70);

const _alto = 180.0;
const _linea = AppColors.border;

/// "12K", "2.5K", "1.2M" para los ejes (el título ya dice que son pesos).
String rdCorto(double v) {
  String corto(double x) => x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
  if (v >= 1000000) return '${corto(v / 1000000)}M';
  if (v >= 1000) return '${corto(v / 1000)}K';
  return v.toStringAsFixed(0);
}

/// Tope del eje redondeado (1, 2, 2.5 o 5 × 10ⁿ) y el paso entre rayas,
/// para que las marcas del eje sean números limpios.
({double tope, double paso}) ejeLimpio(double maximo, {int rayas = 4}) {
  if (maximo <= 0) return (tope: 1000, paso: 250);
  final crudo = maximo / rayas;
  final potencia = math.pow(10, (math.log(crudo) / math.ln10).floor()).toDouble();
  final paso = [1.0, 2.0, 2.5, 5.0, 10.0].map((m) => m * potencia).firstWhere((p) => p >= crudo);
  return (tope: paso * (maximo / paso).ceil(), paso: paso);
}

/// Una serie de barras: su nombre, su color y sus valores.
class SerieBarras {
  final String nombre;
  final Color color;
  final List<double> valores;
  const SerieBarras(this.nombre, this.color, this.valores);
}

/// Leyenda: una muestra del color al lado del nombre (el texto nunca va
/// en el color de la serie).
class Leyenda extends StatelessWidget {
  final List<(String, Color)> items;
  const Leyenda(this.items, {super.key});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final (nombre, color) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 6),
                Text(nombre, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
              ],
            ),
        ],
      );
}

/// Gráfica de columnas: apiladas (una sobre otra) o una al lado de la otra.
/// Al tocar una columna sale el detalle. "Ver números" la muestra en tabla.
class GraficaBarras extends StatefulWidget {
  final String titulo;

  /// El número grande de arriba (ej. "RD$84,500 en 30 días").
  final String resumen;

  /// Una línea debajo del número grande (opcional).
  final String? detalle;
  final List<String> etiquetas;

  /// Etiqueta del eje de abajo para la columna i (null = no se muestra).
  final String? Function(int i) etiquetaEje;
  final List<SerieBarras> series;
  final bool apiladas;

  const GraficaBarras({
    super.key,
    required this.titulo,
    required this.resumen,
    this.detalle,
    required this.etiquetas,
    required this.etiquetaEje,
    required this.series,
    this.apiladas = true,
  });

  @override
  State<GraficaBarras> createState() => _GraficaBarrasState();
}

class _GraficaBarrasState extends State<GraficaBarras> {
  bool _tabla = false;

  double _total(int i) => widget.series.fold(0.0, (s, x) => s + x.valores[i]);

  @override
  Widget build(BuildContext context) {
    final n = widget.etiquetas.length;
    final maximo = widget.apiladas
        ? List.generate(n, _total).fold(0.0, math.max)
        : widget.series.expand((s) => s.valores).fold(0.0, math.max);
    final eje = ejeLimpio(maximo);
    // Espacio de 2px entre los pedazos de una columna apilada.
    final hueco = eje.tope * 2 / _alto;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.titulo, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
          const SizedBox(height: 2),
          Text(widget.resumen,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (widget.detalle != null)
            Text(widget.detalle!, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          if (widget.series.length > 1) ...[
            Leyenda([for (final s in widget.series) (s.nombre, s.color)]),
            const SizedBox(height: 12),
          ],
          if (_tabla) _tablaNumeros() else _grafica(n, eje, hueco),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _tabla = !_tabla),
              child: Text(_tabla ? 'Ver gráfica' : 'Ver números'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grafica(int n, ({double tope, double paso}) eje, double hueco) {
    return LayoutBuilder(builder: (context, medidas) {
      // Barras finas: nunca más de 24px, y aire entre una y otra.
      final porGrupo = (medidas.maxWidth - 36) / n;
      final grosor = widget.apiladas
          ? math.min(24.0, math.max(3.0, porGrupo * 0.6))
          : math.min(24.0, math.max(3.0, porGrupo * 0.6 / widget.series.length));

      BarChartRodData barra(double desde, double hasta, Color color) => BarChartRodData(
            fromY: desde,
            toY: hasta,
            color: color,
            width: grosor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(4, grosor / 2))),
          );

      final grupos = [
        for (var i = 0; i < n; i++)
          BarChartGroupData(
            x: i,
            barsSpace: 2,
            barRods: widget.apiladas
                ? [
                    () {
                      var base = 0.0;
                      final pedazos = <BarChartRodStackItem>[];
                      for (final s in widget.series) {
                        final v = s.valores[i];
                        if (v <= 0) continue;
                        final desde = pedazos.isEmpty ? 0.0 : base + hueco;
                        pedazos.add(BarChartRodStackItem(desde, desde + v, s.color));
                        base = desde + v;
                      }
                      return BarChartRodData(
                        toY: base,
                        width: grosor,
                        color: Colors.transparent,
                        rodStackItems: pedazos,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(math.min(4, grosor / 2))),
                      );
                    }(),
                  ]
                : [for (final s in widget.series) barra(0, s.valores[i], s.color)],
          ),
      ];

      return SizedBox(
        height: _alto,
        child: BarChart(
          BarChartData(
            maxY: eje.tope * 1.02,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            barGroups: grupos,
            borderData: FlBorderData(
              show: true,
              border: const Border(bottom: BorderSide(color: _linea)),
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: eje.paso,
              getDrawingHorizontalLine: (_) => const FlLine(color: _linea, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: eje.paso,
                  getTitlesWidget: (v, meta) => v > eje.tope + 0.001
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          child: Text(rdCorto(v),
                              style: const TextStyle(color: AppColors.grey, fontSize: 10)),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, meta) {
                    final texto = widget.etiquetaEje(v.toInt());
                    if (texto == null) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(texto,
                          style: const TextStyle(color: AppColors.grey, fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.surfaceAlt,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (grupo, i, rod, r) {
                  final lineas = [
                    for (final s in widget.series) '${s.nombre}: ${rd(s.valores[i])}',
                    if (widget.apiladas && widget.series.length > 1) 'Total: ${rd(_total(i))}',
                  ];
                  return BarTooltipItem(
                    '${widget.etiquetas[i]}\n',
                    const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 12),
                    children: [
                      TextSpan(
                        text: lineas.join('\n'),
                        style: const TextStyle(
                            color: AppColors.grey, fontWeight: FontWeight.w500, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
  }

  /// Los mismos números en una tabla (lo más reciente arriba).
  Widget _tablaNumeros() {
    const estilo = TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]);
    final filas = [
      for (var i = widget.etiquetas.length - 1; i >= 0; i--)
        if (_total(i) > 0 || !widget.apiladas) i
    ];
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: SizedBox()),
            for (final s in widget.series)
              SizedBox(
                width: 90,
                child: Text(s.nombre,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.grey, fontSize: 12)),
              ),
          ],
        ),
        const Divider(height: 12),
        if (filas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Sin cobros en este tiempo', style: TextStyle(color: AppColors.grey)),
          ),
        for (final i in filas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(widget.etiquetas[i], style: estilo)),
                for (final s in widget.series)
                  SizedBox(
                    width: 90,
                    child: Text(rd(s.valores[i]), textAlign: TextAlign.right, style: estilo),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La cartera en una sola barra: al día, vence hoy y atrasado, cada parte
/// del largo de su dinero, con su ícono, nombre, monto y porcentaje abajo.
class BarraCartera extends StatelessWidget {
  final double alDia;
  final double venceHoy;
  final double atrasado;

  const BarraCartera({
    super.key,
    required this.alDia,
    required this.venceHoy,
    required this.atrasado,
  });

  @override
  Widget build(BuildContext context) {
    final total = alDia + venceHoy + atrasado;
    final partes = [
      (Icons.check_circle_rounded, 'Al día', alDia, AppColors.green),
      (Icons.today_rounded, 'Vence hoy', venceHoy, AppColors.amber),
      (Icons.warning_amber_rounded, 'Atrasado', atrasado, AppColors.red),
    ];
    final conValor = partes.where((p) => p.$3 > 0).toList();

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cómo está tu dinero en la calle',
              style: TextStyle(color: AppColors.grey, fontSize: 13)),
          const SizedBox(height: 2),
          Text(rd(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (total <= 0)
            const Text('No tienes dinero en la calle ahora.',
                style: TextStyle(color: AppColors.grey))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    for (var i = 0; i < conValor.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        // Al menos un poquito, para que una parte pequeña se vea.
                        flex: math.max(1, (conValor[i].$3 / total * 1000).round()),
                        child: Container(color: conValor[i].$4),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final (icono, nombre, valor, color) in partes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(icono, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(child: Text(nombre)),
                    Text(rd(valor), style: const TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(
                      width: 48,
                      child: Text('${(valor / total * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: AppColors.grey)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
