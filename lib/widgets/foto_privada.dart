import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

/// Foto del bucket privado: pide un enlace temporal y la muestra. Recibe lo
/// que esté guardado en la base de datos (ubicación o enlace viejo).
class FotoPrivada extends StatefulWidget {
  final String? guardado;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Lo que se ve mientras carga o si la foto no se puede mostrar.
  final Widget? sinFoto;

  const FotoPrivada({
    super.key,
    required this.guardado,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.sinFoto,
  });

  @override
  State<FotoPrivada> createState() => _FotoPrivadaState();
}

class _FotoPrivadaState extends State<FotoPrivada> {
  late Future<String?> _enlace;

  @override
  void initState() {
    super.initState();
    _enlace = _pedir();
  }

  @override
  void didUpdateWidget(FotoPrivada viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.guardado != widget.guardado) _enlace = _pedir();
  }

  // Si falla (sin conexión, sin permiso), se muestra `sinFoto`.
  Future<String?> _pedir() =>
      SupabaseService.instance.enlaceFoto(widget.guardado).catchError((_) => null);

  Widget get _vacio =>
      widget.sinFoto ??
      SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey)),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _enlace,
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return _vacio;
        return Image.network(
          url,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => _vacio,
        );
      },
    );
  }
}

/// Abre la foto en grande (se puede ampliar con los dedos).
void verFoto(BuildContext context, String? guardado) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.black,
      child: InteractiveViewer(child: FotoPrivada(guardado: guardado, fit: BoxFit.contain)),
    ),
  );
}
