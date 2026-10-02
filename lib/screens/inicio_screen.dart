import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/gestiones.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cobro_prestamo.dart';
import '../widgets/contacto.dart';
import '../widgets/gestiones.dart';
import '../widgets/ui.dart';
import 'calculadora_screen.dart';
import 'mapa_cobros_screen.dart';

/// Qué préstamos muestra la lista de abajo.
enum _Filtro { hoy, atrasados, todos }

/// Tablero principal: totales, aviso de solicitudes y cobros del día.
class InicioScreen extends StatefulWidget {
  final Map<String, dynamic> perfil;
  final int solicitudesNuevas;
  final VoidCallback onVerSolicitudes;
  final VoidCallback onVerPerfil;

  /// Para la app del cobrador: [perfil] trae el id del jefe y el nombre del
  /// cobrador, y la base de datos solo le manda los clientes de su ruta.
  /// Sin calculadora (no presta).
  final bool modoCobrador;

  /// Nombre del negocio del jefe (solo en modo cobrador).
  final String? negocioDelJefe;

  const InicioScreen({
    super.key,
    required this.perfil,
    required this.solicitudesNuevas,
    required this.onVerSolicitudes,
    required this.onVerPerfil,
    this.modoCobrador = false,
    this.negocioDelJefe,
  });

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

/// Un préstamo con lo que hay que cobrarle hoy.
class _Fila {
  final PrestamoConDatos datos;
  final EstadoPrestamo estado;
  final ({double atrasado, double venceHoy, int diasAtraso}) hoy;
  final InfoPromesa? promesa;
  _Fila(this.datos, this.estado, this.hoy, this.promesa);

  double get aCobrar => hoy.atrasado + hoy.venceHoy;
  EstadoCobro get etiqueta => hoy.atrasado > 0
      ? EstadoCobro.atrasado
      : hoy.venceHoy > 0
          ? EstadoCobro.venceHoy
          : EstadoCobro.alDia;
}

class _InicioScreenState extends State<InicioScreen> {
  List<_Fila>? _filas;
  String? _error;
  _Filtro _filtro = _Filtro.hoy;
  StreamSubscription? _cambios;

  String get _prestamistaId => widget.perfil['id'] as String;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Recarga cuando cambia algún préstamo (nuevo, cobrado, saldado).
    _cambios = SupabaseService.instance
        .prestamosEnCalleStream(_prestamistaId)
        .skip(1)
        // Si la conexión en vivo falla, Inicio igual carga (y se recarga
        // jalando hacia abajo); solo deja de refrescarse solo.
        .listen((_) => _cargar(), onError: (_) {});
  }

