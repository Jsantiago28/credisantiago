import 'package:flutter/material.dart';

import '../logic/cobradores.dart';
import '../logic/dominio.dart';
import '../logic/validacion.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/contacto.dart';
import '../widgets/formato_campos.dart';
import '../widgets/ui.dart';
import 'planes_screen.dart';

/// Perfil → Mis cobradores: agregarlos (por correo), mandarles cómo entrar,
/// repartirles los clientes y quitarles el acceso.
class CobradoresScreen extends StatefulWidget {
  final Map<String, dynamic> perfil;
  const CobradoresScreen({super.key, required this.perfil});

  @override
  State<CobradoresScreen> createState() => _CobradoresScreenState();
}

class _CobradoresScreenState extends State<CobradoresScreen> {
  List<Cobrador>? _cobradores;
  int? _limite; // null = sin límite
  Map<String, int> _clientesPorCobrador = const {};

  String get _id => widget.perfil['id'] as String;

  String get _negocio {
    final n = (widget.perfil['negocio'] as String?)?.trim() ?? '';
    return n.isNotEmpty ? n : ((widget.perfil['nombre'] as String?) ?? '');
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final servicio = SupabaseService.instance;
    var cobradores = const <Cobrador>[];
    try {
      cobradores = await servicio.listarCobradores(_id);
    } catch (e, pila) {
      registrarError(e, pila, 'COBRADORES');
    }
    int? limite = 0;
    try {
      limite = limiteCobradores(
          perfil: widget.perfil, planes: await servicio.obtenerPlanes(), hoy: DateTime.now());
    } catch (_) {}
    var porCobrador = <String, int>{};
    try {
      for (final c in await servicio.clientesParaRepartir(_id)) {
        final cobrador = c['cobrador_id'] as String?;
        if (cobrador != null) porCobrador[cobrador] = (porCobrador[cobrador] ?? 0) + 1;
      }
    } catch (_) {
      porCobrador = {};
    }
    if (!mounted) return;
    setState(() {
      _cobradores = cobradores;
      _limite = limite;
      _clientesPorCobrador = porCobrador;
    });
  }

  int get _activos => (_cobradores ?? const []).where((c) => c.activo).length;
  bool get _puedeAgregar => _limite == null || _activos < _limite!;

  Future<void> _agregar() async {
    if (!_puedeAgregar) {
      _ofrecerPlan(LimiteCobradores(_limite ?? 0).toString());
      return;
    }
    final nuevo = await showModalBottomSheet<Cobrador>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => FormularioCobrador(prestamistaId: _id),
    );
    if (nuevo == null) return;
    await _cargar();
    if (mounted) await _mandarInvitacion(nuevo);
  }

  void _ofrecerPlan(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      action: SnackBarAction(
        label: 'Ver planes',
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanesScreen())),
      ),
    ));
  }

  Future<void> _mandarInvitacion(Cobrador c) async {
    final mensaje = mensajeInvitacionCobrador(
        nombre: c.nombre, email: c.email, negocio: _negocio, link: kDominioBase);
    await abrirWhatsApp(context, c.telefono, mensaje);
  }

  Future<void> _cambiarActivo(Cobrador c) async {
    final mensajero = ScaffoldMessenger.of(context);
    if (c.activo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('¿Quitarle el acceso a ${c.nombre}?'),
          content: const Text('Deja de ver la ruta al instante. Lo que ya cobró queda guardado. '
              'Sus clientes siguen asignados a él: repártelos a otro o quedan para ti '
              'si los quitas.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Quitar acceso', style: TextStyle(color: AppColors.red)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await SupabaseService.instance.actualizarCobrador(c.id, {'activo': !c.activo});
      mensajero.showSnackBar(SnackBar(
          content:
              Text(c.activo ? '${c.nombre} ya no tiene acceso' : '${c.nombre} activo de nuevo')));
      _cargar();
    } on LimiteCobradores catch (e) {
      _ofrecerPlan('$e');
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo. ${mensajeError(e)}')));
    }
  }

  Future<void> _repartir(Cobrador c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RepartirClientesScreen(prestamistaId: _id, cobrador: c),
    ));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final cobradores = _cobradores;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis cobradores')),
      floatingActionButton: cobradores == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _agregar,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Agregar cobrador'),
            ),
      body: cobradores == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Text(
                    _limite == null
                        ? 'Tu plan permite cobradores sin límite. Tienes ${plural(_activos, 'activo', 'activos')}.'
                        : _limite == 0
                            ? 'Tu plan no incluye cobradores. Con el Básico tienes 1 y con el Pro, 3.'
                            : 'Tu plan permite ${plural(_limite ?? 0, 'cobrador', 'cobradores')}. Tienes ${plural(_activos, 'activo', 'activos')}.',
                    style: TextStyle(color: AppColors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cada cobrador entra a esta misma app con su correo y solo ve los '
                    'clientes que le repartas. No ve reportes ni ganancias, no presta y no '
                    'anula cobros.',
                    style: TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (cobradores.isEmpty)
                    const Vacio(
                        icono: Icons.delivery_dining_rounded,
                        texto: 'Todavía no tienes cobradores.'),
                  for (final c in cobradores)
                    TarjetaCobrador(
                      cobrador: c,
                      clientes: _clientesPorCobrador[c.id] ?? 0,
                      onRepartir: () => _repartir(c),
                      onInvitar: () => _mandarInvitacion(c),
                      onCambiarActivo: () => _cambiarActivo(c),
                    ),
                ],
              ),
            ),
    );
  }
}

