import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/whatsapp.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Verde de WhatsApp, para que el botón se reconozca de una vez.
const verdeWhatsApp = Color(0xFF25D366);

/// Abre el chat de WhatsApp del teléfono con el mensaje ya escrito.
Future<void> abrirWhatsApp(BuildContext context, String? telefono, String mensaje) async {
  final mensajero = ScaffoldMessenger.of(context);
  final enlace = enlaceWhatsApp(telefono, mensaje);
  if (enlace == null) {
    mensajero.showSnackBar(
        SnackBar(content: Text('El teléfono "${telefono ?? ''}" no es válido para WhatsApp.')));
    return;
  }
  if (!await launchUrl(enlace, mode: LaunchMode.externalApplication)) {
    mensajero.showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
  }
}

/// Abre WhatsApp con el mensaje de cobro que corresponde al estado de hoy.
Future<void> whatsAppCobro(
  BuildContext context, {
  required String nombreCliente,
  required String? telefono,
  required EstadoPrestamo estado,
}) async {
  final perfil = await SupabaseService.instance.perfilDelNegocio();
  if (!context.mounted) return;
  final mensaje = mensajeCobro(
    nombreCliente: nombreCliente,
    negocio: (perfil?['nombre'] as String?) ?? 'su prestamista',
    estado: estado,
    hoy: DateTime.now(),
  );
  await abrirWhatsApp(context, telefono, mensaje);
}

/// Llama al teléfono.
Future<void> llamar(BuildContext context, String? telefono) async {
  final digitos = telefono?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
  if (digitos.isEmpty) return;
  if (!await launchUrl(Uri(scheme: 'tel', path: digitos))) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo hacer la llamada.')));
    }
  }
}

/// Botón redondo de WhatsApp.
class BotonWhatsApp extends StatelessWidget {
  final VoidCallback onPressed;
  final double tamano;
  final String tooltip;
  const BotonWhatsApp(
      {super.key, required this.onPressed, this.tamano = 48, this.tooltip = 'Cobrar por WhatsApp'});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tamano,
      height: tamano,
      child: IconButton.filled(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: verdeWhatsApp.withValues(alpha: 0.15),
          foregroundColor: verdeWhatsApp,
        ),
        onPressed: onPressed,
        icon: Icon(Icons.chat_rounded, size: tamano * 0.5),
      ),
    );
  }
}

/// Fila con botones de WhatsApp y llamada, con el número a la vista.
class FilaContacto extends StatelessWidget {
  final String? telefono;
  final VoidCallback onWhatsApp;
  const FilaContacto({super.key, required this.telefono, required this.onWhatsApp});

  @override
  Widget build(BuildContext context) {
    final tel = telefono ?? '';
    return Row(
      children: [
        Icon(Icons.phone_rounded, size: 16, color: AppColors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(tel.isEmpty ? 'Sin teléfono' : tel,
              style: TextStyle(color: AppColors.grey)),
        ),
        if (tel.isNotEmpty) ...[
          TextButton.icon(
            // 48 de alto como mínimo: fácil de tocar en la calle.
            style: TextButton.styleFrom(
                foregroundColor: verdeWhatsApp, minimumSize: const Size(48, 48)),
            onPressed: onWhatsApp,
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('WhatsApp'),
          ),
          IconButton(
            tooltip: 'Llamar',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => llamar(context, tel),
            icon: Icon(Icons.call_rounded, color: AppColors.green),
          ),
        ],
      ],
    );
  }
}