  @override
  void dispose() {
    _cambios?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final cartera = await SupabaseService.instance.obtenerCartera(_prestamistaId);
      final ahora = DateTime.now();
      final filas = cartera.map((d) {
        final e = d.estado(ahora);
        return _Fila(d, e, cobroDelDia(e, ahora), d.promesa(ahora));
      }).toList();
      if (mounted) {
        setState(() {
          _filas = filas;
          _error = null;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL INICIO: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _abrir(_Fila f) => CobroPrestamo(context, f.datos, onCambio: _cargar).abrirCuotas();

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _encabezado(),
              const SizedBox(height: 16),
              if (filas == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar tus préstamos.\n$_error')
              else ...[
                _totales(filas!),
                if (widget.solicitudesNuevas > 0) ...[
                  const SizedBox(height: 12),
                  _avisoSolicitudes(),
                ],
                if (filas.any((f) => f.promesa?.esAviso == true)) ...[
                  const SizedBox(height: 12),
                  _avisoPromesas(filas),
                ],
                const SizedBox(height: 24),
                _tituloLista(),
                const SizedBox(height: 12),
                ..._lista(filas),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezado() {
    final nombre = (widget.perfil['nombre'] as String?) ?? '';
    final primerNombre = nombre.split(' ').first;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.payments_rounded, color: Colors.black, size: 28),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.modoCobrador ? 'Mi ruta\nde cobro' : 'Prestamistas\nRD',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.05)),
            ),
            if (!widget.modoCobrador)
              IconButton(
                tooltip: 'Calculadora de préstamos',
                icon: const Icon(Icons.calculate_rounded, color: AppColors.green, size: 28),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CalculadoraScreen(prestamistaId: _prestamistaId),
                )),
              ),
            const SizedBox(width: 4),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onVerPerfil,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(BorderSide(color: AppColors.green, width: 2)),
                ),
                child: AvatarIniciales(nombre: nombre, tamano: 42),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
              'Hola, $primerNombre\nHoy es ${fechaLarga(DateTime.now())}'
              '${widget.negocioDelJefe == null ? '' : '\nCobras para ${widget.negocioDelJefe}'}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
        ),
      ],
    );
  }

  Widget _totales(List<_Fila> filas) {
    final enLaCalle = filas.fold<double>(0, (s, f) => s + f.estado.balance);
    final hoy = filas.where((f) => f.hoy.venceHoy > 0).toList();
    final atrasados = filas.where((f) => f.hoy.atrasado > 0).toList();
    final montoHoy = hoy.fold<double>(0, (s, f) => s + f.hoy.venceHoy);
    final montoAtrasado = atrasados.fold<double>(0, (s, f) => s + f.hoy.atrasado);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TarjetaTotal(
              icono: Icons.account_balance_wallet_rounded,
              titulo: 'EN LA CALLE',
              valor: rd(enLaCalle),
              detalle: '${filas.length} préstamo(s)',
              color: AppColors.green,
              fondoIcono: AppColors.greenDark,
              seleccionada: _filtro == _Filtro.todos,
              onTap: () => setState(() => _filtro = _Filtro.todos),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TarjetaTotal(
              icono: Icons.event_available_rounded,
              titulo: 'POR COBRAR HOY',
              valor: rd(montoHoy),
              detalle: '${hoy.length} cobro(s) hoy',
              color: AppColors.amber,
              fondoIcono: AppColors.amberDark,
              seleccionada: _filtro == _Filtro.hoy,
              onTap: () => setState(() => _filtro = _Filtro.hoy),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TarjetaTotal(
              icono: Icons.warning_amber_rounded,
              titulo: 'ATRASADOS',
              valor: rd(montoAtrasado),
              detalle: '${atrasados.length} cliente(s)',
              color: AppColors.red,
              fondoIcono: AppColors.redDark,
              seleccionada: _filtro == _Filtro.atrasados,
              onTap: () => setState(() => _filtro = _Filtro.atrasados),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoSolicitudes() {
    final n = widget.solicitudesNuevas;
    return Panel(
      margin: EdgeInsets.zero,
      borde: AppColors.green.withValues(alpha: 0.5),
      onTap: widget.onVerSolicitudes,
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_rounded, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(n == 1 ? 'Tienes 1 solicitud nueva' : 'Tienes $n solicitudes nuevas',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.chevron_right, color: AppColors.grey),
        ],
      ),
    );
  }

  /// Promesas de pago que vencen hoy o que no se cumplieron: a quién hay
  /// que ir a ver. Al tocar una se abre su cobro.
  Widget _avisoPromesas(List<_Fila> filas) {
    final avisos = filas.where((f) => f.promesa?.esAviso == true).toList()
      // Primero las no cumplidas, luego las de hoy.
      ..sort((a, b) => b.promesa!.estado.index.compareTo(a.promesa!.estado.index));
    final noCumplidas = avisos.where((f) => f.promesa!.estado == EstadoPromesa.incumplida).length;
    final hoy = avisos.length - noCumplidas;
    return Panel(
      margin: EdgeInsets.zero,
      borde: (noCumplidas > 0 ? AppColors.red : AppColors.amber).withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handshake_rounded,
                  color: noCumplidas > 0 ? AppColors.red : AppColors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  [
                    if (hoy > 0) '$hoy promesa${hoy == 1 ? '' : 's'} de pago para hoy',
                    if (noCumplidas > 0) '$noCumplidas no cumplida${noCumplidas == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          for (final f in avisos)
            InkWell(
              onTap: () => _abrir(f),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.datos.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    LineaPromesa(f.promesa!),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tituloLista() {
    final titulo = switch (_filtro) {
      _Filtro.hoy => 'Cobros del día',
      _Filtro.atrasados => 'Atrasados',
      _Filtro.todos => 'En la calle',
    };
    return Row(
      children: [
        Expanded(
          child: Text(titulo, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        if (_filtro != _Filtro.todos)
          IconButton(
            tooltip: 'Ver en el mapa',
            icon: const Icon(Icons.map_rounded, color: AppColors.green),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MapaCobrosScreen(
                cartera: [for (final f in _filas ?? const <_Fila>[]) f.datos],
                onCambio: _cargar,
              ),
            )),
          ),
        PopupMenuButton<_Filtro>(
          initialValue: _filtro,
          onSelected: (f) => setState(() => _filtro = f),
          color: AppColors.surfaceAlt,
          itemBuilder: (_) => const [
            PopupMenuItem(value: _Filtro.hoy, child: Text('Cobros del día')),
            PopupMenuItem(value: _Filtro.atrasados, child: Text('Solo atrasados')),
            PopupMenuItem(value: _Filtro.todos, child: Text('Todos en la calle')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.green),
            ),
            child: const Row(
              children: [
                Icon(Icons.tune, color: AppColors.green, size: 18),
                SizedBox(width: 6),
                Text('Filtrar',
                    style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                Icon(Icons.expand_more, color: AppColors.green, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _lista(List<_Fila> filas) {
    final visibles = switch (_filtro) {
      _Filtro.hoy => filas.where((f) => f.aCobrar > 0).toList(),
      _Filtro.atrasados => filas.where((f) => f.hoy.atrasado > 0).toList(),
      _Filtro.todos => [...filas],
    }
      // Primero los más atrasados, luego lo que vence hoy, luego el resto.
      ..sort((a, b) {
        final porAtraso = b.hoy.diasAtraso.compareTo(a.hoy.diasAtraso);
        if (porAtraso != 0) return porAtraso;
        return b.aCobrar.compareTo(a.aCobrar);
      });

    if (visibles.isEmpty) {
      return [
        Vacio(
          icono: Icons.celebration_rounded,
          texto: switch (_filtro) {
            _Filtro.hoy => 'No tienes cobros pendientes para hoy.',
            _Filtro.atrasados => 'Nadie atrasado por ahora. ¡Bien!',
            _Filtro.todos => 'No tienes préstamos en la calle todavía.\n'
                'Aprueba una solicitud y préstale desde Clientes.',
          },
        ),
      ];
    }
    return visibles.map(_filaCobro).toList();
  }

  Widget _filaCobro(_Fila f) {
    final proximo = f.estado.proximoPago;
    final cuando = f.hoy.atrasado > 0
        ? '${f.hoy.diasAtraso} día(s) atrasado'
        : f.hoy.venceHoy > 0
            ? 'Pago hoy'
            : proximo != null
                ? 'Próximo pago ${fechaCorta(proximo)}'
                // Préstamos viejos sin cronograma: debe, pero sin fechas.
                : f.estado.cuotas.isEmpty
                    ? 'Sin cronograma'
                    : 'Sin cuotas pendientes';
    final monto = f.aCobrar > 0 ? f.aCobrar : f.estado.balance;

    return Panel(
      onTap: () => _abrir(f),
      child: Row(
        children: [
          AvatarIniciales(
              nombre: f.datos.nombre, fotoUrl: f.datos.cliente?['foto_cara_url'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.datos.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  [if (f.datos.direccion.isNotEmpty) f.datos.direccion, cuando].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.grey, fontSize: 12),
                ),
                if (f.promesa case final p?
                    when p.estado != EstadoPromesa.cumplida && !p.conSeguimiento) ...[
                  const SizedBox(height: 2),
                  Text(textoPromesa(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: estiloPromesa(p.estado).color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          if (_filtro != _Filtro.todos &&
              (f.datos.cliente?['telefono'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(width: 4),
            BotonWhatsApp(
              onPressed: () => whatsAppCobro(context,
                  nombreCliente: f.datos.nombre,
                  telefono: f.datos.cliente?['telefono'] as String?,
                  estado: f.estado),
            ),
          ],
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rd(monto), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              EtiquetaEstado(f.etiqueta),
            ],
          ),
        ],
      ),
    );
  }
}
