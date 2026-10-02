import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'admin_screen.dart';
import 'cobradores_screen.dart';
import 'link_generado_screen.dart' show kDominioBase;
import 'mi_recibo_screen.dart';
import 'planes_screen.dart';

/// Perfil del prestamista: sus datos, su link para clientes y cerrar sesión.
class PerfilScreen extends StatefulWidget {
  final Map<String, dynamic> perfil;
  const PerfilScreen({super.key, required this.perfil});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  Map<String, dynamic> get perfil => widget.perfil;
  late bool _exigirEvidencias = perfil['exigir_evidencias'] == true;

  String get _link => '$kDominioBase/s/${perfil['slug']}';

  Future<void> _cambiarExigir(bool valor) async {
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _exigirEvidencias = valor);
    try {
      await SupabaseService.instance.cambiarExigirEvidencias(perfil['id'] as String, valor);
      perfil['exigir_evidencias'] = valor;
    } catch (e) {
      if (mounted) setState(() => _exigirEvidencias = !valor);
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = (perfil['nombre'] as String?) ?? '';
    final telefono = (perfil['phone'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            child: Row(
              children: [
                AvatarIniciales(nombre: nombre, tamano: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      if (telefono.isNotEmpty)
                        Text(telefono, style: const TextStyle(color: AppColors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('MI PLAN',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          const TarjetaMiPlan(),
          if (perfil['es_admin'] == true)
            Panel(
              borde: AppColors.amber.withValues(alpha: 0.5),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AdminScreen())),
              child: const Row(
                children: [
                  Icon(Icons.admin_panel_settings_rounded, color: AppColors.amber),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Administrar prestamistas',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.grey),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text('TU LINK PARA CLIENTES',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Panel(
            borde: AppColors.green.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_link,
                          style: const TextStyle(
                              color: AppColors.green, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy, color: AppColors.grey),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _link));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Link copiado')));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Share.share(
                    'Solicita tu préstamo aquí sin venir a mi casa, llena esto y te digo si te apruebo: $_link',
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir por WhatsApp'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('COBRADORES',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Panel(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CobradoresScreen(perfil: perfil))),
            child: const Row(
              children: [
                Icon(Icons.delivery_dining_rounded, color: AppColors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mis cobradores', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('Agrégalos y repárteles los clientes',
                          style: TextStyle(color: AppColors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.grey),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('MI RECIBO',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Panel(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MiReciboScreen(perfil: perfil))),
            child: const Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: AppColors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Personalizar mi recibo', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('Logo, nombre del negocio, teléfono y mensaje al pie',
                          style: TextStyle(color: AppColors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.grey),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('SOLICITUDES',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.green,
              title: const Text('Exigir evidencia de ingresos',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                _exigirEvidencias
                    ? 'Tu link no deja enviar la solicitud sin al menos una foto '
                        '(volante de pago, carta de trabajo o estado de cuenta).'
                    : 'Es opcional: el cliente puede subirla o no.',
                style: const TextStyle(color: AppColors.grey, fontSize: 12),
              ),
              value: _exigirEvidencias,
              onChanged: _cambiarExigir,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
            ),
            onPressed: () async {
              final confirmar = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: const Text('¿Cerrar sesión?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar')),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Cerrar sesión',
                            style: TextStyle(color: AppColors.red))),
                  ],
                ),
              );
              if (confirmar == true) await SupabaseService.instance.cerrarSesion();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
