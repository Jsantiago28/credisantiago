import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  bool _codigoEnviado = false;
  bool _cargando = false;
  String? _error;

  Future<void> _enviarCodigo() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Ingresa un correo válido');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.enviarCodigoEmail(email);
      setState(() => _codigoEnviado = true);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL: $e');
      setState(() => _error = 'No pudimos enviar el código. Intenta de nuevo.');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _verificarCodigo() async {
    final email = _emailCtrl.text.trim();
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.verificarCodigoEmail(
        email: email,
        codigo: _codigoCtrl.text.trim(),
      );
      // main.dart (_Router) detecta la sesión y redirige solo.
      if (mounted) setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL: $e');
      setState(() => _error = 'Código incorrecto. Intenta de nuevo.');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          // En la computadora no se estira de lado a lado.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.green, width: 2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.shield, color: AppColors.green),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'CrediSantiago',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.green,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Text(
                    _codigoEnviado
                        ? 'Ingresa el código'
                        : 'Entrar o registrarte',
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codigoEnviado
                        ? 'Te enviamos un código a ${_emailCtrl.text}'
                        : 'Pon tu correo y te enviamos un código. ¿Primera vez? '
                            'Con ese mismo código registras tu negocio en un minuto.',
                    style: TextStyle(color: AppColors.grey, fontSize: 15),
                  ),
                  const SizedBox(height: 32),
                  if (!_codigoEnviado)
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        prefixIcon:
                            Icon(Icons.email, color: AppColors.green),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    )
                  else
                    TextField(
                      controller: _codigoCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      style: const TextStyle(fontSize: 24, letterSpacing: 8),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _cargando
                        ? null
                        : (_codigoEnviado ? _verificarCodigo : _enviarCodigo),
                    child: _cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_codigoEnviado
                            ? 'Verificar código'
                            : 'Enviar código'),
                  ),
                  if (_codigoEnviado) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _cargando ? null : _enviarCodigo,
                      child: const Text('Reenviar código'),
                    ),
                  ],
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
    );
  }
}
