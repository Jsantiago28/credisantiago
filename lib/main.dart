import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
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
  await ModoColor.cargar();
  runApp(const PrestamistasRDApp());
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

        return FutureBuilder<_QuienEntra>(
          // key fuerza a recargar el perfil cada vez que cambia la sesión
          key: ValueKey(session.user.id),
          future: _quienEntra(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final quien = snapshot.data;
            if (quien?.cobrador != null) return CobradorShell(sesion: quien!.cobrador!);
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