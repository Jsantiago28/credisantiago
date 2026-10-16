import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/historial.dart';
import '../logic/historial_pagos.dart';
import '../logic/ruta.dart';
import '../recibos/contrato_pdf.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cobro_prestamo.dart';
import '../widgets/contacto.dart';
import '../widgets/evidencias.dart';
import '../widgets/foto_privada.dart';
import '../widgets/gestiones.dart';
import '../widgets/historial_cliente.dart';
import '../widgets/ubicacion.dart';
import '../widgets/selector_cobrador.dart';
import '../widgets/ui.dart';
import 'editar_cliente_screen.dart';
import 'historial_pagos_screen.dart';
import 'prestar_screen.dart';

/// Ficha completa de un cliente: los datos de su solicitud (cédula, trabajo,
/// referencias, fotos) y todos sus préstamos, activos y saldados.
class ClienteDetalleScreen extends StatefulWidget {
  final String clienteId;
  const ClienteDetalleScreen({super.key, required this.clienteId});

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  Map<String, dynamic>? _cliente;
  Map<String, dynamic>? _solicitud;
  List<PrestamoConDatos> _prestamos = const [];
  List<CambioCliente> _cambios = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final servicio = SupabaseService.instance;
    try {
      final cliente = await servicio.obtenerCliente(widget.clienteId);
      if (cliente == null) throw Exception('No se encontró el cliente');
      final solicitudId = cliente['solicitud_id'] as String?;
      final solicitud = solicitudId != null ? await servicio.obtenerSolicitud(solicitudId) : null;
      final prestamos = await servicio.obtenerPrestamosDeCliente(widget.clienteId);
      final cambios = await servicio.obtenerHistorialCliente(widget.clienteId);
      final conPagos = await Future.wait(prestamos.map((p) async => PrestamoConDatos(
            prestamo: p,
            cliente: cliente,
            pagos: await servicio.obtenerPagos(p['id']),
            gestiones: await servicio.obtenerGestiones(p['id']),
          )));
      if (!mounted) return;
      setState(() {
        _cliente = cliente;
        _solicitud = solicitud;
        _prestamos = conPagos;
        _cambios = cambios;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL FICHA CLIENTE: $e');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  PrestamoConDatos? get _activo {
    for (final p in _prestamos) {
      if (p.prestamo['estado'] == 'en_calle') return p;
    }
    return null;
  }

  bool get _puedePrestar =>
      !_prestamos.any((p) => p.prestamo['estado'] == 'en_calle' || p.prestamo['estado'] == 'borrador');

  Future<void> _prestar(Map<String, dynamic> prestamo) async {
    final listo = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PrestarScreen(cliente: _cliente!, prestamo: prestamo),
    ));
    if (listo == true) _cargar();
  }

