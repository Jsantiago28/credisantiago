import 'dart:async';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'clientes_screen.dart';
import 'inicio_screen.dart';
import 'perfil_screen.dart';
import 'planes_screen.dart';
import 'reportes_screen.dart';
import 'solicitudes_screen.dart';

/// Pantalla principal del prestamista: barra de navegación de abajo con
/// Inicio, Solicitudes, Clientes, Reportes y Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _inicio = 0, _solicitudes = 1, _clientes = 2, _reportes = 3, _perfil = 4;

  int _tab = _inicio;
  Map<String, dynamic>? _perfilDatos;
  StreamSubscription? _solicitudesSub;

  /// Solicitudes nuevas (en vivo). Una sola conexión para el número de la
  /// barra y para la pestaña Solicitudes: dos conexiones iguales a la misma
  /// tabla pueden estorbarse. Null mientras carga.
  List<Map<String, dynamic>>? _nuevas;
  String? _errorSolicitudes;
  int get _solicitudesNuevas => _nuevas?.length ?? 0;

  /// Cambian cada vez que se entra a Reportes / Clientes, para que recarguen.
  int _versionReportes = 0;
  int _versionClientes = 0;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _solicitudesSub?.cancel();
    super.dispose();
  }

  Future<void> _cargarPerfil() async {
    final perfil = await SupabaseService.instance.obtenerMiPerfil();
    if (!mounted || perfil == null) return;
    setState(() => _perfilDatos = perfil);
    // Solo las cuentas aprobadas escuchan sus solicitudes (antes de la
    // migración de planes no existe "aprobado": se toma como aprobada).
    if (perfil['aprobado'] != false) _escucharSolicitudes(perfil['id'] as String);
  }

  void _escucharSolicitudes(String prestamistaId) {
    _solicitudesSub?.cancel();
    _solicitudesSub = SupabaseService.instance.solicitudesNuevasStream(prestamistaId).listen(
      (todas) {
        if (!mounted) return;
        setState(() {
          _nuevas = todas.where((s) => s['estado'] == 'nueva').toList()
            ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
          _errorSolicitudes = null;
        });
      },
      onError: (e) {
        // ignore: avoid_print
        print('ERROR REAL SOLICITUDES EN VIVO: $e');
        if (mounted) setState(() => _errorSolicitudes = '$e');
      },
    );
  }

  void _ir(int tab) => setState(() {
        if (tab == _reportes && _tab != _reportes) _versionReportes++;
        if (tab == _clientes && _tab != _clientes) _versionClientes++;
        _tab = tab;
      });

  @override
  Widget build(BuildContext context) {
    final perfil = _perfilDatos;
    if (perfil == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final id = perfil['id'] as String;

    // Registro cerrado: la cuenta espera que el administrador la apruebe.
    if (perfil['aprobado'] == false) {
      return CuentaEnRevisionScreen(perfil: perfil, onRecargar: _cargarPerfil);
    }

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          InicioScreen(
            perfil: perfil,
            solicitudesNuevas: _solicitudesNuevas,
            onVerSolicitudes: () => _ir(_solicitudes),
            onVerPerfil: () => _ir(_perfil),
          ),
          SolicitudesScreen(
            prestamistaId: id,
            nuevas: _nuevas,
            error: _errorSolicitudes,
            onReintentar: () {
              setState(() => _errorSolicitudes = null);
              _escucharSolicitudes(id);
            },
          ),
          ClientesScreen(key: ValueKey(_versionClientes), prestamistaId: id),
          ReportesScreen(key: ValueKey(_versionReportes), prestamistaId: id),
          PerfilScreen(perfil: perfil),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _ir,
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _solicitudesNuevas > 0,
                label: Text('$_solicitudesNuevas'),
                child: const Icon(Icons.description_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _solicitudesNuevas > 0,
                label: Text('$_solicitudesNuevas'),
                child: const Icon(Icons.description_rounded),
              ),
              label: 'Solicitudes',
            ),
            const NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Clientes'),
            const NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart_rounded),
                label: 'Reportes'),
            const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}
