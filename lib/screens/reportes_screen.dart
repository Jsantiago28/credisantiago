import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import '../archivos/archivos.dart';
import '../logic/caja.dart';
import '../logic/calculo_prestamo.dart';
import '../logic/gastos.dart';
import '../logic/graficas.dart' show gananciaPorMes;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cobro_prestamo.dart';
import '../widgets/ui.dart';
import 'caja_screen.dart';
import 'cliente_detalle_screen.dart';
import 'gastos_screen.dart';
import 'graficas_screen.dart';

/// Pantalla de Reportes (Fase 3).
/// Nota técnica: la descarga de Excel usa dart:html porque, por ahora,
/// la app solo se está probando en la web. Cuando se compile el APK de
/// Android, esta parte de la descarga habrá que adaptarla (por ejemplo
/// con share_plus, que ya está en el proyecto) para que funcione ahí
/// también — en Android, dart:html no existe.
class ReportesScreen extends StatefulWidget {
  final String prestamistaId;
  const ReportesScreen({super.key, required this.prestamistaId});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  List<Map<String, dynamic>>? _prestamos;
  bool _cargando = true;

  /// Caja de los últimos días (hoy primero) y sus cierres.
  List<DiaCaja> _caja = const [];
  Map<String, Map<String, dynamic>> _cierres = const {};

