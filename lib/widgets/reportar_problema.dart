import 'package:flutter/material.dart';

import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Perfil: "Reportar un problema". El usuario escribe qué le pasó y le llega
/// al admin en Admin → "Errores de la app" (con su nombre y correo).
class BotonReportarProblema extends StatelessWidget {
  /// Nombre de quien reporta (el negocio o el cobrador).
  final String nombre;
  const BotonReportarProblema({super.key, required this.nombre});

  Future<void> _abrir(BuildContext context) async {
    final texto = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Reportar un problema'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cuéntanos qué pasó y en qué pantalla. Lo revisamos y te escribimos.',
                  style: TextStyle(color: AppColors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: texto,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                onChanged: (_) => setEstado(() {}),
                decoration: const InputDecoration(
                  hintText: 'Ej. Al cobrar a Juan me salió un error',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            TextButton(
              onPressed: texto.text.trim().length < 5 ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (enviar != true || !context.mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final correo = SupabaseService.instance.usuarioActual?.email ?? '';
      await Errores.reportarProblema(texto.text, quien: '$nombre ($correo)');
      mensajero.showSnackBar(
          const SnackBar(content: Text('¡Gracias! Recibimos tu reporte y lo vamos a revisar.')));
    } catch (e, pila) {
      registrarError(e, pila, 'REPORTAR PROBLEMA');
      mensajero.showSnackBar(SnackBar(content: Text(mensajeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: () => _abrir(context),
      child: Row(
        children: [
          Icon(Icons.support_agent_rounded, color: AppColors.green),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reportar un problema', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('¿Algo no funciona bien? Avísanos desde aquí.', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }
}
