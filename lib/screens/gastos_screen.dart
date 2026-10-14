import 'package:flutter/material.dart';

import '../logic/gastos.dart';
import '../logic/graficas.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formato_campos.dart' show soloNumeros;
import '../widgets/ui.dart';

const _mesesLargos = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "septiembre 2026"
String nombreMes(DateTime mes) => '${_mesesLargos[mes.month - 1]} ${mes.year}';

/// Reportes → Gastos: los gastos de un mes y la ganancia real
/// (interés cobrado + mora − gastos). Se puede ir a meses anteriores.
class GastosScreen extends StatefulWidget {
  final String prestamistaId;

  /// Los préstamos del prestamista (para saber qué parte de cada cobro es
  /// interés), los mismos que ya cargó Reportes.
  final List<Map<String, dynamic>> prestamos;

  const GastosScreen({super.key, required this.prestamistaId, required this.prestamos});

  @override
  State<GastosScreen> createState() => _GastosScreenState();
}

class _GastosScreenState extends State<GastosScreen> {
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  List<Gasto>? _gastos;
  ({double interes, double mora})? _ganado;

  late final _prestamosPorId = {
    for (final p in widget.prestamos) p['id'] as String: p,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  bool get _esEsteMes {
    final hoy = DateTime.now();
    return _mes.year == hoy.year && _mes.month == hoy.month;
  }

  Future<void> _cargar() async {
    final servicio = SupabaseService.instance;
    final mes = _mes;
    final finDeMes = DateTime(mes.year, mes.month + 1, 0);
    setState(() => _gastos = null);
    final gastos = await servicio.obtenerGastos(widget.prestamistaId, desde: mes, hasta: finDeMes);
    ({double interes, double mora}) ganado = (interes: 0, mora: 0);
    try {
      final cobros = await servicio.obtenerCobrosGraficas(widget.prestamistaId, mes);
      final g = gananciaPorMes(cobros, _prestamosPorId, mes, meses: 1).single;
      ganado = (interes: g.interes, mora: g.mora);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GANANCIA EN GASTOS: $e');
    }
    if (!mounted || mes != _mes) return;
    setState(() {
      _gastos = gastos;
      _ganado = ganado;
    });
  }

  void _cambiarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
    _cargar();
  }

  Future<void> _anotar() async {
    final listo = await anotarGasto(context, widget.prestamistaId,
        dia: _esEsteMes ? null : DateTime(_mes.year, _mes.month + 1, 0));
    if (listo) _cargar();
  }

