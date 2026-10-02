import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'elegir_foto.dart';
import 'foto_privada.dart';

/// Máximo de fotos de evidencia de ingresos por solicitud.
const maxEvidencias = 5;

/// Agregar fotos de evidencia de ingresos (volante de pago, carta de
/// trabajo, estado de cuenta). Usa los colores del tema, así sirve en el
/// formulario claro del link y en la app oscura del prestamista.
class SelectorEvidencias extends StatelessWidget {
  final List<Uint8List> fotos;
  final ValueChanged<List<Uint8List>> onCambio;
  final bool obligatorio;

  const SelectorEvidencias({
    super.key,
    required this.fotos,
    required this.onCambio,
    this.obligatorio = false,
  });

  Future<void> _agregar(BuildContext context) async {
    final bytes = await elegirVariasFotos(context, maximo: maxEvidencias - fotos.length);
    if (bytes.isNotEmpty) onCambio([...fotos, ...bytes]);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(obligatorio ? 'Evidencia de ingresos *' : 'Evidencia de ingresos (opcional)',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Foto del volante de pago, carta de trabajo o estado de cuenta. '
          'Hasta $maxEvidencias fotos.',
          style: TextStyle(color: tema.onSurface.withValues(alpha: 0.6), fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < fotos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(fotos[i], width: 84, height: 84, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: () => onCambio([...fotos]..removeAt(i)),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            if (fotos.length < maxEvidencias)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _agregar(context),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tema.onSurface.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_rounded, color: tema.primary),
                      const SizedBox(height: 4),
                      Text('Agregar', style: TextStyle(color: tema.primary, fontSize: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Muestra las evidencias guardadas; al tocar una se amplía.
class GaleriaEvidencias extends StatelessWidget {
  final List<String> urls;
  const GaleriaEvidencias({super.key, required this.urls});

  /// Lee la lista tal como viene de Supabase (text[] → List<dynamic>).
  static List<String> desde(dynamic valor) =>
      valor is List ? valor.whereType<String>().toList() : const [];

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return Text('No subió evidencia de ingresos.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final guardado in urls)
          GestureDetector(
            onTap: () => verFoto(context, guardado),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FotoPrivada(guardado: guardado, width: 96, height: 96),
            ),
          ),
      ],
    );
  }
}
