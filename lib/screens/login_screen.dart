import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/inactividad.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/legal.dart';
import '../widgets/ui.dart' show LogoApp;

/// Lo que se ve en la pantalla de entrada.
enum _Modo {
  /// Correo y contraseña de quien ya tiene cuenta.
  entrar,

  /// Crear cuenta: correo, contraseña y repetirla.
  registrarse,

  /// Olvidó la contraseña (o su cuenta es de antes y nunca tuvo): se le
  /// manda un código para entrar y luego crea una nueva.
  olvide,

  /// Escribir el código que llegó al correo (del registro o de "olvidé").
  codigo,
}

/// Largo mínimo de la contraseña.
const minimoClave = 8;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _claveCtrl = TextEditingController();
  final _clave2Ctrl = TextEditingController();
  final _codigoCtrl = TextEditingController();

  _Modo _modo = _Modo.entrar;

  /// El código que se espera es del registro (si no, de "olvidé").
  bool _codigoDeRegistro = false;
  bool _verClave = false;

  /// Al registrarse: aceptó los Términos y la Política de privacidad.
  bool _aceptaTerminos = false;
  bool _cargando = false;
  String? _error;

  String get _email => _emailCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    // Se cerró sola por 40 minutos sin usarse: se le explica por qué.
    if (Inactividad.cerradaPorInactividad) {
      Inactividad.cerradaPorInactividad = false;
      _error = 'Tu sesión se cerró porque la app estuvo '
          '${Inactividad.limite.inMinutes} minutos sin usarse. Entra de nuevo.';
    }
  }

  @override
  void dispose() {
    for (final c in [_emailCtrl, _claveCtrl, _clave2Ctrl, _codigoCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ir(_Modo modo) => setState(() {
        _modo = modo;
        _error = null;
      });

  /// Corre [accion] mostrando el círculo de carga y el error en palabras.
  Future<void> _hacer(Future<void> Function() accion) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await accion();
    } on AuthException catch (e) {
      // ignore: avoid_print
      print('ERROR REAL AUTH: ${e.code} ${e.message}');
      if (mounted) setState(() => _error = _mensaje(e));
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL: $e');
      if (mounted) setState(() => _error = 'Algo falló. Revisa tu internet e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _mensaje(AuthException e) {
    final texto = '${e.code} ${e.message}'.toLowerCase();
    if (texto.contains('invalid_credentials') || texto.contains('invalid login')) {
      return 'Correo o contraseña incorrectos. Si nunca has creado una contraseña, '
          'toca "¿Olvidaste tu contraseña?".';
    }
    if (texto.contains('rate') || texto.contains('security purposes')) {
      return 'Espera un minuto antes de pedir otro código.';
    }
    if (texto.contains('otp') || texto.contains('token') || texto.contains('expired')) {
      return 'Código incorrecto o vencido. Revísalo o pide otro.';
    }
    if (texto.contains('user_not_found') || texto.contains('signups not allowed')) {
      return 'No hay ninguna cuenta con ese correo. Toca "Registrarme".';
    }
    if (texto.contains('weak') || texto.contains('password')) {
      return 'Esa contraseña no sirve. Usa al menos $minimoClave caracteres.';
    }
    return 'No se pudo: ${e.message}';
  }

  bool _correoValido() {
    if (_email.contains('@') && _email.contains('.')) return true;
    setState(() => _error = 'Escribe un correo válido');
    return false;
  }

  Future<void> _entrar() async {
    if (!_correoValido()) return;
    if (_claveCtrl.text.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña');
      return;
    }
    await _hacer(() async {
      try {
        await SupabaseService.instance.entrarConClave(_email, _claveCtrl.text);
        // main.dart (_Router) ve la sesión y abre la app solo.
      } on AuthException catch (e) {
        // Se registró pero no confirmó el correo: se le manda el código otra vez.
        if ('${e.code} ${e.message}'.toLowerCase().contains('not confirmed')) {
          await SupabaseService.instance.reenviarCodigoRegistro(_email);
          _codigoDeRegistro = true;
          _ir(_Modo.codigo);
          return;
        }
        rethrow;
      }
    });
  }

  Future<void> _registrarse() async {
    if (!_correoValido()) return;
    if (_claveCtrl.text.length < minimoClave) {
      setState(() => _error = 'La contraseña debe tener al menos $minimoClave caracteres');
      return;
    }
    if (_claveCtrl.text != _clave2Ctrl.text) {
      setState(() => _error = 'Las dos contraseñas no son iguales');
      return;
    }
    if (!_aceptaTerminos) {
      setState(() => _error = 'Para crear la cuenta, acepta los Términos y la Política de privacidad');
      return;
    }
    await _hacer(() async {
      final r = await SupabaseService.instance.registrarConClave(_email, _claveCtrl.text);
      switch (r) {
        case ResultadoRegistro.confirmarCorreo:
          _codigoDeRegistro = true;
          _ir(_Modo.codigo);
        case ResultadoRegistro.yaExiste:
          _ir(_Modo.entrar);
          setState(() => _error = 'Ese correo ya tiene cuenta. Entra con tu contraseña, '
              'o toca "¿Olvidaste tu contraseña?".');
        case ResultadoRegistro.listo:
          break; // ya tiene sesión: _Router sigue
      }
    });
  }

  Future<void> _enviarCodigoOlvide() async {
    if (!_correoValido()) return;
    await _hacer(() async {
      await SupabaseService.instance.enviarCodigoOlvide(_email);
      _codigoDeRegistro = false;
      _ir(_Modo.codigo);
    });
  }

  Future<void> _reenviar() => _hacer(() => _codigoDeRegistro
      ? SupabaseService.instance.reenviarCodigoRegistro(_email)
      : SupabaseService.instance.enviarCodigoOlvide(_email));

  Future<void> _verificarCodigo() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.length < 6) {
      setState(() => _error = 'Escribe el código que te llegó al correo');
      return;
    }
    await _hacer(() async {
      final servicio = SupabaseService.instance;
      // Entró por "olvidé": al tener sesión, primero crea su contraseña nueva.
      servicio.pedirNuevaClave = !_codigoDeRegistro;
      try {
        await servicio.verificarCodigoEmail(
            email: _email, codigo: codigo, recuperarClave: !_codigoDeRegistro);
      } catch (_) {
        servicio.pedirNuevaClave = false;
        rethrow;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final (titulo, ayuda) = switch (_modo) {
      _Modo.entrar => ('Iniciar sesión', 'Entra con tu correo y tu contraseña.'),
      _Modo.registrarse => (
          'Crear cuenta',
          'Pon tu correo y una contraseña. Te mandamos un código para confirmar el correo.'
        ),
      _Modo.olvide => (
          '¿Olvidaste tu contraseña?',
          'Te mandamos un código al correo. Con él entras y creas una contraseña nueva.'
        ),
      _Modo.codigo => (
          'Escribe el código',
          'Te lo enviamos a $_email. Revisa también el spam.'
              '${_codigoDeRegistro ? '' : ' Si no te llega, revisa que sea el correo con que te registraste.'}'
        ),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            // En la computadora no se estira de lado a lado.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _marca(context),
                    const SizedBox(height: 32),
                    Text(titulo,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(ayuda, style: TextStyle(color: AppColors.grey, fontSize: 15)),
                    const SizedBox(height: 24),
                    ..._campos(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: AppColors.red)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _cargando
                          ? null
                          : switch (_modo) {
                              _Modo.entrar => _entrar,
                              _Modo.registrarse => _registrarse,
                              _Modo.olvide => _enviarCodigoOlvide,
                              _Modo.codigo => _verificarCodigo,
                            },
                      child: _cargando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(switch (_modo) {
                              _Modo.entrar => 'Entrar',
                              _Modo.registrarse => 'Crear cuenta',
                              _Modo.olvide => 'Enviar código',
                              _Modo.codigo => 'Confirmar código',
                            }),
                    ),
                    const SizedBox(height: 8),
                    ..._enlaces(),
                    const SizedBox(height: 24),
                    Center(
                      child: Text('República Dominicana • RD',
                          style: TextStyle(color: AppColors.grey, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _marca(BuildContext context) => Row(
        children: [
          const LogoApp(tamano: 52),
          const SizedBox(width: 12),
          Text(
            'CrediSantiago',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: AppColors.green, fontWeight: FontWeight.bold),
          ),
        ],
      );

  List<Widget> _campos() {
    if (_modo == _Modo.codigo) {
      return [
        TextField(
          controller: _codigoCtrl,
          keyboardType: TextInputType.number,
          maxLength: 8,
          autofocus: true,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: _decoracion(null, null).copyWith(counterText: ''),
          onSubmitted: (_) => _verificarCodigo(),
        ),
      ];
    }
    return [
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        style: const TextStyle(fontSize: 18),
        decoration: _decoracion('Correo', Icons.email),
      ),
      if (_modo != _Modo.olvide) ...[
        const SizedBox(height: 12),
        _campoClave(_claveCtrl, 'Contraseña',
            alTerminar: _modo == _Modo.entrar ? _entrar : null),
      ],
      if (_modo == _Modo.registrarse) ...[
        const SizedBox(height: 12),
        _campoClave(_clave2Ctrl, 'Repite la contraseña', alTerminar: _registrarse),
        const SizedBox(height: 6),
        Text('Mínimo $minimoClave caracteres.',
            style: TextStyle(color: AppColors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        CasillaAcepto(
          valor: _aceptaTerminos,
          onCambio: (v) => setState(() => _aceptaTerminos = v),
          texto: 'Acepto los',
        ),
      ],
    ];
  }

  Widget _campoClave(TextEditingController c, String etiqueta, {VoidCallback? alTerminar}) =>
      TextField(
        controller: c,
        obscureText: !_verClave,
        autofillHints: [
          _modo == _Modo.registrarse ? AutofillHints.newPassword : AutofillHints.password
        ],
        style: const TextStyle(fontSize: 18),
        onSubmitted: alTerminar == null ? null : (_) => alTerminar(),
        decoration: _decoracion(etiqueta, Icons.lock).copyWith(
          suffixIcon: IconButton(
            tooltip: _verClave ? 'Ocultar' : 'Ver',
            icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility,
                color: AppColors.grey),
            onPressed: () => setState(() => _verClave = !_verClave),
          ),
        ),
      );

  InputDecoration _decoracion(String? etiqueta, IconData? icono) => InputDecoration(
        labelText: etiqueta,
        prefixIcon: icono == null ? null : Icon(icono, color: AppColors.green),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  /// Los enlaces de abajo: olvidé / registrarme / volver / reenviar.
  List<Widget> _enlaces() {
    TextButton enlace(String texto, VoidCallback alTocar) =>
        TextButton(onPressed: _cargando ? null : alTocar, child: Text(texto));

    return switch (_modo) {
      _Modo.entrar => [
          enlace('¿Olvidaste tu contraseña?', () => _ir(_Modo.olvide)),
          const Divider(height: 32),
          Text('¿No tienes cuenta?',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.grey)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _cargando ? null : () => _ir(_Modo.registrarse),
            child: const Text('Registrarme'),
          ),
        ],
      _Modo.registrarse => [enlace('Ya tengo cuenta: iniciar sesión', () => _ir(_Modo.entrar))],
      _Modo.olvide => [enlace('Volver a iniciar sesión', () => _ir(_Modo.entrar))],
      _Modo.codigo => [
          enlace('Reenviar código', _reenviar),
          enlace('Volver', () => _ir(_codigoDeRegistro ? _Modo.registrarse : _Modo.olvide)),
        ],
    };
  }
}
