import 'package:flutter/material.dart';

import '../logic/calculo_prestamo.dart';
import '../logic/gestiones.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

const _forma = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// "25 sep 3:40 pm"
String fechaHora(DateTime f) {
  final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
  return '${fechaCorta(f)} $h:${f.minute.toString().padLeft(2, '0')} ${f.hour < 12 ? 'am' : 'pm'}';
}

IconData iconoGestion(String tipo) => switch (tipo) {
      'visita' => Icons.directions_walk_rounded,
      'llamada' => Icons.phone_rounded,
      'whatsapp' => Icons.chat_rounded,
      _ => Icons.edit_note_rounded,
    };

/// Color y texto corto de cómo va una promesa.
({Color color, Color fondo, String texto}) estiloPromesa(EstadoPromesa e) => switch (e) {
      EstadoPromesa.pendiente =>
        (color: AppColors.grey, fondo: AppColors.surfaceAlt, texto: 'PENDIENTE'),
      EstadoPromesa.venceHoy =>
        (color: AppColors.amber, fondo: AppColors.amberDark, texto: 'PROMETIÓ HOY'),
      EstadoPromesa.cumplida =>
        (color: AppColors.green, fondo: AppColors.greenDark, texto: 'CUMPLIÓ'),
      EstadoPromesa.incumplida =>
        (color: AppColors.red, fondo: AppColors.redDark, texto: 'NO CUMPLIÓ'),
    };

/// "Prometió RD$2,000 para el 25 sep · ha dado RD$800"
String textoPromesa(InfoPromesa p) {
  final g = p.gestion;
  return [
    'Prometió ${g.promesaMonto != null ? '${rd(g.promesaMonto!)} ' : ''}'
        'para el ${fechaCorta(g.promesaFecha!)}',
    if (p.pagado > 0 && p.estado != EstadoPromesa.cumplida) 'ha dado ${rd(p.pagado)}',
  ].join(' · ');
}

/// Línea con la última promesa de pago y su estado, para la hoja de cobro,
/// la ficha del cliente e Inicio.
class LineaPromesa extends StatelessWidget {
  final InfoPromesa promesa;
  const LineaPromesa(this.promesa, {super.key});

