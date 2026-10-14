import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/caja.dart';
import '../logic/cobradores.dart';
import '../logic/gastos.dart';
import '../recibos/recibo_pdf.dart' show numeroReciboTexto;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/formato_campos.dart' show soloNumeros;
import '../widgets/ui.dart';
import 'gastos_screen.dart' show anotarGasto;

const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "Hoy", "Ayer" o "lun 21 sep".
String nombreDia(DateTime dia, {DateTime? hoy}) {
  final h = hoy ?? DateTime.now();
  final hoySinHora = DateTime(h.year, h.month, h.day);
  final diferencia = hoySinHora.difference(DateTime(dia.year, dia.month, dia.day)).inDays;
  if (diferencia == 0) return 'Hoy';
  if (diferencia == 1) return 'Ayer';
  return '${_dias[dia.weekday - 1]} ${fechaCorta(dia)}';
}

/// Fila de un día de caja (se usa en Reportes y en la lista completa).
class FilaDiaCaja extends StatelessWidget {
  final DiaCaja dia;
  final Map<String, dynamic>? cierre;
  final VoidCallback onTap;

  const FilaDiaCaja({super.key, required this.dia, required this.cierre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombreDia(dia.dia),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                  dia.cantidad == 0
                      ? 'Sin cobros'
                      : '${dia.cantidad} cobro(s)${dia.mora > 0 ? ' · mora ${rd(dia.mora)}' : ''}',
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(rd(dia.total),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          if (cierre != null)
            const Pildora('CERRADO ✓')
          else
            Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }
}

/// Todos los días con cobros (hasta un año) y sus cierres.
class CajaScreen extends StatefulWidget {
  final String prestamistaId;
  const CajaScreen({super.key, required this.prestamistaId});

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  List<DiaCaja>? _dias;
  Map<String, Map<String, dynamic>> _cierres = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final servicio = SupabaseService.instance;
    try {
      final hoy = DateTime.now();
      final cobros = await servicio.obtenerCobrosCaja(widget.prestamistaId,
          desde: DateTime(hoy.year - 1, hoy.month, hoy.day));
      Map<String, Map<String, dynamic>> cierres = const {};
      try {
        cierres = await servicio.obtenerCierres(widget.prestamistaId);
      } catch (_) {
        // Sin la tabla de cierres (migración pendiente) la caja se ve igual.
      }
      final dias = cajaPorDia(cobros);
      // Días que solo tienen cierre (cobros de hace más de un año).
      final conCobros = dias.map((d) => claveDia(d.dia)).toSet();
      for (final clave in cierres.keys) {
        if (!conCobros.contains(clave)) dias.add(DiaCaja(DateTime.parse(clave), const []));
      }
      dias.sort((a, b) => b.dia.compareTo(a.dia));
      if (mounted) {
        setState(() {
          _dias = dias;
          _cierres = cierres;
          _error = null;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL CAJA: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dias = _dias;
    return Scaffold(
      appBar: AppBar(title: const Text('Caja por día')),
      body: dias == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar la caja.\n$_error'))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: dias.isEmpty
                  ? ListView(children: const [
                      Vacio(icono: Icons.payments_outlined, texto: 'Todavía no hay cobros.'),
                    ])
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final d in dias)
                          FilaDiaCaja(
                            dia: d,
                            cierre: _cierres[claveDia(d.dia)],
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => CajaDiaScreen(
                                  prestamistaId: widget.prestamistaId,
                                  dia: d,
                                  cierre: _cierres[claveDia(d.dia)],
                                ),
                              ));
                              _cargar(); // pudo cerrar o borrar el cierre
                            },
                          ),
                      ],
                    ),
            ),
    );
  }
}

/// Detalle de un día: total, cuotas y mora, cada cobro, cerrar caja o
/// borrar el cierre, y compartir el resumen por WhatsApp.
class CajaDiaScreen extends StatefulWidget {
  final String prestamistaId;
  final DiaCaja dia;
  final Map<String, dynamic>? cierre;

  /// Gastos del día. Si es null, la pantalla los busca.
  final List<Gasto>? gastos;

