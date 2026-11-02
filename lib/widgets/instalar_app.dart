import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../instalar/instalar.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Inicio (solo en la web del celular): tarjeta para poner CrediSantiago en
/// la pantalla de inicio, como una app. Con Chrome o Samsung basta un botón;
/// en iPhone se explican los dos pasos. No sale si ya está instalada, en el
/// APK, en la computadora, ni por [diasOculta] días después de "No ahora".
class TarjetaInstalar extends StatefulWidget {
  const TarjetaInstalar({
    super.key,
    this.estado = estadoInstalacion,
    this.instalar = instalarApp,
    this.alCambiar = alCambiarInstalacion,
    this.hoy,
  });

  /// Para pruebas; por defecto, el navegador de verdad.
  final Instalacion Function() estado;
  final Future<bool> Function() instalar;
  final void Function(void Function()) alCambiar;
  final DateTime? hoy;

  static const claveOculta = 'instalar_oculta_desde';
  static const diasOculta = 14;

  @override
  State<TarjetaInstalar> createState() => _TarjetaInstalarState();
}

class _TarjetaInstalarState extends State<TarjetaInstalar> {
  late Instalacion _estado = widget.estado();

  /// Hasta saber si la cerró, no se muestra (para que no parpadee).
  bool _oculta = true;

  DateTime get _hoy => widget.hoy ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _leerOculta();
    // El navegador puede avisar que se puede instalar después de cargar.
    widget.alCambiar(() {
      if (mounted) setState(() => _estado = widget.estado());
    });
  }

  Future<void> _leerOculta() async {
    var oculta = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final desde =
          DateTime.tryParse(prefs.getString(TarjetaInstalar.claveOculta) ?? '');
      oculta = desde != null &&
          _hoy.difference(desde).inDays < TarjetaInstalar.diasOculta;
    } catch (_) {
      // Sin almacenamiento (modo privado): se muestra.
    }
    if (mounted) setState(() => _oculta = oculta);
  }

  Future<void> _noAhora() async {
    setState(() => _oculta = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          TarjetaInstalar.claveOculta, _hoy.toIso8601String());
    } catch (_) {}
  }

  Future<void> _instalar() async {
    final instalada = await widget.instalar();
    if (!mounted) return;
    setState(() => _estado = widget.estado());
    if (instalada) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Listo: CrediSantiago quedó en tu pantalla de inicio.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_oculta || _estado == Instalacion.instalada) {
      return const SizedBox.shrink();
    }

    final titulo = _estado == Instalacion.conBoton
        ? 'Instala CrediSantiago en tu celular'
        : 'Pon CrediSantiago en tu pantalla de inicio';

    return Panel(
      key: const Key('tarjeta-instalar'),
      borde: AppColors.green.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LogoApp(tamano: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        'La abres con un toque, a pantalla completa, como cualquier app. '
                        'Sin buscar el enlace.',
                        style: TextStyle(color: AppColors.grey, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                key: const Key('instalar-cerrar'),
                tooltip: 'No ahora',
                onPressed: _noAhora,
                icon: Icon(Icons.close_rounded, color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),
          switch (_estado) {
            Instalacion.conBoton => ElevatedButton.icon(
                key: const Key('instalar-boton'),
                onPressed: _instalar,
                icon: const Icon(Icons.add_to_home_screen_rounded),
                label: const Text('Instalar CrediSantiago'),
              ),
            Instalacion.iphone => const _Pasos([
                (
                  Icons.ios_share_rounded,
                  'Toca Compartir, abajo en la pantalla.'
                ),
                (
                  Icons.add_box_outlined,
                  'Elige "Agregar a pantalla de inicio" y luego "Agregar".'
                ),
              ]),
            _ => const _Pasos([
                (
                  Icons.more_vert_rounded,
                  'Toca el menú ⋮ del navegador, arriba.'
                ),
                (
                  Icons.add_to_home_screen_rounded,
                  'Elige "Instalar app" o "Agregar a la pantalla de inicio".'
                ),
              ]),
          },
        ],
      ),
    );
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos(this.pasos);

  final List<(IconData, String)> pasos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < pasos.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.green,
                  child: Text('${i + 1}',
                      style: TextStyle(
                          color: AppColors.sobreVerde,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Icon(pasos[i].$1, color: AppColors.green, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(pasos[i].$2)),
              ],
            ),
          ),
      ],
    );
  }
}
