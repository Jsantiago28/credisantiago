import 'package:flutter/material.dart';

import '../logic/ruta_del_dia.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

const _nombresDias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// La semana de lunes a domingo: cuánto vence cada día (según el cronograma
/// de los préstamos en la calle) y cuánto se cobró. Tocando un día se ve
/// quiénes pagan ese día.
class SemanaScreen extends StatelessWidget {
  final List<PrestamoConDatos> cartera;

  /// Al tocar un cliente en la lista de un día (abre su cobro).
  final void Function(PrestamoConDatos)? onAbrir;

  /// Para las pruebas; si no se da, hoy.
  final DateTime? hoy;

  const SemanaScreen({super.key, required this.cartera, this.onAbrir, this.hoy});

  @override
  Widget build(BuildContext context) {
    final ahora = hoy ?? DateTime.now();
    final estados = {for (final d in cartera) d: d.estado(ahora)};
    final dias = totalesDeLaSemana(cartera, (d) => estados[d]!, (d) => d.pagos, ahora);
    final programado = dias.fold<double>(0, (s, d) => s + d.programado);
    final cobrado = dias.fold<double>(0, (s, d) => s + d.cobrado);

    return Scaffold(
      appBar: AppBar(title: const Text('Esta semana')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Panel(
            child: Row(
              children: [
                Expanded(child: _dato('Vence en la semana', rd(programado), AppColors.texto)),
                Expanded(child: _dato('Cobrado', rd(cobrado), AppColors.green)),
              ],
            ),
          ),
          for (final d in dias)
            _filaDia(context, d, _mismoDia(d.dia, ahora)),
          const SizedBox(height: 8),
          Text('Solo cuenta los préstamos que siguen en la calle.',
              style: TextStyle(color: AppColors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: TextStyle(color: AppColors.grey, fontSize: 13)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(valor,
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      );

  Widget _filaDia(BuildContext context, DiaSemana d, bool esHoy) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      borde: esHoy ? AppColors.green.withValues(alpha: 0.7) : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _DiaScreen(cartera: cartera, dia: d.dia, hoy: hoy, onAbrir: onAbrir),
      )),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_nombresDias[d.dia.weekday - 1]} ${fechaCorta(d.dia)}${esHoy ? ' · hoy' : ''}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(d.clientes == 0 ? 'Nadie paga este día' : plural(d.clientes, 'cliente', 'clientes'),
                    style: TextStyle(color: AppColors.grey, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rd(d.programado), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text('Cobrado ${rd(d.cobrado)}',
                  style: TextStyle(
                      color: d.cobrado > 0 ? AppColors.green : AppColors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }
}

/// Quiénes tienen cuota un día de la semana, y si ya la pagaron.
class _DiaScreen extends StatelessWidget {
  final List<PrestamoConDatos> cartera;
  final DateTime dia;
  final DateTime? hoy;
  final void Function(PrestamoConDatos)? onAbrir;

  const _DiaScreen({required this.cartera, required this.dia, this.hoy, this.onAbrir});

  @override
  Widget build(BuildContext context) {
    final ahora = hoy ?? DateTime.now();
    final filas = [
      for (final d in cartera)
        if (d.estado(ahora) case final e when programadoDelDia(e, dia) > 0)
          (
            datos: d,
            programado: programadoDelDia(e, dia),
            falta: pendienteDelDia(e, dia),
            cobrado: cobradoEnDia(d.pagos, dia),
          ),
    ]..sort((a, b) => a.datos.nombre.toLowerCase().compareTo(b.datos.nombre.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: Text('${_nombresDias[dia.weekday - 1]} ${fechaCorta(dia)}')),
      body: filas.isEmpty
          ? const Vacio(icono: Icons.event_available_rounded, texto: 'Nadie tiene cuota este día.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final f in filas)
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 8),
                    onTap: onAbrir == null ? null : () => onAbrir!(f.datos),
                    child: Row(
                      children: [
                        AvatarIniciales(nombre: f.datos.nombre, tamano: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.datos.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                              Text(
                                  [
                                    'Cuota ${rd(f.programado)}',
                                    if (f.cobrado > 0) 'cobrado ese día ${rd(f.cobrado)}',
                                  ].join(' · '),
                                  style: TextStyle(color: AppColors.grey, fontSize: 13)),
                            ],
                          ),
                        ),
                        f.falta < 0.005
                            ? const Pildora('PAGÓ')
                            : Text(rd(f.falta),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
