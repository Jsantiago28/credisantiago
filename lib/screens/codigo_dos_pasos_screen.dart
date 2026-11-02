import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/dos_pasos.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Entró con la contraseña y tiene la verificación en dos pasos: falta el
/// código de 6 números de su app de códigos. Hasta ponerlo, la base de
/// datos no le muestra nada.
class CodigoDosPasosScreen extends StatefulWidget {
  const CodigoDosPasosScreen({super.key});

  @override
  State<CodigoDosPasosScreen> createState() => _CodigoDosPasosScreenState();
}

class _CodigoDosPasosScreenState extends State<CodigoDosPasosScreen> {
  final _codigo = TextEditingController();
  bool _revisando = false;
  String? _error;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final factor = DosPasos.factorActivo;
    if (factor == null || !codigoBienEscrito(_codigo.text)) {
      setState(() => _error = 'Escribe los 6 números que salen en tu app de códigos.');
      return;
    }
    setState(() {
      _revisando = true;
      _error = null;
    });
    try {
      // Si sirve, la sesión cambia y la app sigue sola al Inicio.
      await DosPasos.verificar(factor.id, _codigo.text.replaceAll(' ', ''));
    } catch (e, pila) {
      // Un código malo no es un error de la app: no se reporta.
      if (e is! AuthException) registrarError(e, pila, 'CODIGO DOS PASOS');
      if (mounted) {
        setState(() {
          _revisando = false;
          _error = mensajeCodigo(e);
          _codigo.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: LogoApp(tamano: 52)),
                  const SizedBox(height: 20),
                  Icon(Icons.verified_user_rounded, size: 48, color: AppColors.green),
                  const SizedBox(height: 12),
                  const Text('Escribe tu código',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Tienes la verificación en dos pasos. Abre tu app de códigos '
                    '(Google Authenticator u otra) y escribe los 6 números de CrediSantiago.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _codigo,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(counterText: '', hintText: '000000', errorText: _error),
                    onChanged: (v) {
                      if (v.length == 6 && !_revisando) _entrar();
                    },
                    onSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _revisando ? null : _entrar,
                    child: _revisando
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => SupabaseService.instance.cerrarSesion(),
                    child: const Text('Salir y entrar con otra cuenta'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '¿Perdiste el teléfono con la app de códigos? Escríbele al soporte de '
                    'CrediSantiago por WhatsApp para que te la quiten.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey, fontSize: 13),
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
