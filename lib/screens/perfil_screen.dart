import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ajuste_dos_pasos.dart';
import '../widgets/ajuste_recordatorio.dart';
import '../widgets/reportar_problema.dart';
import '../widgets/legal.dart';
import '../widgets/primeros_pasos.dart';
import '../widgets/selector_colores.dart';
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

  /// Link para invitar a otros prestamistas a usar la app.
  String get _linkInvitar => '$kDominioBase/i/${perfil['slug']}';

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
                        Text(telefono, style: TextStyle(color: AppColors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('MI PLAN',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          const TarjetaMiPlan(),
          if (perfil['es_admin'] == true)
            Panel(
              borde: AppColors.amber.withValues(alpha: 0.5),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AdminScreen())),
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings_rounded, color: AppColors.amber),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Administrar prestamistas',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.grey),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text('TU LINK PARA CLIENTES',
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
                          style: TextStyle(
                              color: AppColors.green, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'Copiar',
                      icon: Icon(Icons.copy, color: AppColors.grey),
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
                  onPressed: () {
                    Share.share(mensajeLinkSolicitudes(perfil['slug'] as String? ?? ''));
                    marcarLinkCompartido(); // paso de la guía de primeros pasos
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir por WhatsApp'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('INVITA A OTRO PRESTAMISTA',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.card_giftcard_rounded, color: AppColors.green),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Gana 1 mes gratis',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Si un prestamista se registra con tu link y paga su primer plan, '
                  'te regalamos 1 mes de tu plan.',
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(_linkInvitar,
                          style: TextStyle(
                              color: AppColors.green, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'Copiar',
                      icon: Icon(Icons.copy, color: AppColors.grey),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _linkInvitar));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Link copiado')));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Share.share(
                    'Te recomiendo CrediSantiago para llevar tus préstamos y cobros desde el '
                    'celular: tus clientes te piden por un link, la mora se calcula sola y '
                    'cobras por WhatsApp. Regístrate con mi link: $_linkInvitar',
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text('Invitar por WhatsApp'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('COBRADORES',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Panel(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CobradoresScreen(perfil: perfil))),
            child: Row(
              children: [
                Icon(Icons.delivery_dining_rounded, color: AppColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mis cobradores', style: TextStyle(fontWeight: FontWeight.w800)),
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
          Text('APARIENCIA',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          const SelectorColores(),
          const SizedBox(height: 8),
          const AjusteRecordatorio(),
          const SizedBox(height: 8),
          const AjusteDosPasos(),
          const SizedBox(height: 8),
          BotonReportarProblema(nombre: (perfil['nombre'] as String?) ?? ''),
          const SizedBox(height: 8),
          Text('MI RECIBO Y CONTRATO',
              style: TextStyle(color: AppColors.grey, fontSize: 12, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Panel(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MiReciboScreen(perfil: perfil))),
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: AppColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Personalizar mi recibo y contrato',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('Logo, nombre del negocio, teléfono, cédula o RNC y mensaje al pie',
                          style: TextStyle(color: AppColors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.grey),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('SOLICITUDES',
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
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
              value: _exigirEvidencias,
              onChanged: _cambiarExigir,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: BorderSide(color: AppColors.red),
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
                        child: Text('Cerrar sesión',
                            style: TextStyle(color: AppColors.red))),
                  ],
                ),
              );
              if (confirmar == true) await SupabaseService.instance.cerrarSesion();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 24),
          // La cuenta del administrador no se borra desde la app.
          if (perfil['es_admin'] != true)
            const BotonBorrarCuenta(
              queSeBorra: 'Se borran tu cuenta, tus clientes, solicitudes, préstamos, cobros, '
                  'gastos, cobradores, fotos, logo y contratos firmados.',
            ),
        ],
      ),
    );
  }
}
