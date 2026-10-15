import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart' show minimoClave;

/// Después de entrar con código por "¿Olvidaste tu contraseña?": crear una
/// contraseña nueva. También la usan, una sola vez, las cuentas de antes
/// que entraban solo con código.
class NuevaClaveScreen extends StatefulWidget {
  final VoidCallback alTerminar;
  const NuevaClaveScreen({super.key, required this.alTerminar});

  @override
  State<NuevaClaveScreen> createState() => _NuevaClaveScreenState();
}

class _NuevaClaveScreenState extends State<NuevaClaveScreen> {
  final _clave = TextEditingController();
  final _clave2 = TextEditingController();
  bool _ver = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _clave.dispose();
    _clave2.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_clave.text.length < minimoClave) {
      setState(() => _error = 'La contraseña debe tener al menos $minimoClave caracteres');
      return;
    }
    if (_clave.text != _clave2.text) {
      setState(() => _error = 'Las dos contraseñas no son iguales');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.cambiarClave(_clave.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Listo. Desde ahora entras con tu correo y esta contraseña.')));
      widget.alTerminar();
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL NUEVA CLAVE: $e');
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar. Prueba con otra contraseña.';
        });
      }
    }
  }

  Widget _campo(TextEditingController c, String etiqueta) => TextField(
        controller: c,
        obscureText: !_ver,
        autofillHints: const [AutofillHints.newPassword],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: Icon(Icons.lock, color: AppColors.green),
          suffixIcon: IconButton(
            tooltip: _ver ? 'Ocultar' : 'Ver',
            icon: Icon(_ver ? Icons.visibility_off : Icons.visibility, color: AppColors.grey),
            onPressed: () => setState(() => _ver = !_ver),
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crea tu contraseña')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ya entraste con el código. Ahora crea la contraseña con la que vas a '
                    'entrar de aquí en adelante.',
                    style: TextStyle(color: AppColors.grey, fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  _campo(_clave, 'Contraseña nueva'),
                  const SizedBox(height: 12),
                  _campo(_clave2, 'Repite la contraseña'),
                  const SizedBox(height: 6),
                  Text('Mínimo $minimoClave caracteres.',
                      style: TextStyle(color: AppColors.grey, fontSize: 12)),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: AppColors.red)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar contraseña'),
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
