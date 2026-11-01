import 'package:flutter/material.dart';
import '../logic/calculo_prestamo.dart';
import '../logic/ultimos_valores_prestamo.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/plazo.dart';
import '../widgets/ui.dart';

class PrestarScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final Map<String, dynamic> prestamo; // el préstamo "borrador" existente

  /// Valores que vienen de la calculadora (si se llegó desde ahí).
  final double? tasaInicial;
  final int? diasInicial;
  final String? frecuenciaInicial;
  final TipoInteres? tipoInicial;

  const PrestarScreen({
    super.key,
    required this.cliente,
    required this.prestamo,
    this.tasaInicial,
    this.diasInicial,
    this.frecuenciaInicial,
    this.tipoInicial,
  });

  @override
  State<PrestarScreen> createState() => _PrestarScreenState();
}

class _PrestarScreenState extends State<PrestarScreen> {
  late final TextEditingController _montoCtrl;
  late final TextEditingController _interesCtrl;
  late final TextEditingController _diasCtrl;
  final _moraCtrl = TextEditingController(text: '5');
  final _graciaCtrl = TextEditingController(text: '1');
  late String _frecuencia;
  bool _guardando = false;

  /// Cómo se cobra el interés (por defecto sobre saldo, o el del último
  /// préstamo).
  TipoInteres _tipo = TipoInteres.saldo;

  /// Fecha del primer pago que eligió el prestamista. Null = la de siempre
  /// (un período después de hoy). Se borra al cambiar la frecuencia.
  DateTime? _primerPagoElegido;

  DateTime get _hoy {
    final h = DateTime.now();
    return DateTime(h.year, h.month, h.day);
  }

  DateTime get _primerPago => _primerPagoElegido ?? primerPagoNormal(_hoy, _frecuencia);

  /// La fecha desde la que sale el cronograma (ver baseParaPrimerPago).
  DateTime get _baseCronograma =>
      fechaDesembolsoParaPrimerPago(_hoy, _frecuencia, _primerPagoElegido);

  @override
  void initState() {
    super.initState();
    final montoInicial = widget.prestamo['monto'] as num?;
    _montoCtrl = TextEditingController(
      text: montoInicial != null && montoInicial > 0 ? montoInicial.toStringAsFixed(0) : '',
    );
    _interesCtrl = TextEditingController(text: numeroCorto(widget.tasaInicial ?? 20));
    _diasCtrl = TextEditingController(text: '${widget.diasInicial ?? 30}');
    _frecuencia = widget.frecuenciaInicial ?? 'diario';
    _tipo = widget.tipoInicial ?? TipoInteres.saldo;
    _usarUltimosValores();
  }

  /// Ya cambió algo a mano: los valores guardados no se lo pisan.
  bool _tocado = false;

  /// Pone los valores del último préstamo que confirmó el prestamista. Los
  /// que mandó quien abrió la pantalla (ej. la calculadora) mandan.
  Future<void> _usarUltimosValores() async {
    final v = await leerUltimosValoresPrestamo();
    final tipo = widget.tipoInicial == null ? await leerUltimoTipoInteres() : null;
    if (!mounted || _tocado) return;
    if (tipo != null) setState(() => _tipo = tipo);
    if (v == null) return;
    setState(() {
      if (widget.tasaInicial == null) _interesCtrl.text = numeroCorto(v.tasa);
      if (widget.diasInicial == null) {
        _diasCtrl.text = '${v.plazo}';
        _enMeses = v.enMeses;
      }
      if (widget.frecuenciaInicial == null) _frecuencia = v.frecuencia;
      _moraCtrl.text = numeroCorto(v.mora);
      _graciaCtrl.text = '${v.gracia}';
    });
  }

  double get _monto => double.tryParse(_montoCtrl.text.replaceAll(',', '')) ?? 0;
  double get _interes => double.tryParse(_interesCtrl.text) ?? 0;
  /// El plazo se escribe en meses (si no, en días).
  bool _enMeses = false;
  int get _dias => diasDelPlazo(int.tryParse(_diasCtrl.text) ?? 0, enMeses: _enMeses);
  double get _mora => double.tryParse(_moraCtrl.text) ?? -1;
  int get _gracia => int.tryParse(_graciaCtrl.text) ?? -1;