  /// Ganancia real de este mes (interés + mora − gastos); null mientras carga.
  ({double interes, double mora, double gastos, double real})? _real;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final servicio = SupabaseService.instance;
    final r = await servicio.obtenerReportePrestamos(widget.prestamistaId);
    await _cargarCaja();
    final real = await _cargarGananciaReal(r);
    if (mounted) {
      setState(() {
        _prestamos = r;
        _real = real;
        _cargando = false;
      });
    }
  }

  /// Últimos 7 días de caja. Si falla (o falta la migración de cierres),
  /// el resto de Reportes se ve igual.
  Future<void> _cargarCaja() async {
    final servicio = SupabaseService.instance;
    final hoy = DateTime.now();
    final desde = DateTime(hoy.year, hoy.month, hoy.day).subtract(const Duration(days: 6));
    try {
      final dias = cajaPorDia(await servicio.obtenerCobrosCaja(widget.prestamistaId, desde: desde));
      // Hoy siempre aparece, aunque no haya cobros todavía.
      final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
      if (dias.isEmpty || dias.first.dia != hoySinHora) dias.insert(0, DiaCaja(hoySinHora, const []));
      _caja = dias;
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL CAJA EN REPORTES: $e');
    }
    try {
      _cierres = await servicio.obtenerCierres(widget.prestamistaId);
    } catch (_) {
      _cierres = const {};
    }
  }

  /// Interés y mora cobrados este mes, menos los gastos del mes.
  Future<({double interes, double mora, double gastos, double real})?> _cargarGananciaReal(
      List<Map<String, dynamic>> prestamos) async {
    final servicio = SupabaseService.instance;
    final hoy = DateTime.now();
    final mes = DateTime(hoy.year, hoy.month);
    try {
      final cobros = await servicio.obtenerCobrosGraficas(widget.prestamistaId, mes);
      final g = gananciaPorMes(cobros, {for (final p in prestamos) p['id'] as String: p}, hoy,
              meses: 1)
          .single;
      final gastos = await servicio.obtenerGastos(widget.prestamistaId, desde: mes);
      return gananciaReal(interes: g.interes, mora: g.mora, gastos: totalGastos(gastos));
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL GANANCIA REAL: $e');
      return null;
    }
  }

  Future<void> _abrirGastos() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          GastosScreen(prestamistaId: widget.prestamistaId, prestamos: _prestamos ?? const []),
    ));
    final real = await _cargarGananciaReal(_prestamos ?? const []);
    if (mounted) setState(() => _real = real);
  }

  Widget _tarjetaGananciaReal() {
    final g = _real;
    final color = g == null || g.real >= 0 ? AppColors.green : AppColors.red;
    return Panel(
      borde: color.withValues(alpha: 0.5),
      onTap: _abrirGastos,
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_rounded, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gastos y ganancia real',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                  g == null
                      ? 'Anota gasolina, pago al cobrador y otros gastos'
                      : 'Este mes: ${rd(g.interes + g.mora)} ganado − ${rd(g.gastos)} gastos',
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          if (g != null)
            Text(rd(g.real),
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          const Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }

  Future<void> _abrirDiaCaja(DiaCaja d) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CajaDiaScreen(
        prestamistaId: widget.prestamistaId,
        dia: d,
        cierre: _cierres[claveDia(d.dia)],
      ),
    ));
    await _cargarCaja();
    if (mounted) setState(() {});
  }

  Widget _seccionCaja() {
    const visibles = 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Caja por día',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CajaScreen(prestamistaId: widget.prestamistaId),
                ));
                await _cargarCaja();
                if (mounted) setState(() {});
              },
              child: const Text('Ver todos los días'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final d in _caja.take(visibles))
          FilaDiaCaja(dia: d, cierre: _cierres[claveDia(d.dia)], onTap: () => _abrirDiaCaja(d)),
      ],
    );
  }

  bool _estaAtrasado(Map<String, dynamic> p) =>
      estaAtrasado(p, (p['total_pagado'] as num).toDouble(), DateTime.now());

  int _diasAtraso(Map<String, dynamic> p) =>
      diasAtraso(p, (p['total_pagado'] as num).toDouble(), DateTime.now());

  List<Map<String, dynamic>> get _alDia => (_prestamos ?? [])
      .where((p) => p['estado'] == 'en_calle' && !_estaAtrasado(p))
      .toList();

  List<Map<String, dynamic>> get _atrasados =>
      (_prestamos ?? []).where(_estaAtrasado).toList()
        ..sort((a, b) => _diasAtraso(b).compareTo(_diasAtraso(a)));

  /// Préstamos ya saldados, el más reciente primero.
  List<Map<String, dynamic>> get _saldados =>
      (_prestamos ?? []).where((p) => p['estado'] == 'pagado').toList()
        ..sort((a, b) {
          final fa = a['fecha_ultimo_pago'] as DateTime?;
          final fb = b['fecha_ultimo_pago'] as DateTime?;
          if (fa == null || fb == null) return fa == null ? 1 : -1;
          return fb.compareTo(fa);
        });

  /// Ganancia que ya entró de un préstamo saldado: lo cobrado a cuotas
  /// menos el capital, más la mora.
  double _gananciaRealizada(Map<String, dynamic> p) =>
      (p['total_pagado'] as num).toDouble() -
      (p['monto'] as num).toDouble() +
      (p['mora_cobrada'] as num).toDouble();

  void _abrirCliente(Map<String, dynamic> p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClienteDetalleScreen(clienteId: p['cliente_id'] as String),
    ));
    _cargar();
  }

  void _descargarSaldados() {
    _descargar('Saldados', [
      'Nombre',
      'Telefono',
      'Prestado',
      'Cobrado',
      'Ganancia',
      'De eso, mora',
      'Desembolso',
      'Saldado',
    ], [
      for (final p in _saldados)
        [
          p['cliente_nombre'] ?? '',
          p['cliente_telefono'] ?? '',
          (p['monto'] as num).toStringAsFixed(0),
          ((p['total_pagado'] as num) + (p['mora_cobrada'] as num)).toStringAsFixed(0),
          _gananciaRealizada(p).toStringAsFixed(0),
          (p['mora_cobrada'] as num).toStringAsFixed(0),
          p['fecha_desembolso'] ?? '',
          (p['fecha_ultimo_pago'] as DateTime?)?.toIso8601String().substring(0, 10) ?? '',
        ],
    ]);
  }

  /// Abre el cobro del cliente (cuotas, mora, recibos) desde el reporte.
  Future<void> _abrirCobro(Map<String, dynamic> p) async {
    final pagos = await SupabaseService.instance.obtenerPagos(p['id']);
    final gestiones = await SupabaseService.instance.obtenerGestiones(p['id']);
    if (!mounted) return;
    final datos = PrestamoConDatos(
      prestamo: p,
      cliente: {
        'nombre': p['cliente_nombre'],
        'direccion': p['cliente_direccion'],
        'telefono': p['cliente_telefono'],
      },
      pagos: pagos,
      gestiones: gestiones,
    );
    CobroPrestamo(context, datos, onCambio: _cargar).abrirCuotas();
  }

  void _descargarAlDia() {
    _descargar('Al dia', [
      'Nombre',
      'Telefono',
      'Debe',
      'Cuota',
      'Proximo Pago',
      'Direccion',
    ], [
      for (final p in _alDia)
        [
          p['cliente_nombre'] ?? '',
          p['cliente_telefono'] ?? '',
          (p['balance'] as num).toStringAsFixed(0),
          (p['cuota'] as num?)?.toStringAsFixed(0) ?? '',
          p['proximo_pago'] ?? '',
          p['cliente_direccion'] ?? '',
        ],
    ]);
  }

  void _descargarAtrasados() {
    _descargar('Atrasados', [
      'Nombre',
      'Dias Atrasado',
      'Debe',
      'De eso, mora',
      'Cuota',
      'Telefono',
      'Supervisor o RRHH',
      'Tel. Supervisor',
      'Referencia',
      'Tel. Referencia',
      'Direccion',
    ], [
      for (final p in _atrasados)
        [
          p['cliente_nombre'] ?? '',
          '${_diasAtraso(p)}',
          (p['balance'] as num).toStringAsFixed(0),
          (p['mora_pendiente'] as num).toStringAsFixed(0),
          (p['cuota'] as num?)?.toStringAsFixed(0) ?? '',
          p['cliente_telefono'] ?? '',
          p['cliente_jefe'] ?? '',
          p['cliente_jefe_telefono'] ?? '',
          p['cliente_ref1'] ?? '',
          p['cliente_ref1_telefono'] ?? '',
          p['cliente_direccion'] ?? '',
        ],
    ]);
  }

  void _descargar(String hoja, List<String> encabezado, List<List<String>> filas) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', hoja);
    final sheet = excel[hoja];
    sheet.appendRow(encabezado.map(TextCellValue.new).toList());
    for (final f in filas) {
      sheet.appendRow(f.map(TextCellValue.new).toList());
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final fecha = DateTime.now();
    final sufijo = hoja.toLowerCase().replaceAll(' ', '_');
    final nombreArchivo =
        'prestamistas_rd_${sufijo}_${fecha.year}${fecha.month.toString().padLeft(2, '0')}${fecha.day.toString().padLeft(2, '0')}.xlsx';
    descargarArchivo(nombreArchivo, bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final prestamos = _prestamos ?? [];
    final hoy = DateTime.now();
    final ganancia = gananciaDelMes(prestamos, hoy);
    final anterior = gananciaDelMes(prestamos, DateTime(hoy.year, hoy.month - 1, 15)).proyectada;
    // Aparte de la ganancia: la mora no se proyecta, solo se cobra.
    final moraDelMes = prestamos.fold<double>(
        0, (s, p) => s + ((p['mora_cobrada_mes'] as num?)?.toDouble() ?? 0));
    final atrasados = _atrasados;

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _tarjetaGanancia(ganancia, anterior, moraDelMes),
            const SizedBox(height: 12),
            _tarjetaGananciaReal(),
            Panel(
              borde: AppColors.green.withValues(alpha: 0.5),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    GraficasScreen(prestamistaId: widget.prestamistaId, prestamos: prestamos),
              )),
              child: const Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: AppColors.green, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gráficas del negocio',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('Cartera, cobros por día, ganancia por mes',
                            style: TextStyle(color: AppColors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.grey),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _seccionCaja(),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('No han pagado hoy',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                Pildora('${atrasados.length} cliente(s)'),
              ],
            ),
            const SizedBox(height: 12),
            if (atrasados.isEmpty)
              const Vacio(
                  icono: Icons.celebration_rounded, texto: 'Nadie atrasado por ahora. ¡Bien!')
            else
              ...atrasados.map(_filaAtrasado),
            const SizedBox(height: 20),
            _seccionSaldados(),
            const SizedBox(height: 20),
            const Text('Descargar Excel',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _botonExcel(
                    icono: Icons.download_rounded,
                    titulo: 'Al día',
                    detalle: 'Clientes al día · ${_alDia.length}',
                    onTap: prestamos.isEmpty ? null : _descargarAlDia,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _botonExcel(
                    icono: Icons.download_rounded,
                    titulo: 'Atrasados',
                    detalle: 'Clientes atrasados · ${atrasados.length}',
                    onTap: atrasados.isEmpty ? null : _descargarAtrasados,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _botonExcel(
              icono: Icons.download_rounded,
              titulo: 'Saldados',
              detalle: 'Préstamos saldados · ${_saldados.length}',
              onTap: _saldados.isEmpty ? null : _descargarSaldados,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaGanancia(
    ({double proyectada, double yaLlevas, double falta}) g,
    double anterior,
    double moraDelMes,
  ) {
    final cambio = anterior > 0 ? (g.proyectada - anterior) / anterior * 100 : null;
    return Panel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      borde: AppColors.green.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.greenDark,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.trending_up_rounded, color: AppColors.green, size: 36),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GANANCIA PROYECTADA ESTE MES',
                        style: TextStyle(
                            color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(rd(g.proyectada),
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                    ),
                    if (cambio != null)
                      Text(
                        '${cambio >= 0 ? '+' : ''}${cambio.toStringAsFixed(1)}% vs. mes anterior',
                        style: TextStyle(
                            color: cambio >= 0 ? AppColors.green : AppColors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _dato('Ya llevas', rd(g.yaLlevas), AppColors.green)),
              Expanded(child: _dato('Te falta', rd(g.falta), AppColors.white)),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: moraDelMes > 0 ? AppColors.red : AppColors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Mora cobrada este mes',
                    style: TextStyle(color: moraDelMes > 0 ? AppColors.red : AppColors.grey)),
              ),
              Text(rd(moraDelMes),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: moraDelMes > 0 ? AppColors.red : AppColors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  /// Resumen de préstamos saldados y los más recientes.
  Widget _seccionSaldados() {
    final saldados = _saldados;
    final hoy = DateTime.now();
    final esteMes = saldados.where((p) {
      final f = p['fecha_ultimo_pago'] as DateTime?;
      return f != null && f.year == hoy.year && f.month == hoy.month;
    }).length;
    final capital = saldados.fold<double>(0, (s, p) => s + (p['monto'] as num).toDouble());
    final ganancia = saldados.fold<double>(0, (s, p) => s + _gananciaRealizada(p));
    final mora = saldados.fold<double>(0, (s, p) => s + (p['mora_cobrada'] as num).toDouble());
    const visibles = 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Préstamos saldados',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Pildora('$esteMes este mes'),
          ],
        ),
        const SizedBox(height: 12),
        if (saldados.isEmpty)
          const Vacio(
              icono: Icons.verified_rounded,
              texto: 'Todavía no hay préstamos saldados.\nAquí aparecen cuando el cliente termina de pagar.')
        else ...[
          Panel(
            child: Row(
              children: [
                Expanded(child: _dato('Capital recuperado', rd(capital), AppColors.white)),
                Expanded(
                  child: _dato(
                    mora > 0 ? 'Ganancia (con ${rd(mora)} mora)' : 'Ganancia cobrada',
                    rd(ganancia),
                    AppColors.green,
                  ),
                ),
              ],
            ),
          ),
          for (final p in saldados.take(visibles)) _filaSaldado(p),
          if (saldados.length > visibles)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('Saldados (${saldados.length})')),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: saldados.map(_filaSaldado).toList(),
                  ),
                ),
              )),
              child: Text('Ver todos (${saldados.length})'),
            ),
        ],
      ],
    );
  }

  Widget _filaSaldado(Map<String, dynamic> p) {
    final fecha = p['fecha_ultimo_pago'] as DateTime?;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => _abrirCliente(p),
      child: Row(
        children: [
          AvatarIniciales(nombre: p['cliente_nombre'] ?? '', tamano: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['cliente_nombre'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                  '${rd(p['monto'] as num)} prestado'
                  '${fecha != null ? ' • saldó el ${fechaLarga(fecha)}' : ''}',
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text('+${rd(_gananciaRealizada(p))}',
              style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
          const Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          Text(valor,
              style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _filaAtrasado(Map<String, dynamic> p) {
    final dias = _diasAtraso(p);
    final mora = (p['mora_pendiente'] as num).toDouble();
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => _abrirCobro(p),
      child: Row(
        children: [
          AvatarIniciales(nombre: p['cliente_nombre'] ?? '', tamano: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['cliente_nombre'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                  '${rd(p['balance'] as num)} • '
                  '${dias == 0 ? 'vence hoy' : '$dias día(s) atrasado'}'
                  '${mora > 0 ? ' • mora ${rd(mora)}' : ''}',
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          EtiquetaEstado(dias == 0 ? EstadoCobro.venceHoy : EstadoCobro.atrasado),
          const Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }

  Widget _botonExcel({
    required IconData icono,
    required String titulo,
    required String detalle,
    required VoidCallback? onTap,
  }) {
    final activo = onTap != null;
    return Material(
      color: activo ? AppColors.greenDark : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: activo ? AppColors.green : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icono, color: activo ? AppColors.green : AppColors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(detalle,
                          style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
