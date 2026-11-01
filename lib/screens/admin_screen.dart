import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart' show fechaSql;
import '../logic/planes.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/contacto.dart';
import '../widgets/foto_privada.dart';
import '../widgets/panel_errores.dart';
import '../widgets/ui.dart';
import 'planes_screen.dart' show FilaPagoPlan, metodosPagoPlan;

/// Panel del administrador de la app: aprobar cuentas nuevas, dar o
/// renovar planes y editar cómo le pagan. Solo lo ve quien tiene
/// es_admin = true (la base de datos tampoco deja a nadie más).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>>? _prestamistas;
  List<Map<String, dynamic>> _planes = const [];
  Map<String, dynamic>? _ajustes;
  String? _error;

  final _soporte = TextEditingController();
  final _instrucciones = TextEditingController();
  final _descuento3 = TextEditingController();
  final _mesesGratis12 = TextEditingController();
  final _apkVersion = TextEditingController();
  final _apkEnlace = TextEditingController();
  List<Map<String, dynamic>> _pagos = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _soporte.dispose();
    _instrucciones.dispose();
    _descuento3.dispose();
    _mesesGratis12.dispose();
    _apkVersion.dispose();
    _apkEnlace.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final s = SupabaseService.instance;
    try {
      final lista = await s.adminPrestamistas();
      final planes = await s.obtenerPlanes();
      final ajustes = await s.obtenerAjustes();
      // Sin la migración de pagos de planes, la lista sale vacía.
      final pagos = await s.obtenerPagosPlanes().catchError((_) => <Map<String, dynamic>>[]);
      if (!mounted) return;
      setState(() {
        _prestamistas = lista;
        _planes = planes;
        _pagos = pagos;
        _error = null;
        if (_ajustes == null && ajustes != null) {
          _soporte.text = ajustes['whatsapp_soporte'] as String? ?? '';
          _instrucciones.text = ajustes['instrucciones_pago'] as String? ?? '';
          final d = DescuentosPlan.desde(ajustes);
          _descuento3.text = '${d.descuento3}';
          _mesesGratis12.text = '${d.mesesGratis12}';
          _apkVersion.text = ajustes['apk_version'] as String? ?? '';
          _apkEnlace.text = ajustes['apk_enlace'] as String? ?? '';
        }
        _ajustes = ajustes;
      });
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL ADMIN: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _cambiar(Map<String, dynamic> p, Map<String, dynamic> cambios, String listo) async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.adminActualizarPrestamista(p['id'] as String, cambios);
      mensajero.showSnackBar(SnackBar(content: Text(listo)));
      _cargar();
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo: $e')));
    }
  }

  /// La cédula que subió [p] al registrarse (número y los dos lados).
  void _verCedula(Map<String, dynamic> p) {
    Widget lado(String titulo, String? ruta) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TextStyle(color: AppColors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FotoPrivada(
                guardado: ruta,
                width: double.infinity,
                height: 190,
                fit: BoxFit.contain,
                sinFoto: Container(
                  height: 190,
                  color: AppColors.surfaceAlt,
                  alignment: Alignment.center,
                  child: Text('Sin foto', style: TextStyle(color: AppColors.grey)),
                ),
              ),
            ),
          ],
        );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cédula de ${p['nombre']}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text((p['cedula'] as String?)?.isNotEmpty == true ? p['cedula'] : 'Sin número',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                lado('Frente', p['cedula_frente_url'] as String?),
                const SizedBox(height: 12),
                lado('Atrás', p['cedula_reverso_url'] as String?),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  /// Da el mes gratis al que invitó a [p] (que ya pagó su primer plan).
  Future<void> _darPremio(Map<String, dynamic> p) async {
    final quien = p['invitado_por_nombre'] as String? ?? 'quien lo invitó';
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Dar 1 mes gratis a $quien?'),
        content: Text('Por invitar a ${p['nombre']}, que ya pagó su primer plan. Se le alarga '
            '1 mes su plan (o recibe 1 mes de Básico si está en Gratis) y queda anotado '
            'en sus pagos como "premio".'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sí, darlo')),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final hasta = await SupabaseService.instance.adminPremioInvitacion(p['id'] as String);
      mensajero.showSnackBar(
          SnackBar(content: Text('Listo: $quien tiene su plan hasta el ${fechaLarga(hasta)}')));
      _cargar();
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo: $e')));
    }
  }

  Future<void> _guardarAjustes() async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.client.from('ajustes_app').update({
        'whatsapp_soporte': _soporte.text.trim(),
        'instrucciones_pago': _instrucciones.text.trim(),
        // Solo si ya se corrió la migración de pagos de planes.
        if (_ajustes?.containsKey('descuento_3_meses') == true) ...{
          'descuento_3_meses': (int.tryParse(_descuento3.text) ?? 10).clamp(0, 90),
          'meses_gratis_12': (int.tryParse(_mesesGratis12.text) ?? 2).clamp(0, 11),
        },
        // Solo si ya se corrió la migración de seguridad (aviso de versión).
        if (_ajustes?.containsKey('apk_version') == true) ...{
          'apk_version': _apkVersion.text.trim(),
          'apk_enlace': _apkEnlace.text.trim(),
        },
      }).eq('id', 1);
      _ajustes = await SupabaseService.instance.obtenerAjustes();
      mensajero.showSnackBar(const SnackBar(content: Text('Ajustes guardados')));
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  Future<void> _elegirPlan(Map<String, dynamic> p) async {
    final elegido = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Cambiar plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            for (final plan in _planes)
              ListTile(
                title: Text(plan['nombre'] as String? ?? ''),
                subtitle: Text(
                    '${rd(plan['precio_mensual'] as num? ?? 0)}/mes · '
                    '${plan['max_clientes'] == null ? 'sin límite' : 'hasta ${plan['max_clientes']} clientes'}'),
                trailing: plan['id'] == p['plan']
                    ? Icon(Icons.check, color: AppColors.green)
                    : null,
                onTap: () => Navigator.of(ctx).pop(plan['id'] as String),
              ),
          ],
        ),
      ),
    );
    if (elegido == null) return;
    if (elegido != 'gratis' && !await _cedulaOConfirmar(p)) return;
    // Plan pagado: vence en un mes desde hoy (o se mantiene si ya tenía
    // fecha futura). Gratis: sin vencimiento.
    final vence = DateTime.tryParse(p['plan_vence'] as String? ?? '');
    await _cambiar(
      p,
      {
        'plan': elegido,
        'plan_vence': elegido == 'gratis'
            ? null
            : fechaSql(vence != null && vence.isAfter(DateTime.now())
                ? vence
                : nuevaFechaVence(null, DateTime.now())),
      },
      'Plan cambiado',
    );
  }

  /// Registrar una mensualidad recibida: plan, 1/3/12 meses, monto (ya
  /// puesto con el precio y su descuento), cómo pagó y una nota. La base
  /// de datos extiende el plan y guarda el pago.
  /// Antes de un plan pagado: si el prestamista no ha dejado su cédula (se
  /// registró en Gratis sin ella), avisa y pregunta si seguir igual.
  Future<bool> _cedulaOConfirmar(Map<String, dynamic> p) async {
    final tiene = ((p['cedula'] as String?) ?? '').trim().isNotEmpty &&
        p['cedula_frente_url'] != null &&
        p['cedula_reverso_url'] != null;
    if (tiene) return true;
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sin cédula'),
        content: Text('${p['nombre']} todavía no ha dejado su cédula. Se le pide sola al tocar '
            '"Enviar comprobante" en Planes. ¿Activarle el plan pagado de todas formas?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sí, seguir')),
        ],
      ),
    );
    return seguir == true;
  }

  Future<void> _registrarPago(Map<String, dynamic> p) async {
    final pagados = _planes.where((x) => ((x['precio_mensual'] as num?) ?? 0) > 0).toList();
    if (pagados.isEmpty) return;
    if (!await _cedulaOConfirmar(p) || !mounted) return;
    final descuentos = DescuentosPlan.desde(_ajustes);
    var plan = pagados.any((x) => x['id'] == p['plan']) ? p['plan'] as String : pagados.first['id'] as String;
    var meses = 1;
    var metodo = 'transferencia';
    final monto = TextEditingController();
    final nota = TextEditingController();
    double precio() => precioPeriodo(
        (pagados.firstWhere((x) => x['id'] == plan)['precio_mensual'] as num?) ?? 0, meses, descuentos);
    String pesos(double v) => v.toStringAsFixed(0);
    monto.text = pesos(precio());

    // Igual que la base de datos: el mismo plan sin vencer se suma desde su
    // vencimiento; si no, desde hoy.
    DateTime quedaHasta() {
      final vence = DateTime.tryParse(p['plan_vence'] as String? ?? '');
      final hoy = DateTime.now();
      final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
      final base = plan == p['plan'] && vence != null && !vence.isBefore(hoyDia) ? vence : hoyDia;
      return nuevaFechaVence(base, base, meses: meses);
    }

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) {
          Widget chips<T>(Map<T, String> opciones, T elegido, ValueChanged<T> onElegir) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in opciones.entries)
                    ChoiceChip(
                      label: Text(o.value),
                      selected: elegido == o.key,
                      showCheckmark: false,
                      selectedColor: AppColors.greenDark,
                      backgroundColor: AppColors.surfaceAlt,
                      labelStyle: TextStyle(
                          color: elegido == o.key ? AppColors.green : AppColors.texto,
                          fontWeight: FontWeight.w600),
                      onSelected: (_) => setEstado(() => onElegir(o.key)),
                    ),
                ],
              );
          final valido = (double.tryParse(monto.text.replaceAll(',', '')) ?? -1) >= 0;
          return Padding(
            padding: EdgeInsets.only(
                left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pago de ${p['nombre']}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  const Text('Plan', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  chips({for (final x in pagados) x['id'] as String: x['nombre'] as String}, plan, (v) {
                    plan = v;
                    monto.text = pesos(precio());
                  }),
                  const SizedBox(height: 12),
                  const Text('Meses', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  chips({
                    for (final m in periodosPlan)
                      m: [nombrePeriodoPlan(m), if (descuentos.etiqueta(m) != null) descuentos.etiqueta(m)!]
                          .join(' · ')
                  }, meses, (v) {
                    meses = v;
                    monto.text = pesos(precio());
                  }),
                  const SizedBox(height: 12),
                  const Text('Cómo pagó', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  chips(metodosPagoPlan, metodo, (v) => metodo = v),
                  const SizedBox(height: 12),
                  TextField(
                    controller: monto,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setEstado(() {}),
                    decoration: InputDecoration(
                      labelText: 'Monto recibido',
                      prefixText: 'RD\$ ',
                      errorText: valido ? null : 'Monto no válido',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nota,
                    decoration: const InputDecoration(
                        labelText: 'Nota (opcional)', hintText: 'Ej. transferencia Banreservas #4521'),
                  ),
                  const SizedBox(height: 12),
                  Text('El plan le queda hasta el ${fechaLarga(quedaHasta())}.',
                      style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: valido ? () => Navigator.of(ctx).pop(true) : null,
                    child: const Text('Registrar pago'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (guardar != true || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final hasta = await SupabaseService.instance.adminRegistrarPago(
        prestamistaId: p['id'] as String,
        plan: plan,
        meses: meses,
        monto: double.parse(monto.text.replaceAll(',', '')),
        metodo: metodo,
        nota: nota.text,
      );
      mensajero.showSnackBar(SnackBar(
          content: Text('Pago registrado. ${p['nombre']} tiene el plan hasta el ${fechaLarga(hasta)}.')));
      _cargar();
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL PAGO PLAN: $e');
      mensajero.showSnackBar(SnackBar(
          content: Text(e.toString().contains('admin_registrar_pago')
              ? 'Falta correr la migración de pagos de planes en Supabase.'
              : 'No se pudo registrar el pago: $e')));
    }
  }

  Future<void> _borrarPago(Map<String, dynamic> pago) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Borrar este pago?'),
        content: const Text('Úsalo solo si lo registraste por error. No le quita días al plan: '
            'si hace falta, corrígelo con "Cambiar plan".'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Borrar', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.adminBorrarPagoPlan(pago['id'] as String);
      _cargar();
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo borrar: $e')));
    }
  }

  /// WhatsApp del prestamista (el que dio al registrarse).
  String? _whatsapp(Map<String, dynamic> p) {
    final w = p['whatsapp'] as String?;
    return w == null || w.isEmpty ? null : w;
  }

  /// Los que vencen en los próximos 7 días o vencieron hace poco, con
  /// botón para recordarles por WhatsApp y para registrar el pago.
  Widget _panelVencen(List<Map<String, dynamic>> lista) {
    final vencen = vencenPronto(lista, DateTime.now());
    if (vencen.isEmpty) return const SizedBox.shrink();
    return Panel(
      borde: AppColors.amber.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${vencen.length} por renovar',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
          for (final p in vencen) ...[
            const Divider(height: 20),
            Builder(builder: (context) {
              final vence = DateTime.parse(p['plan_vence'] as String);
              final hoy = DateTime.now();
              final vencido = vence.isBefore(DateTime(hoy.year, hoy.month, hoy.day));
              final plan = _planes.firstWhere((x) => x['id'] == p['plan'],
                  orElse: () => {'nombre': p['plan']})['nombre'] as String? ?? '';
              final whatsapp = _whatsapp(p);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['nombre'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '$plan · ${vencido ? 'venció' : 'vence'} el ${fechaLarga(vence)}',
                    style: TextStyle(color: vencido ? AppColors.red : AppColors.amber, fontSize: 12),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: verdeWhatsApp),
                        onPressed: whatsapp == null
                            ? null
                            : () => abrirWhatsApp(
                                context,
                                whatsapp,
                                mensajeRecordatorioPlan(
                                    prestamista: p['nombre'] as String? ?? '',
                                    plan: plan,
                                    vence: vence,
                                    hoy: hoy)),
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: Text(whatsapp == null ? 'Sin WhatsApp' : 'Recordarle'),
                      ),
                      TextButton.icon(
                        onPressed: () => _registrarPago(p),
                        icon: const Icon(Icons.payments_rounded, size: 18),
                        label: const Text('Registrar pago'),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Lo que has cobrado de mensualidades: el total de este mes y los
  /// últimos pagos.
  Widget _panelPagos() {
    if (_pagos.isEmpty) return const SizedBox.shrink();
    final hoy = DateTime.now();
    final delMes = _pagos.where((x) {
      final f = DateTime.tryParse(x['created_at'] as String? ?? '')?.toLocal();
      return f != null && f.year == hoy.year && f.month == hoy.month;
    });
    final total = delMes.fold<double>(0, (s, x) => s + ((x['monto'] as num?) ?? 0));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mensualidades cobradas', style: TextStyle(color: AppColors.grey, fontSize: 13)),
          Text(rd(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text('este mes · ${delMes.length} pago(s)',
              style: TextStyle(color: AppColors.grey, fontSize: 12)),
          const Divider(height: 20),
          for (final pago in _pagos.take(10)) FilaPagoPlan(pago, onBorrar: () => _borrarPago(pago)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _prestamistas;
    return Scaffold(
      appBar: AppBar(title: const Text('Administrar')),
      body: lista == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : Vacio(
                  icono: Icons.cloud_off,
                  texto: 'No se pudo cargar. ¿Corriste la migración de planes y eres admin?\n$_error'))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _panelVencen(lista),
                  _panelPagos(),
                  const PanelErrores(),
                  _panelAjustes(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Prestamistas',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                      Pildora('${lista.where((p) => p['aprobado'] != true).length} por aprobar',
                          color: AppColors.amber, fondo: AppColors.amberDark),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final p in lista) _tarjeta(p),
                ],
              ),
            ),
    );
  }

  Widget _panelAjustes() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Ajustes de la app', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _soporte,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Tu WhatsApp de soporte', hintText: '809-555-1234'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _instrucciones,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Tus cuentas para pagar (opcional)',
              helperText: 'Salen arriba de los planes y el botón dice "Enviar '
                  'comprobante". Si lo dejas vacío, el botón dice "Lo quiero" y tú les mandas '
                  'la cuenta por WhatsApp.',
              helperMaxLines: 3,
            ),
          ),
          if (_ajustes?.containsKey('descuento_3_meses') == true) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _descuento3,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '3 meses: % menos', suffixText: '%'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _mesesGratis12,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '12 meses: meses gratis'),
                  ),
                ),
              ],
            ),
          ],
          if (_ajustes?.containsKey('apk_version') == true) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _apkVersion,
              decoration: const InputDecoration(
                labelText: 'Última versión del APK',
                hintText: '1.0.7',
                helperText: 'Los que tengan una más vieja ven un aviso para bajarla.',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apkEnlace,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Enlace para bajar el APK',
                hintText: 'https://drive.google.com/...',
                helperText: 'En Drive: compartir → "Cualquier persona con el enlace".',
              ),
            ),
          ],
          ElevatedButton(onPressed: _guardarAjustes, child: const Text('Guardar ajustes')),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final aprobado = p['aprobado'] == true;
    final esAdmin = p['es_admin'] == true;
    final plan = _planes.firstWhere((x) => x['id'] == p['plan'],
        orElse: () => {'nombre': p['plan'], 'max_clientes': null});
    final vence = DateTime.tryParse(p['plan_vence'] as String? ?? '');
    final efectivo = planEfectivo(p, DateTime.now());
    final vencido = efectivo != p['plan'];
    // "telefono" es con lo que entra (hoy, su correo); "whatsapp" lo da al registrarse.
    final telefono = p['telefono'] as String?;
    final whatsapp = _whatsapp(p);

    return Panel(
      borde: aprobado ? null : AppColors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarIniciales(nombre: p['nombre'] as String? ?? '?', tamano: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['nombre'] as String? ?? '(sin nombre)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      [
                        if (telefono != null && telefono.isNotEmpty) telefono,
                        if (whatsapp != null) 'WhatsApp $whatsapp',
                        '${p['clientes'] ?? 0} clientes',
                        if (esAdmin) 'admin',
                      ].join(' · '),
                      style: TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              aprobado
                  ? Pildora((plan['nombre'] as String? ?? '').toUpperCase())
                  : Pildora('POR APROBAR', color: AppColors.amber, fondo: AppColors.amberDark),
            ],
          ),
          if (vence != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                vencido ? 'Venció el ${fechaLarga(vence)} (está en Gratis)' : 'Vence el ${fechaLarga(vence)}',
                style: TextStyle(color: vencido ? AppColors.red : AppColors.grey, fontSize: 12),
              ),
            ),
          if (p['invitado_por_nombre'] case final String quien)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.card_giftcard_rounded, size: 16, color: AppColors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Invitado por $quien · ${switch (p) {
                        {'premio_invitacion': final String dado} =>
                          'premio dado el ${fechaLarga(DateTime.parse(dado))}',
                        {'ya_pago': true} => 'ya pagó: toca dar el premio',
                        _ => 'premio cuando pague su primer plan',
                      }}',
                      style: TextStyle(
                          color: p['ya_pago'] == true && p['premio_invitacion'] == null
                              ? AppColors.green
                              : AppColors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              if (p['cedula_frente_url'] != null || p['cedula_reverso_url'] != null)
                TextButton.icon(
                  onPressed: () => _verCedula(p),
                  icon: const Icon(Icons.badge_rounded, size: 18),
                  label: const Text('Ver cédula'),
                )
              else if (!esAdmin)
                // Se registró sin cédula (para probar en Gratis): la deja al
                // pedir un plan pagado.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text('Sin cédula todavía',
                      style: TextStyle(color: AppColors.amber, fontSize: 12)),
                ),
              if (!aprobado)
                TextButton.icon(
                  onPressed: () => _cambiar(p, {'aprobado': true}, '${p['nombre']} aprobado'),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Aprobar'),
                )
              else if (!esAdmin)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: () => _cambiar(p, {'aprobado': false}, 'Cuenta suspendida'),
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Suspender'),
                ),
              TextButton.icon(
                onPressed: () => _elegirPlan(p),
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text('Cambiar plan'),
              ),
              if (!esAdmin)
                TextButton.icon(
                  onPressed: () => _registrarPago(p),
                  icon: const Icon(Icons.payments_rounded, size: 18),
                  label: const Text('Registrar pago'),
                ),
              if (p['invitado_por'] != null &&
                  p['ya_pago'] == true &&
                  p['premio_invitacion'] == null)
                TextButton.icon(
                  onPressed: () => _darPremio(p),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                  label: Text('Dar premio a ${p['invitado_por_nombre'] ?? 'quien invitó'}'),
                ),
              if (whatsapp != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: verdeWhatsApp),
                  onPressed: () => abrirWhatsApp(context, whatsapp, 'Hola ${p['nombre']}, '),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text('WhatsApp'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
