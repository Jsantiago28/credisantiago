import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sin_conexion.dart';
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
    // Sin señal no se cierra: para volver a entrar hace falta internet y el
    // cobrador se quedaría sin poder cobrar. Se cierra cuando vuelva.
    if (await _sinSenal()) return;
    // Antes de salir, que suban los cobros hechos sin señal (si falla, no
    // se pierden: quedan en el teléfono y suben al volver a entrar).
    try {
      await SinConexion.subir();
    } catch (_) {}
    cerradaPorInactividad = true;
    await SupabaseService.instance.cerrarSesion();
  }
}

/// La última vez que se miró si hay internet, y qué salió: sin señal no se
/// vuelve a preguntar cada medio minuto (gasta batería y datos).
DateTime? _miradoEn;
bool _ultimoSinSenal = false;
const _cadaCuanto = Duration(minutes: 2);

/// No hay internet ahora mismo (solo cuenta en la app de Android, donde se
/// puede cobrar sin señal).
Future<bool> _sinSenal() async {
  if (!SinConexion.disponible) return false;
  final ahora = DateTime.now();
  if (_miradoEn != null && ahora.difference(_miradoEn!) < _cadaCuanto) return _ultimoSinSenal;
  _miradoEn = ahora;
  try {
    await SupabaseService.instance.client
        .from('ajustes_app')
        .select('id')
        .limit(1)
        .timeout(const Duration(seconds: 5));
    _ultimoSinSenal = false;
  } catch (e) {
    _ultimoSinSenal = SinConexion.esFaltaDeConexion(e);
  }
  SinConexion.sinSenal.value = _ultimoSinSenal;
  return _ultimoSinSenal;
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