  /// Mismo cálculo que se guarda al confirmar (ver calcularPlan). Es null
  /// mientras los datos escritos no son válidos — por ejemplo, mientras se
  /// está escribiendo el monto y va en "1" (no alcanza para las cuotas).
  PlanPrestamo? get _plan {
    if (_monto <= 0 || _dias < 1 || _interes < 0) return null;
    try {
      return calcularPlan(
        monto: _monto,
        tasaInteresMensual: _interes,
        diasPlazo: _dias,
        frecuencia: _frecuencia,
        tipo: _tipo,
      );
    } on ArgumentError {
      return null;
    }
  }

  /// Elegir la fecha del primer pago (desde mañana).
  Future<void> _elegirPrimerPago() async {
    final hoy = _hoy;
    bool permitido(DateTime d) => primerPagoPermitido(hoy, _frecuencia, d);
    var inicial = _primerPago;
    if (!permitido(inicial)) inicial = primerPagoNormal(hoy, _frecuencia);
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: hoy.add(const Duration(days: 1)),
      lastDate: hoy.add(const Duration(days: maxDiasPrimerPago)),
      selectableDayPredicate: permitido,
      helpText: 'Fecha del primer pago',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
    );
    if (elegida == null || !mounted) return;
    setState(() {
      _tocado = true;
      final normal = primerPagoNormal(hoy, _frecuencia);
      _primerPagoElegido = DateUtils.isSameDay(elegida, normal) ? null : elegida;
    });
  }

  /// Por qué no se puede calcular todavía (null si todo está bien).
  String? get _aviso {
    if (_plan != null) return null;
    if (_monto <= 0) return 'Escribe el monto a prestar.';
    if (_dias < 1) return 'El plazo debe ser de al menos 1 día.';
    if (_interes < 0) return 'El interés no puede ser negativo.';
    if (_tipo == TipoInteres.reditos) {
      return 'Con solo réditos el interés tiene que dar al menos RD\$1 por cuota.';
    }
    return 'El monto es muy bajo para ${(_dias / diasPorCuota(_frecuencia)).ceil()} '
        '${nombreCuotas(_frecuencia)}.';
  }

  Future<void> _confirmar() async {
    final aviso = _aviso;
    if (aviso != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
      return;
    }
    if (_mora < 0 || _gracia < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Revisa la mora y los días de gracia (0 o más)')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await SupabaseService.instance.confirmarPrestamo(
        prestamoId: widget.prestamo['id'],
        monto: _monto,
        tasaInteresMensual: _interes,
        frecuencia: _frecuencia,
        diasPlazo: _dias,
        moraDiaria: _mora,
        diasGracia: _gracia,
        tipo: _tipo,
        primerPago: _primerPagoElegido,
      );
      // La próxima vez la pantalla abre con estos mismos valores.
      await guardarUltimosValoresPrestamo(UltimosValoresPrestamo(
        tasa: _interes,
        plazo: int.tryParse(_diasCtrl.text) ?? _dias,
        enMeses: _enMeses,
        frecuencia: _frecuencia,
        mora: _mora,
        gracia: _gracia,
      ));
      await guardarUltimoTipoInteres(_tipo);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('¡${widget.cliente['nombre']} ya está en la calle!')),
        );
      }
    } catch (e, pila) {
      registrarError(e, pila, 'PRESTAR');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pudimos guardar el préstamo. ${mensajeError(e)}')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Prestar a ${widget.cliente['nombre']}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _campo(_montoCtrl, 'Monto a prestar (RD\$)'),
            _campo(_interesCtrl, 'Interés mensual (%)'),
            const Text('Cómo se cobra el interés',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectorTipoInteres(
              valor: _tipo,
              onCambio: (t) => setState(() {
                _tocado = true;
                _tipo = t;
              }),
            ),
            const SizedBox(height: 16),
            const Text('Frecuencia de cobro',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectorFrecuencia(
              valor: _frecuencia,
              onCambio: (f) => setState(() {
                _tocado = true;
                _frecuencia = f;
                // Con otra frecuencia, el primer pago vuelve a ser el de siempre.
                _primerPagoElegido = null;
              }),
            ),
            const SizedBox(height: 12),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                key: const Key('primer_pago'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(Icons.event_rounded, color: AppColors.green),
                title: const Text('Fecha del primer pago'),
                subtitle: Text(
                  _primerPagoElegido == null
                      ? '${fechaLarga(_primerPago)}. Toca para elegir otra.'
                      : '${fechaLarga(_primerPago)}. La primera cuota lleva el interés '
                          'normal de una cuota, aunque falten más o menos días.',
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
                ),
                trailing: _primerPagoElegido == null
                    ? const Icon(Icons.edit_calendar_rounded)
                    : IconButton(
                        tooltip: 'Volver a la de siempre',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _primerPagoElegido = null),
                      ),
                onTap: _elegirPrimerPago,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _campo(
                        _diasCtrl, _enMeses ? 'Plazo total (meses)' : 'Plazo total (días)')),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SelectorUnidadPlazo(
                    enMeses: _enMeses,
                    onCambio: (meses) => setState(() {
                      _tocado = true;
                      _diasCtrl.text = convertirPlazo(_diasCtrl.text, aMeses: meses);
                      _enMeses = meses;
                    }),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: _campo(_moraCtrl, 'Mora diaria (%)')),
                const SizedBox(width: 12),
                Expanded(child: _campo(_graciaCtrl, 'Días de gracia')),
              ],
            ),
            if (_mora > 0 && _gracia >= 0 && _plan != null)
              Text(
                'Si una cuota se atrasa más de $_gracia día(s), se le suma el '
                '${_mora.toStringAsFixed(_mora == _mora.roundToDouble() ? 0 : 1)}% '
                'de lo que falte de ella por cada día '
                '(RD\$ ${(_plan!.cuota * _mora / 100).round()} diarios sobre una cuota completa).',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resumen', style: TextStyle(color: AppColors.grey)),
                  const SizedBox(height: 8),
                  if (_aviso != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_aviso!, style: TextStyle(color: AppColors.amber)),
                    ),
                  if (_plan != null && _plan!.diasCobrados != _dias)
                    _resumenFila('Plazo real',
                        '${_plan!.diasCobrados} días (${_plan!.cantidadCuotas} ${nombrePeriodos(_frecuencia)})'),
                  _resumenFila(
                      'Interés ${_interes.toStringAsFixed(_interes == _interes.roundToDouble() ? 0 : 2)}%'
                      '/mes ${_tipo.nombre}',
                      'RD\$ ${(_plan?.interesTotal ?? 0).toStringAsFixed(0)}'),
                  _resumenFila('Total a devolver',
                      'RD\$ ${(_plan?.montoTotal ?? 0).toStringAsFixed(0)}'),
                  Divider(color: AppColors.grey),
                  _resumenFila(
                    '${_plan?.cantidadCuotas ?? 0} ${nombreCuotas(_frecuencia)}',
                    'RD\$ ${(_plan?.cuota ?? 0).toStringAsFixed(0)}',
                    destacado: true,
                  ),
                  if (_plan != null && _plan!.ultimaCuota != _plan!.cuota)
                    _resumenFila('Última cuota', 'RD\$ ${_plan!.ultimaCuota.toStringAsFixed(0)}'),
                ],
              ),
            ),
            if (_plan != null) ...[
              const SizedBox(height: 16),
              TablaAmortizacion(plan: _plan!, frecuencia: _frecuencia, desde: _baseCronograma),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _guardando ? null : _confirmar,
              child: _guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirmar y mandar a la calle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() => _tocado = true),
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _resumenFila(String label, String valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Expanded: en teléfonos angostos la etiqueta baja de línea en vez
          // de empujar el monto fuera de la pantalla.
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Text(
            valor,
            style: TextStyle(
              color: destacado ? AppColors.green : AppColors.texto,
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
              fontSize: destacado ? 20 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
