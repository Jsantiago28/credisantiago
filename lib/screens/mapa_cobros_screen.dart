import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/ruta.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cobro_prestamo.dart';
import '../widgets/contacto.dart';
import '../widgets/ubicacion.dart';
import '../widgets/ui.dart';
import 'cliente_detalle_screen.dart';

/// Una parada de la ruta: el préstamo, dónde queda y qué cobrarle hoy.
class _Parada {
  final PrestamoConDatos datos;
  final Punto? punto;
  final ({double atrasado, double venceHoy, int diasAtraso}) hoy;
  _Parada(this.datos, this.punto, this.hoy);

  double get aCobrar => hoy.atrasado + hoy.venceHoy;
  EstadoCobro get etiqueta => hoy.atrasado > 0
      ? EstadoCobro.atrasado
      : hoy.venceHoy > 0
          ? EstadoCobro.venceHoy
          : EstadoCobro.alDia;
}

/// Mapa de la ruta de cobro: los clientes a cobrar hoy en el mapa, en el
/// orden más corto desde donde estás, con "Cómo llegar" y "Armar ruta" en
/// Google Maps. Mapa de OpenStreetMap (gratis, sin clave).
class MapaCobrosScreen extends StatefulWidget {
  final List<PrestamoConDatos> cartera;
  final VoidCallback onCambio;

  const MapaCobrosScreen({super.key, required this.cartera, required this.onCambio});

  @override
  State<MapaCobrosScreen> createState() => _MapaCobrosScreenState();
}

class _MapaCobrosScreenState extends State<MapaCobrosScreen> {
  final _mapa = MapController();
  bool _soloHoy = true;
  Punto? _yo;
  bool _buscandoYo = false;

  /// Centro por defecto: Santo Domingo.
  static const _santoDomingo = LatLng(18.4861, -69.9312);

  List<_Parada> get _paradas {
    final ahora = DateTime.now();
    return [
      for (final d in widget.cartera)
        _Parada(
          d,
          puntoDe(d.cliente?['lat'], d.cliente?['lng']),
          cobroDelDia(d.estado(ahora), ahora),
        ),
    ].where((p) => !_soloHoy || p.aCobrar > 0).toList();
  }

  /// Las que tienen ubicación, en orden de ruta (desde mí si sé dónde estoy).
  List<_Parada> _enRuta(List<_Parada> paradas) =>
      ordenarRuta(paradas.where((p) => p.punto != null).toList(), (p) => p.punto!, inicio: _yo);

  Future<void> _ubicarme() async {
    setState(() => _buscandoYo = true);
    final yo = await miUbicacion(context);
    if (!mounted) return;
    setState(() {
      _buscandoYo = false;
      if (yo != null) _yo = yo;
    });
    if (yo != null) _mapa.move(LatLng(yo.lat, yo.lng), 13);
  }

  Future<void> _cambio() async {
    widget.onCambio();
    if (mounted) Navigator.of(context).pop(); // vuelve a Inicio, que recarga
  }

