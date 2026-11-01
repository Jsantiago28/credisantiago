import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../recibos/compartir_recibo.dart';
import '../recibos/imprimir_ticket.dart';
import '../recibos/recibo_pdf.dart';
import '../services/errores.dart';
import '../services/sin_conexion.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'contacto.dart';
import 'foto_privada.dart' show verFoto;
import 'gestiones.dart';
import 'ubicacion.dart' show ubicacionSinAvisar;
import 'ui.dart';

/// Elegir cómo pagó el cliente: efectivo (lo de siempre) o transferencia.
/// En la caja, la entrega del cobrador cuadra solo contra el efectivo.
class SelectorMetodoPago extends StatelessWidget {
  final String valor;
  final ValueChanged<String> onCambio;
  const SelectorMetodoPago({super.key, required this.valor, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: [
          for (final m in metodosPago)
            ButtonSegment(
              value: m,
              label: Text(nombreMetodoPago(m)!),
              icon: Icon(
                  m == 'efectivo' ? Icons.payments_outlined : Icons.account_balance_outlined),
            ),
        ],
        selected: {valor},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onCambio(s.first),
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.greenDark,
          selectedForegroundColor: AppColors.green,
          foregroundColor: AppColors.grey,
          side: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

/// Flujo de cobro de un préstamo: cuotas → cobrar → recibo, e historial de
/// recibos. Se abre desde Inicio y desde Reportes. `onCambio` se llama
/// después de registrar un cobro, para que la pantalla recargue.
class CobroPrestamo {
  final BuildContext context;
  final PrestamoConDatos datos;
  final VoidCallback onCambio;

  CobroPrestamo(this.context, this.datos, {required this.onCambio});

  Map<String, dynamic> get _prestamo => datos.prestamo;
  String get _nombre => datos.nombre;
  String? get _fotoCara => datos.cliente?['foto_cara_url'] as String?;

  /// Los cobros que tienen recibo (sin la marca de 0 de un préstamo importado).
  List<PagoRegistrado> get _recibos => [for (final p in datos.pagos) if (!p.esMarcaImportacion) p];

  static RoundedRectangleBorder get _forma => const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      );

  /// Cronograma de cuotas. Al tocar una pendiente, pide confirmar el cobro
  /// (cuota + su mora, ya puesto).
  Future<void> abrirCuotas() async {
    final hoy = DateTime.now();
    final estado = datos.estado(hoy);
    final delDia = cobroDelDia(estado, hoy);
    final loDeHoy = delDia.atrasado + delDia.venceHoy;
    if (estado.cuotas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este préstamo no tiene cronograma (falta info del plazo).')));
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: _forma,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration:
                    BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  // Tocar la foto la agranda (para reconocer al cliente en la calle).
                  GestureDetector(
                    onTap: _fotoCara == null ? null : () => verFoto(context, _fotoCara),
                    child: AvatarIniciales(nombre: _nombre, fotoUrl: _fotoCara, tamano: 44),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_nombre,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(
                          estado.moraPendiente > 0
                              ? 'Debe ${rd(estado.balance)} · mora ${rd(estado.moraPendiente)}'
                              : 'Debe ${rd(estado.balance)}',
                          style: TextStyle(
                              color: estado.moraPendiente > 0 ? AppColors.red : AppColors.grey,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (_recibos.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        abrirRecibos();
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: Text('Recibos (${_recibos.length})'),
                    ),
                ],
              ),
            ),
            // Cobrar de un toque lo atrasado + lo que vence hoy (con su mora).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: loDeHoy >= 0.5
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('cobrar_lo_de_hoy'),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle:
                                const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _confirmarCobro(estado, loDeHoy);
                        },
                        icon: const Icon(Icons.payments_rounded),
                        label: Text('Cobrar lo de hoy · ${rd(loDeHoy)}'),
                      ),
                    )
                  : Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(estado.saldado ? 'Saldado' : 'Al día',
                            style: TextStyle(
                                color: AppColors.green, fontWeight: FontWeight.w800)),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilaContacto(
                telefono: datos.cliente?['telefono'] as String?,
                onWhatsApp: () => whatsAppCobro(context,
                    nombreCliente: _nombre,
                    telefono: datos.cliente?['telefono'] as String?,
                    estado: estado),
              ),
            ),
            if (datos.promesa(DateTime.now()) case final promesa?)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: LineaPromesa(promesa),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      if (await anotarGestion(ctx, datos)) {
                        onCambio();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('Gestión a $_nombre guardada')));
                        }
                      }
                    },
                    icon: const Icon(Icons.handshake_rounded, size: 18),
                    label: const Text('Anotar gestión'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => verGestiones(context, datos, onCambio: onCambio),
                    child: Text(datos.gestiones.isEmpty
                        ? 'Ver gestiones'
                        : 'Gestiones (${datos.gestiones.length})'),
                  ),
                ],
              ),
            ),
            // Saldar todo antes de tiempo: lo decide el prestamista, no el cobrador.
            if (!SupabaseService.instance.esCobrador && !estado.saldado)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _saldar();
                  },
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('Saldar préstamo hoy'),
                ),
              ),
            const Divider(height: 12),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: estado.cuotas.length,
                itemBuilder: (_, i) {
                  final cuota = estado.cuotas[i];
                  final alDia = cuota.porCobrar < 0.005;
                  final detalle = [
                    rd(cuota.monto),
                    if (!cuota.pagada && cuota.pendiente < cuota.monto)
                      'faltan ${rd(cuota.pendiente)}',
                    if (cuota.moraPendiente > 0) '+ mora ${rd(cuota.moraPendiente)}',
                  ].join(' · ');

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      alDia ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: alDia
                          ? AppColors.green
                          : cuota.moraPendiente > 0
                              ? AppColors.red
                              : AppColors.grey,
                    ),
                    title: Text('Cuota #${cuota.numero} — ${fechaLarga(cuota.fecha)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(detalle,
                        style: TextStyle(
                            color: cuota.moraPendiente > 0 ? AppColors.red : AppColors.grey)),
                    trailing: alDia
                        ? Text('Pagada', style: TextStyle(color: AppColors.green, fontSize: 12))
                        : TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _confirmarCobro(estado, cuota.porCobrar);
                            },
                            child: const Text('Cobrar'),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarCobro(EstadoPrestamo estado, double montoSugerido) async {
    String pesos(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final ctrl = TextEditingController(text: pesos(montoSugerido));
    var metodo = 'efectivo';

    // Botones rápidos: la próxima cuota, todo lo atrasado y todo lo de hoy.
    final delDia = cobroDelDia(estado, DateTime.now());
    final rapidos = <(String, double)>[
      if (proximaCuotaPorCobrar(estado) case final c when c >= 0.5) ('Cuota', c),
      if (delDia.atrasado >= 0.5) ('Todo lo atrasado', delDia.atrasado),
      if (delDia.venceHoy >= 0.5) ('Todo lo de hoy', delDia.atrasado + delDia.venceHoy),
    ];

    final elegido = await showModalBottomSheet<({double monto, String metodo})>(
      context: context,
      isScrollControlled: true,
      shape: _forma,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cobrar a $_nombre',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  estado.moraPendiente > 0
                      ? 'Debe ${rd(estado.balance)} (incluye ${rd(estado.moraPendiente)} de mora)'
                      : 'Balance actual: ${rd(estado.balance)}',
                  style: TextStyle(color: AppColors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setEstado(() {}),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: 'RD\$ ',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (rapidos.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (etiqueta, valor) in rapidos)
                      ChoiceChip(
                        label: Text('$etiqueta · ${rd(valor)}'),
                        selected: ctrl.text == pesos(valor),
                        selectedColor: AppColors.greenDark,
                        labelStyle: TextStyle(
                            color: ctrl.text == pesos(valor) ? AppColors.green : AppColors.grey,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setEstado(() => ctrl.text = pesos(valor)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SelectorMetodoPago(
                valor: metodo,
                onCambio: (m) => setEstado(() => metodo = m),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final monto = double.tryParse(ctrl.text.replaceAll(',', ''));
                  Navigator.of(ctx).pop(monto == null ? null : (monto: monto, metodo: metodo));
                },
                child: const Text('Confirmar cobro'),
              ),
            ],
          ),
        ),
      ),
    );

    final monto = elegido?.monto;
    if (elegido == null || monto == null || monto <= 0 || !context.mounted) return;
    if (!await _confirmarMontoAlto(estado, monto) || !context.mounted) return;
    final mensajero = ScaffoldMessenger.of(context);

    // El id se pone aquí, ANTES de mandarlo: si el cobro llegó pero la
    // respuesta se perdió, el mismo id va a la cola sin señal y la base de
    // datos no lo guarda dos veces.
    final id = SinConexion.nuevoId();
    // Dónde se cobró (si el teléfono lo da), para que el prestamista vea
    // en la caja dónde cobró cada cobrador. El GPS no necesita internet.
    final donde = await ubicacionSinAvisar();
    try {
      // El cobro es del dueño del préstamo, aunque lo haga un cobrador.
      final pago = await SupabaseService.instance.registrarPago(
        prestamoId: _prestamo['id'],
        prestamistaId: _prestamo['prestamista_id'] as String,
        monto: monto,
        ubicacion: donde,
        id: id,
        metodo: elegido.metodo,
      );
      onCambio();
      if (context.mounted) await _mostrarCobroRegistrado(pago);
    } catch (e, pila) {
      registrarError(e, pila, 'COBRAR');
      if (SinConexion.disponible && SinConexion.esFaltaDeConexion(e)) {
        await _guardarSinSenal(id, monto, donde, elegido.metodo);
        return;
      }
      mensajero.showSnackBar(
          SnackBar(content: Text('No se pudo registrar el cobro. ${mensajeError(e)}')));
    }
  }

  /// Cobrar más de lo que debe, o más de 3 cuotas, casi siempre es un cero
  /// de más: se pregunta antes. true si sigue.
  Future<bool> _confirmarMontoAlto(EstadoPrestamo estado, double monto) async {
    final cuota = (_prestamo['cuota'] as num?)?.toDouble() ?? 0;
    final String aviso;
    if (monto > estado.balance + 1) {
      aviso = 'Es más de lo que debe (${rd(estado.balance)}). ¿Seguro?';
    } else if (cuota > 0 && monto > cuota * 3) {
      aviso = 'Son más de 3 cuotas (cada una es ${rd(cuota)}). ¿Seguro?';
    } else {
      return true;
    }
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('¿Cobrar ${rd(monto)}?'),
        content: Text(aviso),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Corregir')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sí, cobrar')),
        ],
      ),
    );
    return seguir == true;
  }

  /// Los cobros del préstamo con el que se acaba de guardar sin señal (para
  /// armar su recibo sin internet).
  List<PagoRegistrado>? _pagosLocales;

  /// Sin señal: el cobro se guarda cifrado en el teléfono y se sube solo
  /// cuando vuelva (ver SinConexion). El recibo dice "pendiente de subir".
  /// [id]: el mismo con que se intentó subir.
  Future<void> _guardarSinSenal(
      String id, double monto, ({double lat, double lng})? donde, String metodo) async {
    final ahora = DateTime.now();
    final reparto = repartirPago(estadoPrestamo(_prestamo, datos.pagos, ahora), monto);
    final cobro = CobroPendiente(
      id: id,
      prestamoId: _prestamo['id'] as String,
      prestamistaId: _prestamo['prestamista_id'] as String,
      monto: monto,
      montoMora: reparto.mora,
      fecha: ahora,
      ubicacion: donde,
      metodo: metodo,
    );
    try {
      await SinConexion.agregar(cobro);
    } catch (e, pila) {
      registrarError(e, pila, 'GUARDAR COBRO SIN SEÑAL');
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('No se pudo guardar el cobro en el teléfono'),
            content: Text('No hay señal y el teléfono no lo pudo guardar. El cobro de '
                '${rd(monto)} NO quedó anotado: inténtalo otra vez o anótalo en papel.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Entendido')),
            ],
          ),
        );
      }
      return;
    }
    SinConexion.sinSenal.value = true;
    _pagosLocales = [...datos.pagos, cobro.comoPago];
    onCambio();
    if (context.mounted) await _mostrarCobroRegistrado(cobro.comoPago);
  }

  /// Lo que ya pagó alcanza para saldarlo hoy: pregunta y lo marca saldado.
  Future<void> _cerrarYaCubierto() async {
    final cerrar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Ya está cubierto'),
        content: Text('${const SaldoCubierto().mensaje} ¿Lo marco como saldado?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sí, saldarlo')),
        ],
      ),
    );
    if (cerrar != true || !context.mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.marcarSaldado(_prestamo['id'] as String);
      onCambio();
      mensajero.showSnackBar(SnackBar(content: Text('Préstamo de $_nombre saldado')));
    } catch (e, pila) {
      registrarError(e, pila, 'MARCAR SALDADO');
      mensajero.showSnackBar(SnackBar(content: Text(mensajeError(e))));
    }
  }

  /// Saldar todo hoy, antes de tiempo: muestra cuánto paga (capital, interés
  /// solo hasta hoy más 1 día, y mora) y cuánto interés se le perdona.
  Future<void> _saldar() async {
    final s = calcularSaldarHoy(_prestamo, datos.pagos, DateTime.now());
    if (s.monto < 1) {
      // Pagó por adelantado más de lo que cuesta saldarlo hoy: no hay nada
      // que cobrar (no se guarda un cobro de 0); solo se cierra el préstamo.
      await _cerrarYaCubierto();
      return;
    }
    Widget fila(String texto, double valor, {bool negrita = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                  child: Text(texto,
                      style: TextStyle(
                          color: color ?? (negrita ? null : AppColors.grey),
                          fontWeight: negrita ? FontWeight.w800 : null))),
              Text(rd(valor),
                  style: TextStyle(
                      color: color,
                      fontSize: negrita ? 20 : 14,
                      fontWeight: negrita ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );

    var metodo = 'efectivo';
    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: _forma,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setEstado) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Saldar el préstamo de $_nombre',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                s.conDescuento
                    ? 'Paga hoy todo lo que debe. Del interés solo se cobran los días que '
                        'pasaron más 1 día de cierre; el resto se le descuenta.'
                    : 'Ya vencieron todas las cuotas: para saldar paga todo lo que debe.',
                style: TextStyle(color: AppColors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            fila('Capital que falta', s.capital),
            if (s.interesVencido >= 0.5) fila('Interés vencido sin pagar', s.interesVencido),
            if (s.conDescuento)
              fila('Interés de ${s.dias} día${s.dias == 1 ? '' : 's'} (incluye 1 de cierre)',
                  s.interesDias),
            if (s.mora > 0) fila('Mora', s.mora, color: AppColors.red),
            const Divider(height: 20),
            fila('Total a pagar hoy', s.monto, negrita: true),
            if (s.conDescuento) ...[
              fila('Debía según las cuotas', s.balance),
              fila('Se le descuenta', s.descuento, color: AppColors.green),
            ],
            const SizedBox(height: 14),
            SelectorMetodoPago(valor: metodo, onCambio: (m) => setEstado(() => metodo = m)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.task_alt_rounded),
              label: Text('Cobrar ${rd(s.monto)} y saldar'),
            ),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ],
        ),
      )),
    );
    if (confirmado != true || !context.mounted) return;

    final mensajero = ScaffoldMessenger.of(context);
    try {
      final donde = await ubicacionSinAvisar();
      final pago = await SupabaseService.instance.registrarPago(
        prestamoId: _prestamo['id'],
        prestamistaId: _prestamo['prestamista_id'] as String,
        monto: s.monto,
        descuento: s.descuento,
        ubicacion: donde,
        metodo: metodo,
      );
      onCambio();
      if (context.mounted) await _mostrarCobroRegistrado(pago);
    } on AvisoParaUsuario catch (e) {
      // El saldo cambió mientras miraba, o ya está cubierto: se dice tal cual.
      onCambio();
      mensajero.showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (e, pila) {
      registrarError(e, pila, 'SALDAR');
      mensajero.showSnackBar(SnackBar(
          content: Text(SinConexion.esFaltaDeConexion(e)
              ? 'Para saldar con descuento hace falta internet.'
              : 'No se pudo saldar. ${mensajeError(e)}')));
    }
  }

  /// Genera y comparte el PDF del recibo, avisando si algo falla.
  Future<void> _compartirRecibo(PagoRegistrado pago) async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await compartirRecibo(
          prestamo: _prestamo,
          pago: pago,
          pagosLocales: _pagosLocales ?? datos.pagos,
          cliente: datos.cliente);
    } catch (e, pila) {
      registrarError(e, pila, 'RECIBO');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo generar el recibo. ${mensajeError(e)}')));
    }
  }

  /// Después de cobrar: confirma el reparto y ofrece compartir el recibo.
  Future<void> _mostrarCobroRegistrado(PagoRegistrado pago) {
    return showModalBottomSheet(
      context: context,
      shape: _forma,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.green, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Cobrado ${rd(pago.monto)} a $_nombre',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pago.sinSubir)
              Text(
                  'Sin señal: quedó guardado en este teléfono y se sube solo cuando vuelva '
                  'el internet. El recibo dice "pendiente de subir".',
                  style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600))
            else
              Text(
                  'Recibo ${numeroReciboTexto(pago.numeroRecibo)}'
                  '${nombreMetodoPago(pago.metodo) == null ? '' : ' · ${nombreMetodoPago(pago.metodo)}'}',
                  style: TextStyle(color: AppColors.grey)),
            if (pago.montoMora > 0)
              Text('Cuota ${rd(pago.montoCuota)} + mora ${rd(pago.montoMora)}',
                  style: TextStyle(color: AppColors.grey)),
            if (pago.descuento > 0)
              Text('Préstamo saldado · se descontaron ${rd(pago.descuento)} de interés',
                  style: TextStyle(color: AppColors.green)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _compartirRecibo(pago),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Compartir recibo (PDF)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => imprimirTicket(context,
                  prestamo: _prestamo,
                  pago: pago,
                  pagosLocales: _pagosLocales ?? datos.pagos,
                  cliente: datos.cliente),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Imprimir ticket'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Listo'),
            ),
            // El cobrador no anula: le avisa al jefe. Sin subir no se anula.
            if (pago.sinSubir)
              const SizedBox.shrink()
            else if (!SupabaseService.instance.esCobrador)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                onPressed: () async {
                  if (await _anular(pago) && ctx.mounted) Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('¿Te equivocaste? Anular este cobro'),
              )
            else
              Text('¿Te equivocaste? Avísale a tu jefe para que lo anule.',
                  style: TextStyle(color: AppColors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Pide el motivo y anula el cobro. Devuelve true si se anuló.
  Future<bool> _anular(PagoRegistrado pago) async {
    final motivo = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Anular recibo ${numeroReciboTexto(pago.numeroRecibo)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El cobro de ${rd(pago.monto)} del ${fechaLarga(pago.fecha)} deja de contar: '
                'vuelve a subir lo que debe $_nombre. No se borra: queda anulado con el motivo.',
                style: TextStyle(color: AppColors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivo,
                autofocus: true,
                onChanged: (_) => setEstado(() {}),
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Ej. puse 4000 en vez de 400',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            TextButton(
              onPressed: motivo.text.trim().length < 3 ? null : () => Navigator.of(ctx).pop(true),
              child: Text('Anular cobro', style: TextStyle(color: AppColors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !context.mounted) return false;

    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance
          .anularPago(prestamo: _prestamo, pago: pago, motivo: motivo.text);
      onCambio();
      mensajero.showSnackBar(SnackBar(
          content: Text('Recibo ${numeroReciboTexto(pago.numeroRecibo)} anulado. '
              'El balance de $_nombre se recalculó.')));
      return true;
    } catch (e, pila) {
      registrarError(e, pila, 'ANULAR');
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo anular. ${mensajeError(e)}')));
      return false;
    }
  }

  /// Historial de pagos del préstamo, para reenviar cualquier recibo.
  Future<void> abrirRecibos() {
    final pagos = [..._recibos]..sort((a, b) => b.fecha.compareTo(a.fecha));
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: _forma,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Recibos de $_nombre',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: pagos.length,
                itemBuilder: (_, i) {
                  final pago = pagos[i];
                  if (pago.anulado) {
                    // Queda a la vista, tachado, para que haya rastro.
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.block_rounded, color: AppColors.red),
                      title: Text('${numeroReciboTexto(pago.numeroRecibo)} — ${rd(pago.monto)}',
                          style: TextStyle(
                              color: AppColors.grey, decoration: TextDecoration.lineThrough)),
                      subtitle: Text(
                        'ANULADO'
                        '${pago.anuladoEn != null ? ' el ${fechaLarga(pago.anuladoEn!)}' : ''}'
                        '${pago.motivoAnulacion != null ? ' · ${pago.motivoAnulacion}' : ''}',
                        style: TextStyle(color: AppColors.red, fontSize: 12),
                      ),
                    );
                  }
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(pago.sinSubir ? Icons.cloud_upload_outlined : Icons.receipt_long,
                        color: pago.sinSubir ? AppColors.amber : AppColors.grey),
                    title: Text('${numeroReciboTexto(pago.numeroRecibo)} — ${rd(pago.monto)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text((pago.sinSubir ? 'Pendiente de subir · ' : '') +
                        fechaLarga(pago.fecha) +
                        (pago.metodo == 'transferencia' ? ' · transferencia' : '') +
                        (pago.montoMora > 0 ? ' · incluye mora ${rd(pago.montoMora)}' : '')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Compartir PDF',
                          icon: Icon(Icons.picture_as_pdf, color: AppColors.green),
                          onPressed: () => _compartirRecibo(pago),
                        ),
                        IconButton(
                          tooltip: 'Imprimir ticket',
                          icon: Icon(Icons.print_rounded, color: AppColors.grey),
                          onPressed: () => imprimirTicket(context,
                              prestamo: _prestamo,
                              pago: pago,
                              pagosLocales: _pagosLocales ?? datos.pagos,
                              cliente: datos.cliente),
                        ),
                        if (!SupabaseService.instance.esCobrador && !pago.sinSubir)
                          PopupMenuButton<String>(
                            tooltip: 'Más opciones',
                            color: AppColors.surfaceAlt,
                            icon: Icon(Icons.more_vert, color: AppColors.grey),
                            onSelected: (_) async {
                              if (await _anular(pago) && ctx.mounted) Navigator.of(ctx).pop();
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'anular',
                                child: Row(
                                  children: [
                                    Icon(Icons.undo_rounded, color: AppColors.red, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Anular este cobro'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
