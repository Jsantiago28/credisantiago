import 'package:flutter/material.dart';

import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Admin: los últimos errores que reportó la app en los teléfonos y
/// navegadores (tabla errores_app). Se ve solo si hay alguno.
class PanelErrores extends StatefulWidget {
  const PanelErrores({super.key});

  @override
  State<PanelErrores> createState() => _PanelErroresState();
}

class _PanelErroresState extends State<PanelErrores> {
  List<Map<String, dynamic>> _errores = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final filas = await SupabaseService.instance.client
          .from('errores_app')
          .select()
          .order('creado', ascending: false)
          .limit(50);
      if (mounted) setState(() => _errores = List<Map<String, dynamic>>.from(filas));
    } catch (_) {
      // Sin la migración todavía: no se muestra nada.
    }
  }

  Future<void> _borrarTodos() async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.client.from('errores_app').delete().not('id', 'is', null);
      if (mounted) setState(() => _errores = const []);
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errores.isEmpty) return const SizedBox.shrink();
    return Panel(
      borde: AppColors.red.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_rounded, color: AppColors.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Errores y reportes (${_errores.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              TextButton(onPressed: _borrarTodos, child: const Text('Ya los revisé')),
            ],
          ),
          Text('Fallas de la app y problemas que reportaron los usuarios (con el ícono de soporte).',
              style: TextStyle(color: AppColors.grey, fontSize: 12)),
          for (final e in _errores.take(10))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              // Lo que escribió un usuario ("Reportar un problema"), no un error automático.
              leading: e['pantalla'] == Errores.pantallaReporte
                  ? Icon(Icons.support_agent_rounded, color: AppColors.green)
                  : null,
              title: Text(e['mensaje'] as String? ?? '',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  if (DateTime.tryParse(e['creado'] as String? ?? '') case final f?)
                    fechaLarga(f.toLocal()),
                  e['plataforma'],
                  if ((e['version'] as String? ?? '').isNotEmpty) 'v${e['version']}',
                ].join(' · '),
                style: TextStyle(color: AppColors.grey, fontSize: 11),
              ),
              children: [
                SelectableText(
                  '${e['mensaje']}\n\n${e['detalle'] ?? ''}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
