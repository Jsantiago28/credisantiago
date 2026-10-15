import 'package:flutter/material.dart';
import '../logic/validacion.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/evidencias.dart';
import '../widgets/foto_privada.dart';
import '../widgets/ui.dart';
import 'planes_screen.dart';

/// Solicitudes nuevas que llegan por el link del prestamista.
class SolicitudesScreen extends StatefulWidget {
  final String prestamistaId;

  /// Solicitudes nuevas, ya ordenadas (las trae la barra de abajo en vivo).
  /// Null mientras cargan.
  final List<Map<String, dynamic>>? nuevas;
  final String? error;
  final VoidCallback onReintentar;

  const SolicitudesScreen({
    super.key,
    required this.prestamistaId,
    required this.nuevas,
    required this.error,
    required this.onReintentar,
  });

  @override
  State<SolicitudesScreen> createState() => _SolicitudesScreenState();
}

class _SolicitudesScreenState extends State<SolicitudesScreen> {
  /// Clientes que ya existen, para avisar si la solicitud es de uno de ellos.
  List<Map<String, dynamic>> _clientes = const [];

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    try {
      final lista = await SupabaseService.instance.listarClientes(widget.prestamistaId);
      if (mounted) setState(() => _clientes = lista);
    } catch (_) {
      // Sin la lista no hay avisos de repetidos, pero se puede aprobar igual.
    }
  }

  /// Avisos de repetidos de una solicitud: contra tus clientes y contra
  /// otras solicitudes nuevas. `esCliente` = misma cédula que un cliente.
  List<({String texto, bool esCliente})> _avisosRepetidos(
      Map<String, dynamic> s, List<Map<String, dynamic>> otrasNuevas) {
    final avisos = <({String texto, bool esCliente})>[];
    final deClientes = buscarRepetidos(_clientes,
        cedula: s['cedula'], telefono: s['telefono'], nombre: s['nombre']);
    for (final r in deClientes) {
      avisos.add((
        texto: r.dato == DatoRepetido.cedula
            ? 'Ya es tu cliente: ${r.registro['nombre']} (misma cédula)'
            : 'Mismo ${r.dato.texto} que tu cliente ${r.registro['nombre']}',
        esCliente: r.dato == DatoRepetido.cedula,
      ));
    }
    final deSolicitudes = buscarRepetidos(otrasNuevas,
        cedula: s['cedula'], telefono: s['telefono'], excluirId: s['id'] as String?);
    for (final dato in deSolicitudes.map((r) => r.dato).toSet()) {
      avisos.add((texto: 'Hay otra solicitud nueva con el mismo ${dato.texto}', esCliente: false));
    }
    return avisos;
  }

  String _tiempoTranscurrido(String createdAt) {
    final fecha = DateTime.tryParse(createdAt);
    if (fecha == null) return '';
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} días';
  }

  /// Traduce el código guardado en metodo_cobro a un texto claro para el prestamista.
  String _metodoCobroTexto(Map<String, dynamic> s) {
    switch (s['metodo_cobro']) {
      case 'transferencia':
        final banco = s['banco'];
        final cuenta = (s['numero_cuenta'] ?? '').toString();
        if (banco != null && cuenta.isNotEmpty) {
          final ultimos4 = cuenta.length >= 4 ? cuenta.substring(cuenta.length - 4) : cuenta;
          return '$banco • **** $ultimos4';
        }
        return 'Transferencia bancaria';
      case 'billetera':
        return s['billetera'] != null ? 'Billetera ${s['billetera']}' : 'Billetera';
      case 'efectivo':
        return 'Efectivo / Sin banco';
      default:
        return 'Sin definir método de pago';
    }
  }

  Future<void> _aprobar(Map<String, dynamic> solicitud) async {
    final mensajero = ScaffoldMessenger.of(context);
    // Si ya es cliente (misma cédula), no se crea otro: se usa su ficha.
    final existente = buscarRepetidos(_clientes, cedula: solicitud['cedula'])
        .map((r) => r.registro)
        .firstOrNull;
    try {
      if (existente != null) {
        final usarFicha = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('${existente['nombre']} ya es tu cliente'),
            content: const Text(
                'Tiene la misma cédula. Para no tenerlo dos veces, el préstamo se le '
                'abre en su ficha de cliente.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Aprobar en su ficha')),
            ],
          ),
        );
        if (usarFicha != true) return;
        await SupabaseService.instance.aprobarParaClienteExistente(solicitud, existente);
      } else {
        await SupabaseService.instance.aprobarSolicitud(solicitud);
        _cargarClientes(); // ya es cliente: próximas solicitudes lo detectan
      }
      mensajero.showSnackBar(
        SnackBar(content: Text('${solicitud['nombre']} aprobado. Préstale desde Clientes.')),
      );
    } on LimitePlan catch (e) {
      if (mounted) await avisarLimitePlan(context, e);
    } catch (e) {
      mensajero.showSnackBar(SnackBar(content: Text('No se pudo aprobar: $e')));
    }
  }

  Future<void> _rechazar(Map<String, dynamic> solicitud) async {
    await SupabaseService.instance.rechazarSolicitud(solicitud['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${solicitud['nombre']} rechazado.')),
    );
  }

  void _verFicha(Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FichaSolicitud(solicitud: s, metodoCobroTexto: _metodoCobroTexto(s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('CREDISANTIAGO',
            style: TextStyle(
                color: AppColors.green, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ),
      body: Builder(
        builder: (context) {
          final nuevas = widget.nuevas;
          if (nuevas == null) {
            if (widget.error == null) return const Center(child: CircularProgressIndicator());
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Vacio(
                        icono: Icons.cloud_off,
                        texto: 'No pudimos cargar las solicitudes.\n${widget.error}'),
                    ElevatedButton.icon(
                      onPressed: widget.onReintentar,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
          final hoy = DateTime.now();
          final deHoy = nuevas.where((s) {
            final f = DateTime.tryParse(s['created_at'] ?? '')?.toLocal();
            return f != null && f.year == hoy.year && f.month == hoy.month && f.day == hoy.day;
          }).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Solicitudes nuevas',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  ),
                  Pildora('HOY • $deHoy'),
                ],
              ),
              const SizedBox(height: 4),
              Text('Aprobar o rechazar las nuevas solicitudes de préstamo',
                  style: TextStyle(color: AppColors.grey)),
              const SizedBox(height: 16),
              if (nuevas.isEmpty)
                const Vacio(
                  icono: Icons.inbox_rounded,
                  texto: 'No tienes solicitudes nuevas por ahora.\n'
                      'Comparte tu link desde Perfil para recibir más.',
                )
              else
                ...nuevas.map((s) => _tarjetaSolicitud(s, _avisosRepetidos(s, nuevas))),
            ],
          );
        },
      ),
    );
  }

  Widget _tarjetaSolicitud(Map<String, dynamic> s, List<({String texto, bool esCliente})> avisos) {
    final monto = s['monto_solicitado'] as num?;
    final foto = s['foto_cara_url'] as String?;
    final nombre = (s['nombre'] as String?) ?? '';
    final direccion = s['direccion'] as String?;
    final lugar = direccion != null && direccion.isNotEmpty ? direccion : 'RD';

    return Panel(
      borde: AppColors.green.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: foto != null
                      ? FotoPrivada(
                          guardado: foto,
                          width: 84,
                          height: 84,
                          sinFoto: Container(
                            color: AppColors.surfaceAlt,
                            alignment: Alignment.center,
                            child: AvatarIniciales(nombre: nombre, tamano: 56),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceAlt,
                          alignment: Alignment.center,
                          child: AvatarIniciales(nombre: nombre, tamano: 56),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '$lugar • ${_tiempoTranscurrido(s['created_at'] ?? '')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.schedule, size: 14, color: AppColors.green),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(monto != null ? rd(monto) : 'Monto no especificado',
                        style: TextStyle(
                            color: AppColors.green,
                            fontSize: monto != null ? 28 : 18,
                            fontWeight: FontWeight.w800)),
                    Row(
                      children: [
                        Icon(Icons.account_balance, size: 15, color: AppColors.grey),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(_metodoCobroTexto(s),
                              style: TextStyle(color: AppColors.grey, fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final aviso in avisos)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: aviso.esCliente ? AppColors.redDark : AppColors.amberDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(aviso.esCliente ? Icons.person_search_rounded : Icons.content_copy_rounded,
                      size: 18, color: aviso.esCliente ? AppColors.red : AppColors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(aviso.texto,
                        style: TextStyle(
                            color: aviso.esCliente ? AppColors.red : AppColors.amber,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _aprobar(s),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Aprobar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: BorderSide(color: AppColors.red),
                    backgroundColor: AppColors.redDark.withValues(alpha: 0.4),
                  ),
                  onPressed: () => _rechazar(s),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _verFicha(s),
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Ver'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FichaSolicitud extends StatelessWidget {
  final Map<String, dynamic> solicitud;
  final String metodoCobroTexto;
  const _FichaSolicitud({required this.solicitud, required this.metodoCobroTexto});

  Widget _fila(String label, String? valor) {
    if (valor == null || valor.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label, style: TextStyle(color: AppColors.grey))),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }

  String? _montoTexto(dynamic valor) {
    if (valor == null) return null;
    final n = valor is num ? valor : num.tryParse(valor.toString());
    if (n == null) return null;
    return rd(n);
  }

  @override
  Widget build(BuildContext context) {
    final tieneOtrosIngresos = solicitud['tiene_otros_ingresos'] == true;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Text(solicitud['nombre'] ?? '',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text('Datos personales',
              style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold)),
          _fila('Cédula', solicitud['cedula']),
          _fila('Teléfono', solicitud['telefono']),
          _fila('Dirección', solicitud['direccion']),
          _fila('Vivienda', switch (solicitud['tipo_vivienda']) {
            'propia' => 'Casa propia',
            'alquilada' => 'Alquilada',
            _ => null,
          }),
          const SizedBox(height: 12),
          Text('Trabajo e ingresos',
              style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold)),
          _fila('Lugar', solicitud['trabajo_lugar']),
          _fila('Dirección trabajo', solicitud['trabajo_direccion']),
          _fila('Supervisor / RR.HH.', solicitud['jefe_nombre']),
          _fila('Tel. supervisor', solicitud['jefe_telefono']),
          _fila('Gana al mes', _montoTexto(solicitud['ingreso_mensual'])),
          if (tieneOtrosIngresos) ...[
            _fila('Otros ingresos', solicitud['otros_ingresos_descripcion']),
            _fila('Monto otros ingresos', _montoTexto(solicitud['otros_ingresos_monto'])),
          ],
          const SizedBox(height: 12),
          Text('Evidencias de ingresos',
              style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          GaleriaEvidencias(urls: GaleriaEvidencias.desde(solicitud['evidencias_ingresos'])),
          const SizedBox(height: 12),
          Text('Referencias',
              style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold)),
          _fila('Ref 1',
              '${solicitud['ref1_nombre'] ?? ''} (${solicitud['ref1_parentesco'] ?? ''}) - ${solicitud['ref1_telefono'] ?? ''}'),
          _fila('Ref 2',
              '${solicitud['ref2_nombre'] ?? ''} (${solicitud['ref2_parentesco'] ?? ''}) - ${solicitud['ref2_telefono'] ?? ''}'),
          const SizedBox(height: 12),
          Text('Monto y forma de pago',
              style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold)),
          _fila('Monto solicitado', _montoTexto(solicitud['monto_solicitado'])),
          _fila('Frecuencia de pago', solicitud['frecuencia_pago']),
          _fila('Capacidad de pago', _montoTexto(solicitud['capacidad_pago'])),
          _fila('Cómo quiere el dinero', metodoCobroTexto),
        ],
      ),
    );
  }
}
