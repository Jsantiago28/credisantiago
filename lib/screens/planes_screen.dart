import 'package:flutter/material.dart';

import '../logic/planes.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/contacto.dart';
import '../widgets/ui.dart';
import 'registro_formal_screen.dart';

/// Carga lo que necesitan las pantallas de planes: mi perfil, los planes,
/// los ajustes (WhatsApp de soporte, cómo pagar) y cuántos clientes tengo.
Future<({Map<String, dynamic> perfil, List<Map<String, dynamic>> planes, Map<String, dynamic>? ajustes, EstadoPlan estado})>
    _cargarPlanes() async {
  final s = SupabaseService.instance;
  final perfil = await s.obtenerMiPerfil();
  if (perfil == null) throw Exception('No se encontró tu perfil');
  final planes = await s.obtenerPlanes();
  final ajustes = await s.obtenerAjustes();
  final clientes = await s.contarClientes(perfil['id'] as String);
  return (
    perfil: perfil,
    planes: planes,
    ajustes: ajustes,
    estado: estadoPlan(perfil: perfil, planes: planes, clientes: clientes, hoy: DateTime.now()),
  );
}

/// Aviso cuando el plan no deja agregar más clientes.
Future<void> avisarLimitePlan(BuildContext context, LimitePlan e) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(e.limite == 0 ? 'Cuenta en revisión' : 'Llegaste al límite de tu plan'),
      content: Text(e.limite == 0
          ? 'Tu cuenta todavía no está aprobada. Cuando el administrador la apruebe podrás agregar clientes.'
          : 'Tu plan permite ${e.limite} clientes. Para agregar más, mejora tu plan.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Ahora no')),
        if (e.limite > 0)
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanesScreen()));
            },
            child: const Text('Ver planes'),
          ),
      ],
    ),
  );
}

/// Tarjeta "Mi plan" (en Perfil).
class TarjetaMiPlan extends StatefulWidget {
  const TarjetaMiPlan({super.key});

  @override
  State<TarjetaMiPlan> createState() => _TarjetaMiPlanState();
}

class _TarjetaMiPlanState extends State<TarjetaMiPlan> {
  late Future<EstadoPlan> _estado = _cargar();

  Future<EstadoPlan> _cargar() async => (await _cargarPlanes()).estado;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EstadoPlan>(
      future: _estado,
      builder: (context, snap) {
        final e = snap.data;
        if (e == null) {
          return snap.hasError
              ? const SizedBox.shrink() // sin la migración de planes no se muestra
              : const Panel(child: Center(child: CircularProgressIndicator()));
        }
        final dias = e.diasParaVencer(DateTime.now());
        return Panel(
          borde: (e.puedeAgregar ? AppColors.green : AppColors.amber).withValues(alpha: 0.5),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanesScreen()));
            setState(() => _estado = _cargar());
          },
          child: Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: e.puedeAgregar ? AppColors.green : AppColors.amber, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan ${e.nombre}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(
                      e.limite == null
                          ? '${e.usados} clientes · sin límite'
                          : '${e.usados} de ${e.limite} clientes',
                      style: TextStyle(color: AppColors.grey),
                    ),
                    if (e.vencido)
                      Text('Tu plan pagado venció: estás en Gratis',
                          style: TextStyle(color: AppColors.amber, fontSize: 12))
                    else if (e.diasDeGraciaQuedan(DateTime.now()) case final gracia?)
                      Text(
                          'Tu plan venció. Renueva en $gracia día${gracia == 1 ? '' : 's'} '
                          'para no perder nada.',
                          style: TextStyle(
                              color: AppColors.amber, fontSize: 13, fontWeight: FontWeight.w700))
                    else if (dias != null)
                      Text(
                        dias <= 5 ? 'Vence en ${plural(dias, 'día', 'días')}' : 'Vence el ${fechaLarga(e.vence!)}',
                        style: TextStyle(
                            color: dias <= 5 ? AppColors.amber : AppColors.grey, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Text('Ver planes', style: TextStyle(color: AppColors.green)),
              Icon(Icons.chevron_right, color: AppColors.green),
            ],
          ),
        );
      },
    );
  }
}

/// Los planes por 1, 3 o 12 meses y el botón para pedirlo por WhatsApp. La
/// cuenta para depositar no se publica: el administrador la manda por
/// WhatsApp (o se paga en efectivo si queda cerca).
class PlanesScreen extends StatefulWidget {
  const PlanesScreen({super.key});

  @override
  State<PlanesScreen> createState() => _PlanesScreenState();
}

class _PlanesScreenState extends State<PlanesScreen> {
  late final _datos = _cargarPlanes();
  int _meses = 1;