class TarjetaCobrador extends StatelessWidget {
  final Cobrador cobrador;
  final int clientes;
  final VoidCallback onRepartir;
  final VoidCallback onInvitar;
  final VoidCallback onCambiarActivo;

  const TarjetaCobrador({
    super.key,
    required this.cobrador,
    required this.clientes,
    required this.onRepartir,
    required this.onInvitar,
    required this.onCambiarActivo,
  });

  @override
  Widget build(BuildContext context) {
    final c = cobrador;
    final color = !c.activo
        ? AppColors.grey
        : c.yaEntro
            ? AppColors.green
            : AppColors.amber;
    return Panel(
      borde: color.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarIniciales(nombre: c.nombre, tamano: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nombre,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: c.activo ? null : AppColors.grey)),
                    Text(c.email,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.grey, fontSize: 12)),
                    Text(c.estado,
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${plural(clientes, 'cliente', 'clientes')} en su ruta',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (c.activo && !c.yaEntro)
            Text('Mándale cómo entrar por WhatsApp.',
                style: TextStyle(color: AppColors.amber, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              if (c.activo)
                TextButton.icon(
                  onPressed: onRepartir,
                  icon: const Icon(Icons.route_rounded, size: 18),
                  label: const Text('Repartir clientes'),
                ),
              if (c.activo)
                TextButton.icon(
                  onPressed: onInvitar,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Cómo entrar'),
                ),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: c.activo ? AppColors.red : AppColors.green),
                onPressed: onCambiarActivo,
                child: Text(c.activo ? 'Quitar acceso' : 'Activar de nuevo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nombre, correo y teléfono del cobrador nuevo. Devuelve el cobrador
/// guardado (o null si cancela).
class FormularioCobrador extends StatefulWidget {
  final String prestamistaId;
  const FormularioCobrador({super.key, required this.prestamistaId});

  @override
  State<FormularioCobrador> createState() => _FormularioCobradorState();
}

class _FormularioCobradorState extends State<FormularioCobrador> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final navegador = Navigator.of(context);
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final c = await SupabaseService.instance.agregarCobrador(widget.prestamistaId,
          nombre: _nombre.text, email: _email.text, telefono: _telefono.text);
      navegador.pop(c);
    } catch (e, pila) {
      registrarError(e, pila, 'AGREGAR COBRADOR');
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = mensajeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Agregar cobrador',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombre,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                validator: errorNombre,
                decoration: const InputDecoration(labelText: 'Nombre y apellido'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                validator: errorCorreo,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  helperText: 'Con este correo se registra en la app y crea su contraseña.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                inputFormatters: [FormatoTelefono()],
                validator: errorTelefono,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp',
                  helperText: 'Para mandarle cómo entrar.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: AppColors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Guardar y mandarle cómo entrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marca los clientes de la ruta de un cobrador. Los que son de otro
/// cobrador dicen de quién son; al marcarlos, pasan a este.
class RepartirClientesScreen extends StatefulWidget {
  final String prestamistaId;
  final Cobrador cobrador;

  /// Para pruebas: clientes y cobradores ya cargados.
  final List<Map<String, dynamic>>? clientes;
  final List<Cobrador>? cobradores;

  const RepartirClientesScreen({
    super.key,
    required this.prestamistaId,
    required this.cobrador,
    this.clientes,
    this.cobradores,
  });

  @override
  State<RepartirClientesScreen> createState() => _RepartirClientesScreenState();
}

class _RepartirClientesScreenState extends State<RepartirClientesScreen> {
  late List<Map<String, dynamic>>? _clientes = widget.clientes;
  late Map<String, String> _nombresCobradores = {
    for (final c in widget.cobradores ?? const <Cobrador>[]) c.id: c.nombre,
  };

  /// Clientes marcados ahora (empieza con los que ya son suyos).
  late Set<String> _marcados = _suyos();
  String _busqueda = '';
  bool _guardando = false;

  Set<String> _suyos() => {
        for (final c in _clientes ?? const <Map<String, dynamic>>[])
          if (c['cobrador_id'] == widget.cobrador.id) c['id'] as String,
      };

  @override
  void initState() {
    super.initState();
    if (widget.clientes == null) _cargar();
  }

  Future<void> _cargar() async {
    final servicio = SupabaseService.instance;
    final clientes = await servicio.clientesParaRepartir(widget.prestamistaId);
    var cobradores = const <Cobrador>[];
    try {
      cobradores = await servicio.listarCobradores(widget.prestamistaId);
    } catch (e, pila) {
      registrarError(e, pila, 'COBRADORES');
    }
    if (!mounted) return;
    setState(() {
      _clientes = clientes;
      _nombresCobradores = {for (final c in cobradores) c.id: c.nombre};
      _marcados = _suyos();
    });
  }

  /// Nombre o dirección, sin importar mayúsculas ni acentos.
  bool _coincide(Map<String, dynamic> c) {
    final q = normalizarTexto(_busqueda);
    if (q.isEmpty) return true;
    return normalizarTexto('${c['nombre'] ?? ''} ${c['direccion'] ?? ''}').contains(q);
  }

  Future<void> _guardar() async {
    final clientes = _clientes ?? const [];
    final antes = _suyos();
    final agregar = _marcados.difference(antes).toList();
    final quitar = antes.difference(_marcados).toList();
    final mensajero = ScaffoldMessenger.of(context);
    final navegador = Navigator.of(context);
    setState(() => _guardando = true);
    try {
      final servicio = SupabaseService.instance;
      await servicio.asignarCobrador(agregar, widget.cobrador.id);
      await servicio.asignarCobrador(quitar, null);
      mensajero.showSnackBar(SnackBar(
          content: Text('${widget.cobrador.nombre}: ${plural(_marcados.length, 'cliente', 'clientes')} en su ruta')));
      navegador.pop(true);
    } catch (e, pila) {
      registrarError(e, pila, 'REPARTIR (${clientes.length} clientes)');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo guardar. ${mensajeError(e)}')));
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _clientes;
    final visibles =
        (clientes ?? const <Map<String, dynamic>>[]).where((c) => _coincide(c)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Ruta de ${widget.cobrador.nombre.split(' ').first}')),
      bottomNavigationBar: clientes == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.check),
                  label: Text('Guardar (${plural(_marcados.length, 'cliente', 'clientes')})'),
                ),
              ),
            ),
      body: clientes == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                TextField(
                  onChanged: (t) => setState(() => _busqueda = t),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por nombre o dirección',
                  ),
                ),
                const SizedBox(height: 8),
                if (clientes.isEmpty)
                  const Vacio(icono: Icons.people_outline, texto: 'Todavía no tienes clientes.'),
                for (final c in visibles)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _marcados.contains(c['id']),
                    activeColor: AppColors.green,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _marcados.add(c['id'] as String);
                      } else {
                        _marcados.remove(c['id']);
                      }
                    }),
                    title: Text(c['nombre'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      [
                        if ((c['direccion'] as String?)?.isNotEmpty == true) c['direccion'],
                        if (c['cobrador_id'] != null && c['cobrador_id'] != widget.cobrador.id)
                          _marcados.contains(c['id'])
                              ? 'Pasa de ${_nombresCobradores[c['cobrador_id']] ?? 'otro cobrador'} a ${widget.cobrador.nombre.split(' ').first}'
                              : 'Lo cobra ${_nombresCobradores[c['cobrador_id']] ?? 'otro cobrador'}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }
}
