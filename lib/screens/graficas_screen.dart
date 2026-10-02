import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/graficas.dart';
import '../services/supabase_service.dart';
import '../widgets/graficas.dart';
import '../widgets/ui.dart';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Gráficas del negocio, todas con datos reales: cómo está la cartera,
/// lo cobrado cada día, la ganancia de cada mes y lo prestado contra lo
/// cobrado. Recibe los préstamos que ya cargó Reportes.
class GraficasScreen extends StatefulWidget {
  final String prestamistaId;
  final List<Map<String, dynamic>> prestamos;

  const GraficasScreen({super.key, required this.prestamistaId, required this.prestamos});

  @override
  State<GraficasScreen> createState() => _GraficasScreenState();
}

class _GraficasScreenState extends State<GraficasScreen> {
  List<CobroGrafica>? _cobros;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final hoy = DateTime.now();
    // Lo que cubra 6 meses y 30 días, lo que sea más viejo.
    final seisMeses = DateTime(hoy.year, hoy.month - 5);
    final treintaDias = DateTime(hoy.year, hoy.month, hoy.day - 29);
    final desde = seisMeses.isBefore(treintaDias) ? seisMeses : treintaDias;
    try {
      final cobros = await SupabaseService.instance.obtenerCobrosGraficas(widget.prestamistaId, desde);
      if (mounted) setState(() => _cobros = cobros);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GRAFICAS: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gráficas del negocio')),
      body: _error != null
          ? Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar las gráficas.\n$_error')
          : _cobros == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: contenidoGraficas(widget.prestamos, _cobros!, DateTime.now()),
                  ),
                ),
    );
  }
}

/// Las 4 gráficas (aparte, para poder probarlas sin Supabase).
List<Widget> contenidoGraficas(
    List<Map<String, dynamic>> prestamos, List<CobroGrafica> cobros, DateTime hoy) {
  final enLaCalle = [
    for (final p in prestamos)
      if (p['estado'] == 'en_calle' && p['estado_calculado'] is EstadoPrestamo)
        p['estado_calculado'] as EstadoPrestamo
  ];
  final cartera = carteraPorEstado(enLaCalle, hoy);

  final porDia = cobradoPorDia(cobros, hoy);
  final totalDias = porDia.fold<double>(0, (s, d) => s + d.cuotas + d.mora);

  final porId = {for (final p in prestamos) p['id'] as String: p};
  final ganancia = gananciaPorMes(cobros, porId, hoy);
  final gananciaMes = ganancia.last.interes + ganancia.last.mora;

  final flujo = prestadoVsCobrado(prestamos, cobros, hoy);
  final totalPrestado = flujo.fold<double>(0, (s, m) => s + m.prestado);
  final totalCobrado = flujo.fold<double>(0, (s, m) => s + m.cobrado);

  String mesCorto(DateTime m) => _meses[m.month - 1];
  String mesLargo(DateTime m) => '${_meses[m.month - 1]} ${m.year}';

  return [
    BarraCartera(alDia: cartera.alDia, venceHoy: cartera.venceHoy, atrasado: cartera.atrasado),
    GraficaBarras(
      titulo: 'Lo que entró cada día · últimos 30 días',
      resumen: rd(totalDias.roundToDouble()),
      etiquetas: [for (final d in porDia) fechaCorta(d.dia)],
      // Una fecha cada semana, terminando en hoy.
      etiquetaEje: (i) => (porDia.length - 1 - i) % 7 == 0 ? fechaCorta(porDia[i].dia) : null,
      series: [
        SerieBarras('Cuotas', colorCuotas, [for (final d in porDia) d.cuotas]),
        SerieBarras('Mora', colorMora, [for (final d in porDia) d.mora]),
      ],
    ),
    GraficaBarras(
      titulo: 'Ganancia de cada mes · ${mesLargo(ganancia.last.mes)}',
      resumen: rd(gananciaMes.roundToDouble()),
      detalle: 'Interés de lo cobrado a cuotas, más la mora',
      etiquetas: [for (final m in ganancia) mesLargo(m.mes)],
      etiquetaEje: (i) => mesCorto(ganancia[i].mes),
      series: [
        SerieBarras('Interés', colorCuotas, [for (final m in ganancia) m.interes]),
        SerieBarras('Mora', colorMora, [for (final m in ganancia) m.mora]),
      ],
    ),
    GraficaBarras(
      titulo: 'Prestado contra cobrado · últimos 6 meses',
      resumen: 'Cobraste ${rd(totalCobrado.roundToDouble())}',
      detalle: 'Prestaste ${rd(totalPrestado.roundToDouble())} en los mismos meses',
      etiquetas: [for (final m in flujo) mesLargo(m.mes)],
      etiquetaEje: (i) => mesCorto(flujo[i].mes),
      apiladas: false,
      series: [
        SerieBarras('Prestado', colorPrestado, [for (final m in flujo) m.prestado]),
        SerieBarras('Cobrado', colorCuotas, [for (final m in flujo) m.cobrado]),
      ],
    ),
  ];
}
