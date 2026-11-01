import 'package:flutter/material.dart';

import '../logic/dominio.dart';
import '../logic/volver_a_prestar.dart';
import '../logic/whatsapp.dart';
import '../services/consultas_extra.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/contacto.dart';
import '../widgets/ui.dart';
import 'cliente_detalle_screen.dart';

/// "Pagaron todo y no tienen préstamo": clientes buenos a los que se les
/// puede ofrecer otro. Cada uno con su botón de WhatsApp con el mensaje y
/// el link de solicitudes ya escritos.
class VolverAPrestarScreen extends StatefulWidget {
  final String prestamistaId;
  const VolverAPrestarScreen({super.key, required this.prestamistaId});

  @override
  State<VolverAPrestarScreen> createState() => _VolverAPrestarScreenState();
}

class _VolverAPrestarScreenState extends State<VolverAPrestarScreen> {
  List<Map<String, dynamic>>? _clientes;
  String? _error;

  /// Link de solicitudes del prestamista (/s/{slug}); vacío si no tiene.
  String _link = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final servicio = SupabaseService.instance;
    try {
      final clientes = await servicio.listarClientes(widget.prestamistaId);
      final prestamos = await estadosDePrestamos(widget.prestamistaId);
      final perfil = await servicio.perfilDelNegocio();
      final slug = (perfil?['slug'] as String?)?.trim() ?? '';
      if (!mounted) return;
      setState(() {
        _clientes = clientesParaVolverAPrestar(clientes, prestamos);
        _link = slug.isEmpty ? '' : '$kDominioBase/s/$slug';
        _error = null;
      });
    } catch (e, pila) {
      registrarError(e, pila, 'VOLVER A PRESTAR');
      if (mounted) setState(() => _error = mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _clientes;
    return Scaffold(
      appBar: AppBar(title: const Text('Volver a prestarles')),
      body: clientes == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar la lista.\n$_error'))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                      'Pagaron todo y no tienen préstamo: '
                      '${plural(clientes.length, 'cliente', 'clientes')}. '
                      'Escríbeles para ofrecerles otro.',
                      style: TextStyle(color: AppColors.grey, fontSize: 14)),
                  const SizedBox(height: 12),
                  if (clientes.isEmpty)
                    const Vacio(
                        icono: Icons.verified_rounded,
                        texto: 'Por ahora nadie. Aquí salen los clientes que terminan de '
                            'pagar y no tienen otro préstamo.'),
                  for (final c in clientes) _fila(c),
                ],
              ),
            ),
    );
  }

  Widget _fila(Map<String, dynamic> c) {
    final nombre = (c['nombre'] as String?) ?? '';
    final telefono = (c['telefono'] as String?) ?? '';
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ClienteDetalleScreen(clienteId: c['id'] as String),
      )),
      child: Row(
        children: [
          AvatarIniciales(nombre: nombre, fotoUrl: c['foto_cara_url'] as String?, tamano: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(telefono.isEmpty ? 'Sin teléfono' : telefono,
                    style: TextStyle(color: AppColors.grey, fontSize: 13)),
              ],
            ),
          ),
          if (telefono.isNotEmpty)
            BotonWhatsApp(
              tooltip: 'Ofrecerle otro préstamo',
              onPressed: () => abrirWhatsApp(
                  context, telefono, mensajeVolverAPrestar(nombreCliente: nombre, link: _link)),
            ),
        ],
      ),
    );
  }
}
