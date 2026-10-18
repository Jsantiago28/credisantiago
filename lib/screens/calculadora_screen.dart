import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/calculo_prestamo.dart';
import '../theme/app_theme.dart';
import '../widgets/plazo.dart';
import '../widgets/ui.dart';
import 'nuevo_cliente_screen.dart';

/// Calculadora de préstamos: con monto, tasa mensual y plazo muestra cómo
/// quedaría en diario, semanal, quincenal y mensual (misma fórmula que
/// Prestar), para decirle al cliente de una vez cuánto y cuándo pagaría.
class CalculadoraScreen extends StatefulWidget {
  final String prestamistaId;
  const CalculadoraScreen({super.key, required this.prestamistaId});

  @override
  State<CalculadoraScreen> createState() => _CalculadoraScreenState();
}

class _CalculadoraScreenState extends State<CalculadoraScreen> {
  final _monto = TextEditingController(text: '10000');
  final _tasa = TextEditingController(text: '20');
  final _dias = TextEditingController(text: '30');
  String _elegida = 'diario';

  /// El plazo se escribe en meses (si no, en días).
  bool _enMeses = false;

  static const _plazosRapidos = [15, 30, 45, 60, 90, 120];
  static const _mesesRapidos = [1, 2, 3, 6, 12, 24, 36, 60];

  double get _montoValor => double.tryParse(_monto.text.replaceAll(',', '')) ?? 0;
  double get _tasaValor => double.tryParse(_tasa.text) ?? -1;
  int get _diasValor => diasDelPlazo(int.tryParse(_dias.text) ?? 0, enMeses: _enMeses);

  /// El plan de cada frecuencia, o null si con estos datos no aplica.
  PlanPrestamo? _plan(String frecuencia) {
    if (_montoValor <= 0 || _tasaValor < 0 || _diasValor < 1) return null;
    try {
      return calcularPlan(
        monto: _montoValor,
        tasaInteresMensual: _tasaValor,
        diasPlazo: _diasValor,
        frecuencia: frecuencia,
        tipo: TipoInteres.saldo,
      );
    } on ArgumentError {
      return null; // ej. monto muy chico para tantas cuotas
    }
  }

  String _titulo(String f) => switch (f) {
        'diario' => 'Diario',
        'semanal' => 'Semanal',
        'quincenal' => 'Quincenal',
        _ => 'Mensual',
      };

  /// Texto para mandarle al cliente con las 4 opciones.
  String _cotizacion() {
    final hoy = DateTime.now();
    final lineas = <String>[
      'Préstamo de ${rd(_montoValor)} (${_tasa.text}% mensual sobre saldo, '
          '${_enMeses ? '${_dias.text} meses' : '$_diasValor días'}):',
      '',
    ];
    for (final f in frecuencias) {
      final p = _plan(f);
      if (p == null) continue;
      final ultima = fechaCuota(hoy, f, p.cantidadCuotas);
      final ajuste = p.ultimaCuota != p.cuota ? ' (la última de ${rd(p.ultimaCuota)})' : '';
      lineas.add('• ${_titulo(f)}: ${p.cantidadCuotas} ${nombreCuotas(f)} de ${rd(p.cuota)}$ajuste. '
          'Total ${rd(p.montoTotal)}. Último pago ${fechaLarga(ultima)}.');
    }
    return lineas.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final elegido = _plan(_elegida);
    return Scaffold(
      appBar: AppBar(title: const Text('Calculadora')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _campo(_monto, 'Monto a prestar (RD\$)', grande: true),
          Row(
            children: [
              Expanded(child: _campo(_tasa, 'Interés mensual (%)')),
              const SizedBox(width: 10),
              Expanded(child: _campo(_dias, _enMeses ? 'Plazo (meses)' : 'Plazo (días)')),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SelectorUnidadPlazo(
              enMeses: _enMeses,
              onCambio: (meses) => setState(() {
                _dias.text = convertirPlazo(_dias.text, aMeses: meses);
                _enMeses = meses;
              }),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in _enMeses ? _mesesRapidos : _plazosRapidos)
                ChoiceChip(
                  label: Text(_enMeses
                      ? '$n mes${n == 1 ? '' : 'es'}'
                      : (n % 30 == 0 ? '$n días (${n ~/ 30} mes${n == 30 ? '' : 'es'})' : '$n días')),
                  selected: _dias.text == '$n',
                  selectedColor: AppColors.greenDark,
                  labelStyle: TextStyle(
                      color: _dias.text == '$n' ? AppColors.green : AppColors.grey,
                      fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _dias.text = '$n'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Cómo quedaría',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Interés sobre saldo, con cuota fija. Toca una opción para ver su tabla de pagos.',
              style: TextStyle(color: AppColors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          for (final f in frecuencias) _opcion(f),
          if (elegido != null) ...[
            const SizedBox(height: 8),
            TablaAmortizacion(plan: elegido, frecuencia: _elegida, desde: DateTime.now()),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Share.share(_cotizacion()),
              icon: const Icon(Icons.share),
              label: const Text('Mandar cotización por WhatsApp'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => NuevoClienteScreen(
                  prestamistaId: widget.prestamistaId,
                  monto: _montoValor,
                  tasa: _tasaValor,
                  dias: _diasValor,
                  frecuencia: _elegida,
                ),
              )),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text('Prestar con esto (${_titulo(_elegida).toLowerCase()})'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _opcion(String f) {
    final p = _plan(f);
    final seleccionada = f == _elegida;
    final hoy = DateTime.now();
    return Panel(
      margin: const EdgeInsets.only(bottom: 10),
      borde: seleccionada ? AppColors.green : null,
      onTap: p == null ? null : () => setState(() => _elegida = f),
      child: p == null
          ? Text('${_titulo(f)}: no aplica con estos datos',
              style: TextStyle(color: AppColors.grey))
          : Row(
              children: [
                Icon(seleccionada ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: seleccionada ? AppColors.green : AppColors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_titulo(f),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Text(
                        '${p.cantidadCuotas} ${nombreCuotas(f, plural: p.cantidadCuotas != 1)}'
                        '${p.ultimaCuota != p.cuota ? ' · última ${rd(p.ultimaCuota)}' : ''}',
                        style: TextStyle(color: AppColors.grey, fontSize: 12),
                      ),
                      Text(
                        'Total ${rd(p.montoTotal)} · interés ${rd(p.interesTotal)}\n'
                        'Último pago ${fechaLarga(fechaCuota(hoy, f, p.cantidadCuotas))}'
                        '${p.diasCobrados != _diasValor ? ' (${p.diasCobrados} días)' : ''}',
                        style: TextStyle(color: AppColors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(rd(p.cuota),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: seleccionada ? AppColors.green : AppColors.texto)),
                    Text('por ${nombrePeriodo(f)}',
                        style: TextStyle(color: AppColors.grey, fontSize: 12)),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _campo(TextEditingController c, String etiqueta, {bool grande = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: grande ? 26 : 18, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: etiqueta,
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
}
