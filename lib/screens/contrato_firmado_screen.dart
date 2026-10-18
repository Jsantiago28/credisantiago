import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../archivos/archivos.dart';
import '../logic/fotos.dart' show esPdf;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/elegir_foto.dart';
import '../widgets/foto_privada.dart';
import '../widgets/ui.dart';

/// El contrato firmado de un préstamo: fotos de las páginas o el PDF
/// escaneado, guardados en la carpeta privada del prestamista (solo él los
/// ve). Para tenerlo a mano en un reclamo o una demanda.
class ContratoFirmadoScreen extends StatefulWidget {
  final Map<String, dynamic> prestamo;
  final String cliente;
  const ContratoFirmadoScreen({super.key, required this.prestamo, required this.cliente});

  @override
  State<ContratoFirmadoScreen> createState() => _ContratoFirmadoScreenState();
}

class _ContratoFirmadoScreenState extends State<ContratoFirmadoScreen> {
  late List<String> _archivos = SupabaseService.contratoFirmadoDe(widget.prestamo);
  bool _subiendo = false;

  Future<void> _subir(List<({Uint8List bytes, bool pdf})> archivos) async {
    if (archivos.isEmpty) return;
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _subiendo = true);
    try {
      final lista = await SupabaseService.instance.agregarContratoFirmado(widget.prestamo, archivos);
      if (!mounted) return;
      setState(() => _archivos = lista);
      mensajero.showSnackBar(const SnackBar(content: Text('Contrato guardado')));
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo subir: $e')));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _agregarFotos() async {
    final fotos = await elegirVariasFotos(context, maximo: 10);
    await _subir([for (final f in fotos) (bytes: f, pdf: false)]);
  }

  Future<void> _agregarPdf() async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final archivo = await elegirArchivo(tipos: '.pdf');
      if (archivo == null) return;
      if (archivo.bytes.length > maxBytesFoto) {
        mensajero.showSnackBar(const SnackBar(content: Text('El PDF pesa más de 10MB.')));
        return;
      }
      await _subir([(bytes: archivo.bytes, pdf: true)]);
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo elegir el PDF: $e')));
    }
  }

  Future<void> _abrirPdf(String archivo) async {
    final mensajero = ScaffoldMessenger.of(context);
    final enlace = await SupabaseService.instance.enlaceFoto(archivo);
    if (enlace == null ||
        !await launchUrl(Uri.parse(enlace), mode: LaunchMode.externalApplication)) {
      mensajero.showSnackBar(const SnackBar(content: Text('No se pudo abrir el PDF')));
    }
  }

  Future<void> _quitar(String archivo) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar este archivo?'),
        content: const Text('Úsalo solo si lo subiste por error. Deja siempre el contrato firmado '
            'bueno: puede hacerte falta en un reclamo.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sí, quitar', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final lista = await SupabaseService.instance.quitarDeContratoFirmado(widget.prestamo, archivo);
      if (mounted) setState(() => _archivos = lista);
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo quitar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contrato firmado')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${widget.cliente} · ${rd(widget.prestamo['monto'] as num? ?? 0)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 16, color: AppColors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Solo tú puedes verlo. Tus cobradores no tienen acceso.',
                    style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: const Size(150, 48)),
                onPressed: _subiendo ? null : _agregarFotos,
                icon: const Icon(Icons.add_a_photo_rounded),
                label: const Text('Agregar fotos'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(150, 48)),
                onPressed: _subiendo ? null : _agregarPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Agregar PDF'),
              ),
            ],
          ),
          if (_subiendo) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text('Subiendo…', style: TextStyle(color: AppColors.grey, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          if (_archivos.isEmpty)
            const Vacio(
              icono: Icons.description_outlined,
              texto: 'Todavía no has subido el contrato firmado.\n'
                  'Toma una foto de cada página o sube el PDF escaneado.',
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, archivo) in _archivos.indexed) _miniatura(i + 1, archivo),
              ],
            ),
        ],
      ),
    );
  }

  Widget _miniatura(int numero, String archivo) {
    final pdf = esPdf(archivo);
    return SizedBox(
      width: 120,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => pdf ? _abrirPdf(archivo) : verFoto(context, archivo),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: pdf
                  ? Container(
                      width: 120,
                      height: 140,
                      color: AppColors.surfaceAlt,
                      child: Icon(Icons.picture_as_pdf_rounded, size: 48, color: AppColors.red),
                    )
                  : FotoPrivada(guardado: archivo, width: 120, height: 140),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(pdf ? 'PDF $numero' : 'Página $numero',
                    style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ),
              IconButton(
                tooltip: 'Quitar',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 20),
                onPressed: () => _quitar(archivo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
