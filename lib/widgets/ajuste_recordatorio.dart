import 'package:flutter/material.dart';

import '../services/recordatorio.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Perfil: encender o apagar el recordatorio diario y elegir la hora. Solo
/// se ve en la app de Android.
class AjusteRecordatorio extends StatefulWidget {
  const AjusteRecordatorio({super.key});

  @override
  State<AjusteRecordatorio> createState() => _AjusteRecordatorioState();
}

class _AjusteRecordatorioState extends State<AjusteRecordatorio> {
  bool _activo = true;
  TimeOfDay _hora = Recordatorio.horaInicial;

  @override
  void initState() {
    super.initState();
    Recordatorio.ajustes().then((a) {
      if (!mounted) return;
      setState(() {
        _activo = a.activo;
        _hora = a.hora;
      });
    });
  }

  Future<void> _cambiar({bool? activo, TimeOfDay? hora}) async {
    setState(() {
      _activo = activo ?? _activo;
      _hora = hora ?? _hora;
    });
    await Recordatorio.guardar(activo: _activo, hora: _hora);
  }

  @override
  Widget build(BuildContext context) {
    if (!Recordatorio.disponible) return const SizedBox.shrink();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: AppColors.green),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Recordatorio de cobros', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              Switch(value: _activo, onChanged: (v) => _cambiar(activo: v)),
            ],
          ),
          Text('Un aviso cada día en este teléfono para revisar a quién te toca cobrar.',
              style: TextStyle(color: AppColors.grey, fontSize: 12)),
          if (_activo) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded),
              label: Text('Hora del aviso: ${_hora.format(context)}'),
              onPressed: () async {
                final elegida = await showTimePicker(context: context, initialTime: _hora);
                if (elegida != null) await _cambiar(hora: elegida);
              },
            ),
          ],
        ],
      ),
    );
  }
}