  /// Cobradores y sus entregas de ese día. Si son null, la pantalla los busca.
  final List<Cobrador>? cobradores;
  final Map<String, Entrega>? entregas;

  const CajaDiaScreen({
    super.key,
    required this.prestamistaId,
    required this.dia,
    required this.cierre,
    this.gastos,
    this.cobradores,
    this.entregas,
  });

  @override
  State<CajaDiaScreen> createState() => _CajaDiaScreenState();
}

class _CajaDiaScreenState extends State<CajaDiaScreen> {
  late Map<String, dynamic>? _cierre = widget.cierre;
  late List<Gasto> _gastos = widget.gastos ?? const [];
  late List<Cobrador> _cobradores = widget.cobradores ?? const [];
  late Map<String, Entrega> _entregas = widget.entregas ?? const {};
  bool _trabajando = false;

  DiaCaja get _d => widget.dia;

  Map<String, String> get _nombres => {for (final c in _cobradores) c.id: c.nombre};

  @override
  void initState() {
    super.initState();
    if (widget.gastos == null) _cargarGastos();
    if (widget.cobradores == null) _cargarCobradores();
  }

  Future<void> _cargarCobradores() async {
    final servicio = SupabaseService.instance;
    final cobradores = await servicio.listarCobradores(widget.prestamistaId);
    final entregas = cobradores.isEmpty
        ? const <String, Entrega>{}
        : await servicio.obtenerEntregas(widget.prestamistaId, _d.dia);
    if (mounted) {
      setState(() {
        _cobradores = cobradores;
        _entregas = entregas;
      });
    }
  }