  /// Acaba de completar el registro formal en esta pantalla.
  bool _registroFormal = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planes')),
      body: FutureBuilder(
        future: _datos,
        builder: (context, snap) {
          if (snap.hasError) {
            return Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar los planes.\n${snap.error}');
          }
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          final soporte = d.ajustes?['whatsapp_soporte'] as String?;
          final instrucciones = (d.ajustes?['instrucciones_pago'] as String?)?.trim();
          final descuentos = DescuentosPlan.desde(d.ajustes);
          final cuentasPublicadas = instrucciones?.isNotEmpty == true;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                d.estado.limite == null
                    ? 'Tienes ${d.estado.usados} clientes.'
                    : 'Usas ${d.estado.usados} de ${d.estado.limite} clientes de tu plan ${d.estado.nombre}.',
                style: TextStyle(color: AppColors.grey),
              ),
              const SizedBox(height: 16),
              // Con las cuentas publicadas (Admin → Ajustes) van de primero:
              // elige el plan, paga y manda el comprobante.
              if (cuentasPublicadas) ...[
                const Text('Elige tu plan, paga y envíanos el comprobante',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Panel(
                  borde: AppColors.green.withValues(alpha: 0.5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.account_balance_rounded, color: AppColors.green),
                      const SizedBox(width: 12),
                      Expanded(child: SelectableText(instrucciones!)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Text('¿Por cuánto tiempo?', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _selectorMeses(descuentos),
              const SizedBox(height: 16),
              for (final p in d.planes) _tarjetaPlan(d, p, soporte, descuentos, cuentasPublicadas),
              if (!cuentasPublicadas) ...[
                const SizedBox(height: 8),
                const Text('Cómo pagar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Panel(
                  child: Text(
                    'Toca "Lo quiero" en el plan: te llega por WhatsApp la cuenta para '
                    'depositar o transferir. Si estás cerca, también se puede pagar en efectivo. '
                    'Cuando se reciba el pago, se te activa el plan.',
                  ),
                ),
              ],
              _MisPagos(prestamistaId: d.perfil['id'] as String),
            ],
          );
        },
      ),
    );
  }

