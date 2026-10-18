import 'package:flutter/material.dart';

import '../logic/caja.dart';
import '../logic/cobradores.dart';
import '../recibos/recibo_pdf.dart' show numeroReciboTexto;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/selector_colores.dart';
import '../widgets/ui.dart';
import 'inicio_screen.dart';

/// La app del cobrador: su ruta del día, lo que ha cobrado hoy y su
/// cuenta. No ve reportes, ganancias ni solicitudes, ni presta: eso lo
/// bloquea la base de datos, y aquí ni se muestra.
class CobradorShell extends StatefulWidget {
  final SesionCobrador sesion;
  const CobradorShell({super.key, required this.sesion});

  @override
  State<CobradorShell> createState() => _CobradorShellState();
}

class _CobradorShellState extends State<CobradorShell> {
  static const _ruta = 0, _caja = 1, _yo = 2;
  int _tab = _ruta;

  /// Cambia cada vez que se entra a "Mi caja", para que recargue.
  int _versionCaja = 0;

  void _ir(int tab) => setState(() {
        if (tab == _caja && _tab != _caja) _versionCaja++;
        _tab = tab;
      });

  @override
  void initState() {
    super.initState();
    darBienvenida(context, widget.sesion.cobradorNombre);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sesion;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          InicioScreen(
            // El id del jefe: los préstamos son suyos. El nombre, el del cobrador.
            perfil: {'id': s.prestamistaId, 'nombre': s.cobradorNombre},
            solicitudesNuevas: 0,
            onVerSolicitudes: () {},
            onVerPerfil: () => _ir(_yo),
            modoCobrador: true,
            negocioDelJefe: s.negocio,
          ),
          MiCajaCobrador(key: ValueKey(_versionCaja)),
          _Yo(sesion: s),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _ir,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route_rounded),
                label: 'Mi ruta'),
            NavigationDestination(
                icon: Icon(Icons.payments_outlined),
                selectedIcon: Icon(Icons.payments_rounded),
                label: 'Mi caja'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Yo'),
          ],
        ),
      ),
    );
  }
}

/// Lo que el cobrador ha cobrado hoy: el total que tiene que entregar y
/// cada cobro.
class MiCajaCobrador extends StatefulWidget {
  /// Para pruebas: los cobros ya cargados (si es null, los busca).
  final List<CobroCaja>? cobros;

  /// Para pruebas: la entrega de hoy (si [cobros] se da, no se busca).
  final Entrega? entrega;
  const MiCajaCobrador({super.key, this.cobros, this.entrega});

  @override
  State<MiCajaCobrador> createState() => _MiCajaCobradorState();
}

class _MiCajaCobradorState extends State<MiCajaCobrador> {
  late List<CobroCaja>? _cobros = widget.cobros;
  late Entrega? _entrega = widget.entrega;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.cobros == null) _cargar();
  }

  Future<void> _cargar() async {
    try {
      final servicio = SupabaseService.instance;
      final cobros = await servicio.misCobrosDeHoy();
      final entrega = await servicio.miEntregaDeHoy();
      if (mounted) {
        setState(() {
          _cobros = cobros;
          _entrega = entrega;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL MI CAJA: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _hora(DateTime f) {
    final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
    return '$h:${f.minute.toString().padLeft(2, '0')} ${f.hour < 12 ? 'am' : 'pm'}';
  }

  @override
  Widget build(BuildContext context) {
    final cobros = _cobros;
    final hoy = DateTime.now();
    final dia = DiaCaja(DateTime(hoy.year, hoy.month, hoy.day), cobros ?? const []);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi caja de hoy')),
      body: _error != null
          ? Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar tu caja.\n$_error')
          : cobros == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Panel(
                        borde: AppColors.green.withValues(alpha: 0.4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('COBRASTE HOY',
                                style: TextStyle(
                                    color: AppColors.green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                            Text(rd(dia.total),
                                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                            Text('${dia.cantidad} cobro(s) · esto es lo que entregas',
                                style: TextStyle(color: AppColors.grey)),
                            if (dia.mora > 0)
                              Text('De eso, mora: ${rd(dia.mora)}',
                                  style: TextStyle(color: AppColors.red, fontSize: 13)),
                            if (_entrega case final e?) ...[
                              const Divider(height: 20),
                              Text(
                                'Tu jefe recibió ${rd(e.entregado)} · '
                                '${cuadre(cobrado: dia.total, entregado: e.entregado).texto}',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Tus cobros de hoy',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (cobros.isEmpty)
                        Text('Todavía no has cobrado hoy.',
                            style: TextStyle(color: AppColors.grey)),
                      for (final c in dia.cobros)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text(_hora(c.fecha),
                              style: TextStyle(color: AppColors.grey, fontSize: 12)),
                          title: Text(c.cliente,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: c.anulado ? AppColors.grey : null,
                                  decoration: c.anulado ? TextDecoration.lineThrough : null)),
                          subtitle: Text(
                            'Recibo ${numeroReciboTexto(c.numeroRecibo)}'
                            '${c.anulado ? ' · ANULADO por tu jefe' : ''}',
                            style: TextStyle(
                                color: c.anulado ? AppColors.red : AppColors.grey, fontSize: 12),
                          ),
                          trailing: Text(rd(c.monto),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: c.anulado ? AppColors.grey : null,
                                  decoration: c.anulado ? TextDecoration.lineThrough : null)),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _Yo extends StatelessWidget {
  final SesionCobrador sesion;
  const _Yo({required this.sesion});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            child: Row(
              children: [
                AvatarIniciales(nombre: sesion.cobradorNombre, tamano: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sesion.cobradorNombre,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('Cobrador de ${sesion.negocio}',
                          style: TextStyle(color: AppColors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Panel(
            child: Text(
              'Ves y cobras solo a los clientes que tu jefe te asignó. '
              'Si te equivocas en un cobro, avísale para que lo anule.',
              style: TextStyle(color: AppColors.grey),
            ),
          ),
          const SizedBox(height: 8),
          const SelectorColores(),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: BorderSide(color: AppColors.red),
            ),
            onPressed: () => SupabaseService.instance.cerrarSesion(),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