  /// Anota lo que el cobrador entregó; la app dice si cuadra con lo cobrado.
  Future<void> _anotarEntrega(String cobradorId, double cobrado) async {
    final nombre = _nombres[cobradorId] ?? 'el cobrador';
    final antes = _entregas[cobradorId];
    final monto = TextEditingController(text: (antes?.entregado ?? cobrado).toStringAsFixed(0));
    final nota = TextEditingController(text: antes?.nota ?? '');
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) {
          final entregado = double.tryParse(monto.text.trim());
          final c = entregado == null ? null : cuadre(cobrado: cobrado, entregado: entregado);
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Entrega de ${nombre.split(' ').first}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cobró ${rd(cobrado)} el ${fechaLarga(_d.dia)}.',
                    style: TextStyle(color: AppColors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: monto,
                  keyboardType: TextInputType.number,
                  inputFormatters: [soloNumeros],
                  onChanged: (_) => setEstado(() {}),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(labelText: '¿Cuánto te entregó? (RD\$)'),
                ),
                if (c != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(c.texto,
                        style: TextStyle(fontWeight: FontWeight.w800, color: _colorCuadre(c.diferencia))),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: nota,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    hintText: 'Ej. mañana trae lo que falta',
                  ),
                ),
              ],
            ),
            actions: [
              if (antes != null)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('borrar'),
                  child: Text('Borrar', style: TextStyle(color: AppColors.red)),
                ),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              TextButton(
                onPressed: entregado == null ? null : () => Navigator.of(ctx).pop('guardar'),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    if (accion == null || !mounted) return;
    final servicio = SupabaseService.instance;
    await _hacer(() async {
      if (accion == 'borrar') {
        await servicio.borrarEntrega(antes!.id!);
      } else {
        await servicio.guardarEntrega(
          widget.prestamistaId,
          Entrega(
            cobradorId: cobradorId,
            fecha: _d.dia,
            cobrado: cobrado,
            entregado: double.parse(monto.text.trim()),
            nota: nota.text,
          ),
        );
      }
      _entregas = await servicio.obtenerEntregas(widget.prestamistaId, _d.dia);
    }, accion == 'borrar' ? 'Entrega borrada' : 'Entrega de $nombre anotada');
  }

  Color _colorCuadre(double diferencia) => diferencia == 0
      ? AppColors.green
      : diferencia < 0
          ? AppColors.red
          : AppColors.amber;

  /// Cuánto cobró cada cobrador (y tú), y si ya te entregó.
  Widget _porCobrador() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const Text('Por cobrador', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final f in cajaPorCobrador(_d)) _filaCobrador(f.cobradorId, f.total, f.cantidad),
      ],
    );
  }

  Widget _filaCobrador(String? cobradorId, double total, int cantidad) {
    final entrega = cobradorId == null ? null : _entregas[cobradorId];
    final c = entrega == null ? null : cuadre(cobrado: total, entregado: entrega.entregado);
    final color = c == null ? AppColors.grey : _colorCuadre(c.diferencia);
    final cambio = entrega != null && (entrega.cobrado - total).abs() >= 0.5;
    final nota = entrega?.nota?.trim() ?? '';
    return Panel(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borde: c == null ? null : color.withValues(alpha: 0.5),
      onTap: cobradorId == null || _trabajando ? null : () => _anotarEntrega(cobradorId, total),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cobradorId == null ? 'Tú' : (_nombres[cobradorId] ?? 'Cobrador'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('$cantidad cobro(s)',
                        style: TextStyle(color: AppColors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Text(rd(total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          if (cobradorId != null) ...[
            const SizedBox(height: 6),
            if (entrega == null)
              Text('Toca para anotar lo que te entregó',
                  style: TextStyle(
                      color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w700))
            else
              Text('Te entregó ${rd(entrega.entregado)} · ${c!.texto}',
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
            if (cambio)
              Text(
                  'Cuando te entregó había cobrado ${rd(entrega.cobrado)}; ahora suma ${rd(total)}. '
                  'Se anuló o se agregó un cobro después.',
                  style: TextStyle(color: AppColors.amber, fontSize: 12)),
            if (nota.isNotEmpty)
              Text('Nota: $nota', style: TextStyle(color: AppColors.grey, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Future<void> _cargarGastos() async {
    final gastos = await SupabaseService.instance
        .obtenerGastos(widget.prestamistaId, desde: _d.dia, hasta: _d.dia);
    if (mounted) setState(() => _gastos = gastos);
  }

  Future<void> _anotarGasto() async {
    if (await anotarGasto(context, widget.prestamistaId, dia: _d.dia)) _cargarGastos();
  }

  String _hora(DateTime f) {
    final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
    return '$h:${f.minute.toString().padLeft(2, '0')} ${f.hour < 12 ? 'am' : 'pm'}';
  }

  Future<void> _cerrar() async {
    final nota = TextEditingController(text: _cierre?['nota'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(_cierre == null ? 'Cerrar caja de ${nombreDia(_d.dia).toLowerCase()}'
            : 'Actualizar el cierre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se guarda: ${rd(_d.total)} en ${_d.cantidad} cobro(s).',
                style: TextStyle(color: AppColors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: nota,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Ej. le entregué RD\$8,000 a Juan',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cerrar caja')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _hacer(() async {
      await SupabaseService.instance.cerrarCaja(widget.prestamistaId, _d, nota: nota.text);
      final cierres = await SupabaseService.instance.obtenerCierres(widget.prestamistaId);
      _cierre = cierres[claveDia(_d.dia)];
    }, 'Caja cerrada');
  }

  Future<void> _borrarCierre() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Borrar este cierre?'),
        content: const Text(
            'Se borra solo el resumen guardado. Los cobros del día no se tocan: '
            'siguen en cada préstamo y en esta caja.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Borrar cierre', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _hacer(() async {
      await SupabaseService.instance.borrarCierre(_cierre!['id'] as String);
      _cierre = null;
    }, 'Cierre borrado');
  }

  Future<void> _hacer(Future<void> Function() accion, String listo) async {
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _trabajando = true);
    try {
      await accion();
      mensajero.showSnackBar(SnackBar(content: Text(listo)));
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL CIERRE: $e');
      mensajero.showSnackBar(SnackBar(
          content: Text('No se pudo. ¿Corriste la migración de cierres de caja? ($e)')));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _compartir() async {
    final perfil = await SupabaseService.instance.obtenerMiPerfil();
    await Share.share(resumenCajaTexto(
      _d,
      negocio: (perfil?['nombre'] as String?) ?? 'Prestamistas RD',
      nota: _cierre?['nota'] as String?,
      gastos: _gastos,
      nombresCobradores: _nombres,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cierre = _cierre;
    final totalCierre = (cierre?['total'] as num?)?.toDouble();
    final cambio = totalCierre != null && (totalCierre - _d.total).abs() >= 0.01;
    final gastado = totalGastos(_gastos);

    return Scaffold(
      appBar: AppBar(title: Text('Caja · ${nombreDia(_d.dia)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Panel(
            borde: AppColors.green.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RECIBIDO EL ${fechaLarga(_d.dia).toUpperCase()}',
                    style: TextStyle(
                        color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                Text(rd(_d.total),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                Text('${_d.cantidad} cobro(s)', style: TextStyle(color: AppColors.grey)),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(child: _dato('A cuotas', rd(_d.cuotas), AppColors.texto)),
                    Expanded(
                        child: _dato('A mora', rd(_d.mora),
                            _d.mora > 0 ? AppColors.red : AppColors.grey)),
                  ],
                ),
                if (_gastos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _dato('Gastos', '− ${rd(gastado)}', AppColors.red)),
                      Expanded(
                          child: _dato('Te queda', rd(_d.total - gastado),
                              _d.total - gastado >= 0 ? AppColors.green : AppColors.red)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_d.validos.any((c) => c.cobradorId != null)) _porCobrador(),
          if (cierre != null)
            Panel(
              borde: (cambio ? AppColors.amber : AppColors.green).withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(cambio ? Icons.warning_amber_rounded : Icons.lock_rounded,
                          color: cambio ? AppColors.amber : AppColors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Caja cerrada${cierre['created_at'] != null ? ' el ${fechaLarga(DateTime.parse(cierre['created_at'] as String).toLocal())}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  if (cambio)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Al cerrar sumaba ${rd(totalCierre)}; ahora suma ${rd(_d.total)}. '
                        'Se anuló o se agregó un cobro después del cierre.',
                        style: TextStyle(color: AppColors.amber, fontSize: 13),
                      ),
                    ),
                  if ((cierre['nota'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Nota: ${cierre['nota']}',
                          style: TextStyle(color: AppColors.grey)),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _trabajando ? null : _cerrar,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(cierre == null ? 'Cerrar caja' : 'Actualizar cierre'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _compartir,
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir'),
                ),
              ),
            ],
          ),
          if (cierre != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                onPressed: _trabajando ? null : _borrarCierre,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Borrar cierre'),
              ),
            ),
          const SizedBox(height: 12),
          const Text('Cobros del día',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_d.cobros.isEmpty)
            Text('Sin cobros este día.', style: TextStyle(color: AppColors.grey)),
          for (final c in _d.cobros)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(_hora(c.fecha),
                  style: TextStyle(color: AppColors.grey, fontSize: 12)),
              title: Text(c.cliente,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.anulado ? AppColors.grey : null,
                      decoration: c.anulado ? TextDecoration.lineThrough : null)),
              subtitle: Text(
                'Recibo ${numeroReciboTexto(c.numeroRecibo)}'
                '${c.montoMora > 0 ? ' · mora ${rd(c.montoMora)}' : ''}'
                '${c.anulado ? ' · ANULADO' : ''}',
                style: TextStyle(color: c.anulado ? AppColors.red : AppColors.grey, fontSize: 12),
              ),
              trailing: Text(rd(c.monto),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: c.anulado ? AppColors.grey : null,
                      decoration: c.anulado ? TextDecoration.lineThrough : null)),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text('Gastos del día',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: _anotarGasto,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Anotar gasto'),
              ),
            ],
          ),
          if (_gastos.isEmpty)
            Text('Sin gastos este día.', style: TextStyle(color: AppColors.grey)),
          for (final g in _gastos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(g.descripcion, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text('− ${rd(g.monto)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.red)),
            ),
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: TextStyle(color: AppColors.grey, fontSize: 12)),
          Text(valor, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      );
}