  Future<void> _borrar(Gasto g) async {
    final mensajero = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Borrar este gasto?'),
        content: Text('${g.descripcion}: ${rd(g.monto)} del ${fechaLarga(g.fecha)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Borrar', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.borrarGasto(g.id!);
      mensajero.showSnackBar(const SnackBar(content: Text('Gasto borrado')));
      _cargar();
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo borrar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gastos = _gastos;
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos y ganancia real')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _anotar,
        icon: const Icon(Icons.add),
        label: const Text('Anotar gasto'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: () => _cambiarMes(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(nombreMes(_mes).toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: _esEsteMes ? null : () => _cambiarMes(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (gastos == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ...contenidoGastos(
                gastos: gastos,
                interes: _ganado?.interes ?? 0,
                mora: _ganado?.mora ?? 0,
                mes: _mes,
                onBorrar: _borrar,
              ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de ganancia real, gastos por categoría y la lista de gastos
/// (aparte, para poder probarlo sin Supabase).
List<Widget> contenidoGastos({
  required List<Gasto> gastos,
  required double interes,
  required double mora,
  required DateTime mes,
  void Function(Gasto)? onBorrar,
}) {
  final g = gananciaReal(interes: interes, mora: mora, gastos: totalGastos(gastos));
  final porCategoria = gastosPorCategoria(gastos);

  Widget linea(String texto, String valor, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(texto, style: TextStyle(color: AppColors.grey))),
            Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  return [
    Panel(
      borde: (g.real >= 0 ? AppColors.green : AppColors.red).withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GANANCIA REAL DE ${nombreMes(mes).toUpperCase()}',
              style: TextStyle(
                  color: g.real >= 0 ? AppColors.green : AppColors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(rd(g.real),
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: g.real >= 0 ? null : AppColors.red)),
          ),
          Text('Lo que te queda después de los gastos',
              style: TextStyle(color: AppColors.grey, fontSize: 12)),
          const Divider(height: 24),
          linea('+ Interés cobrado', rd(g.interes), AppColors.green),
          linea('+ Mora cobrada', rd(g.mora), AppColors.green),
          linea('− Gastos', rd(g.gastos), g.gastos > 0 ? AppColors.red : AppColors.grey),
        ],
      ),
    ),
    if (porCategoria.isNotEmpty) ...[
      const SizedBox(height: 8),
      const Text('En qué se fue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Panel(
        child: Column(
          children: [
            for (final c in porCategoria)
              linea(nombreCategoria(c.categoria), rd(c.total), AppColors.texto),
          ],
        ),
      ),
    ],
    const SizedBox(height: 8),
    Text('Gastos (${gastos.length})',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
    const SizedBox(height: 4),
    if (gastos.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No hay gastos anotados este mes. Toca "Anotar gasto" para agregar uno.',
            style: TextStyle(color: AppColors.grey)),
      ),
    for (final gasto in gastos)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Text(fechaCorta(gasto.fecha),
            style: TextStyle(color: AppColors.grey, fontSize: 12)),
        title: Text(gasto.descripcion,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rd(gasto.monto),
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.red)),
            if (onBorrar != null && gasto.id != null)
              IconButton(
                tooltip: 'Borrar',
                icon: Icon(Icons.delete_outline, color: AppColors.grey, size: 20),
                onPressed: () => onBorrar(gasto),
              ),
          ],
        ),
      ),
  ];
}

/// Pide los datos de un gasto y lo guarda. [dia]: la fecha que sale
/// puesta (hoy si es null). Devuelve true si se guardó.
Future<bool> anotarGasto(BuildContext context, String prestamistaId, {DateTime? dia}) async {
  final guardado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => FormularioGasto(prestamistaId: prestamistaId, dia: dia),
  );
  return guardado == true;
}

class FormularioGasto extends StatefulWidget {
  final String prestamistaId;
  final DateTime? dia;
  const FormularioGasto({super.key, required this.prestamistaId, this.dia});

  @override
  State<FormularioGasto> createState() => _FormularioGastoState();
}

class _FormularioGastoState extends State<FormularioGasto> {
  final _monto = TextEditingController();
  final _nota = TextEditingController();
  String _categoria = 'gasolina';
  late DateTime _fecha = widget.dia ?? DateTime.now();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(hoy.year - 1),
      lastDate: hoy,
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    final monto = double.tryParse(_monto.text.trim());
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Escribe cuánto gastaste');
      return;
    }
    final navegador = Navigator.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.agregarGasto(
        widget.prestamistaId,
        Gasto(
          fecha: DateTime(_fecha.year, _fecha.month, _fecha.day),
          monto: monto,
          categoria: _categoria,
          nota: _nota.text,
        ),
      );
      mensajero.showSnackBar(SnackBar(content: Text('Gasto de ${rd(monto)} anotado')));
      navegador.pop(true);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL ANOTAR GASTO: $e');
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar. ¿Corriste la migración de gastos? ($e)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final esHoy = _fecha.year == hoy.year && _fecha.month == hoy.month && _fecha.day == hoy.day;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Anotar gasto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _monto,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [soloNumeros],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: '¿Cuánto? (RD\$)',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (valor, texto) in categoriasGasto)
                  ChoiceChip(
                    label: Text(texto),
                    selected: _categoria == valor,
                    selectedColor: AppColors.greenDark,
                    labelStyle: TextStyle(
                        color: _categoria == valor ? AppColors.green : AppColors.grey,
                        fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(() => _categoria = valor),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nota,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Ej. la moto de Juan',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _guardando ? null : _elegirFecha,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(esHoy ? 'Hoy' : fechaLarga(_fecha)),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Guardar gasto'),
            ),
          ],
        ),
      ),
    );
  }
}
