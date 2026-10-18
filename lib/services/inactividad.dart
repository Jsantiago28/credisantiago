import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// Cierra la sesión si nadie usa la app por [limite]: así un teléfono
/// olvidado (o prestado) no queda con la cartera abierta. Cuenta también
/// si la app se cerró: al abrirla otra vez se mira cuándo se usó por última
/// vez. Solo aplica con sesión abierta (el formulario de los clientes no).
class Inactividad {
  static const limite = Duration(minutes: 40);
  static const _clave = 'ultima_actividad';

  static DateTime _ultima = DateTime.now();
  static DateTime? _guardada;

  /// La última sesión se cerró por inactividad: la pantalla de entrada lo dice.
  static bool cerradaPorInactividad = false;

  static bool get _haySesion => SupabaseService.instance.client.auth.currentSession != null;

  /// Al abrir la app (antes de mostrar nada): si la sesión guardada lleva
  /// más de [limite] sin usarse, se cierra.
  static Future<void> revisarAlAbrir() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_clave);
      if (ms != null && _haySesion &&
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)) > limite) {
        await _cerrar();
        return;
      }
    } catch (_) {
      // Sin almacenamiento: se cuenta desde ahora.
    }
    tocar();
  }

  /// Alguien usó la app (un toque en la pantalla).
  static void tocar() {
    final ahora = DateTime.now();
    _ultima = ahora;
    // Se guarda en el teléfono como mucho una vez por minuto.
    if (_guardada == null || ahora.difference(_guardada!) > const Duration(minutes: 1)) {
      _guardada = ahora;
      SharedPreferences.getInstance()
          .then((p) => p.setInt(_clave, ahora.millisecondsSinceEpoch))
          .catchError((_) => false);
    }
  }

  /// Cierra la sesión si ya pasó el límite sin usarla.
  static Future<void> revisar() async {
    if (_haySesion && DateTime.now().difference(_ultima) > limite) await _cerrar();
  }

  static Future<void> _cerrar() async {
    cerradaPorInactividad = true;
    await SupabaseService.instance.cerrarSesion();
  }
}

/// Envuelve la app: cada toque cuenta como uso, cada medio minuto (y al
/// volver a la app desde otra) se revisa si ya pasaron los 40 minutos.
class VigilanteInactividad extends StatefulWidget {
  final Widget child;
  const VigilanteInactividad({super.key, required this.child});

  @override
  State<VigilanteInactividad> createState() => _VigilanteInactividadState();
}

class _VigilanteInactividadState extends State<VigilanteInactividad> with WidgetsBindingObserver {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => Inactividad.revisar());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) Inactividad.revisar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => Inactividad.tocar(),
        child: widget.child,
      );
}
