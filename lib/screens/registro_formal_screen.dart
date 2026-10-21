import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../logic/validacion.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elegir_foto.dart';
import '../widgets/formato_campos.dart';

/// Ya dejó su cédula (número y fotos de los dos lados).
bool tieneRegistroFormal(Map<String, dynamic> perfil) =>
    ((perfil['contrato_cedula'] as String?) ?? '').trim().isNotEmpty &&
    perfil['cedula_frente_url'] != null &&
    perfil['cedula_reverso_url'] != null;

/// Registro formal: la cédula del prestamista (número y fotos). Para probar
/// en Gratis no se pide; se pide al comprar un plan, para verificar quién
/// es antes de activarlo. Devuelve true si se guardó.
class RegistroFormalScreen extends StatefulWidget {
  final String prestamistaId;
  const RegistroFormalScreen({super.key, required this.prestamistaId});

  @override
  State<RegistroFormalScreen> createState() => _RegistroFormalScreenState();
}

class _RegistroFormalScreenState extends State<RegistroFormalScreen> {
  final _cedulaCtrl = TextEditingController();
  Uint8List? _fotoFrente;
  Uint8List? _fotoReverso;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
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
      _guardando = true;
      _error = null;
    });
    try {
      final servicio = SupabaseService.instance;
      final id = widget.prestamistaId;
      final frente = await servicio.subirFoto(bytes: _fotoFrente!, prestamistaId: id, tipo: 'mi_cedula_f');
      final reverso =
          await servicio.subirFoto(bytes: _fotoReverso!, prestamistaId: id, tipo: 'mi_cedula_r');
      await servicio.guardarCedulaPrestamista(id,
          cedula: _cedulaCtrl.text.trim(), frente: frente, reverso: reverso);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL REGISTRO FORMAL: $e');
      if (mounted) setState(() => _error = 'No se pudo guardar. Intenta de nuevo.\n($e)');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completa tu registro')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Antes de activar tu plan',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                'Para los planes pagados verificamos quién eres con tu cédula. Solo la ve el '
                'administrador de la app; tus clientes no.',
                style: TextStyle(color: AppColors.grey)),
            const SizedBox(height: 24),
            TextField(
              controller: _cedulaCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FormatoCedula()],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Tu cédula',
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
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar y seguir'),
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
      onTap: _guardando ? null : alTocar,
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
