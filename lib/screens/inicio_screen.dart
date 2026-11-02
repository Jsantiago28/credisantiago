import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/gestiones.dart';
import '../logic/ruta.dart';
import '../logic/ruta_del_dia.dart';
import '../services/errores.dart';
import '../services/sin_conexion.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/aviso_sin_conexion.dart';
import '../widgets/cobro_prestamo.dart';
import '../widgets/contacto.dart';
import '../widgets/gestiones.dart';
import '../widgets/primeros_pasos.dart';
import '../widgets/progreso_ruta.dart';
import '../widgets/ubicacion.dart';
import '../widgets/ui.dart';
import '../widgets/instalar_app.dart';
import 'calculadora_screen.dart';
import 'mapa_cobros_screen.dart';
import 'recordar_manana_screen.dart';
import 'semana_screen.dart';

/// Qué préstamos muestra la lista de abajo.
enum _Filtro { hoy, atrasados, todos }

/// En qué orden sale la lista: los más atrasados primero, o el más cercano
/// (desde donde está el teléfono) y de ahí al siguiente más cercano.
enum _Orden { atraso, cercania }

/// Tablero principal: totales, aviso de solicitudes y cobros del día.
class InicioScreen extends StatefulWidget {
  final Map<String, dynamic> perfil;
  final int solicitudesNuevas;
  final VoidCallback onVerSolicitudes;
  final VoidCallback onVerPerfil;

  /// La lupa del encabezado: buscar un cliente. Sin ella (cobrador) no sale.
  final VoidCallback? onBuscar;

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
    this.onBuscar,
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

  /// Lo que entró hoy de este préstamo (también lo cobrado sin señal).
  final double cobradoHoy;
  _Fila(this.datos, this.estado, this.hoy, this.promesa, this.cobradoHoy);

  double get aCobrar => hoy.atrasado + hoy.venceHoy;
  ParadaDelDia get parada => (aCobrar: aCobrar, cobradoHoy: cobradoHoy);

  /// Dónde vive el cliente (null si no se guardó).
  Punto? get punto => puntoDe(datos.cliente?['lat'], datos.cliente?['lng']);
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
  _Orden _orden = _Orden.atraso;

  /// Dónde estaba el teléfono al elegir "Por cercanía".
  Punto? _yo;
  bool _buscandoUbicacion = false;

  /// La sección "Ya cobrados hoy" está abierta.
  bool _verCobrados = false;

  /// Espera un momento antes de recargar por un cambio en vivo: un cobro
  /// manda varios avisos seguidos y basta con una sola recarga.
  Timer? _espera;
  static const _esperaCambios = Duration(milliseconds: 1500);