  void _abrirParada(_Parada p, int? numero) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AvatarIniciales(
                    nombre: p.datos.nombre,
                    fotoUrl: p.datos.cliente?['foto_cara_url'] as String?,
                    tamano: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${numero != null ? '$numero. ' : ''}${p.datos.nombre}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      if (p.datos.direccion.isNotEmpty)
                        Text(p.datos.direccion,
                            style: TextStyle(color: AppColors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                EtiquetaEstado(p.etiqueta),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              p.aCobrar > 0
                  ? 'Cobrar hoy: ${rd(p.aCobrar)}'
                      '${p.hoy.diasAtraso > 0 ? ' · ${plural(p.hoy.diasAtraso, 'día', 'días')} atrasado' : ''}'
                  : 'Nada que cobrar hoy · debe ${rd(p.datos.estado(DateTime.now()).balance)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (_yo != null && p.punto != null)
              Text('A ${distanciaKm(_yo!, p.punto!).toStringAsFixed(1)} km en línea recta',
                  style: TextStyle(color: AppColors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                CobroPrestamo(context, p.datos, onCambio: _cambio).abrirCuotas();
              },
              icon: const Icon(Icons.payments_rounded),
              label: const Text('Cobrar'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (p.punto != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => abrirMapa(context, enlaceComoLlegar(p.punto!)),
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Cómo llegar'),
                    ),
                  ),
                if (p.punto != null) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: verdeWhatsApp,
                        side: const BorderSide(color: verdeWhatsApp)),
                    onPressed: () => whatsAppCobro(context,
                        nombreCliente: p.datos.nombre,
                        telefono: p.datos.cliente?['telefono'] as String?,
                        estado: p.datos.estado(DateTime.now())),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paradas = _paradas;
    final ruta = _enRuta(paradas);
    final sinUbicacion = paradas.where((p) => p.punto == null).toList();
    final numero = {for (var i = 0; i < ruta.length; i++) ruta[i]: i + 1};
    final puntos = [for (final p in ruta) LatLng(p.punto!.lat, p.punto!.lng)];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta de cobro'),
        actions: [
          IconButton(
            tooltip: 'Mi ubicación',
            onPressed: _buscandoYo ? null : _ubicarme,
            icon: _buscandoYo
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.my_location, color: _yo != null ? AppColors.green : null),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Cobros de hoy'),
                  selected: _soloHoy,
                  selectedColor: AppColors.greenDark,
                  onSelected: (_) => setState(() => _soloHoy = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Todos en la calle'),
                  selected: !_soloHoy,
                  selectedColor: AppColors.greenDark,
                  onSelected: (_) => setState(() => _soloHoy = false),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: FlutterMap(
              mapController: _mapa,
              options: MapOptions(
                initialCenter: puntos.isNotEmpty ? puntos.first : _santoDomingo,
                initialZoom: 12,
                initialCameraFit: puntos.length > 1
                    ? CameraFit.coordinates(
                        coordinates: puntos, padding: const EdgeInsets.all(48), maxZoom: 15)
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.credisantiago.app',
                ),
                if (puntos.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: [if (_yo != null) LatLng(_yo!.lat, _yo!.lng), ...puntos],
                        strokeWidth: 3,
                        color: AppColors.green.withValues(alpha: 0.6)),
                  ]),
                MarkerLayer(markers: [
                  if (_yo != null)
                    Marker(
                      point: LatLng(_yo!.lat, _yo!.lng),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  for (final p in ruta)
                    Marker(
                      point: LatLng(p.punto!.lat, p.punto!.lng),
                      width: 36,
                      height: 36,
                      child: GestureDetector(
                        onTap: () => _abrirParada(p, numero[p]),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.etiqueta.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text('${numero[p]}',
                              style: TextStyle(
                                  color: AppColors.sobreVerde, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
                ]),
                RichAttributionWidget(attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap',
                    onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
                  ),
                ]),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (ruta.isNotEmpty) ...[
                  ElevatedButton.icon(
                    onPressed: () => abrirMapa(
                        context, enlaceRuta([for (final p in ruta) p.punto!], origen: _yo)),
                    icon: const Icon(Icons.route_rounded),
                    label: Text(ruta.length > 10
                        ? 'Armar ruta en Google Maps (primeras 10)'
                        : 'Armar ruta en Google Maps (${ruta.length} paradas)'),
                  ),
                  if (_yo == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Toca 🎯 arriba para ordenar la ruta desde donde estás.',
                          style: TextStyle(color: AppColors.grey, fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                ],
                if (paradas.isEmpty)
                  Vacio(
                    icono: Icons.celebration_rounded,
                    texto: _soloHoy ? 'No hay cobros pendientes hoy.' : 'No hay préstamos en la calle.',
                  ),
                for (final p in ruta) _fila(p, numero[p]),
                if (sinUbicacion.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Sin ubicación (${sinUbicacion.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    'Ábrelos y toca "Marcar ubicación aquí" cuando estés en su casa.',
                    style: TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (final p in sinUbicacion) _fila(p, null),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(_Parada p, int? numero) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () async {
        if (p.punto != null) {
          _mapa.move(LatLng(p.punto!.lat, p.punto!.lng), 15);
          _abrirParada(p, numero);
        } else {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ClienteDetalleScreen(clienteId: p.datos.prestamo['cliente_id'] as String),
          ));
          widget.onCambio(); // pudo marcar la ubicación
        }
      },
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: numero != null ? p.etiqueta.color : AppColors.surfaceAlt,
            child: Text(numero != null ? '$numero' : '?',
                style: TextStyle(
                    color: numero != null ? AppColors.sobreVerde : AppColors.grey,
                    fontWeight: FontWeight.w900,
                    fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.datos.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  [
                    if (p.datos.direccion.isNotEmpty) p.datos.direccion,
                    if (_yo != null && p.punto != null)
                      '${distanciaKm(_yo!, p.punto!).toStringAsFixed(1)} km',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          // Hoy: lo que toca cobrar. Si no toca nada, lo que debe (en gris).
          p.aCobrar > 0
              ? Text(rd(p.aCobrar), style: const TextStyle(fontWeight: FontWeight.w800))
              : Text(rd(p.datos.estado(DateTime.now()).balance),
                  style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