  Widget _selectorMeses(DescuentosPlan descuentos) => Row(
        children: [
          for (final m in periodosPlan) ...[
            if (m != periodosPlan.first) const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _meses = m),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: _meses == m ? AppColors.greenDark : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _meses == m ? AppColors.green : AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Text(nombrePeriodoPlan(m),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _meses == m ? AppColors.green : AppColors.texto)),
                      Text(descuentos.etiqueta(m) ?? 'Precio normal',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _tarjetaPlan(
    ({Map<String, dynamic> perfil, List<Map<String, dynamic>> planes, Map<String, dynamic>? ajustes, EstadoPlan estado}) d,
    Map<String, dynamic> p,
    String? soporte,
    DescuentosPlan descuentos,
    bool cuentasPublicadas,
  ) {
    final actual = p['id'] == d.estado.planId;
    final mensual = (p['precio_mensual'] as num?) ?? 0;
    final precio = precioPeriodo(mensual, _meses, descuentos);
    final max = (p['max_clientes'] as num?)?.toInt();
    return Panel(
      borde: actual ? AppColors.green : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(p['nombre'] as String? ?? '',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    if (actual) ...[const SizedBox(width: 8), const Pildora('TU PLAN')],
                  ],
                ),
                Text(max == null ? 'Clientes sin límite' : 'Hasta $max clientes',
                    style: TextStyle(color: AppColors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(mensual == 0 ? 'Gratis' : rd(precio),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (mensual > 0)
                Text(
                  _meses == 1
                      ? 'al mes'
                      : 'por ${nombrePeriodoPlan(_meses)} · ${rd((precio / _meses).roundToDouble())}/mes',
                  style: TextStyle(color: AppColors.grey, fontSize: 11),
                ),
              if (mensual > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: verdeWhatsApp),
                  // Sin el WhatsApp de soporte (Admin → ajustes) no hay a quién
                  // escribirle: se explica en vez de dejar el botón apagado.
                  onPressed: soporte == null || soporte.trim().isEmpty
                      ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Todavía no se puede pedir el plan por aquí: falta el '
                              'WhatsApp de soporte. Escríbele al administrador de la app.')))
                      : () async {
                          // Para un plan pagado se pide el registro formal
                          // (la cédula), si todavía no lo hizo.
                          if (!_registroFormal && !tieneRegistroFormal(d.perfil)) {
                            final listo = await Navigator.of(context).push<bool>(MaterialPageRoute(
                              builder: (_) =>
                                  RegistroFormalScreen(prestamistaId: d.perfil['id'] as String),
                            ));
                            if (listo != true || !mounted) return;
                            _registroFormal = true;
                          }
                          if (!context.mounted) return;
                          await abrirWhatsApp(
                            context,
                            soporte,
                            mensajePedidoPlan(
                              prestamista: (d.perfil['nombre'] as String?) ?? '',
                              plan: p['nombre'] as String? ?? '',
                              meses: _meses,
                              precio: precio,
                              yaPago: cuentasPublicadas,
                            ),
                          );
                        },
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: Text(cuentasPublicadas
                      ? 'Enviar comprobante'
                      : (actual ? 'Renovar' : 'Lo quiero')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Las mensualidades que ha pagado el prestamista (si hay).
class _MisPagos extends StatelessWidget {
  final String prestamistaId;
  const _MisPagos({required this.prestamistaId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      // Sin la migración de pagos de planes, simplemente no se muestra.
      future: SupabaseService.instance
          .obtenerPagosPlanes(prestamistaId: prestamistaId, limite: 24)
          .catchError((_) => <Map<String, dynamic>>[]),
      builder: (context, snap) {
        final pagos = snap.data ?? const [];
        if (pagos.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text('Mis pagos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Panel(
              child: Column(
                children: [
                  for (final p in pagos) FilaPagoPlan(p, conNombre: false),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Cómo se pagó un plan.
const metodosPagoPlan = {
  'transferencia': 'Transferencia',
  'deposito': 'Depósito',
  'efectivo': 'Efectivo',
};

/// Un pago de plan: fecha, plan y meses, cómo se pagó, monto y hasta
/// cuándo quedó. [conNombre] muestra de quién es (para el admin).
class FilaPagoPlan extends StatelessWidget {
  final Map<String, dynamic> pago;
  final bool conNombre;
  final VoidCallback? onBorrar;
  const FilaPagoPlan(this.pago, {super.key, this.conNombre = true, this.onBorrar});

  @override
  Widget build(BuildContext context) {
    final fecha = DateTime.tryParse(pago['created_at'] as String? ?? '')?.toLocal();
    final hasta = DateTime.tryParse(pago['vence_despues'] as String? ?? '');
    final nombre = (pago['profiles'] as Map?)?['nombre'] as String?;
    final nota = pago['nota'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              switch (pago['metodo']) {
                'efectivo' => Icons.payments_rounded,
                'premio' => Icons.card_giftcard_rounded,
                _ => Icons.account_balance_rounded,
              },
              size: 20, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (conNombre && nombre != null) nombre,
                    'Plan ${pago['plan']} · ${nombrePeriodoPlan((pago['meses'] as num?)?.toInt() ?? 1)}',
                  ].join(' — '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    if (fecha != null) fechaLarga(fecha),
                    pago['metodo'] == 'premio'
                        ? 'Premio por invitar'
                        : metodosPagoPlan[pago['metodo']] ?? '${pago['metodo']}',
                    if (hasta != null) 'hasta el ${fechaLarga(hasta)}',
                  ].join(' · '),
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
                ),
                if (nota != null && nota.isNotEmpty)
                  Text(nota, style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ],
            ),
          ),
          Text(rd((pago['monto'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
          if (onBorrar != null)
            IconButton(
              tooltip: 'Borrar (registrado por error)',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.grey),
              onPressed: onBorrar,
            ),
        ],
      ),
    );
  }
}

/// Lo que ve un prestamista nuevo mientras el administrador no lo aprueba.
class CuentaEnRevisionScreen extends StatelessWidget {
  final Map<String, dynamic> perfil;
  final VoidCallback onRecargar;
  const CuentaEnRevisionScreen({super.key, required this.perfil, required this.onRecargar});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top_rounded, color: AppColors.amber, size: 64),
                  const SizedBox(height: 16),
                  const Text('Tu cuenta está en revisión',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Hola ${(perfil['nombre'] as String? ?? '').split(' ').first}. '
                    'El administrador tiene que aprobar tu cuenta antes de que puedas usar la app. '
                    'Te avisará cuando esté lista.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey),
                  ),
                  const SizedBox(height: 24),
                  FutureBuilder<Map<String, dynamic>?>(
                    future: SupabaseService.instance.obtenerAjustes(),
                    builder: (context, snap) {
                      final soporte = snap.data?['whatsapp_soporte'] as String?;
                      if (soporte == null || soporte.isEmpty) return const SizedBox.shrink();
                      return ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: verdeWhatsApp),
                        onPressed: () => abrirWhatsApp(context, soporte,
                            'Hola, soy ${perfil['nombre']}. Me registré en CrediSantiago y espero la aprobación de mi cuenta.'),
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('Escribir al administrador'),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onRecargar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Ya me aprobaron'),
                  ),
                  TextButton(
                    onPressed: () => SupabaseService.instance.cerrarSesion(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