  Future<void> _nuevoPrestamo() async {
    try {
      final borrador = await SupabaseService.instance.crearPrestamoBorrador(_cliente!);
      if (mounted) await _prestar(borrador);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo crear el préstamo: $e')));
      }
    }
  }

  void _whatsApp() {
    final c = _cliente!;
    final activo = _activo;
    if (activo != null) {
      whatsAppCobro(context,
          nombreCliente: c['nombre'] ?? '',
          telefono: c['telefono'] as String?,
          estado: activo.estado(DateTime.now()));
    } else {
      final nombre = ((c['nombre'] as String?) ?? '').split(' ').first;
      abrirWhatsApp(context, c['telefono'] as String?, 'Hola $nombre, ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cliente;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?['nombre'] ?? 'Cliente'),
        actions: [
          if (c != null)
            IconButton(
              tooltip: 'Corregir datos',
              icon: Icon(Icons.edit_rounded, color: AppColors.green),
              onPressed: _editar,
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar el cliente.\n$_error')
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _encabezado(c!),
                      SelectorCobrador(cliente: c),
                      _fotos(c),
                      _titulo('Préstamos'),
                      if (_prestamos.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text('Todavía no tiene préstamos.',
                              style: TextStyle(color: AppColors.grey)),
                        ),
                      ..._prestamos.map(_tarjetaPrestamo),
                      if (_prestamos.any((p) => p.prestamo['estado'] != 'borrador'))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton.icon(
                            onPressed: () => _verHistorial(c),
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: const Text('Historial de pagos'),
                          ),
                        ),
                      if (_puedePrestar)
                        ElevatedButton.icon(
                          onPressed: _nuevoPrestamo,
                          icon: const Icon(Icons.add),
                          label: const Text('Nuevo préstamo'),
                        ),
                      _titulo('Datos personales'),
                      _seccion([
                        ('Cédula', c['cedula']),
                        ('Teléfono', c['telefono']),
                        ('Dirección', c['direccion']),
                        ('Vivienda', _vivienda(c['tipo_vivienda'] ?? _solicitud?['tipo_vivienda'])),
                      ]),
                      _titulo('Trabajo e ingresos'),
                      _seccion([
                        ('Lugar', c['trabajo_lugar']),
                        ('Dirección trabajo', c['trabajo_direccion']),
                        ('Supervisor / RR.HH.', c['jefe_nombre']),
                        ('Tel. supervisor', c['jefe_telefono']),
                        ('Gana al mes',
                            _monto(c['ingreso_mensual'] ?? _solicitud?['ingreso_mensual'])),
                        if (_solicitud?['tiene_otros_ingresos'] == true) ...[
                          ('Otros ingresos', _solicitud?['otros_ingresos_descripcion']),
                          ('Monto otros ingresos', _monto(_solicitud?['otros_ingresos_monto'])),
                        ],
                      ]),
                      _titulo('Evidencias de ingresos'),
                      Panel(
                        child: GaleriaEvidencias(
                          urls: GaleriaEvidencias.desde(c['evidencias_ingresos']).isNotEmpty
                              ? GaleriaEvidencias.desde(c['evidencias_ingresos'])
                              : GaleriaEvidencias.desde(_solicitud?['evidencias_ingresos']),
                        ),
                      ),
                      _titulo('Referencias'),
                      _seccion([
                        ('Referencia 1', _referencia(c, 1)),
                        ('Referencia 2', _referencia(c, 2)),
                      ]),
                      _titulo('Solicitud'),
                      _seccion(_solicitud == null
                          ? [('Origen', 'Creado a mano, sin solicitud')]
                          : [
                              ('Fecha', _fecha(_solicitud!['created_at'])),
                              ('Monto solicitado', _monto(_solicitud!['monto_solicitado'])),
                              ('Frecuencia de pago', _solicitud!['frecuencia_pago']),
                              ('Capacidad de pago', _monto(_solicitud!['capacidad_pago'])),
                              ('Cómo quiere el dinero', _metodoCobro(c)),
                            ]),
                      _titulo('Historial de cambios'),
                      _historial(c),
                    ],
                  ),
                ),
    );
  }

  Widget _encabezado(Map<String, dynamic> c) {
    return Panel(
      child: Column(
        children: [
          Row(
            children: [
              AvatarIniciales(
                  nombre: c['nombre'] ?? '', fotoUrl: c['foto_cara_url'] as String?, tamano: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['nombre'] ?? '',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if ((c['cedula'] as String?)?.isNotEmpty == true)
                      Text('Cédula ${c['cedula']}', style: TextStyle(color: AppColors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FilaContacto(telefono: c['telefono'] as String?, onWhatsApp: _whatsApp),
          _filaUbicacion(c),
        ],
      ),
    );
  }

  Widget _fotos(Map<String, dynamic> c) {
    final fotos = [
      ('Cara', c['foto_cara_url'] as String?),
      ('Cédula frente', c['foto_cedula_frente_url'] as String?),
      ('Cédula atrás', c['foto_cedula_reverso_url'] as String?),
    ].where((f) => f.$2 != null).toList();
    if (fotos.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: fotos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => verFoto(context, fotos[i].$2),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FotoPrivada(guardado: fotos[i].$2, width: 120, height: 84),
              ),
              const SizedBox(height: 4),
              Text(fotos[i].$1, style: TextStyle(color: AppColors.grey, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaPrestamo(PrestamoConDatos d) {
    final p = d.prestamo;
    final estadoTexto = p['estado'] as String? ?? '';
    final hoy = DateTime.now();

    if (estadoTexto == 'cancelado') {
      return Panel(
        child: Row(
          children: [
            Expanded(
              child: Text('${rd(p['monto'] as num? ?? 0)} — cancelado',
                  style: TextStyle(
                      color: AppColors.grey, decoration: TextDecoration.lineThrough)),
            ),
            Pildora('CANCELADO', color: AppColors.grey, fondo: AppColors.surfaceAlt),
          ],
        ),
      );
    }

    if (estadoTexto == 'borrador') {
      return Panel(
        onTap: () => _prestar(p),
        child: Row(
          children: [
            const Expanded(
              child: Text('Préstamo por confirmar', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Pildora('POR PRESTAR', color: AppColors.amber, fondo: AppColors.amberDark),
            IconButton(
              tooltip: 'Cancelar préstamo',
              icon: Icon(Icons.close, color: AppColors.grey),
              onPressed: () => _cancelar(p),
            ),
          ],
        ),
      );
    }

    final estado = d.estado(hoy);
    final saldado = estadoTexto == 'pagado';
    final validos = pagosValidos(d.pagos);
    final ultimoPago = validos.isEmpty
        ? null
        : validos.map((x) => x.fecha).reduce((a, b) => a.isAfter(b) ? a : b);
    final desembolso = DateTime.tryParse(p['fecha_desembolso'] as String? ?? '');
    final cobro = CobroPrestamo(context, d, onCambio: _cargar);

    return Panel(
      onTap: saldado ? cobro.abrirRecibos : cobro.abrirCuotas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${rd(p['monto'] as num? ?? 0)} prestado',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              saldado
                  ? Pildora('SALDADO', color: AppColors.grey, fondo: AppColors.surfaceAlt)
                  : const Pildora('EN LA CALLE'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (desembolso != null) 'Desde ${fechaLarga(desembolso)}',
              '${p['cantidad_cuotas'] ?? '?'} ${nombreCuotas(p['frecuencia'] as String? ?? 'diario')}',
              '${p['tasa_interes'] ?? 0}% mensual',
            ].join(' · '),
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            saldado
                ? 'Cobrado ${rd(estado.cobradoCuotas + estado.moraCobrada)}'
                    '${estado.moraCobrada > 0 ? ' (mora ${rd(estado.moraCobrada)})' : ''}'
                    '${ultimoPago != null ? ' · saldó el ${fechaLarga(ultimoPago)}' : ''}'
                : 'Debe ${rd(estado.balance)} de ${rd(estado.montoTotal)}'
                    '${estado.moraPendiente > 0 ? ' · mora ${rd(estado.moraPendiente)}' : ''}',
            style: TextStyle(
                color: !saldado && estado.moraPendiente > 0 ? AppColors.red : AppColors.texto,
                fontSize: 13),
          ),
          if (!saldado && d.promesa(hoy) != null) ...[
            const SizedBox(height: 6),
            LineaPromesa(d.promesa(hoy)!),
          ],
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(saldado ? 'Toca para ver sus recibos' : 'Toca para ver cuotas y cobrar',
                    style: TextStyle(color: AppColors.green, fontSize: 12)),
              ),
              if (!saldado || d.gestiones.isNotEmpty)
                TextButton.icon(
                  onPressed: () => verGestiones(context, d, onCambio: _cargar),
                  icon: const Icon(Icons.handshake_rounded, size: 18),
                  label: Text('Gestiones (${d.gestiones.length})'),
                ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _contrato(p),
                icon: const Icon(Icons.description_rounded, size: 18),
                label: const Text('Contrato'),
              ),
              // Préstamo hecho por error: sin cobros se puede cancelar.
              if (!saldado && validos.isEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: () => _cancelar(p),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancelar préstamo'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Todos los pagos del cliente, de todos sus préstamos (y el PDF para él).
  void _verHistorial(Map<String, dynamic> c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HistorialPagosScreen(
        cliente: c['nombre'] as String? ?? '',
        cedula: c['cedula'] as String?,
        prestamos: historialPagos(
          [for (final d in _prestamos) (prestamo: d.prestamo, pagos: d.pagos)],
          DateTime.now(),
        ),
      ),
    ));
  }

  /// Contrato del préstamo en PDF, para imprimir y firmar.
  Future<void> _contrato(Map<String, dynamic> prestamo) async {
    final mensajero = ScaffoldMessenger.of(context);
    mensajero.showSnackBar(const SnackBar(content: Text('Preparando el contrato...')));
    try {
      await compartirContrato(prestamo);
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo hacer el contrato: $e')));
    }
  }

  /// Cancela un préstamo sin cobros (hecho por error), con confirmación.
  Future<void> _cancelar(Map<String, dynamic> prestamo) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Cancelar este préstamo?'),
        content: const Text(
            'Sale de "En la calle" y de los reportes. Queda en la ficha como cancelado. '
            'Úsalo solo si se hizo por error.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sí, cancelar', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.cancelarPrestamo(prestamo);
      mensajero.showSnackBar(const SnackBar(content: Text('Préstamo cancelado')));
      _cargar();
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo cancelar: $e')));
    }
  }

  /// Ubicación de la casa del cliente: "Cómo llegar" si ya la tiene, y
  /// "Marcar ubicación aquí" (con el GPS del teléfono) para ponerla o
  /// corregirla estando en el lugar.
  Widget _filaUbicacion(Map<String, dynamic> c) {
    final punto = puntoDe(c['lat'], c['lng']);
    return Row(
      children: [
        Icon(punto != null ? Icons.location_on : Icons.location_off,
            size: 16, color: punto != null ? AppColors.green : AppColors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(punto != null ? 'Ubicación guardada' : 'Sin ubicación',
              style: TextStyle(color: AppColors.grey)),
        ),
        if (punto != null)
          TextButton.icon(
            onPressed: () => abrirMapa(context, enlaceComoLlegar(punto)),
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: const Text('Cómo llegar'),
          ),
        TextButton.icon(
          onPressed: () => _marcarUbicacion(c, reemplaza: punto != null),
          icon: const Icon(Icons.my_location, size: 18),
          label: Text(punto != null ? 'Corregir' : 'Marcar aquí'),
        ),
      ],
    );
  }

  Future<void> _marcarUbicacion(Map<String, dynamic> c, {required bool reemplaza}) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(reemplaza ? '¿Corregir la ubicación?' : '¿Marcar la ubicación aquí?'),
        content: Text('Se guarda el lugar donde está tu teléfono ahora como la casa de '
            '${c['nombre']}. Hazlo estando allí.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Marcar')),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    final aqui = await miUbicacion(context);
    if (aqui == null || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.guardarUbicacionCliente(c['id'] as String, aqui.lat, aqui.lng);
      mensajero.showSnackBar(const SnackBar(content: Text('Ubicación guardada')));
      _cargar();
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  Future<void> _editar() async {
    final guardo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditarClienteScreen(cliente: _cliente!)),
    );
    if (guardo == true) _cargar();
  }

  /// Cuántas veces se corrigieron sus datos y cuándo fue la última. Al
  /// tocarlo se ve cada cambio con lo que decía antes.
  Widget _historial(Map<String, dynamic> c) {
    final ediciones = agruparCambios(_cambios);
    return Panel(
      onTap: () => verHistorialCliente(context, c['nombre'] ?? '', _cambios),
      child: Row(
        children: [
          Icon(Icons.history_rounded, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ediciones.isEmpty
                  ? 'Sin cambios registrados'
                  : '${ediciones.length} ${ediciones.length == 1 ? 'vez corregido' : 'veces corregido'}'
                      ' · último el ${fechaHora(ediciones.first.fecha)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );

  Widget _seccion(List<(String, dynamic)> filas) {
    final conValor = filas
        .where((f) => f.$2 != null && '${f.$2}'.trim().isNotEmpty)
        .toList();
    return Panel(
      child: conValor.isEmpty
          ? Text('Sin datos', style: TextStyle(color: AppColors.grey))
          : Column(
              children: [
                for (final f in conValor)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: 130,
                            child: Text(f.$1, style: TextStyle(color: AppColors.grey))),
                        Expanded(child: Text('${f.$2}')),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  String? _referencia(Map<String, dynamic> c, int n) {
    final nombre = c['ref${n}_nombre'] as String?;
    if (nombre == null || nombre.isEmpty) return null;
    final parentesco = c['ref${n}_parentesco'] as String?;
    final tel = c['ref${n}_telefono'] as String?;
    return [
      nombre + (parentesco != null && parentesco.isNotEmpty ? ' ($parentesco)' : ''),
      if (tel != null && tel.isNotEmpty) tel,
    ].join(' · ');
  }

  String? _vivienda(dynamic v) => switch (v) {
        'propia' => 'Casa propia',
        'alquilada' => 'Alquilada',
        _ => null,
      };

  String? _monto(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v : num.tryParse('$v');
    return n == null ? null : rd(n);
  }

  String? _fecha(dynamic v) {
    final f = DateTime.tryParse(v as String? ?? '')?.toLocal();
    return f == null ? null : fechaLarga(f);
  }

  String _metodoCobro(Map<String, dynamic> c) {
    switch (c['metodo_cobro']) {
      case 'transferencia':
        return [c['banco'], c['numero_cuenta']].where((x) => x != null).join(' · ');
      case 'billetera':
        return 'Billetera ${c['billetera'] ?? ''}';
      case 'efectivo':
        return 'Efectivo';
      default:
        return 'Sin definir';
    }
  }
}
