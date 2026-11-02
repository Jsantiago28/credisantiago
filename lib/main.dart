import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/dos_pasos.dart';
import 'services/errores.dart';
import 'services/inactividad.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'screens/codigo_dos_pasos_screen.dart';
import 'screens/login_screen.dart';
import 'screens/nueva_clave_screen.dart';
import 'screens/registro_screen.dart';
import 'logic/cobradores.dart';
import 'screens/cobrador_shell.dart';
import 'screens/home_shell.dart';
import 'screens/solicitud_publica_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  // Los errores que nadie esperaba se guardan para el admin (Admin → Errores).
  await Errores.iniciar();
  await ModoColor.cargar();
  // Si la app se dejó más de 40 minutos sin usar, se entra de nuevo.
  await Inactividad.revisarAlAbrir();
  runApp(const VigilanteInactividad(child: PrestamistasRDApp()));
}

class PrestamistasRDApp extends StatelessWidget {
  const PrestamistasRDApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Al elegir otro modo (claro u oscuro) cambia el tema de toda la app.
    return ValueListenableBuilder<ModoColor>(
      valueListenable: ModoColor.actual,
      builder: (context, modo, _) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'CrediSantiago',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.app(),
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');
        // Link de invitación de otro prestamista: se recuerda quién invitó
        // y se sigue al registro de siempre.
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'i') {
          SupabaseService.instance.guardarInvitacion(uri.pathSegments[1]);
          return MaterialPageRoute(builder: (_) => const _Router());
        }
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 's') {
          final slug = uri.pathSegments[1];
          return MaterialPageRoute(
            builder: (_) => SolicitudPublicaScreen(slug: slug),
          );
        }
        return MaterialPageRoute(builder: (_) => const _Router());
      },
    );
  }
}

/// Escucha los cambios de sesión (login por código o por link) y decide
/// qué pantalla mostrar: Login, Registro (crear perfil/slug) o el Inicio.
class _Router extends StatefulWidget {
  const _Router();

  @override
  State<_Router> createState() => _RouterState();
}

/// Quien entró: un prestamista (con su perfil), un cobrador invitado, o
/// alguien nuevo que tiene que registrar su negocio (los dos null).
typedef _QuienEntra = ({Map<String, dynamic>? perfil, SesionCobrador? cobrador});

Future<_QuienEntra> _quienEntra() async {
  final servicio = SupabaseService.instance;
  final perfil = await servicio.obtenerMiPerfil();
  if (perfil != null) {
    servicio.sesionCobrador = null;
    return (perfil: perfil, cobrador: null);
  }
  return (perfil: null, cobrador: await servicio.entrarComoCobrador());
}

class _RouterState extends State<_Router> {
  late final Stream<AuthState> _authStream;

  /// Sube con "Reintentar" para volver a buscar quién entró.
  var _intento = 0;

  @override
  void initState() {
    super.initState();
    _authStream = SupabaseService.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      builder: (context, authSnapshot) {
        final session = SupabaseService.instance.client.auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        // Tiene la verificación en dos pasos: falta el código de su app.
        if (DosPasos.faltaCodigo) {
          return const CodigoDosPasosScreen();
        }

        // Entró con código por "¿Olvidaste tu contraseña?": primero crea
        // una contraseña nueva y después sigue a la app.
        if (SupabaseService.instance.pedirNuevaClave) {
          return NuevaClaveScreen(
            alTerminar: () => setState(() => SupabaseService.instance.pedirNuevaClave = false),
          );
        }

        return FutureBuilder<_QuienEntra>(
          // key fuerza a recargar el perfil cada vez que cambia la sesión
          key: ValueKey('${session.user.id}-$_intento'),
          future: _quienEntra(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            // No se pudo saber quién es (sin señal, o falló la base de
            // datos): NO se manda a registrar un negocio, se reintenta.
            if (snapshot.hasError) {
              return ErrorAlEntrar(
                onReintentar: () => setState(() => _intento++),
                onSalir: () => SupabaseService.instance.cerrarSesion(),
              );
            }
            final quien = snapshot.data;
            if (quien?.cobrador != null) return CobradorShell(sesion: quien!.cobrador!);
            // Cobrador cuyo jefe no tiene plan para cobradores: se le avisa
            // (no se le manda a registrar un negocio).
            final jefeSinPlan = SupabaseService.instance.cobradorSinPlan;
            if (quien?.perfil == null && jefeSinPlan != null) {
              return CobradorSinPlan(negocio: jefeSinPlan);
            }
            if (quien?.perfil == null) {
              return const RegistroScreen();
            }
            return const HomeShell();
          },
        );
      },
    );
  }
}

/// No se pudo cargar quién entró: en vez de mandarlo a registrarse (un
/// cobrador podría crear un negocio sin querer), se le deja reintentar.
class ErrorAlEntrar extends StatelessWidget {
  final VoidCallback onReintentar;
  final VoidCallback onSalir;
  const ErrorAlEntrar({super.key, required this.onReintentar, required this.onSalir});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                const Text('No pudimos cargar tu cuenta',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Revisa tu internet e intenta de nuevo.', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: onReintentar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
                TextButton(onPressed: onSalir, child: const Text('Salir de la cuenta')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}