  @override
  Widget build(BuildContext context) {
    final estilo = estiloPromesa(promesa.estado);
    return Row(
      children: [
        Icon(Icons.handshake_rounded, size: 16, color: estilo.color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(textoPromesa(promesa),
              style: TextStyle(color: estilo.color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        Pildora(estilo.texto, color: estilo.color, fondo: estilo.fondo),
      ],
    );
  }
}

/// Formulario para anotar una gestión de cobro (visita, llamada, WhatsApp):
/// qué pasó, el acuerdo y, si prometió pagar, cuándo y cuánto. Devuelve
/// true si se guardó.
Future<bool> anotarGestion(BuildContext context, PrestamoConDatos datos) async {
  final estado = datos.estado(DateTime.now());
  final dia = cobroDelDia(estado, DateTime.now());
  final sugerido = dia.atrasado + dia.venceHoy > 0
      ? dia.atrasado + dia.venceHoy
      : estado.cuotas.where((c) => c.porCobrar > 0).firstOrNull?.porCobrar ?? estado.balance;
  String pesos(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  var tipo = 'visita';
  var resultado = 'promesa';
  final acuerdo = TextEditingController();
  final monto = TextEditingController(text: sugerido > 0 ? pesos(sugerido) : '');
  final manana = DateTime.now().add(const Duration(days: 1));
  DateTime? fecha = DateTime(manana.year, manana.month, manana.day);
  var guardando = false;

  final guardo = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: _forma,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setEstado) {
        final esPromesa = resultado == 'promesa';
        final montoValido = monto.text.trim().isEmpty ||
            (double.tryParse(monto.text.replaceAll(',', '')) ?? 0) > 0;
        final puedeGuardar = !guardando && (!esPromesa || (fecha != null && montoValido));

        Future<void> guardar() async {
          setEstado(() => guardando = true);
          final mensajero = ScaffoldMessenger.of(context);
          try {
            await SupabaseService.instance.registrarGestion(
              prestamo: datos.prestamo,
              tipo: tipo,
              resultado: resultado,
              acuerdo: acuerdo.text,
              promesaFecha: fecha,
              promesaMonto: double.tryParse(monto.text.replaceAll(',', '')),
            );
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          } catch (e, pila) {
            registrarError(e, pila, 'GESTION');
            setEstado(() => guardando = false);
            mensajero.showSnackBar(SnackBar(
                content: Text(e.toString().contains('gestiones')
                    ? 'Falta correr la migración de gestiones en Supabase.'
                    : 'No se pudo guardar la gestión. ${mensajeError(e)}')));
          }
        }

        Widget chips(Map<String, String> opciones, String elegido, ValueChanged<String> onElegir) =>
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in opciones.entries)
                  ChoiceChip(
                    label: Text(o.value),
                    selected: elegido == o.key,
                    onSelected: (_) => setEstado(() => onElegir(o.key)),
                    selectedColor: AppColors.greenDark,
                    backgroundColor: AppColors.surfaceAlt,
                    labelStyle: TextStyle(
                        color: elegido == o.key ? AppColors.green : AppColors.texto,
                        fontWeight: FontWeight.w600),
                    showCheckmark: false,
                  ),
              ],
            );

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gestión a ${datos.nombre}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('Debe ${rd(estado.balance)}', style: TextStyle(color: AppColors.grey)),
                const SizedBox(height: 16),
                const Text('¿Cómo fue?', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                chips(tiposGestion, tipo, (v) => tipo = v),
                const SizedBox(height: 16),
                const Text('¿Qué pasó?', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                chips(resultadosGestion, resultado, (v) => resultado = v),
                if (esPromesa) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final hoy = DateTime.now();
                            final elegida = await showDatePicker(
                              context: ctx,
                              initialDate: fecha ?? hoy,
                              firstDate: DateTime(hoy.year, hoy.month, hoy.day),
                              lastDate: hoy.add(const Duration(days: 365)),
                              helpText: '¿Para cuándo prometió pagar?',
                            );
                            if (elegida != null) setEstado(() => fecha = elegida);
                          },
                          icon: const Icon(Icons.event_rounded, size: 18),
                          label: Text(fecha == null ? 'Fecha' : fechaLarga(fecha!)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: monto,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setEstado(() {}),
                          decoration: InputDecoration(
                            labelText: 'Monto prometido',
                            prefixText: 'RD\$ ',
                            errorText: montoValido ? null : 'Monto no válido',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: acuerdo,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: esPromesa ? 'Acuerdo' : 'Nota',
                    hintText: esPromesa
                        ? 'Ej. paga el viernes 2,000 y el resto el lunes'
                        : 'Ej. la esposa dice que llega a las 6',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: puedeGuardar ? guardar : null,
                  child: Text(guardando ? 'Guardando…' : 'Guardar gestión'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return guardo == true;
}

/// Historial de gestiones del préstamo (la más reciente arriba), con el
/// estado de cada promesa. Se lee de nuevo para que salga lo último.
Future<void> verGestiones(BuildContext context, PrestamoConDatos datos,
    {VoidCallback? onCambio}) async {
  List<Gestion> lista;
  try {
    lista = await SupabaseService.instance.obtenerGestiones(datos.prestamo['id']);
  } catch (e, pila) {
    registrarError(e, pila, 'VER GESTIONES');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar las gestiones. ${mensajeError(e)}')));
    }
    return;
  }
  if (!context.mounted) return;
  final activo = datos.prestamo['estado'] == 'en_calle';

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: _forma,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setEstado) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Gestiones de ${datos.nombre}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  if (activo)
                    TextButton.icon(
                      onPressed: () async {
                        if (await anotarGestion(ctx, datos)) {
                          onCambio?.call();
                          lista = await SupabaseService.instance
                              .obtenerGestiones(datos.prestamo['id']);
                          setEstado(() {});
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Anotar'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: lista.isEmpty
                  ? const Vacio(
                      icono: Icons.handshake_rounded,
                      texto: 'Todavía no hay gestiones.\n'
                          'Anota cada visita, llamada o promesa de pago.')
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (_, i) => FilaGestion(lista[i], pagos: datos.pagos),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Una gestión en el historial.
class FilaGestion extends StatelessWidget {
  final Gestion gestion;
  final List<PagoRegistrado> pagos;
  const FilaGestion(this.gestion, {super.key, required this.pagos});

  @override
  Widget build(BuildContext context) {
    final g = gestion;
    final promesa = g.esPromesa ? estadoPromesa(g, pagos, DateTime.now()) : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.surfaceAlt,
          child: Icon(iconoGestion(g.tipo), size: 18, color: AppColors.green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${g.nombreTipo} · ${g.nombreResultado}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(fechaHora(g.fecha),
                  style: TextStyle(color: AppColors.grey, fontSize: 12)),
              if (g.acuerdo != null) ...[
                const SizedBox(height: 4),
                Text('"${g.acuerdo}"', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
              if (promesa != null) ...[
                const SizedBox(height: 6),
                LineaPromesa(promesa),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
