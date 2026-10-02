import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../logic/validacion.dart';
import '../theme/app_theme.dart';
import '../widgets/formato_campos.dart';
import 'link_generado_screen.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _nombreCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  Future<void> _crearPerfil() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Escribe tu nombre para generar tu link');
      return;
    }
    final errorWhatsApp = errorTelefono(_whatsappCtrl.text);
    if (errorWhatsApp != null) {
      setState(() => _error = 'WhatsApp: $errorWhatsApp');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final user = SupabaseService.instance.usuarioActual;
      final slug = await SupabaseService.instance.crearPerfilConSlug(
        userId: user!.id,
        // En modo de prueba con email, usamos el email como identificador.
        // Cuando actives el SMS real, esto vuelve a ser user.phone.
        // Ojo: con correo, Supabase deja user.phone como "" (vacío, no null),
        // y "phone" es único: si se guardara "", el segundo registro chocaría.
        telefono: [user.phone, user.email].firstWhere(
          (x) => x != null && x.trim().isNotEmpty,
          orElse: () => 'sin-telefono-${user.id}',
        )!,
        nombre: _nombreCtrl.text.trim(),
      );
      // Aparte: si falta la migración de pagos de planes (sin la columna
      // whatsapp), el registro igual se completa.
      try {
        await SupabaseService.instance
            .guardarMiWhatsApp(user.id, formatearTelefono(_whatsappCtrl.text));
      } catch (e) {
        // ignore: avoid_print
        print('ERROR REAL WHATSAPP REGISTRO: $e');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LinkGeneradoScreen(slug: slug)),
      );
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL REGISTRO: $e');
      setState(() => _error = 'No pudimos crear tu perfil. Intenta de nuevo.\n($e)');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crea tu perfil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Cómo te llamas o cómo llamas tu negocio?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Con esto generamos tu link personal para mandar a tus clientes.',
              style: TextStyle(color: AppColors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nombreCtrl,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Ej: Juan Préstamos',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Tu WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Para avisarte cuando aprueben tu cuenta o te toque renovar.',
                style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _whatsappCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FormatoTelefono()],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: '809-555-1234',
                prefixIcon: const Icon(Icons.chat_rounded, color: AppColors.green),
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
              Text(_error!, style: const TextStyle(color: AppColors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _cargando ? null : _crearPerfil,
              child: _cargando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Generar mi link'),
            ),
          ],
        ),
      ),
    );
  }
}
