import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../logic/validacion.dart';
import '../theme/app_theme.dart';
import '../widgets/elegir_foto.dart';
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
  final _cedulaCtrl = TextEditingController();
  Uint8List? _fotoFrente;
  Uint8List? _fotoReverso;

  /// Link ya creado: si después falla subir la cédula, al reintentar no se
  /// crea otro perfil.
  String? _slugCreado;
  bool _cargando = false;
  String? _error;

  /// El prestamista que lo invitó, si entró por un link /i/... (null si no).
  ({String id, String nombre})? _invito;

  @override
  void initState() {
    super.initState();
    SupabaseService.instance.quienInvito().then((p) {
      if (mounted && p != null) setState(() => _invito = p);
    });
  }

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
    final errorDeCedula = errorCedula(_cedulaCtrl.text);
    if (errorDeCedula != null) {
      setState(() => _error = 'Cédula: $errorDeCedula');
      return;
    }
    if (_fotoFrente == null || _fotoReverso == null) {
      setState(() => _error = 'Sube la foto de tu cédula de los dos lados');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final servicio = SupabaseService.instance;
      final user = servicio.usuarioActual!;
      final slug = _slugCreado ??= await servicio.crearPerfilConSlug(
        userId: user.id,
        // En modo de prueba con email, usamos el email como identificador.
        // Cuando actives el SMS real, esto vuelve a ser user.phone.
        // Ojo: con correo, Supabase deja user.phone como "" (vacío, no null),
        // y "phone" es único: si se guardara "", el segundo registro chocaría.
        telefono: [user.phone, user.email].firstWhere(
          (x) => x != null && x.trim().isNotEmpty,
          orElse: () => 'sin-telefono-${user.id}',
        )!,
        nombre: _nombreCtrl.text.trim(),
        // Nadie se invita a sí mismo (lo revisa también la base de datos).
        invitadoPor: _invito?.id == user.id ? null : _invito?.id,
      );
      await servicio.olvidarInvitacion();
      // La cédula va después del perfil: la carpeta de fotos de un
      // prestamista solo existe cuando ya tiene perfil.
      final frente =
          await servicio.subirFoto(bytes: _fotoFrente!, prestamistaId: user.id, tipo: 'mi_cedula_f');
      final reverso = await servicio.subirFoto(
          bytes: _fotoReverso!, prestamistaId: user.id, tipo: 'mi_cedula_r');
      await servicio.guardarCedulaPrestamista(user.id,
          cedula: _cedulaCtrl.text.trim(), frente: frente, reverso: reverso);
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
            if (_invito != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.greenDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.card_giftcard_rounded, color: AppColors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Te invitó ${_invito!.nombre}',
                          style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            const Text(
              '¿Cómo te llamas o cómo llamas tu negocio?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
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
            Text('Para avisarte cuando aprueben tu cuenta o te toque renovar.',
                style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _whatsappCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FormatoTelefono()],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: '809-555-1234',
                prefixIcon: Icon(Icons.chat_rounded, color: AppColors.green),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Tu cédula', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Para verificar quién eres al aprobar tu cuenta. Solo la ve el administrador.',
                style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _cedulaCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FormatoCedula()],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: '001-0000000-1',
                prefixIcon: Icon(Icons.badge_rounded, color: AppColors.green),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _foto('Cédula de frente', _fotoFrente, () async {
                    final b = await elegirFoto(context);
                    if (b != null) setState(() => _fotoFrente = b);
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _foto('Cédula de atrás', _fotoReverso, () async {
                    final b = await elegirFoto(context);
                    if (b != null) setState(() => _fotoReverso = b);
                  }),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.red)),
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

  /// Recuadro para subir una foto (o verla si ya se eligió).
  Widget _foto(String etiqueta, Uint8List? bytes, VoidCallback alTocar) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _cargando ? null : alTocar,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bytes != null ? AppColors.green : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, width: double.infinity)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, color: AppColors.grey),
                  const SizedBox(height: 6),
                  Text(etiqueta,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.grey, fontSize: 12)),
                ],
              ),
      ),
    );
  }
}