  /// Número de la última carga: si una carga vieja termina después de una
  /// nueva, su resultado se bota.
  int _secuencia = 0;

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
        .listen((_) => _recargarPronto(), onError: (_) {});
  }

  /// Recarga 1.5 s después del último aviso de cambio.
  void _recargarPronto() {
    _espera?.cancel();
    if (!mounted) return;
    _espera = Timer(_esperaCambios, () {
      if (mounted) _cargar();
    });
  }

  @override
  void dispose() {
    _cambios?.cancel();
    _reintento?.cancel();
    _espera?.cancel();
    super.dispose();
  }

  /// Mientras haya cobros sin subir o no haya señal, se reintenta solo.
  Timer? _reintento;

  /// La cartera: en vivo (y se guarda para cuando no haya señal) o, sin
  /// señal, la guardada en el teléfono. Siempre con los cobros sin subir.
  Future<List<PrestamoConDatos>> _cartera() async {
    final servicio = SupabaseService.instance;
    if (!SinConexion.disponible) return servicio.obtenerCartera(_prestamistaId);
    await SinConexion.subir();
    try {
      final cartera = await servicio.obtenerCartera(_prestamistaId);
      await SinConexion.guardarRuta(cartera);
      return SinConexion.mezclar(cartera, await SinConexion.cola());
    } catch (e) {
      if (!SinConexion.esFaltaDeConexion(e)) rethrow;
      SinConexion.sinSenal.value = true;
      final guardada = await SinConexion.ruta();
      if (guardada == null) {
        throw 'No hay señal y este teléfono no tiene la ruta guardada (o ya pasaron '
            '${SinConexion.validez.inDays} días). Conéctate un momento para bajarla.';
      }
      SinConexion.rutaGuardadaDe.value = guardada.guardada;
      return SinConexion.mezclar(guardada.cartera, await SinConexion.cola());
    } finally {
      final seguir = SinConexion.sinSenal.value || SinConexion.pendientes.value > 0;
      _reintento?.cancel();
      // Si ya se salió de la pantalla, no queda un reloj recargando.
      _reintento = null;
      if (seguir && mounted) {
        _reintento = Timer(const Duration(minutes: 1), () {
          if (mounted) _cargar();
        });
      }
    }
  }

  Future<void> _cargar() async {
    final mia = ++_secuencia;
    try {
      final cartera = await _cartera();
      final ahora = DateTime.now();
      final filas = cartera.map((d) {
        final e = d.estado(ahora);
        return _Fila(d, e, cobroDelDia(e, ahora), d.promesa(ahora), cobradoEnDia(d.pagos, ahora));
      }).toList();
      // Ya salió de la pantalla, o empezó otra carga más nueva: esta se bota.
      if (!mounted || mia != _secuencia) return;
      setState(() {
        _filas = filas;
        _error = null;
      });
    } catch (e, pila) {
      if (!mounted || mia != _secuencia) return;
      registrarError(e, pila, 'INICIO');
      // El aviso de "sin ruta guardada" ya viene en palabras; lo demás no.
      setState(() => _error = e is String ? e : mensajeError(e));
    }
  }

  /// Cambia el orden de la lista. Para "Por cercanía" busca dónde está el
  /// teléfono; si no se puede, se queda por atraso.
  Future<void> _elegirOrden(_Orden orden) async {
    if (orden == _Orden.atraso) {
      setState(() => _orden = orden);
      return;
    }
    final mensajero = ScaffoldMessenger.of(context);
    setState(() => _buscandoUbicacion = true);
    final yo = await ubicacionSinAvisar();
    if (!mounted) return;
    setState(() {
      _buscandoUbicacion = false;
      if (yo != null) {
        _yo = yo;
        _orden = _Orden.cercania;
      }
    });
    if (yo == null) {
      mensajero.showSnackBar(const SnackBar(
          content: Text('No pudimos saber dónde estás. Prende la ubicación y dale permiso '
              'a la app.')));
    }
  }

  /// Ordena la lista según lo elegido. Por cercanía, los que no tienen
  /// ubicación guardada van al final (por atraso).
  List<_Fila> _ordenar(List<_Fila> filas) {
    int porAtraso(_Fila a, _Fila b) {
      final dias = b.hoy.diasAtraso.compareTo(a.hoy.diasAtraso);
      if (dias != 0) return dias;
      return b.aCobrar.compareTo(a.aCobrar);
    }

    final yo = _yo;
    if (_orden == _Orden.atraso || yo == null) return [...filas]..sort(porAtraso);
    final conLugar = filas.where((f) => f.punto != null).toList();
    final sinLugar = filas.where((f) => f.punto == null).toList()..sort(porAtraso);
    return [...ordenarRuta(conLugar, (f) => f.punto!, inicio: yo), ...sinLugar];
  }

  Future<void> _noEstaba(_Fila f) async {
    if (await anotarNoEstaba(context, f.datos)) _cargar();
  }

  /// Nombre del negocio que firma los mensajes.
  String get _negocio {
    final n = widget.modoCobrador
        ? widget.negocioDelJefe
        : (widget.perfil['nombre'] as String?);
    return (n == null || n.trim().isEmpty) ? 'su prestamista' : n.trim();
  }

  List<RecordatorioManana> _deManana(List<_Fila> filas) => [
        for (final m in pagosDeManana(filas, (f) => f.estado, DateTime.now()))
          (
            nombre: m.item.datos.nombre,
            telefono: m.item.datos.cliente?['telefono'] as String?,
            monto: m.monto,
            fecha: m.fecha,
          ),
      ];

  Widget _accesos(List<_Fila> filas) {
    final manana = _deManana(filas);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SemanaScreen(
              cartera: [for (final f in filas) f.datos],
              onAbrir: (d) => CobroPrestamo(context, d, onCambio: _cargar).abrirCuotas(),
            ),
          )),
          icon: const Icon(Icons.calendar_view_week_rounded, size: 20),
          label: const Text('Semana'),
        ),
        if (manana.isNotEmpty)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RecordarMananaScreen(clientes: manana, negocio: _negocio),
            )),
            icon: const Icon(Icons.notifications_active_rounded, size: 20),
            label: Text('Recordar a los de mañana (${manana.length})'),
          ),
      ],
    );
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
              const AvisoSinConexion(),
              const TarjetaInstalar(),
              if (filas == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar tus préstamos.\n$_error')
              else ...[
                if (!widget.modoCobrador)
                  PrimerosPasos(
                    perfil: widget.perfil,
                    tienePrestamos: filas!.isNotEmpty,
                    onCambio: _cargar,
                    onVerClientes: widget.onBuscar,
                  ),
                _totales(filas!),
                const SizedBox(height: 12),
                _accesos(filas),
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
                const SizedBox(height: 8),
                _selectorOrden(),
                const SizedBox(height: 12),
                if (_filtro == _Filtro.hoy && progresoRuta(filas.map((f) => f.parada)).total > 0)
                  BarraProgresoRuta(progresoRuta(filas.map((f) => f.parada))),
                ..._lista(filas),
                if (_filtro == _Filtro.hoy) ..._yaCobrados(filas),
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
    // La ciudad que puso para sus contratos (Perfil → Mi recibo y contrato).
    final ciudad = ((widget.perfil['contrato_ciudad'] as String?) ?? '').trim();
    return Column(
      children: [
        if (ciudad.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.location_on_rounded, color: AppColors.green, size: 18),
              const SizedBox(width: 4),
              Expanded(
                child: Text(ciudad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            LogoNegocio(logo: widget.perfil['recibo_logo'] as String?, tamano: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.modoCobrador ? 'Mi ruta\nde cobro' : 'Credi\nSantiago',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.05)),
            ),
            if (widget.onBuscar != null)
              IconButton(
                tooltip: 'Buscar cliente',
                icon: Icon(Icons.search_rounded, color: AppColors.texto, size: 28),
                onPressed: widget.onBuscar,
              ),
            if (!widget.modoCobrador)
              IconButton(
                tooltip: 'Calculadora de préstamos',
                icon: Icon(Icons.calculate_rounded, color: AppColors.green, size: 28),
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
                decoration: BoxDecoration(
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
              detalle: plural(filas.length, 'préstamo', 'préstamos'),
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
              detalle: '${plural(hoy.length, 'cobro', 'cobros')} hoy',
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
              detalle: plural(atrasados.length, 'cliente', 'clientes'),
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
          Icon(Icons.mark_email_unread_rounded, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(n == 1 ? 'Tienes 1 solicitud nueva' : 'Tienes $n solicitudes nuevas',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Icon(Icons.chevron_right, color: AppColors.grey),
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
            icon: Icon(Icons.map_rounded, color: AppColors.green),
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
            child: Row(
              children: [
                Icon(Icons.tune, color: AppColors.green, size: 18),
                const SizedBox(width: 6),
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
    // Por atraso: primero los más atrasados, luego lo que vence hoy, luego
    // el resto. Por cercanía: del más cercano al siguiente.
    final visibles = _ordenar(switch (_filtro) {
      _Filtro.hoy => filas.where((f) => f.aCobrar > 0).toList(),
      _Filtro.atrasados => filas.where((f) => f.hoy.atrasado > 0).toList(),
      _Filtro.todos => [...filas],
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

  /// "Por atraso / Por cercanía".
  Widget _selectorOrden() {
    Widget opcion(_Orden o, String texto, IconData icono) => ChoiceChip(
          avatar: Icon(icono,
              size: 18, color: _orden == o ? AppColors.green : AppColors.grey),
          label: Text(texto),
          selected: _orden == o,
          showCheckmark: false,
          selectedColor: AppColors.greenDark,
          backgroundColor: AppColors.surface,
          labelStyle: TextStyle(
              color: _orden == o ? AppColors.green : AppColors.texto,
              fontWeight: FontWeight.w700),
          onSelected: _buscandoUbicacion ? null : (_) => _elegirOrden(o),
        );
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        opcion(_Orden.atraso, 'Por atraso', Icons.warning_amber_rounded),
        opcion(_Orden.cercania, 'Por cercanía', Icons.near_me_rounded),
        if (_buscandoUbicacion)
          const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

  /// Sección plegable con los que ya pagaron todo lo de hoy.
  List<Widget> _yaCobrados(List<_Fila> filas) {
    final cobrados = filas.where((f) => yaCobradoHoy(f.parada)).toList()
      ..sort((a, b) => a.datos.nombre.toLowerCase().compareTo(b.datos.nombre.toLowerCase()));
    if (cobrados.isEmpty) return const [];
    final total = cobrados.fold<double>(0, (s, f) => s + f.cobradoHoy);
    return [
      const SizedBox(height: 8),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _verCobrados = !_verCobrados),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Ya cobrados hoy (${cobrados.length}) · ${rd(total)}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Icon(_verCobrados ? Icons.expand_less : Icons.expand_more, color: AppColors.grey),
            ],
          ),
        ),
      ),
      if (_verCobrados)
        for (final f in cobrados)
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 8),
            onTap: () => _abrir(f),
            child: Row(
              children: [
                AvatarIniciales(
                    nombre: f.datos.nombre,
                    fotoUrl: f.datos.cliente?['foto_cara_url'] as String?,
                    tamano: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(f.datos.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Text(rd(f.cobradoHoy),
                    style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
    ];
  }

  Widget _filaCobro(_Fila f) {
    final proximo = f.estado.proximoPago;
    final cuando = f.hoy.atrasado > 0
        ? (f.hoy.diasAtraso > 0
            ? '${plural(f.hoy.diasAtraso, 'día', 'días')} atrasado'
            : 'Debe mora')
        : f.hoy.venceHoy > 0
            ? 'Vence hoy'
            : proximo != null
                ? 'Próximo pago ${fechaCorta(proximo)}'
                // Préstamos viejos sin cronograma: debe, pero sin fechas.
                : f.estado.cuotas.isEmpty
                    ? 'Sin cronograma'
                    : 'Sin cuotas pendientes';
    final monto = f.aCobrar > 0 ? f.aCobrar : f.estado.balance;

    final fila = Row(
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
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
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
      );

    return Panel(
      onTap: () => _abrir(f),
      child: _filtro == _Filtro.todos || f.aCobrar <= 0
          ? fila
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fila,
                Align(
                  alignment: Alignment.centerRight,
                  // Un toque: anota la visita sin abrir el formulario.
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.grey, minimumSize: const Size(48, 48)),
                    onPressed: () => _noEstaba(f),
                    icon: const Icon(Icons.person_off_rounded, size: 18),
                    label: const Text('No estaba'),
                  ),
                ),
              ],
            ),
    );
  }
}
